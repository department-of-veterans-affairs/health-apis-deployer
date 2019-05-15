#!/usr/bin/env bash

#
# Wait for the load-balancer to leave it's initialization period for the new rule
# before launching tests against it
#

COLOR=$1

test -n "$DU_LOAD_BALANCER_RULE_PATH"
test -n "$COLOR"
test -n "$CLUSTER_ID"
test -n "$VPC_NAME"

echo "Waiting for load balancer to be ready."
timeout=$($(date +%s) + 20)
while [ $(date +%s) -lt $timeout ]
do
  sleep 1
  load-balancer rule-health --env $VPC_NAME --cluster-id $CLUSTER_ID --color $COLOR --rule-path $DU_LOAD_BALANCER_RULE_PATH
  [ $? != 0 ] && echo "Load balancer is not healthy" && continue
  echo "Load balancer is healthy"
  return
done
echo "Timeout waiting for load balancer to become healthy"
exit 1
