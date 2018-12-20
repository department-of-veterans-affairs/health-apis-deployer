#!/usr/bin/env bash

#
# Pre-flight check
#
[ -z "$DOCKER_SOURCE_REGISTRY" ] && echo "Not defined: DOCKER_SOURCE_REGISTRY" && exit 1
[ -z "$DOCKER_USERNAME" ] && echo "Not defined: DOCKER_USERNAME" && exit 1
[ -z "$DOCKER_PASSWORD" ] && echo "Not defined: DOCKER_PASSWORD" && exit 1
[ -z "$OPENSHIFT_USERNAME" ] && echo "Not defined: OPENSHIFT_USERNAME" && exit 1
[ -z "$OPENSHIFT_PASSWORD" ] && echo "Not defined: OPENSHIFT_PASSWORD" && exit 1
[ -z "$ARGONAUT_TOKEN" ] &&  echo "Not defined: ARGONAUT_TOKEN" && exit 1
[ -z "$ARGONAUT_REFRESH_TOKEN" ] &&  echo "Not defined: ARGONAUT_REFRESH_TOKEN" && exit 1
[ -z "$ARGONAUT_CLIENT_ID" ] &&  echo "Not defined: ARGONAUT_CLIENT_ID" && exit 1
[ -z "$ARGONAUT_CLIENT_SECRET" ] &&  echo "Not defined: ARGONAUT_CLIENT_SECRET" && exit 1


#
# Configuration
#
JENKINS_DIR=$WORKSPACE/.jenkins
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"

AGENT_K_LOG=$WORKSPACE/agent-k.log

[ -z "$PULL_IMAGES" ] && PULL_IMAGES=false
[ -z "$QA_DEPLOY" ] && QA_DEPLOY=false
[ -z "$QA_TEST" ] && QA_TEST=false
[ -z "$LAB_DEPLOY" ] && LAB_DEPLOY=false
[ -z "$LAB_TEST" ] && LAB_TEST=false

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
  argonaut
"

BASE_DOMAIN=lighthouse.va.gov
DOCKER_SOURCE_ORG=vasdvp
OCP_PROJECT=vasdvp

PROD_REGISTRY=registry.$BASE_DOMAIN:5000
PROD_ARGONAUT=argonaut.$BASE_DOMAIN
PROD_OCP=https://ocp.$BASE_DOMAIN:8443

STANDBY_REGISTRY=standby-registry.$BASE_DOMAIN:5000
STANDBY_ARGONAUT=argonaut.$BASE_DOMAIN
STANDBY_OCP=https://standby-ocp.$BASE_DOMAIN:8443

LAB_REGISTRY=staging-registry.$BASE_DOMAIN:5000
LAB_ARGONAUT=staging-argonaut.$BASE_DOMAIN
LAB_OCP=https://staging-ocp.$BASE_DOMAIN:8443

QA_REGISTRY=qa-registry.$BASE_DOMAIN:5000
QA_ARGONAUT=qa-argonaut.$BASE_DOMAIN
QA_OCP=https://qa-ocp.$BASE_DOMAIN:8443


PULL_FILTER="(Preparing|Waiting|already exists)"

env | sort




pullLatestImages() {
  local registry="$1"
  local user="$2"
  local password="$3"
  docker login -u "$user" -p "$password" "$registry"
  for app in $APPS; do docker pull $DOCKER_SOURCE_ORG/${app}:latest | grep -vE $PULL_FILTER; done
  docker pull $DOCKER_SOURCE_ORG/agent-k | grep -vE $PULL_FILTER
  docker logout "$registry"
}

restoreImages() {
  local ocp="$1"
  local registry="$2"
  echo "============================================================"
  echo "Restoring images in $ocp ($registry)"
  oc login "$ocp" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify
  oc project $OCP_PROJECT
  docker login -p $(oc whoami -t) -u unused $registry
  for app in $APPS
  do
    echo "------------------------------------------------------------"
    echo "Restoring $app ..."
    local image=${registry}/$OCP_PROJECT/${app}
    docker tag ${image}:previous ${image}:latest
    docker push ${image}:latest
  done
  docker logout $registry
}

