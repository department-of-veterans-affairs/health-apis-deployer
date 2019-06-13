#!/usr/bin/env bash
set -euo pipefail

set -x

test -n "$ENVIRONMENT"
test -f "$WORKSPACE/environments/$ENVIRONMENT.conf"
. "$WORKSPACE/environments/$ENVIRONMENT.conf"


AVAILABILITY_ZONES="$(cluster-fox list-availability-zones)"

cluster-fox copy-kubectl-config

for az in $AVAILABILITY_ZONES
do
  cluster-fox kubectl $AVAILABILITY_ZONE -- get ns -o json > namespaces.$az.json
done
