#!/usr/bin/env bash
set -euo pipefail

set -x

export PATH=$WORKSPACE/bin:$PATH
test -n "$ENVIRONMENT"
test -f "$WORKSPACE/environments/$ENVIRONMENT.conf"
. "$WORKSPACE/environments/$ENVIRONMENT.conf"


AVAILABILITY_ZONES="$(cluster-fox list-availability-zones)"

cluster-fox copy-kubectl-config

for az in $AVAILABILITY_ZONES
do
  echo "Collecting status from $az"
  cluster-fox kubectl $az -- get ns -o json > namespaces.$az.json
done
