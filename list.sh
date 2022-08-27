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
Usage: $0
"
  exit
fi

echo -e " ID      STATE      TYPE   VER   DATE          TIME      TZ       IP
---------------------------------------------------------------------------------------"
while IFS='_' read _type _ver _ip _d _t _tz; do
  _name="${_type}_${_ver}_${_ip}_${_d}_${_t}_${_tz}"
  if [[ ${_ver} == v4 ]]; then
    _ip=${_ip//-/.}
  elif [[ ${_ver} == v6 ]]; then
    _ip=${_ip//-/:}
  fi
  _d=${_d#D}
  _t=${_t#T}
  _t=${_t//-/:}

  _id=$(find ${_home_dir}/${_name} -maxdepth 1 -name '*.id' -type f -printf '%f')
  _id=${_id%.id}

  _ping_file="${_home_dir}/${_name}/ping.log"
  _ping_file_tail="$(tail ${_ping_file})"

  # get the total seq num and format it
  _seq_sum=$(tac <<<"${_ping_file_tail}" | grep 'icmp_seq=' | head -1)
  _seq_sum=${_seq_sum#*icmp_seq=}
  _seq_sum=${_seq_sum%% *}
  _seq_sum_count=${#_seq_sum}
  for (( _i = ${_seq_sum_count}; _i < 22; ++_i )); do
    _seq_sum+=' '
  done

  if ls ${_home_dir}/${_name}/RUNNING &>/dev/null; then
    _state='\033[32m\033[1mrunning\033[0m '
  else
    _state='finished'
    _edt=$(grep '^=====\s' <<<"${_ping_file_tail}" | tail -1)
    _ed=$(date -d "${_edt#===== }" '+%Y-%m-%d')
    _et=$(date -d "${_edt#===== }" '+%H:%M:%S')
    _etz=$(date -d "${_edt#===== }" '+%z')
  fi

  echo -e " ${_id}   ${_state}   ${_type}   ${_ver}    S:${_d}  ${_t}  ${_tz}    ${_ip}"
  if [[ ${_state} == "finished" ]]; then
    echo "         ${_seq_sum}  E:${_ed}  ${_et}  ${_etz}"
  else
    echo "         ${_seq_sum}"
  fi
  echo "---------------------------------------------------------------------------------------"
done <<<"$(ls -1 ${_home_dir})"
