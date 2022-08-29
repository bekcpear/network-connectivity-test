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
Usage: $0 <ID> | <PATH>
"
  exit
fi


if [[ ${1} =~ ^[_0-9a-zA-Z]{5}(\.id)?$ ]]; then
  _work_dir="$(find ${_home_dir} -maxdepth 2 -name ${1%.id}'.id' -type f -printf '%h\n')"
else
  _work_dir="${_home_dir}/${1##*/}"
fi

_ip=''
while IFS='_' read _ _type __ip _; do
  if [[ ${_type} == "v4" ]]; then
    _ip=${__ip//-/.}
  elif [[ ${_type} == "v6" ]]; then
    _ip=${__ip//-/:}
  fi
done <<<"${_work_dir#*/}"

_ping_file="${_work_dir}/ping.log"

if [[ ! -f ${_ping_file} ]]; then
  echo "Invaild work dir" >&2
  exit 1
fi

cd "${_work_dir}"

_tmp_dir=$(ls -1d ${_work_dir}/tmp.* 2>/dev/null | head -1)
if [[ ! -d ${_tmp_dir} ]]; then
  _tmp_dir=$(mktemp -dp ${_work_dir})
fi

declare -i _i=0
declare -i _cnr=1

_tmp_i=$(find ${_tmp_dir} -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort -n | tail -1)
if [[ -n ${_tmp_i} && ${_tmp_i} > ${_i} ]]; then
  if tail -2 ${_tmp_dir}/${_tmp_i} | grep '^=====\s' &>/dev/null; then
    _i=$(( ${_tmp_i} + 1 ))
    _cnr=$(tail -1 ${_tmp_dir}/${_tmp_i})
    _cnr+=1
  else
    _i=${_tmp_i}
    _cnr=$(tail -1 ${_tmp_dir}/$(( ${_i} - 1 )))
    _cnr+=1
  fi
fi

_total=$(wc -l ${_ping_file} | cut -d' ' -f1)
while (( ${_cnr} < ${_total} )); do
  _sep_tmpfile="${_tmp_dir}/${_i}"
  echo -ne "\033[G\033[Jfilter ${_cnr}/${_total} > ${_i} ..." >&2
  export _cnr
  awk '
    NR >= ENVIRON["_cnr"] &&
    /^[[:digit:]]+[[:space:]]+byt.*ttl.*$/ {
      print $0;
    }

    NR >= ENVIRON["_cnr"] &&
    /^=====\s/ {
      print $0;
      exit;
    }

    END {
      print "_seq0_fixed=";
      print "_seq1_fixed=";
      print "_seq_fixed=";
      print NR;
    }
  ' ${_ping_file} >${_sep_tmpfile}
  _cnr=$(tail -1 ${_sep_tmpfile})
  _cnr+=1
  _i+=1
done
echo -ne "\033[G\033[J" >&2

_report="$(pwd)/report.txt"

_get_date() {
  local _d=$(grep '^=====' ${1})
  echo -n "${_d#===== }"
}

pushd ${_tmp_dir} >/dev/null
eval "$(cat __pos 2>/dev/null)"
declare -i _ii_p=1
if [[ ! -f ${_report} || -z ${_i_p} ]]; then
  echo "IP: ${_ip}" >${_report}
  echo -e "idx.   start datetime                 -   end datetime                   recv/trans     loss%   avg.time" >>${_report}
  echo -n '1      '$(_get_date 0)'   -   ' >>${_report}
else
  sed -Ei '$s@-\s\s\s.*@-   -----@' ${_report}
  sed -zEi '$s@-----\n@@' ${_report}
  declare -i _ii_p=${_i_p:-1}
fi
declare -a _seq0_fixed _seq1_fixed
for (( _ii = ${_ii_p} ; _ii < _i; )); do
  echo -ne "\033[G\033[Jparsing ${_ii} ..." >&2
  _d=$(_get_date ${_ii})
  if [[ -z ${_d} ]]; then
    _d="   --                       "
  fi
  echo -n "${_d}   " >>${_report}

  unset _seq0_fixed _seq1_fixed _seq_fixed
  while read _line; do
    eval "declare ${_line}"
  done <<<"$(grep '^_seq' -- $((${_ii} - 1)))"
  _seq0_last=${_seq0_fixed}
  _seq1_last=${_seq1_fixed}
  _seq_last=${_seq_fixed}
  while read _line; do
    eval "declare ${_line}"
  done <<<"$(grep '^_seq' -- ${_ii})"

  if [[ -n ${_seq_fixed} ]]; then
    _seq=${_seq_fixed}
  else
    if [[ -n ${_seq0_fixed} ]]; then
      _seq0=${_seq0_fixed}
    else
      _seq0=$(head -1 ${_ii} | cut -d' ' -f5)
      _seq0=${_seq0#icmp_seq=}
      # check discontinuous seq
      if [[ ${_seq0} -gt ${_seq1_last} && ${_seq0} != $(( ${_seq1_last} + 1 )) ]]; then
        if [[ ${_seq0} -lt 500 && ${_ii} -le 1 ]]; then
          _seq0=1
        else
          if [[ ${_seq_last} -lt 598 ]]; then
            # re-parse the last sequence set
            sed -Ei '$d;' ${_report}
            sed -Ei '$s@-\s\s\s.*@-   -----@' ${_report}
            sed -zEi '$s@-----\n@@' ${_report}
            eval "sed -Ei '/^_seq1_fixed/s/_seq1_fixed=.*/_seq1_fixed=$(( ${_seq0} - 1 ))/' $((${_ii} - 1))"
            _ii=$(( ${_ii} - 2 ))
            continue
          else
            _seq0=$(( ${_seq1_last} + 1 ))
          fi
        fi
      fi
    fi

    if [[ -n ${_seq1_fixed} ]]; then
      _seq1=${_seq1_fixed}
    else
      while read _ _ _ _ _seq1 _; do
        if [[ ${_seq1} =~ ^icmp_seq ]]; then
          _seq1=${_seq1#icmp_seq=}
          break
        fi
      done <<<"$(tail ${_ii} | tac)"
    fi

    if [[ ${_seq1} -gt ${_seq0} ]]; then
      _seq=$(( ${_seq1} - ${_seq0} + 1 ))
    else
      _seq=$(( 65535 - ${_seq0} + ${_seq1} + 2 ))
    fi
    if [[ ${_seq} -gt 600 ]]; then
      _seq1=$(( ${_seq1} - ${_seq} + 600 ))
      _seq=600
    fi
    eval "sed -Ei \
      -e '/^_seq0_fixed/s/_seq0_fixed=.*/_seq0_fixed=${_seq0}/' \
      -e '/^_seq1_fixed/s/_seq1_fixed=.*/_seq1_fixed=${_seq1}/' \
      -e '/^_seq_fixed/s/_seq_fixed=.*/_seq_fixed=${_seq}/' ${_ii}"
  fi

  _aseq=$(awk '/^.*bytes\sfrom.*ttl=.*$/' ${_ii} | wc -l | cut -d' ' -f1)

  _placeholder='       '
  _the_seq="${_aseq}/${_seq}"
  echo -n ${_aseq}/${_seq}"${_placeholder:${#_the_seq}}      " >>${_report}

  # loss rate
  _loss_rate=$(echo "scale=0; (${_seq} - ${_aseq})*10000/${_seq}" | bc)
  if (( ${_loss_rate} < 10 )); then
    _color="32" #green
  elif (( ${_loss_rate} < 100 )); then
    _color="33" #yellow
  else
    _color="31" #red
  fi
  printf "\e[%sm%6.2f%%\e[0m" ${_color} $(echo "scale=2; ${_loss_rate}/100" | bc ) >>${_report}

  # avg. time
  echo -n "   " >>${_report}
  printf "%d ms\n" $(echo $(awk -F'[= ]' '
      BEGIN {
        n=0
        t=0
      }
      /time=/ {
        n+=1
        t+=$10
      }
      END {
        printf "scale=0; "t" / "n
      }
    ' ${_ii}) | bc ) >>${_report}
  echo "_i_p=${_ii}" >__pos

  _ii=$((${_ii} + 1))
  _placeholder='    '
  echo -n "${_ii}${_placeholder:${#_ii}}   "${_d}'   -   ' >>${_report}
done
echo -ne "\033[G\033[J" >&2

sed -i '$d' ${_report}
echo "report:" ${_report}
echo

cat ${_report}
