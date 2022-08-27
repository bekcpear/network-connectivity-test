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


if [[ ${1} =~ ^[0-9a-zA-Z]{5}(\.id)?$ ]]; then
  _work_dir="$(find ${_home_dir} -maxdepth 2 -name ${1%.id}'.id' -type f -printf '%h\n')"
else
  _work_dir="${_home_dir}/${1##*/}"
fi

_ping_file="${_work_dir}/ping.log"

if [[ ! -f ${_ping_file} ]]; then
  echo "Invaild work dir" >&2
  exit 1
fi

cd "${_work_dir}"
pwd

_tmp_dir=$(ls -1d ${_work_dir}/tmp.* | head -1)
if [[ ! -d ${_tmp_dir} ]]; then
  _tmp_dir=$(mktemp -dp ${_work_dir})
fi

declare -i _i=0
declare -i _cnr=1

_total=$(wc -l ${_ping_file} | cut -d' ' -f1)
while (( ${_cnr} < ${_total} )); do
  _sep_tmpfile="${_tmp_dir}/${_i}"
  echo "start ${_cnr}/${_total} > ${_i} ..."
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
      print NR;
    }
  ' ${_ping_file} >${_sep_tmpfile}
  _cnr=$(tail -1 ${_sep_tmpfile})
  _cnr+=1
  _i+=1
done

_report="$(pwd)/report.txt"

_get_date() {
  local _d=$(grep '^=====' ${1})
  echo -n "${_d#===== }"
}

pushd ${_tmp_dir} >/dev/null
echo -e "START\t\t\t\t-\tEND\t\t\t\trecv/trans\tloss%" >${_report}
echo -n $(_get_date 0)$'\t''-'$'\t' >>${_report}
for (( _ii = 1 ; _ii < _i; ++_ii )); do
  _d=$(_get_date ${_ii})
  if [[ -z ${_d} ]]; then
    _d=" -- "
  fi
  echo -n ${_d}$'\t' >>${_report}

  _seq0=$(head -1 ${_ii} | cut -d' ' -f5)
  _seq0=${_seq0#icmp_seq=}
  while read _ _ _ _ _seq1 _; do
    if [[ ${_seq1} =~ ^icmp_seq ]]; then
      _seq1=${_seq1#icmp_seq=}
      break
    fi
  done <<<"$(tail ${_ii} | tac)"
  _seq=$(( ${_seq1} - ${_seq0} + 1 ))

  _aseq=$(awk '/^.*bytes\sfrom.*ttl=.*$/' ${_ii} | wc -l | cut -d' ' -f1)

  echo -n ${_aseq}/${_seq}$'\t\t' >>${_report}

  _loss_rate=$(echo "scale=0; (${_seq} - ${_aseq})*10000/${_seq}" | bc)
  if (( ${_loss_rate} < 10 )); then
    _color="32" #green
  elif (( ${_loss_rate} < 100 )); then
    _color="33" #yellow
  else
    _color="31" #red
  fi
  printf "\e[%sm%4.2f%%\e[0m\n" ${_color} $(echo "scale=2; ${_loss_rate}/100" | bc ) >>${_report}

  echo -n ${_d}$'\t''-'$'\t' >>${_report}
done

sed -i '$d' ${_report}
echo "report:" ${_report}
echo

cat ${_report}
