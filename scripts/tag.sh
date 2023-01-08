#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/../env"

_id=${1}
_action=${2}

if ! _is_id ${_id}; then
  eval "$(_id_and_work_dir_from_tag ${_id})"
  _id=${_this_id}
fi

shift 2 || \
  {
    echo "missing arguments!" >&2
    exit 1
  }

unset _ret
case ${_action} in
  a|add)
    _tag add ${_id} "${@}" || _ret=$?
    ;;
  d|del)
    _tag del ${_id} "${@}" || _ret=$?
    ;;
  clr|clear)
    _tag clear ${_id} || _ret=$?
    ;;
  *)
    echo "Unrecognized action '${_action}'!" >&2
    exit 1
    ;;
esac

if [[ -z ${_ret} ]]; then
  echo "${_action} for '${_id}' succeed."
elif [[ ${_ret} == 9 ]]; then
  echo "nothing happend!"
else
  return ${_ret}
fi

${_sp}/list.sh ${_id}
