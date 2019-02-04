#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh

loginToOpenShift

oc get dc \
  | awk '{print $1}' \
  | grep -- '-[0-9]\+-[0-9]\+-[0-9]\+-[0-9]\+-[a-z0-9]\+$' \
  | sed 's/^[-a-z]\+-//' \
  | sort -uV
