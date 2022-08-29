#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#


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
