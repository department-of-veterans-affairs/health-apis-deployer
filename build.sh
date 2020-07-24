#!/usr/bin/env bash
set +x -euo pipefail
export PATH=${WORKSPACE:-.}/bin:$PATH
export BANNER_DEFAULT_SIZE=158
export STAGE_PREFIX="${VPC:-} ${PRODUCT:-}"

cat <<EOF


--- TODO ---
- Default to 'latest' deploy-tools image
- Promotion

EOF

#============================================================
onExit() {
  STATUS=$?
  if [ $STATUS -ne 0 ]
  then
    deployment add-build-info \
      -d "Stage \"$(stage current)\" failed with status $STATUS"
    stage start -s "CRASH AND BURN"
    echo "OH NOES! SOMETHING BORKED!"
    echo "TERMINATING WITH STATUS: $STATUS"
  fi
  stage end
  if [ $STATUS  == 99 ]; then echo ABORTED; fi
  exit $STATUS
}
trap onExit EXIT

abort() {
cat <<EOF
============================================================
ABORTING

An unrecoveralble error condition is preventing this deployment.

${1:-}
============================================================
EOF
exit 99
}


#============================================================
initialize() {
  stage start -s "Initializing"
  export NEXUS_URL=https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases
  if [ -z "${VPC:-}" ]; then VPC=Dev; fi
  export ENVIRONMENT=$(vpc hyphenize -e "${VPC}")
  export BUILD_TIMESTAMP="$(date)"
  export ENVIRONMENT_CONFIGURATION=$(readlink -f environments/$ENVIRONMENT.conf)
  . $ENVIRONMENT_CONFIGURATION
  export WORK=$(emptyDirectory work)
  export PRODUCT_CONFIGURATION_DIR=$(emptyDirectory $WORK/product-configuration)
  export DU_DIR=$(emptyDirectory $WORK/du)
  PLUGIN_DIR=plugins
  export PLUGIN_LIB=$PLUGIN_DIR/.plugin
  export PLUGIN_SUBSTITION_DIR=$(emptyDirectory $WORK/substitions)
  setDeploymentId
  echo "Deployment $DEPLOYMENT_ID"
}

emptyDirectory() {
  local d="$1"
  if [ -d "$d" ]; then rm -rf $d; fi
  mkdir -p $d
  readlink -f $d
}

setDeploymentId() {
  local prefix=
  local short=
  if [ "${GIT_BRANCH:-unknown}" != d2]
  then
    local commit="${GIT_COMMIT:-0000000}"
    prefix="x-${commit:0:7}-"
    short="x${commit:0:4}"
  fi
  export DEPLOYMENT_ID="$prefix$ENVIRONMENT-$PRODUCT-$BUILD_NUMBER"
  export SHORT_DEPLOYMENT_ID="$short${ENVIRONMENT:0:1}${PRODUCT}${BUILD_NUMBER}"
}

#============================================================
initDebugMode() {
  if [ "${DEBUG:=false}" == true ]; then
    set -x
    env | sort
  fi
  export DEBUG
}

productConfiguration() {
  stage start -s "product configuration"
  product-configuration fetch -e $ENVIRONMENT -p $PRODUCT -d $PRODUCT_CONFIGURATION_DIR
  . $(product-configuration load-script -d $PRODUCT_CONFIGURATION_DIR)
  deployment-unit fetch -c $DU_COORDINATES -d $DU_DIR
  if [ $DEBUG == true ]
  then
    find $PRODUCT_CONFIGURATION_DIR
    find $DU_DIR
  fi
}

initializePlugins() {
  stage start -s "plugin initialization"
  PLUGINS=()
  local pluginOrder=$WORK/plugins
  for plugin in $(find $PLUGIN_DIR -type f -name "[a-z]*")
  do
    if $plugin activate
    then
      echo "$($plugin priority) $(basename $plugin)" >> $pluginOrder
    else
      if [ $? != 86 ]; then abort "$plugin failed to activate"; fi
    fi
  done
  for plugin in $(sort -n $pluginOrder|awk '{print $2}')
  do
    PLUGINS+=( $(basename $plugin) )
  done
  echo "Enabled plugins: ${PLUGINS[@]}"
}



