#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh
[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK

env | sort

exit 0
