#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/env"

# help
if [[ $1 =~ ^- ]]; then
  echo "
Usage: $0 <ip>...
"
  exit
fi

_check_ipv4() {
  local IFS='.'
  local _c=(${1})
  local _ret=1
  for __c in ${_c[@]}; do
    if [[ ${__c} =~ ^[0-9]{1,3}$ ]]; then
      if [[ ${__c} -lt 256 ]]; then
        _ret=0
      fi
    fi
  done
  return ${_ret}
}

_check_ipv6() {
  local IFS=':'
  local _c=(${1})
  local _ret=0
  for __c in ${_c[@]}; do
    if [[ ! ${__c} =~ ^[0-9a-fA-F]{0,4}$ ]]; then
      _ret=1
    fi
  done
  return ${_ret}
}

#
# $1: file
_insert_time() {
  trap '
    echo "===== $(_date)" >>"${1}"
  ' SIGINT
  while :; do
    echo "===== $(_date)" >>"${1}"
    sleep 600
  done
}

# main process
declare -a _ping_subprocesses _insert_subprocesses
for _ip; do
  _c_date=$(_date '+%Y-%m-%d+T%H_%M_%S%z')
  _opts=''

  if _check_ipv4 ${_ip}; then
    _work_dir="ping_v4_${_ip//./-}_DATE-${_c_date}"
    _opts="-4"
  elif _check_ipv6 ${_ip}; then
    _work_dir="ping_v6_${_ip//:/-}_DATE-${_c_date}"
    _opts="-6"
  else
    echo "Invaild IP address!" >&2
    exit 1
  fi

  _work_dir="${_home_dir}/${_work_dir}"
  set -- mkdir -p "${_work_dir}"
  echo ">>>" "${@}"
  "${@}"

  _ping_file="${_work_dir}/ping.log"

  echo ">>>" "do inserting time job ..."
  ( _insert_time "${_ping_file}" ) &
  _insert_subprocesses+=($!)

  set -- ping ${_opts} ${_ip}
  echo ">>>" "${@}" " ..."
  ( "${@}" &>>"${_ping_file}" ) &
  _ping_subprocesses+=($!)

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
  echo ">>>" "${@}"
  "${@}"

  echo "
      IP: ${_ip}
      ID: ${_this_id}
work dir: ${_work_dir}
ping log: ${_ping_file}
"
done

echo "<CTRL-C> to finish it"

trap '
for _subid in ${_ping_subprocesses[@]} ${_insert_subprocesses[@]}; do
  kill -s SIGINT ${_subid} && \
    echo "subprocess ${_subid} killed." || \
    echo "kill subprocess ${_subid} failed."
done
' EXIT

wait
