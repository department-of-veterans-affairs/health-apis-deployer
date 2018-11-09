#!/usr/bin/env bash

[ -z "$OPENSHIFT_SOURCE_REGISTRY" ] && echo "Not defined: DOCKER_SOURCE_REGISTRY" && exit 1
[ -z "$OPENSHIFT_USERNAME" ] && echo "Not defined: DOCKER_USERNAME" && exit 1
[ -z "$OPENSHIFT_PASSWORD" ] && echo "Not defined: DOCKER_PASSWORD" && exit 1
[ -z "$OPENSHIFT_USERNAME" ] && echo "Not defined: OPENSHIFT_USERNAME" && exit 1
[ -z "$OPENSHIFT_PASSWORD" ] && echo "Not defined: OPENSHIFT_PASSWORD" && exit 1

APPS="
  health-apis-ids
  health-apis-mr-anderson
  health-apis-argonaut
  mule-allergy-intolerance-cdw
  mule-appointment-cdw
  mule-cdw-connector
  mule-cdw-schemas
  mule-cdw-schemas-runner
  mule-condition-cdw
  mule-diagnostic-report-cdw
  mule-encounter-cdw
  mule-immunization-cdw
  mule-location-cdw
  mule-medication-cdw
  mule-medication-order-cdw
  mule-medication-statement-cdw
  mule-observation-cdw
  mule-organization-cdw
  mule-patient-cdw
  mule-practitioner-cdw
  mule-procedure-cdw
"


DEPLOYER_HOME=$(readlink -f $(dirname $0))
export WORK_DIR=$DEPLOYER_HOME/work
BASE_DOMAIN=$BASE_DOMAIN
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
  echo --$APPS--
  docker login -u "$user" -p "$password" "$registry"
  for app in $APPS; do docker pull $DOCKER_SOURCE_ORG/${app}:latest; done
  docker logout "$registry"
}

pushOpenshiftRegistry() {
  local ocp="$1"
  local registry="$2"
  oc login "$ocp" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify
  oc project $OCP_PROJECT
  docker login -p $(oc whoami -t) -u unused $registry
  for app in $APPS
  do
    docker tag $DOCKER_SOURCE_ORG/${app}:latest ${registry}/${app}:latest
    docker push ${registry}/${app}:latest
  done
  docker logout $registry
}

deployToQa() {
  echo "Deploying applications to QA"
  pushToOpenshiftRegistry $QA_OCP $QA_REGISTRY 

}

pullLatestImages "$DOCKER_SOURCE_REGISTRY" "$DOCKER_USERNAME" "$DOCKER_PASSWORD"
deployToQa "$QA_OCP" "$QA_REGISTRY"

