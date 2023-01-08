#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

# prepare sock and fifo vars
mkdir -p ${_sock}
mkdir -p ${_NC_FIFO}
mkdir -p ${_home_dir}
_home_sha1=$(sha1sum <<<"${_home_dir}" | cut -d' ' -f1)
_sock="${_sock}/${_home_sha1}"
_NC_FIFO="${_NC_FIFO}/${_home_sha1}"

_date() {
  export LC_TIME="C.UTF-8"
  export TZ="Asia/Shanghai"
  date "${@}"
}

_is_path() {
  if [[ -e "${1}" ]]; then
    return 0
  else
    return 1
  fi
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
  if [[ ${#_c[@]} -lt 3 ]]; then
    _ret=1
  fi
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
    if [[ $( echo 'check_running' ${1} | nc -W 1 -U ${_sock} ) == "RUNNING" ]]; then
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

_id_file_from_id() {
  local _id_file="$(find ${_home_dir} -mindepth 2 -maxdepth 2 -name ${1%.id}'.id' -type f)"
  if [[ -n ${_id_file} ]]; then
    echo "${_id_file}"
  else
    return 1
  fi

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

_id_and_work_dir_from_tag() {
  local _this_id _work_dir
  local -a _id_files=( $(find ${_home_dir} -mindepth 2 -maxdepth 2 -name '*.id' -type f) )
  local -a _hited_id_files
  local f
  for f in "${_id_files[@]}"; do
    if eval "grep -E '^${1}$' '${f}'" &>/dev/null; then
      _hited_id_files+=( "${f}" )
    fi
  done
  if [[ ${#_hited_id_files[@]} -gt 1 ]]; then
    echo "multiple items for tag '${1}', ID:" >&2
    for f in "${_hited_id_files[@]}"; do
      echo "  ${f##*/}" >&2
    done
    return 1
  fi
  _this_id="${_hited_id_files[0]##*/}"
  _work_dir=$(_work_dir_from_id ${_this_id})
  if [[ $? != 0 ]]; then
    echo "cannot get work dir from tag '${1}'" >&2
    return 1
  fi
  declare -p _this_id _work_dir
}

#
# $1: id or work dir
_id_and_work_dir() {
  local _this_id _work_dir
  local -i _ret=0
  if ! _is_path ${1}; then
    _work_dir=$(_work_dir_from_id ${1}) || _ret=$?
    if [[ ${_ret} != 0 ]]; then
      eval "$(_id_and_work_dir_from_tag ${1} || true)"
      if [[ -z ${_work_dir} ]]; then
        echo "cannot get work dir from ID or Tag: '${1}'" >&2
        return 1
      fi
    fi
    : ${_this_id:=${1}}
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

#
# $1: the array name of tags
# $2: file path
_write_tags() {
  local _file="${2}"
  local _new_tags=''
  eval "set -- \"\${${1}[@]}\""
  for _t; do
    _new_tags+="${_t}"$'\n'
  done
  echo "${_new_tags}" >${_file}
}

#
# $1: action
# $2: id
# $3: [tag...]
_tag() {
  local _action=${1}
  local _id=${2}
  local _id_file

  _id_file="$(_id_file_from_id ${_id})" || \
    return 1

  if [[ ${_action} == "clear" ]]; then
    echo >${_id_file}
    return
  fi

  IFS=$'\n'
  local _tags=($(cat ${_id_file} 2>/dev/null))

  if [[ ${_action} == "get" ]]; then
    for _t in "${_tags[@]}"; do
      _txt+="${_t}; "
    done
    echo "${_txt%; }"
    return
  fi

  shift 2
  for _t; do
    case ${_action} in
      add)
        for _t_e in ${_tags[@]}; do
          if [[ "${_t}" == "${_t_e}" ]]; then
            continue 2
          fi
        done
        _tags+=("${_t}")
        _modified=1
        ;;
      del)
        for (( _i = 0; _i<${#_tags[@]}; ++_i )); do
          if [[ "${_t}" == "${_tags[${_i}]}" ]]; then
            eval "unset _tags[${_i}]"
            _modified=1
          fi
        done
        ;;
    esac
  done

  if [[ ${_modified} == 1 ]]; then
    _write_tags _tags "${_id_file}"
    return
  fi
  return 9 # means do nothing
}
