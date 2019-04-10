#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh
[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK

env | sort

echo ------------------------------------------------------------
aws ec2 describe-instances --filters Name=tag-key,Values=KubernetesCluster \
  | jq -r '.Reservations[].Instances[]|.InstanceId,(.Tags[]|select(.Key=="KubernetesCluster").Value)' \
  | paste -sd ' \n'

exit 0
