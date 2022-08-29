#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/env"

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
    echo "(no statistics)"
    return
  fi
  IFS=$'\n\t ' read _trans _ _ _recv _ _err _ _loss _ <<<$(head -1 <<<"${_ss}")
  if [[ ! ${_err} =~ ^\+ ]]; then
    _loss=${_err}
    unset _err
  fi
  IFS=$'\n\t ' read _ _ _ _ms _ <<<$(tail -1 <<<"${_ss}")
  if [[ ${2} == 'short' ]]; then
    _ms=$(printf '%5.1f' $(cut -d'/' -f2 <<<${_ms}))
    _loss=$(printf '%5.2f%%' ${_loss%\%})
    echo "(${_loss}, ${_ms} ms)"
  else
    echo "(${_recv}/${_trans} ${_loss}${_err:+, }${_err}${_err:+ errors}, ${_ms} ms)"
  fi
}

#
# $1: ping file
_live_seq_sum() {
  # get the total seq num and format it
  local _ping_file="${1}"
  local _seq_sum
  _seq_sum=$(tac "${_ping_file}" | grep 'icmp_seq=' | head -1)
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
    echo -e "${_seq_sum} *${_seq_loop}"
  else
    echo "${_seq_sum}"
  fi
}

#
# $1: ping file
_end_time() {
  _edt=$(tail ${1} | grep '^=====\s' | tail -1)
  _ed=$(date -d "${_edt#===== }" '+%Y-%m-%d')
  _et=$(date -d "${_edt#===== }" '+%H:%M:%S')
  _etz=$(date -d "${_edt#===== }" '+%z')
  declare -p _ed _et _etz
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
  _ping_file="${_work_dir}/ping.log"
  if _is_running ${_id}; then
    _status="\033[1m\033[32mRunning\033[0m"
  else
    _status="${_status} $(_statistics ${_ping_file})"
    eval "$(_end_time ${_ping_file})"
  fi
  echo -e "
          ID: ${_id}
          IP: ${_ip}
        Type: ${_type} (${_ver})
      Status: ${_status}
    Last Seq: $(_live_seq_sum ${_ping_file})
 Time period: ${_d} ${_t} ${_tz}" - "${_ed:-<Now>} ${_et} ${_etz}
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

echo -e " ID      STATE      TYPE   VER       DATE         TIME     TZ       IP
---------------------------------------------------------------------------------------"
while IFS='_' read _type _ver _ip _d _t _tz; do
  if [[ ${_type} != 'ping' ]]; then
    continue
  fi
  _name="${_type}_${_ver}_${_ip}_${_d}_${_t}_${_tz}"
  _ip=$(_restored_ip ${_ip} ${_ver})
  _d=${_d#D}
  _t=$(_restored_time ${_t})

  _id=$(find ${_home_dir}/${_name} -maxdepth 1 -name '*.id' -type f -printf '%f')
  _id=${_id%.id}

  _ping_file="${_home_dir}/${_name}/ping.log"

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
    eval "$(_end_time ${_ping_file})"
  fi

  _seq_sum="$(_live_seq_sum ${_ping_file})"
  _seq_sum_ph='         '

  echo -e " ${_id}   ${_state}   ${_type}   ${_ver}        S:${_d} ${_t} ${_tz}    ${_ip}"
  if [[ ${_state} == "finished" ]]; then
    _statistics_short="$(_statistics ${_ping_file} short)"
    _statistics_short_ph='                  '
    echo "         ${_seq_sum}${_seq_sum_ph:${#_seq_sum}}${_statistics_short}${_statistics_short_ph:${#_statistics_short}} E:${_ed} ${_et} ${_etz}"
  else
    echo "         ${_seq_sum}${_seq_sum_ph:${#_seq_sum}}"
  fi
  echo "---------------------------------------------------------------------------------------"
done <<<"$(find ${_home_dir} -mindepth 1 -maxdepth 1 -name "${_ip_pattern}" -printf '%f\n')"
