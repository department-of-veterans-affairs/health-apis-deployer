#!/usr/bin/env bash

[ -z "$DOCKER_SOURCE_REGISTRY" ] && echo "Not defined: DOCKER_SOURCE_REGISTRY" && exit 1
[ -z "$DOCKER_USERNAME" ] && echo "Not defined: DOCKER_USERNAME" && exit 1
[ -z "$DOCKER_PASSWORD" ] && echo "Not defined: DOCKER_PASSWORD" && exit 1

APPS="
  vasdvp/health-apis-ids
  vasdvp/health-apis-mr-anderson
  vasdvp/health-apis-argonaut
  vasdvp/mule-allergy-intolerance-cdw
  vasdvp/mule-appointment-cdw
  vasdvp/mule-cdw-connector
  vasdvp/mule-cdw-schemas
  vasdvp/mule-cdw-schemas-runner
  vasdvp/mule-condition-cdw
  vasdvp/mule-diagnostic-report-cdw
  vasdvp/mule-encounter-cdw
  vasdvp/mule-immunization-cdw
  vasdvp/mule-location-cdw
  vasdvp/mule-medication-cdw
  vasdvp/mule-medication-order-cdw
  vasdvp/mule-medication-statement-cdw
  vasdvp/mule-observation-cdw
  vasdvp/mule-organization-cdw
  vasdvp/mule-patient-cdw
  vasdvp/mule-practitioner-cdw
  vasdvp/mule-procedure-cdw
"
prodEnvironment() {
  TO_REGISTRY=registry.lighthouse.va.gov:5000
  TO_HOST=argonaut.lighthouse.va.gov
  TO_OCP=https://ocp.lighthouse.va.gov:8443
}

standbyEnvironment() {
  TO_REGISTRY=standby-registry.lighthouse.va.gov:5000
  TO_HOST=argonaut.lighthouse.va.gov
  TO_OCP=https://standby-ocp.lighthouse.va.gov:8443
}

stagingEnvironment() {
  TO_REGISTRY=staging-registry.lighthouse.va.gov:5000
  TO_HOST=staging-argonaut.lighthouse.va.gov
  TO_OCP=https://staging-ocp.lighthouse.va.gov:8443
}

qaEnvironment() {
  TO_REGISTRY=qa-registry.lighthouse.va.gov:5000
  TO_HOST=qa-argonaut.lighthouse.va.gov
  TO_OCP=https://qa-ocp.lighthouse.va.gov:8443
}


pullLatestImages() {
  local registry="$1"
  local user="$2"
  local password="$3"
  echo --$APPS--
  docker login -u "$user" -p "$password" "$registry"
  for app in $APPS; do docker pull ${app}:latest; done
}

#  oc login "$TO_OCP" -u "$TO_USER" -p "$TO_PW" --insecure-skip-tls-verify
#  oc project vasdvp
#  docker login -p $(oc whoami -t) -u unused $TO_REGISTRY
#  [ -z "$targetAvailable" ] && docker push $targetImage
#  docker push $TO_REGISTRY/$name:latest

deployToQa() {
  echo "Deploying applications to QA"


}

pullLatestImages "$DOCKER_SOURCE_REGISTRY" "$DOCKER_USERNAME" "$DOCKER_PASSWORD"
