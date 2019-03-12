#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh
[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK

[ -z "$TEST_FUNCTIONAL" ] && TEST_FUNCTIONAL=true
[ -z "$TEST_CRAWL" ] && TEST_CRAWL=true

PULL_FILTER='(Preparing|Waiting|already exists)'

openShiftImageName() {
  # app, version
  echo "${OPENSHIFT_REGISTRY}/${OPENSHIFT_PROJECT}/${1}:${2}"
}

export IMAGE_IDS=${OPENSHIFT_INTERNAL_REGISTRY}/${OPENSHIFT_PROJECT}/health-apis-ids:${HEALTH_APIS_IDS_VERSION}
export IMAGE_MR_ANDERSON=${OPENSHIFT_INTERNAL_REGISTRY}/${OPENSHIFT_PROJECT}/health-apis-mr-anderson:${HEALTH_APIS_VERSION}
export IMAGE_DATA_QUERY=${OPENSHIFT_INTERNAL_REGISTRY}/${OPENSHIFT_PROJECT}/health-apis-data-query:${HEALTH_APIS_VERSION}

envVarName() {
  echo $1 | tr [:lower:] [:upper:] | tr - _
}

export DATA_QUERY_HOST_ENV="\${$(envVarName data-query-${VERSION}-service-host)}"
export DATA_QUERY_PORT_ENV="\${$(envVarName data-query-${VERSION}-service-port)}"
export MR_ANDERSON_HOST_ENV="\${$(envVarName mr-anderson-${VERSION}-service-host)}"
export MR_ANDERSON_PORT_ENV="\${$(envVarName mr-anderson-${VERSION}-service-port)}"
export IDS_HOST_ENV="\${$(envVarName universal-identity-service-${VERSION}-service-host)}"
export IDS_PORT_ENV="\${$(envVarName universal-identity-service-${VERSION}-service-port)}"

printGreeting() {
  env | sort
  echo ==== $ENVIRONMENT ========================================================
  echo "Upgrading Health APIs in $ENVIRONMENT to $VERSION"
  cat $ENV_CONF | sort
  echo "Build info"
  cat $BUILD_INFO | sort
  echo "Version Configuration"
  cat $VERSION_CONF | sort
}

pullImage() {
  # app, version
  docker pull $DOCKER_SOURCE_ORG/$1:$2 | grep -vE "$PULL_FILTER";
}

pullImages() {
  echo ==== $ENVIRONMENT ========================================================
  docker login -u "$DOCKER_USERNAME" -p "$DOCKER_PASSWORD" "$DOCKER_SOURCE_REGISTRY"
  pullImage health-apis-ids ${HEALTH_APIS_IDS_VERSION}
  pullImage health-apis-mr-anderson ${HEALTH_APIS_VERSION}
  pullImage health-apis-data-query ${HEALTH_APIS_VERSION}
  pullImage health-apis-data-query-tests ${HEALTH_APIS_VERSION}
  docker logout "$DOCKER_SOURCE_REGISTRY"
}

pushToOpenShiftRegistry() {
  # app, version
  local image=$(openShiftImageName $1 $2)
  # Deploy the new image
  echo ------------------------------------------------------------
  echo "Pushing new $1 images ..."
  echo "Tagging new ${image}"
  docker tag $DOCKER_SOURCE_ORG/$1:$2 ${image}
  echo "Pushing new ${image}"
  docker push ${image} | grep -vE "$PULL_FILTER"
}

pushAllToOpenShiftRegistry() {
  echo ==== $ENVIRONMENT ========================================================
  echo "Updating images in $OPENSHIFT_URL ($OPENSHIFT_REGISTRY)"
  loginToOpenShift
  docker login -p $(oc whoami -t) -u unused $OPENSHIFT_REGISTRY
  pushToOpenShiftRegistry health-apis-ids $HEALTH_APIS_IDS_VERSION
  pushToOpenShiftRegistry health-apis-mr-anderson $HEALTH_APIS_VERSION
  pushToOpenShiftRegistry health-apis-data-query $HEALTH_APIS_VERSION
  docker logout $OPENSHIFT_REGISTRY
}

createOpenShiftConfigs() {
  loginToOpenShift
  echo ==== $ENVIRONMENT ========================================================
  for TEMPLATE in $(find $BASE/$1 -type f -name "*.yaml")
  do
    CONFIGS=$WORK/$(basename $TEMPLATE)
    cat $TEMPLATE | envsubst > $CONFIGS
    echo ------------------------------------------------------------
    echo $CONFIGS
    cat $CONFIGS
    echo ------------------------------------------------------------
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
  echo ==== $ENVIRONMENT ========================================================
  echo "Updating green route to $VERSION"
  $BASE/blue-green.sh green-route --green-version "$VERSION"
}

transitionFromGreenToBlue() {
  echo ==== $ENVIRONMENT ========================================================
  echo "Transitioning from blue to green over $((4 * GREEN_TO_BLUE_INTERVAL)) seconds"
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

waitForGreen() {
  echo ==== $ENVIRONMENT ========================================================
  echo "Waiting for green to be ready"
  sleep 15s
  local timeout=$(($(date +%s) + 120))
  local json=$WORK/health.json
  while [ $(date +%s) -lt $timeout ]
  do
    sleep 1
    local status=$(curl -sk -w %{http_code} -o $json $GREEN_DATA_QUERY_URL/actuator/health)
    [ $status != 200 ] && echo "Green is not ready ($status)" && continue
    jq . $json
    local up=$(jq -r .status $json)
    [ "$up" != "UP" ] && echo "Green is $up" && continue
    echo "Green is ready"
    return
  done
  echo "Timeout waiting for green to be ready"
  exit 1
}

testGreenFunctional() {
  local id="data-query-tests-$VERSION"
  echo ==== $ENVIRONMENT ========================================================
  echo "Executing functional tests ($HEALTH_APIS_VERSION)"
  docker run \
    --rm --init \
    --name="$id" \
    --network=host \
    vasdvp/health-apis-data-query-tests:$HEALTH_APIS_VERSION \
    test \
    --include-category="$SENTINEL_CATEGORY" \
    -Dsentinel=$SENTINEL_ENV \
    -Daccess-token=$TOKEN \
    -Dsentinel.argonaut.url=$GREEN_DATA_QUERY_URL \
    -Dsentinel.argonaut.api-path=$GREEN_DATA_QUERY_API_PATH
  local status=$?
  [ $status != 0 ] \
    && echo "Functional tests failed" \
    && [ "$ABORT_ON_TEST_FAILURES" == true ] \
    && exit 1
}

testGreenCrawl() {
  echo ==== $ENVIRONMENT ========================================================
  echo "Executing crawler tests ($HEALTH_APIS_VERSION)"
  docker run \
    --rm --init \
    --name="$id" \
    --network=host \
    vasdvp/health-apis-data-query-tests:$HEALTH_APIS_VERSION \
    test \
    -Dsentinel=$SENTINEL_ENV \
    -Daccess-token=$TOKEN \
    -Dsentinel.argonaut.url=$GREEN_DATA_QUERY_URL \
    -Dsentinel.argonaut.api-path=$GREEN_DATA_QUERY_API_PATH \
    -Dsentinel.argonaut.url.replace=$GREEN_LINK_REPLACE_URL \
    -Djargonaut=true \
    -Dlab.user-password=$LAB_USER_PASSWORD \
    -Dlab.client-id=$LAB_CLIENT_ID \
    -Dlab.client-secret=$LAB_CLIENT_SECRET \
    $SENTINEL_CRAWLER
  local status=$?
  [ $status != 0 ] \
    && echo "Functional tests failed" \
    && [ "$ABORT_ON_TEST_FAILURES" == true ] \
    && exit 1
}

printGreeting
pullImages
createApplicationConfigs
loginToOpenShift
pushAllToOpenShiftRegistry
createOpenShiftConfigs "deployment-configs"
createOpenShiftConfigs "service-configs"
createOpenShiftConfigs "autoscaling-configs"
setGreenRoute
waitForGreen
[ "$TEST_FUNCTIONAL" == true ] && testGreenFunctional
[ "$TEST_CRAWL" == true ] &&  testGreenCrawl

echo "Transitioning to green 30 seconds" && sleep 30
transitionFromGreenToBlue
exit 0
