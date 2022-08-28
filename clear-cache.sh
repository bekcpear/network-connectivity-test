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
  if [[ ${_a} =~ ^[_0-9a-zA-Z]{5}(\.id)?$ ]]; then
    _work_dir="$(find ${_home_dir} -maxdepth 2 -name ${_a%.id}'.id' -type f -printf '%h\n')"
  else
    _work_dir="${_home_dir}/${_a##*/}"
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
