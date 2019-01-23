#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))

WORK=$BASE/work
[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK

BUILD_INFO=$BASE/build.conf
CONF=$BASE/upgrade.conf
ENV_CONF=
[ -z "$ENVIRONMENT" ] && echo "Environment not specified" && exit 1
case $ENVIRONMENT in
  qa) ENV_CONF=$BASE/qa.conf;;
  *) echo "Unknown environment: $ENVIRONMENT" && exit 1
esac

[ -z "$BUILD_INFO" ] && echo "Build info file not found: $BUILD_INFO" && exit 1
[ ! -f "$CONF" ] && echo "Configuration file not found: $CONF" && exit 1
. $BUILD_INFO
. $CONF
. $ENV_CONF

export DOCKER_SOURCE_ORG=vasdvp
export VERSION=$(echo ${HEALTH_APIS_VERSION}|tr . -)-${BUILD_HASH}-${BUILD_ID}
PULL_FILTER='(Preparing|Waiting|already exists)'
APPS="
  health-apis-ids
  health-apis-mr-anderson
  health-apis-argonaut
"


openShiftImageName() {
  echo "${OPENSHIFT_REGISTRY}/${OPENSHIFT_PROJECT}/${1}:${HEALTH_APIS_VERSION}"
}

export IMAGE_IDS=${OPENSHIFT_INTERNAL_REGISTRY}/${OPENSHIFT_PROJECT}/health-apis-ids:${HEALTH_APIS_VERSION}
export IMAGE_MR_ANDERSON=${OPENSHIFT_INTERNAL_REGISTRY}/${OPENSHIFT_PROJECT}/health-apis-mr-anderson:${HEALTH_APIS_VERSION}
export IMAGE_ARGONAUT=${OPENSHIFT_INTERNAL_REGISTRY}/${OPENSHIFT_PROJECT}/health-apis-argonaut:${HEALTH_APIS_VERSION}

printGreeting() {
  env | sort
  echo ============================================================
  echo "Upgrading Health APIs in $ENVIRONMENT to $VERSION"
  cat $ENV_CONF | sort
  echo "Build info"
  cat $BUILD_INFO | sort
  echo "Configuration"
  cat $CONF | sort
}

pullImages() {
  echo ============================================================
  docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD" "$DOCKER_SOURCE_REGISTRY"
  for app in $APPS; do docker pull $DOCKER_SOURCE_ORG/${app}:${HEALTH_APIS_VERSION} | grep -vE "$PULL_FILTER"; done
  docker pull $DOCKER_SOURCE_ORG/health-apis-sentinel:${HEALTH_APIS_VERSION} | grep -vE "$PULL_FILTER"
  docker logout "$DOCKER_SOURCE_REGISTRY"
}

loginToOpenShift() {
  echo ============================================================
  oc login $OPENSHIFT_URL --token $OPENSHIFT_API_TOKEN --insecure-skip-tls-verify=true
  oc project $OPENSHIFT_PROJECT
}

pushToOpenShiftRegistry() {
  echo ============================================================
  echo "Updating images in $OPENSHIFT_URL ($OPENSHIFT_REGISTRY)"
  oc login "$OPENSHIFT_URL" -u "$OPENSHIFT_USERNAME" -p "$OPENSHIFT_PASSWORD" --insecure-skip-tls-verify
  oc project $OPENSHIFT_PROJECT
  docker login -p $(oc whoami -t) -u unused $OPENSHIFT_REGISTRY
  for app in $APPS
  do
    local image=$(openShiftImageName $app)
    # Deploy the new image
    echo ------------------------------------------------------------
    echo "Pushing new $app images ..."
    echo "Tagging new ${image}"
    docker tag $DOCKER_SOURCE_ORG/${app}:$HEALTH_APIS_VERSION ${image}
    echo "Pushing new ${image}"
    docker push ${image} | grep -vE "$PULL_FILTER"
  done
  docker logout $OPENSHIFT_REGISTRY
}


createDeploymentConfigs() {
  loginToOpenShift
  echo ============================================================
  
  for TEMPLATE in $(find $BASE/deployment-configs -type f -name "*.yaml")
  do
    DC=$WORK/$(basename $TEMPLATE)
    cat $TEMPLATE | envsubst > $DC
    echo ------------------------------------------------------------
    echo $DC
    cat $DC
    echo ------------------------------------------------------------
    set -x
    oc create -f $DC
  done
}


createApplicationConfigs() {
  local ac=$WORK/application-configs
  mkdir -p $ac
  for template in $(find $BASE/application-properties/$APP_CONFIG -name "*.properties")
  do
    local name=$(basename $template);
    local target=$ac/${name%.*}-$VERSION
    mkdir -p $target
    cat $template | envsubst > $target/application.properties
  done
  (cd $ac && aws s3 cp . s3://$APP_CONFIG_BUCKET/ --recursive)
}
printGreeting
pullImages
createApplicationConfigs
loginToOpenShift
pushToOpenShiftRegistry
createDeploymentConfigs







