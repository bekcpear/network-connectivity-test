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
Usage: ${0##*/} [<ID>|<IP>] [r|f]
          r: means filter by running state
          f: means filter by finished state
"
  exit
fi

declare -a _args
for _arg; do
  case ${_arg} in
    r)
      _filter_running=1
      ;;
    f)
      _filter_finished=1
      ;;
    *)
      _args+=("${_arg}")
      ;;
  esac
done
set -- "${_args[@]}"

#
# $1: id
_is_running() {
  if [[ $( echo ${1} 'check_running' | nc -W 1 -U ${_sock} ) == "RUNNING" ]]; then
    return 0
  fi
  return 1
}

#
# $1: ip
# $2: ver
_restored_ip() {
  if [[ ${2} == v4 ]]; then
    echo ${1//-/.}
  elif [[ ${2} == v6 ]]; then
    echo ${1//-/:}
  fi
}

#
# $1: time
_restored_time() {
  local _t=${1#T}
  echo ${_t//-/:}
}

#
# $1: ping.log
# $2: [short]
_statistics() {
  local _ss="$(tail -20 ${1} | grep -A2 'ping statistics' | tail -2)"
  if [[ -z ${_ss} ]]; then
    echo "(statistics error)"
    return
  fi
  IFS=$'\n\t ' read _trans _ _ _recv _ _loss _ <<<$(head -1 <<<"${_ss}")
  IFS=$'\n\t ' read _ _ _ _ms _ <<<$(tail -1 <<<"${_ss}")
  if [[ ${2} == 'short' ]]; then
    echo "($(cut -d'/' -f2 <<<${_ms}) ms, ${_loss})"
  else
    echo "(${_recv}/${_trans} ${_loss}, ${_ms} ms)"
  fi
}

_ip_pattern='*'
if _is_id ${1}; then
  IFS='_' read _type _ver _ip _d _t _tz <<<$(find ${_home_dir} -mindepth 2 -maxdepth 2 -name "${1}.id" -printf '%h\n' | awk -F'/' '{printf $NF"\n"}' )
  _name="${_type}_${_ver}_${_ip}_${_d}_${_t}_${_tz}"
  _id=${1}
  _ip=$(_restored_ip ${_ip} ${_ver})
  _status="Finished"
  _d=${_d#D}
  _t=$(_restored_time ${_t})
  _work_dir="${_home_dir}/${_name}"
  if _is_running ${_id}; then
    _status="\033[1m\033[32mRunning\033[0m"
  else
    _ping_file="${_work_dir}/ping.log"
    _status="${_status} $(_statistics ${_ping_file})"
    _edt=$(tail ${_ping_file} | grep '^=====\s' | tail -1)
    _ed=$(date -d "${_edt#===== }" '+%Y-%m-%d')
    _et=$(date -d "${_edt#===== }" '+%H:%M:%S')
    _etz=$(date -d "${_edt#===== }" '+%z')
  fi
  echo -e "
          ID: ${_id}
          IP: ${_ip}
        Type: ${_type} (${_ver})
      Status: ${_status}
 Time period: ${_d} ${_t} ${_tz}${_ed+ - }${_ed} ${_et} ${_etz}
    Work Dir: ${_work_dir}
"
  exit
elif _is_ip ${1}; then
  _ip_pattern=${1//./-}
  _ip_pattern=${_ip_pattern//:/-}
  _ip_pattern="*_${_ip_pattern}_*"
elif [[ -n ${1} ]]; then
  echo "'${1}' is neither an ID nor an IP!" >&2
  exit 1
fi

echo -e " ID      STATE      TYPE   VER   DATE          TIME      TZ       IP
---------------------------------------------------------------------------------------"
while IFS='_' read _type _ver _ip _d _t _tz; do
  _name="${_type}_${_ver}_${_ip}_${_d}_${_t}_${_tz}"
  _ip=$(_restored_ip ${_ip} ${_ver})
  _d=${_d#D}
  _t=$(_restored_time ${_t})

  _id=$(find ${_home_dir}/${_name} -maxdepth 1 -name '*.id' -type f -printf '%f')
  _id=${_id%.id}

  _ping_file="${_home_dir}/${_name}/ping.log"
  _ping_file_tail="$(tail ${_ping_file})"

  if _is_running ${_id}; then
    if [[ -n ${_filter_finished} ]]; then
      continue
    fi
    _state='\033[32m\033[1mrunning\033[0m '
  else
    if [[ -n ${_filter_running} ]]; then
      continue
    fi
    _state='finished'
    _edt=$(grep '^=====\s' <<<"${_ping_file_tail}" | tail -1)
    _ed=$(date -d "${_edt#===== }" '+%Y-%m-%d')
    _et=$(date -d "${_edt#===== }" '+%H:%M:%S')
    _etz=$(date -d "${_edt#===== }" '+%z')
  fi

  # get the total seq num and format it
  _seq_sum=$(tac <<<"${_ping_file_tail}" | grep 'icmp_seq=' | head -1)
  _seq_sum=${_seq_sum#*icmp_seq=}
  _seq_sum=${_seq_sum%% *}
  # get the number of times the sequence has been cycled
  if [[ ${_seq_sum} -gt 60000 ]]; then
    set -- head -n -50000 ${_ping_file}
  else
    set -- cat ${_ping_file}
  fi
  _test_seqs=($("${@}" | grep -E 'icmp_seq=655[0-9][0-9]' 2>/dev/null | cut -d' ' -f5 | sort))
  _seq_loop=0
  declare -i _seq_loop_last=0
  _test_seq_last=''
  for _test_seq in ${_test_seqs[@]}; do
    if [[ ${_test_seq} != ${_test_seq_last} ]]; then
      _test_seq_last=${_test_seq}
      if [[ ${_seq_loop_last} -gt ${_seq_loop} ]]; then
        _seq_loop=${_seq_loop_last}
      fi
      _seq_loop_last=1
    else
      _seq_loop_last+=1
    fi
  done
  if [[ ${_seq_loop_last} -gt ${_seq_loop} ]]; then
    _seq_loop=${_seq_loop_last}
  fi
  if [[ ${_seq_loop} -gt 0 ]]; then
    _seq_sum="[+${_seq_loop}] ${_seq_sum}"
  else
    _seq_sum="${_seq_sum}"
  fi
  _placeholder='                      '


  echo -e " ${_id}   ${_state}   ${_type}   ${_ver}    S:${_d}  ${_t}  ${_tz}    ${_ip}"
  if [[ ${_state} == "finished" ]]; then
    _seq_sum="${_seq_sum} $(_statistics ${_ping_file} short)"
    echo "         ${_seq_sum}${_placeholder:${#_seq_sum}}  E:${_ed}  ${_et}  ${_etz}"
  else
    echo "         ${_seq_sum}${_placeholder:${#_seq_sum}}"
  fi
  echo "---------------------------------------------------------------------------------------"
done <<<"$(find ${_home_dir} -mindepth 1 -maxdepth 1 -name "${_ip_pattern}" -printf '%f\n')"
