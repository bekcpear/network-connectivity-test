#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

# prepare sock and fifo vars
mkdir -p ${_sock}
mkdir -p ${_NC_FIFO}
_home_sha1=$(sha1sum <<<"${_home_dir}" | cut -d' ' -f1)
_sock="${_sock}/${_home_sha1}"
_NC_FIFO="${_NC_FIFO}/${_home_sha1}"

_date() {
  export LC_TIME="C.UTF-8"
  export TZ="Asia/Shanghai"
  date "${@}"
}

_is_id() {
  if [[ ${1} =~ ^[_0-9a-zA-Z]{5}(\.id)?$ ]]; then
    return 0
  fi
  return 1
}

_is_ipv4() {
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

_is_ipv6() {
  if [[ -z $1 ]]; then
    return 1
  fi
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

_is_ip() {
  if _is_ipv4 ${1}; then
    return 0
  elif _is_ipv6 ${1}; then
    return 0
  else
    return 1
  fi
}

#
# $1: id
_is_running() {
  if [[ -z ${1} ]]; then
    echo "empty ID!" >&2
    exit 1
  fi
  if [[ -S ${_sock} ]]; then
    if [[ $( echo ${1} 'check_running' | nc -W 1 -U ${_sock} ) == "RUNNING" ]]; then
      return 0
    fi
  fi
  return 1
}

_is_work_dir() {
  local _work_dir="${1}"
  _work_dir=${_work_dir%/}
  _work_dir_name0=${_work_dir##*/}
  _work_dir_name1=${_work_dir#${_home_dir%/}/}
  if [[ ${_work_dir} == ${_work_dir_name1} ]]; then
    return 1
  fi
  if [[ ${_work_dir_name0} == ${_work_dir_name1} ]]; then
    if ls ${_work_dir}/ping.log &>/dev/null; then
      if ls ${_work_dir}/*.id &>/dev/null; then
        return 0
      fi
    fi
  fi
  return 1
}

_work_dir_from_id() {
  local _work_dir="$(find ${_home_dir} -maxdepth 2 -name ${1%.id}'.id' -type f -printf '%h\n')"
  if _is_work_dir "${_work_dir}"; then
    echo "${_work_dir}"
  else
    return 1
  fi
}

_id_from_work_dir() {
  local _this_id=$(find "${1}" -mindepth 1 -maxdepth 1 -name '*.id' -type f -printf '%f')
  _this_id=${_this_id%.id}
  if _is_id ${_this_id}; then
    echo ${_this_id}
  else
    return 1
  fi
}

#
# $1: id or work dir
_id_and_work_dir() {
  local _this_id _work_dir
  local -i _ret=0
  if _is_id ${1}; then
    _work_dir=$(_work_dir_from_id ${_a}) || _ret=$?
    if [[ ${_ret} != 0 ]]; then
      echo "cannot get work dir from ID '${_a}'" >&2
      return 1
    fi
    _this_id=${1}
  else
    _work_dir="${_home_dir}/${1##*/}"
  fi
  if ! _is_work_dir "${_work_dir}"; then
    echo "'${_work_dir}' is not a work dir" >&2
    return 1
  fi
  if [[ -z ${_this_id} ]]; then
    _this_id=$(_id_from_work_dir "${_work_dir}") || _ret=$?
    if [[ ${_ret} != 0 ]]; then
      echo "cannot get ID from work dir '${_work_dir}'" >&2
      return 1
    fi
  fi
  declare -p _this_id _work_dir
}
