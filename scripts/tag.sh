#!/usr/bin/env bash
#
# @author cwittlut <i@bitbili.net>
#

set -e

_my_path=$(dirname $(realpath $0))
. "${_my_path}/../env"

_id=${1}
_action=${2}
shift 2 || \
  {
    echo "missing arguments!" >&2
    exit 1
  }

case ${_action} in
  add)
    _tag add ${_id} "${@}"
    ;;
  del)
    _tag del ${_id} "${@}"
    ;;
  clear)
    _tag clear ${_id}
    ;;
  *)
    echo "Unrecognized action '${_action}'!" >&2
    exit 1
    ;;
esac

echo ${_sp}
${_sp}/list.sh ${_id}
