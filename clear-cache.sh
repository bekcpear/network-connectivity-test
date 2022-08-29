#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/env"

declare -a _rm_work_dirs
for _a; do
  eval "$(_id_and_work_dir ${_a})"
  if [[ -z ${_this_id} || -z ${_work_dir} ]]; then
    continue
  fi
  _cache_dir=$(ls -1d ${_work_dir}/tmp.* 2>/dev/null) && \
    _rm_cache_dirs+=("rm -rf ${_cache_dir}"$'\n') || true
done

if [[ ${#_rm_cache_dirs[@]} -lt 1 ]]; then
  exit
fi

set -- "${_rm_cache_dirs[@]}"
echo " ""${@}"
eval "${@}"
