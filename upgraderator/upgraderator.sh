#!/usr/bin/env bash

set -euo pipefail

BASE=$(dirname $(readlink -f $0))
export PATH=$BASE:$PATH
. $BASE/config.sh
[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK

env | sort

echo ------------------------------------------------------------
export CLUSTER_ID=fbs
cluster-fox list-masters

kubectl version

exit 0
