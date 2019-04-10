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
MASTERS=$WORK/masters
cluster-fox list-masters | tee $MASTERS


function copyKubernetesConfig() {
  local az=$1
  local ip=$2
  echo "Retrieving configuration for $az from $ip"
  scp -i $KUBERNETES_NODE_SSH_KEY_FILE ec2-user@$ip:.kube/config ~/.kube/$az-config
}
export -f copyKubernetesConfig
mkdir ~/.kube
cat $MASTERS | xargs -n 2 -I {} bash -c 'copyKubernetesConfig {}'

exit 0
