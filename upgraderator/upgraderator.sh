#!/usr/bin/env bash

set -euo pipefail

if [ -z "$DEBUG" ]; then
  set -x
  env | sort
fi

BASE=$(dirname $(readlink -f $0))
export PATH=$BASE:$PATH
. $BASE/config.sh
[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK





echo ------------------------------------------------------------
export CLUSTER_ID=fbs
export CLUSTER_SSH_KEY="$KUBERNETES_NODE_SSH_KEY_FILE"

MASTERS=$WORK/masters
cluster-fox copy-kubectl-config | tee $MASTERS

cluster-fox kubectl us-gov-west-1a -- get nodes
cluster-fox kubectl us-gov-west-1a -- get pods --all-namespaces


exit 0
