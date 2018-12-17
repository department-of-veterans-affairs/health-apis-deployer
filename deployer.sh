#!/usr/bin/env bash

[ -z "$DOCKER_SOURCE_REGISTRY" ] && echo "Not defined: DOCKER_SOURCE_REGISTRY" && exit 1
[ -z "$DOCKER_USERNAME" ] && echo "Not defined: DOCKER_USERNAME" && exit 1
[ -z "$DOCKER_PASSWORD" ] && echo "Not defined: DOCKER_PASSWORD" && exit 1
[ -z "$OPENSHIFT_USERNAME" ] && echo "Not defined: OPENSHIFT_USERNAME" && exit 1
[ -z "$OPENSHIFT_PASSWORD" ] && echo "Not defined: OPENSHIFT_PASSWORD" && exit 1
[ -z "$ARGONAUT_TOKEN" ] &&  echo "Not defined: ARGONAUT_TOKEN" && exit 1
[ -z "$ARGONAUT_REFRESH_TOKEN" ] &&  echo "Not defined: ARGONAUT_REFRESH_TOKEN" && exit 1
[ -z "$ARGONAUT_CLIENT_ID" ] &&  echo "Not defined: ARGONAUT_CLIENT_ID" && exit 1
[ -z "$ARGONAUT_CLIENT_SECRET" ] &&  echo "Not defined: ARGONAUT_CLIENT_SECRET" && exit 1

APPS="
  health-apis-ids
  health-apis-mr-anderson
  health-apis-argonaut
  mule-argonaut
"
POD_LABELS="
  universal-identity-service
  mr-anderson
  jargonaut
  mule-argonaut
"

DEPLOYER_HOME=$(readlink -f $(dirname $0))
export WORK_DIR=$DEPLOYER_HOME/work
[ ! -d "$WORK_DIR" ] && mkdir -p "$WORK_DIR"
BASE_DOMAIN=lighthouse.va.gov
DOCKER_SOURCE_ORG=vasdvp
OCP_PROJECT=vasdvp

PROD_REGISTRY=registry.$BASE_DOMAIN:5000
PROD_ARGONAUT=argonaut.$BASE_DOMAIN
PROD_OCP=https://ocp.$BASE_DOMAIN:8443

STANDBY_REGISTRY=standby-registry.$BASE_DOMAIN:5000
STANDBY_ARGONAUT=argonaut.$BASE_DOMAIN
STANDBY_OCP=https://standby-ocp.$BASE_DOMAIN:8443

STAGING_REGISTRY=staging-registry.$BASE_DOMAIN:5000
STAGING_ARGONAUT=staging-argonaut.$BASE_DOMAIN
STAGING_OCP=https://staging-ocp.$BASE_DOMAIN:8443

QA_REGISTRY=qa-registry.$BASE_DOMAIN:5000
QA_ARGONAUT=qa-argonaut.$BASE_DOMAIN
QA_OCP=https://qa-ocp.$BASE_DOMAIN:8443



pullLatestImages() {
  local registry="$1"
  local user="$2"
  local password="$3"
  docker login -u "$user" -p "$password" "$registry"
  for app in $APPS; do docker pull $DOCKER_SOURCE_ORG/${app}:latest; done
  docker pull $DOCKER_SOURCE_ORG/agent-k
  docker logout "$registry"
}

pushToOpenshiftRegistry() {
  local ocp="$1"
  local registry="$2"
  oc login "$ocp" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify
  oc project $OCP_PROJECT
  docker login -p $(oc whoami -t) -u unused $registry
  for app in $APPS
  do
    docker tag $DOCKER_SOURCE_ORG/${app}:latest ${registry}/$OCP_PROJECT/${app}:latest
    docker push ${registry}/$OCP_PROJECT/${app}:latest
  done
  docker logout $registry
}

waitForPodsToBeRunning() {
  local ocp="$1"
  local project="$2"
  local timeout=$(($(date +%s) + 600 ))
  echo "============================================================"
  echo "Waiting for pods to start ..."
  sleep 25s
  local running=false
  for label in $POD_LABELS
  do
    running=false
    echo "Waiting on $label ..."
    while [ $(date +%s) -lt $timeout ]
    do
      sleep 5
      curl -sk \
        -H "Authorization: Bearer $OPENSHIFT_API_TOKEN" \
        -H "Accept: application/json" \
        $ocp/api/v1/namespaces/$project/pods?labelSelector=app=$label \
        > pods.json

      local numberOfPods=$(jq '.items | length' pods.json)
      [ "$numberOfPods" == 0 ] && echo "   No $label pods exist" && continue
      
      local podsNotRunning=$(jq -r .items[].status.phase pods.json \
        | grep -v "Running" \
        | wc -l)
      echo "   $podsNotRunning $label pods not ready"
      [ "$podsNotRunning" == 0 ] && running=true && break
    done
    if [ $running == false ]
    then
      echo "ERROR: Timed out waiting for pods to start, aborting."
      echo "OMG! BECKY! This is not happening! I'm like, literally dying right now."
      exit 1
    fi
  done
  return 0
}

runTests() {
  local collection="$1"
  echo "============================================================"
  local now=$(date +%s)
  echo "Running test collection $collection"
  docker run --rm \
    -e JARGONAUT=true \
    -e TOKEN=$ARGONAUT_TOKEN \
    -e REFRESH_TOKEN=$ARGONAUT_REFRESH_TOKEN \
    -e CLIENT_ID=$ARGONAUT_CLIENT_ID \
    -e CLIENT_SECRET=$ARGONAUT_CLIENT_SECRET \
    --network=host \
    $DOCKER_SOURCE_ORG/agent-k \
    $collection | tee $WORK_DIR/agentk.out
  echo "============================================================"
  echo 
  grep -E '[0-9]+ tests ran, [1-9][0-9]* failures' $WORK_DIR/agentk.out
  [ $? == 0 ] && echo "This make me sad." && exit 1
  exit 0
}

deployToQa() {
  echo "Deploying applications to QA"
#  pushToOpenshiftRegistry $QA_OCP $QA_REGISTRY
  waitForPodsToBeRunning $QA_OCP $OCP_PROJECT
  runTests VAQA-PLUTO
  [ $? != 0 ] && echo "ABORT: Failed to update QA" && exit 1
}

pullLatestImages "$DOCKER_SOURCE_REGISTRY" "$DOCKER_USERNAME" "$DOCKER_PASSWORD"
deployToQa "$QA_OCP" "$QA_REGISTRY"
