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
Usage: $0 <ID>... | <PATH>...
"
  exit
fi

declare -a _rm_work_dirs
for _a; do
  if [[ ${_a} =~ ^[0-9a-zA-Z]{5}(\.id)?$ ]]; then
    _work_dir="$(find ${_home_dir} -maxdepth 2 -name ${_a%.id}'.id' -type f -printf '%h\n')"
  else
    _work_dir="${_home_dir}/${_a##*/}"
  fi
  if ls ${_work_dir}/RUNNING &>/dev/null; then
    echo "'${_a}' is running, skip!"
    continue
  fi
  _rm_work_dirs+=("rm -rf ${_work_dir}"$'\n')
done

if [[ ${#_rm_work_dirs[@]} -lt 1 ]]; then
  exit
fi

set -- "${_rm_work_dirs[@]}"
echo " ""${@}"
WAIT=3
echo -en "Starting in: \e[33m\e[1m"
while [[ ${WAIT} -gt 0 ]]; do
  echo -en "${WAIT} "
  WAIT=$((${WAIT} -  1))
  sleep 1
done
echo -e "\e[0m"

eval "${@}"
