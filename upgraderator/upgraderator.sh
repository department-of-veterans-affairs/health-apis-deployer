#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh

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


envVarName() {
  echo $1 | tr [:lower:] [:upper:] | tr - _
}

export ARGONAUT_HOST_ENV="\${$(envVarName argonaut-${VERSION}-service-host)}"
export ARGONAUT_PORT_ENV="\${$(envVarName argonaut-${VERSION}-service-port)}"
export MR_ANDERSON_HOST_ENV="\${$(envVarName mr-anderson-${VERSION}-service-host)}"
export MR_ANDERSON_PORT_ENV="\${$(envVarName mr-anderson-${VERSION}-service-port)}"
export IDS_HOST_ENV="\${$(envVarName universal-identity-service-${VERSION}-service-host)}"
export IDS_PORT_ENV="\${$(envVarName universal-identity-service-${VERSION}-service-port)}"

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

createOpenShiftConfigs() {
  loginToOpenShift
  echo ============================================================
  for TEMPLATE in $(find $BASE/$1 -type f -name "*.yaml")
  do
    CONFIGS=$WORK/$(basename $TEMPLATE)
    cat $TEMPLATE | envsubst > $CONFIGS
    echo ----------------------------------------------------------
    echo $CONFIGS
    cat $CONFIGS
    echo ---------------------------------------------------------
    oc create -f $CONFIGS
    [ $? != 0 ] && echo "Failed to create configurations" && exit 1
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
    cat $BASE/on-start.sh.template | envsubst > $target/on-start.sh
    chmod +x $target/on-start.sh
  done
  (cd $ac && aws s3 cp . s3://$APP_CONFIG_BUCKET/ --recursive)
}

setGreenRoute() {
  echo ============================================================
  echo "Updating green route to $VERSION"
  $BASE/blue-green.sh green-route --green-version "$VERSION"
}

transitionFromGreenToBlue() {
  echo ============================================================
  echo "Transitioning from blue to green"
  for percent in 25 50 75
  do
    echo "Transitioning to ${percent}%"
    $BASE/blue-green.sh blue-route --green-version "$VERSION" --green-percent $percent
    local waitUntil=$(($(date +%s) + $GREEN_TO_BLUE_INTERVAL))
    while [ $(date +%s) -lt $waitUntil ]; do echo -n "."; sleep 15; done
    echo .
  done
  echo "Transitioning to 100%"
  $BASE/blue-green.sh blue-route --blue-version "$VERSION" --green-version "$VERSION" --green-percent 1
}

printGreeting
pullImages
createApplicationConfigs
loginToOpenShift
pushToOpenShiftRegistry
createOpenShiftConfigs "deployment-configs"
createOpenShiftConfigs "service-configs"
echo "sleeping 60" && sleep 60
createOpenShiftConfigs "autoscaling-configs"
setGreenRoute
echo "sleeping 60" && sleep 60
transitionFromGreenToBlue