pushToOpenshiftRegistry() {
  local ocp="$1"
  local registry="$2"
  echo "============================================================"
  echo "Updating images in $ocp ($registry)"
  oc login "$ocp" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify
  oc project $OCP_PROJECT
  docker login -p $(oc whoami -t) -u unused $registry
  for app in $APPS
  do
    local image=${registry}/$OCP_PROJECT/${app}
    # Record the currently running image as the previous
    echo "------------------------------------------------------------"
    echo "Marking currently deployed $app image as previous ..."
    docker pull ${image}:latest | grep -vE $PULL_FILTER
    docker tag ${image}:latest ${image}:previous
    docker push ${image}:previous
    echo "------------------------------------------------------------"
    echo "Pushing new $app images ..."
    # Deploy the new image
    docker tag $DOCKER_SOURCE_ORG/${app}:latest ${image}:latest
    docker push ${image}:latest
  done
  docker logout $registry
}

waitForPodsToBeRunning() {
  local ocp="$1"
  local project="$2"
  local timeout=$(($(date +%s) + 600 ))
  echo "============================================================"
  echo "Waiting for pods to start in $ocp ..."
  sleep 20s
  (IFS=$'\n'; for l in $(cat $WORKSPACE/.messages | sort -R | head -10); do  echo "  $l"; sleep 10; done)
  local running=false
  for label in $POD_LABELS
  do
    running=false
    echo "Checking $label ..."
    while [ $(date +%s) -lt $timeout ]
    do
      curl -sk \
        -H "Authorization: Bearer $OPENSHIFT_API_TOKEN" \
        -H "Accept: application/json" \
        $ocp/api/v1/namespaces/$project/pods?labelSelector=app=$label \
        > pods.json

      local numberOfPods=$(jq '.items | length' pods.json)
      [ "$numberOfPods" == 0 ] && echo "  No $label pods exist" && sleep 5 && continue
      
      local podsNotRunning=$(jq -r .items[].status.phase pods.json \
        | grep -v "Running" \
        | wc -l)
      echo "  Waiting on $podsNotRunning $label pods"
      [ "$podsNotRunning" == 0 ] && running=true && break
      sleep 5
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
    $collection | tee $AGENT_K_LOG
  echo "============================================================"
  echo 
  local failureSummary=$(grep -E '[0-9]+ tests ran, [1-9][0-9]* failures' $AGENT_K_LOG)
  [ -z "$failureSummary" ] && echo "0 failures" > $JENKINS_DIR/build-name && return 0
  # Report failures and die!
  echo "${failureSummary#*, }" > $JENKINS_DIR/build-name
  echo "$failureSummary" > $JENKINS_DIR/description
  grep "fail " $AGENT_K_LOG | head -5  >> $JENKINS_DIR/description
  echo "This make me sad." 
  exit 1
}

deployToQa() {
  echo "============================================================"
  echo "Deploying applications to QA"
  pushToOpenshiftRegistry $QA_OCP $QA_REGISTRY
  waitForPodsToBeRunning $QA_OCP $OCP_PROJECT
  restoreImages $QA_OCP $QA_REGISTRY
  waitForPodsToBeRunning $QA_OCP $OCP_PROJECT
}

testQa() {
  echo "Testing QA"
  runTests VAQA-PLUTO
  [ $? != 0 ] && echo "ABORT: Failed to update QA" && exit 1
}

deployToLab() {
  echo "Deploying applications to Lab"
  echo "============================================================"
  echo "JK... Really deploying to QA again!"
  pushToOpenshiftRegistry $QA_OCP $QA_REGISTRY
  waitForPodsToBeRunning $QA_OCP $OCP_PROJECT
  echo "============================================================"
}

[ $PULL_IMAGES == true ] && pullLatestImages "$DOCKER_SOURCE_REGISTRY" "$DOCKER_USERNAME" "$DOCKER_PASSWORD"

[ $QA_DEPLOY == true ] && deployToQa "$QA_OCP" "$QA_REGISTRY"
[ $QA_TEST == true ] && testQa
[ $LAB_DEPLOY == true ] && deployToLab "$LAB_OCP" "$LAB_REGISTRY"

exit 0
