#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/../env"

if ! command -v nc &>/dev/null; then
  echo "'nc' command (openbsd-netcat) not found!" >&2
  exit 1
fi

#
# $1: A|S
_show_info() {
  local _action=${1}
  local _ip=${2}
  local _id=${3}
  local _work_dir=${4}
  case ${_action} in
    A)
      if [[ ${_ip} != "invalid" ]]; then
        echo -en "\033[32m
New item appended:\033[0m"
      else
        echo "Invalid IP address '${_id}'!" >&2
      fi
      ;;
    S)
      if [[ ${_ip} != "invalid" ]]; then
        echo -en "\033[33m
Item stopped:\033[0m"
      else
        echo "Invalid item ID '${_id}'!" >&2
      fi
      ;;
  esac
  if [[ ${_ip} != "invalid" ]]; then
    echo "
        IP: ${_ip}
        ID: ${_id}
  Work Dir: ${_work_dir}
"
  fi
}

_send_item() {
  echo "$*" | nc -W 1 -U ${_sock}
}

# main client process
if [[ -e ${_sock} ]]; then
  _action='append'
  if [[ ${1} == '-s' ]]; then
    _action='stop'
    shift
  fi
  for _item; do
    _show_info $(_send_item ${_item} ${_action})
  done
  exit
fi

_insert_time_exec() {
  local _ping_file="${1}"
  set -- echo "===== $(_date)"
  echo "${@}" ">>""${_ping_file}" >${_debug_log}
  "${@}" >>"${_ping_file}"
}
#
# $1: file
_insert_time() {
  local _ping_file=${1}
  trap '
    exit 130
  ' SIGINT
  trap '
    _insert_time_exec "${_ping_file}"
  ' ERR EXIT
  while :; do
    _insert_time_exec "${_ping_file}"
    sleep 600
  done
}

#
# $1: ip
_append_task() {
  local _c_date=$(_date '+D%Y-%m-%d_T%H-%M-%S_%z')
  local _opts=''
  local _ip="$1"
  if _is_ipv4 ${_ip}; then
    _work_dir="ping_v4_${_ip//./-}_${_c_date}"
    _opts="-4"
  elif _is_ipv6 ${_ip}; then
    _work_dir="ping_v6_${_ip//:/-}_${_c_date}"
    _opts="-6"
  else
    set -- A invalid ${_ip}
    _show_info "${@}"
    echo "${@}" >${_NC_FIFO}
    return 1
  fi

  _work_dir="${_home_dir}/${_work_dir}"
  set -- mkdir -p "${_work_dir}"
  echo ">>>" "${@}" >${_debug_log}
  "${@}"

  _ping_file="${_work_dir}/ping.log"

  echo ">>>" "do inserting time job ..." >${_debug_log}
  ( _insert_time "${_ping_file}" ) &
  _insert_subprocesses=$!

  set -- ping ${_opts} ${_ip}
  echo ">>>" "${@}" " ..." >${_debug_log}
  ( "${@}" &>>"${_ping_file}" ) &
  _ping_subprocesses=$!

  # generate a unique id
  _existing_ids=($(find ${_home_dir} -maxdepth 2 -name '*.id' -type f -printf '%f\n'))
  _exists() {
    local _ret=1
    for _id in ${_existing_ids[@]}; do
      if [[ "${1}" == ${_id%.id} ]]; then
        _ret=0
      fi
    done
    return ${_ret}
  }
  _generate_id() {
    head /dev/urandom | tr -dc '_a-zA-Z0-9' | fold -w 5 | head -1
  }
  while :; do
    _this_id=$(_generate_id)
    if ! _exists ${_this_id}; then
      break
    fi
  done
  set -- touch "${_work_dir}/${_this_id}.id"
  echo ">>>" "${@}" >${_debug_log}
  "${@}"

  eval "_id_pid_map[${_this_id}]='${_insert_subprocesses} ${_ping_subprocesses} ${_ip} ${_work_dir}'"

  set -- A ${_ip} ${_this_id} ${_work_dir}
  _show_info "${@}"
  echo "${@}" >${_NC_FIFO}
}

#
# $1: id
_stop_task() {
  local _insert_subprocesses _ping_subprocesses _ip _work_dir
  read -r _insert_subprocesses _ping_subprocesses _ip _work_dir <<<"${_id_pid_map[${1}]}"
  if [[ -z ${_insert_subprocesses} && -z ${_ping_subprocesses} ]]; then
    set -- S invalid ${1}
    _show_info "${@}"
    echo "${@}" >${_NC_FIFO}
    return
  fi
  kill -9 ${_insert_subprocesses}
  kill -s INT ${_ping_subprocesses}
  _insert_time_exec "${_work_dir}/ping.log"
  eval "unset _id_pid_map[${1}]"
  set -- S ${_ip} ${1} ${_work_dir}
  _show_info "${@}"
  echo "${@}" >${_NC_FIFO}
}

#
# $1: id
_check_running() {
  if [[ -n ${_id_pid_map[${1}]} ]]; then
    echo "RUNNING" >${_NC_FIFO}
  else
    echo "FINISHED" >${_NC_FIFO}
  fi
}

_listen() {
  set +e
  local _ip
  local -A _id_pid_map
  while :; do
    read -r _item _action
    case ${_action} in
      append)
        _append_task "${_item}"
        ;;
      stop)
        _stop_task "${_item}"
        ;;
      check_running)
        _check_running "${_item}"
        ;;
      socket_test)
        echo "ok" >${_NC_FIFO}
        ;;
      *)
        echo "err" >${_NC_FIFO}
        ;;
    esac
  done
}

trap '
if [[ -n ${_socket_server} ]]; then
  kill -9 ${_socket_server} && \
    { \
      echo "socket server killed."; \
    } || \
    echo "kill socket server failed."
  rm -f ${_sock}
fi
if [[ -e ${_NC_FIFO} ]]; then
  rm -f ${_NC_FIFO}
fi
' ERR EXIT

if [[ ${1} == '-s' ]]; then
  echo "no collecting process for home dir: '${_home_dir}'!" >&2
  exit 1
fi

# main server process
rm -f ${_NC_FIFO}
mkfifo ${_NC_FIFO}
exec {_FD_ITEM}> >(_listen)
_listen_pid=$!
( < <(tail -f ${_NC_FIFO}) nc -k -l -U ${_sock} >&${_FD_ITEM} ) &
_socket_server=$!
declare -i _tries=0
while :; do
  if [[ $(echo '_ socket_test' | nc -W 1 -U ${_sock} 2>${_debug_log}) == 'ok' ]]; then
    break
  fi
  if [[ ${_tries} -gt 50 ]]; then
    echo "cannot connect to the socket server!" >&2
    exit 1
  fi
  _tries+=1
done
for _ip; do
  _send_item ${_ip} append >/dev/null
done

wait