ROLLBACK_STARTED=
isRollingBack() { test -n "${ROLLBACK_STARTED:-}"; }
rollback() {
  if isRollingBack
  then
    echo "An error has occurred while a rollback is in progress."
    return
  fi
  ROLLBACK_STARTED=$LIFECYCLE
  # Based on the current lifecycle, determine what lifecycles need
  # to be executed to perform rollack
  lifecycle before-rollback force
  lifecycle rollback force
  lifecycle verify-rollback force
  lifecycle after-rollback force
  echo TODO ROLLBACK
}

LIFECYCLE_HISTORY=()
declare -A LIFECYCLE_STATE
declare -x LIFECYCLE=not-started
lifecycle() {
  LIFECYCLE="$1"
  LIFECYCLE_HISTORY+=( $LIFECYCLE )
  local force="${2:-false}"
  if isRollingBack && [ "$force" == "false" ]
  then
    echo "Rollback in progress, skipping $LIFECYCLE"
    LIFECYCLE_STATE[$LIFECYCLE]=skipped
    return 0
  fi
  stage start -s "lifecycle $LIFECYCLE"
  LIFECYCLE_STATE[$LIFECYCLE]=started
  . $(product-configuration load-script -d $PRODUCT_CONFIGURATION_DIR)
  local status=complete
  for plugin in ${PLUGINS[@]}
  do
    if ! $PLUGIN_DIR/$plugin $LIFECYCLE | awk -v plugin=$plugin '{ print "[" plugin "] " $0 }'
    then
      echo "$plugin failed to execute lifecycle $LIFECYCLE"
      LIFECYCLE_STATE[$LIFECYCLE]=failed
      if ! isRollingBack; then rollback; return; fi
    fi
  done
  LIFECYCLE_STATE[$LIFECYCLE]=complete
}

recordDeployment() {
  stage start -s "save configuration"
  product-configuration save \
    -e $ENVIRONMENT \
    -p $PRODUCT \
    -d $PRODUCT_CONFIGURATION_DIR
}


promote() {
  if [ "${GIT_BRANCH:-unknown}" != "d2" ]
  then
    echo "This branch is not eligible for promotion"
    return
  fi
  local promotesTo
  promotesTo=$(environment promotes-to-vpc -e $ENVIRONMENT)
  if [ -z "${promotesTo:-}" ]
  then
    echo "Environment $ENVIRONMENT is not eligible for automatic promotion"
    return
  fi
  echo "Promoting to $promotesTo"
  for vpc in $promotesTo
  do
    echo "Promoting to $promotesTo"
    jenkins build \
      -u "$PROMOTATRON_USERNAME_PASSWORD" \
      -o department-of-veterans-affairs \
      -r health-apis-deployer \
      -b d2 \
      -p VPC=$vpc,DEPLOYER_VERSION=$DEPLOYER_VERSION,PRODUCT=$PRODUCT
  done
}

goodbye() {
  stage start -s "goodbye"
  local errorCode=0
  if [ ${#LIFECYCLE_STATE[@]} == 0 ]
  then
    echo "Lifecycle engine did not engage"
    errorCode=1
  else
    banner h2 -m "Lifecycles"
    for lifecycle in ${LIFECYCLE_HISTORY[@]}
    do
      local state=${LIFECYCLE_STATE[$lifecycle]}
      printf "%-15s [%s]\n" "$lifecycle" "$state"
      if [ $state != "complete" ]; then errorCode=1; fi
    done
  fi
  if [ $errorCode -eq 0 ]; then promote; fi
  echo "Goodbye"
  exit $errorCode
}

main() {
  initDebugMode
  deployment add-build-info \
    -b "$DEPLOYMENT_ID" \
    -d "ENVIRONMENT ... $(vpc hyphenize -e "$VPC")"
  productConfiguration
  initializePlugins

  lifecycle initialize
  lifecycle validate
  lifecycle before-deploy
  lifecycle undeploy
  lifecycle deploy
  lifecycle verify-deploy
  lifecycle after-deploy
  lifecycle finalize force

  recordDeployment
  goodbye
}

initialize
main 2>&1
exit 0
