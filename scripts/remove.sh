#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/../env"

declare -a _rm_work_dirs
for _a; do
  eval "$(_id_and_work_dir ${_a})"
  if [[ -z ${_this_id} || -z ${_work_dir} ]]; then
    continue
  fi
  if _is_running ${_this_id}; then
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
