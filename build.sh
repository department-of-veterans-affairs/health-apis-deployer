#!/usr/bin/env bash
set +x -euo pipefail
export PATH=${WORKSPACE:-.}/bin:$PATH
export BANNER_DEFAULT_SIZE=158
export STAGE_PREFIX="${VPC:-} ${PRODUCT:-}"

cat <<EOF

************************************************************
*                                                          *
*                           TODO                           *
*                                                          *
************************************************************
- Default to 'latest' deploy-tools image
- Move tools in bin to deploy-tools image
- Promotion
  - Remove additional d2-ecs check
- Test support
- Update qa configuration to use blue/green albs, ports, https
  - renable blue ALB name in initialize() below
- Re-enable timer plugin
- S3 support
************************************************************

EOF

#============================================================
onExit() {
  STATUS=$?
  banner h2 -m "Deployment"
  if ! cat .deployment/build-name; then echo "No build name"; fi
  if ! cat .deployment/description; then echo "No build description"; fi
  if [ $STATUS -ne 0 ]
  then
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
  printParameters
  export NEXUS_URL=https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases
  export ENVIRONMENT=$(vpc hyphenize -e "${VPC}")
  setShortEnvironment
  export BUILD_TIMESTAMP="$(date)"
  export ENVIRONMENT_CONFIGURATION=$(readlink -f environments/$ENVIRONMENT.conf)
  . $ENVIRONMENT_CONFIGURATION
  export WORK=$(emptyDirectory work)
  export PRODUCT_CONFIGURATION_DIR=$(emptyDirectory $WORK/product-configuration)
  export DU_DIR=$(emptyDirectory $WORK/du)
  export LOG_DIR=$(emptyDirectory $WORK/logs)
  PLUGIN_DIR=plugins
  export PLUGIN_LIB=$PLUGIN_DIR/.plugin
  export PLUGIN_SUBSTITION_DIR=$(emptyDirectory $WORK/substitions)
  export GREEN_LOAD_BALANCER_NAME=green-${ENVIRONMENT}-kubernetes
  # TODO export BLUE_LOAD_BALANCER_NAME=blue-${ENVIRONMENT}-kubernetes
  export BLUE_LOAD_BALANCER_NAME=green-${ENVIRONMENT}-kubernetes
  setDeploymentId
  echo "DEPLOYMENT_ID ..... $DEPLOYMENT_ID"
  export ECS_TASK_EXECUTION_ROLE="arn:aws-us-gov:iam::533575416491:role/project/project-jefe-role"
}

printParameters() {
cat<<EOF
VPC ............... $VPC
PRODUCT ........... $PRODUCT
DEPLOYER_VERSION .. $DEPLOYER_VERSION
DEBUG ............. $DEBUG
EOF
}

emptyDirectory() {
  local d="$1"
  if [ -d "$d" ]; then rm -rf $d; fi
  mkdir -p $d
  readlink -f $d
}

setShortEnvironment() {
  case $ENVIRONMENT in
    staging-lab) export SHORT_ENVIRONMENT=b;;
    # qa, staging, production, lab
    *) export SHORT_ENVIRONMENT=${ENVIRONMENT:0:1};;
  esac
}

setDeploymentId() {
  local suffix=d2
  local short=
  if [ "${GIT_BRANCH:-unknown}" != d2 ]
  then
    suffix=x
  fi
  local commit="${GIT_COMMIT:-0000000}"
  suffix="${suffix}-${commit:0:7}"
  short="${suffix}${commit:0:4}"
  export DEPLOYMENT_ID="$ENVIRONMENT-$BUILD_NUMBER-$suffix-$PRODUCT"
  export SHORT_DEPLOYMENT_ID="${SHORT_ENVIRONMENT}${BUILD_NUMBER}$short${PRODUCT}"
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
  deployment add-build-info \
    -b "$DEPLOYMENT_ID" \
    -d "Deploy $PRODUCT to $ENVIRONMENT" \
    -d "$DU_COORDINATES"
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
      local priority
      priority="$($plugin priority)"
      if [ -z "${priority:-}" ]
      then
        DEBUG=true $plugin priority
        abort "Failed to determine plugin priority"
      fi
      echo "$priority $(basename $plugin)" >> $pluginOrder
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



ROLLBACK_POSSIBLE=true
ROLLBACK_STARTED=
isRollingBack() { test -n "${ROLLBACK_STARTED:-}"; }
rollback() {
  if isRollingBack
  then
    echo "An error has occurred while a rollback is in progress."
    return
  fi
  if [ $ROLLBACK_POSSIBLE == false ]
  then
    echo "Rollback is no longer possible."
    deployment add-build-info \
      -u "Stage \"$(stage current)\" requested a rollback after the point of no return"
    return
  fi
  deployment add-build-info \
    -d "Stage \"$(stage current)\" failed and triggered a rollback"
  ROLLBACK_STARTED=$LIFECYCLE
  # Based on the current lifecycle, determine what lifecycles need
  # to be executed to perform rollack
  lifecycle before-rollback force
  lifecycle rollback force
  lifecycle verify-rollback force
  lifecycle after-rollback force
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
  if [ "${LIFECYCLE_STATE[verify-blue]}" != "complete" ]
  then
    echo "Deployment has not been verified, skipping."
    return
  fi
  product-configuration save \
    -e $ENVIRONMENT \
    -p $PRODUCT \
    -d $PRODUCT_CONFIGURATION_DIR
}


promote() {
  if [ "${GIT_BRANCH:-unknown}" != "d2" -o "${GIT_BRANCH:-unknown}" != "d2-ecs" ]
  then
    echo "This branch is not eligible for promotion"
    return
  fi
  local promotesTo
  promotesTo=( $(environment promotes-to-vpc -e $ENVIRONMENT) )
  if [ "${#promotesTo[@]}" -eq 0 ]
  then
    echo "Environment $ENVIRONMENT is not eligible for automatic promotion"
    return
  fi
  echo "Promoting to: ${promotesTo[@]}"
  local promotedTo=()
  local nextEnvironment
  for vpc in ${promotesTo[@]}
  do
    nextEnvironment=$(vpc hyphenize -e $vpc)
    if [ ! -f $DU_DIR/${nextEnvironment}.conf ]
    then
      echo "Product does not have ${nextEnvironment}.conf and not eligible for promotion to $vpc."
      continue
    fi
    echo "Scheduling promotion to $vpc"
    promotedTo+=($vpc)
    jenkins build \
      -u "$PROMOTATRON_USERNAME_PASSWORD" \
      -o department-of-veterans-affairs \
      -r health-apis-deployer \
      -b d2 \
      -p VPC=$vpc,DEPLOYER_VERSION=$DEPLOYER_VERSION,PRODUCT=$PRODUCT
  done
  if [ ${#promotedTo[@]} -gt 0 ]
  then
    echo "Promoted $PRODUCT to: ${promotedTo[@]}"
    deployment add-build-info -d "Promoted to ${promotedTo[@]}"
  fi
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
      printf "%-20s [%s]\n" "$lifecycle" "$state"
      if [ $state != "complete" ]; then errorCode=1; fi
    done
  fi
  if [ $errorCode -eq 0 ]; then promote; fi
  echo "Goodbye"
  exit $errorCode
}

main() {
  initDebugMode
  productConfiguration
  initializePlugins
  lifecycle initialize
  lifecycle validate
  lifecycle before-deploy-green
  lifecycle deploy-green
  lifecycle verify-green
  lifecycle switch-to-blue
  lifecycle verify-blue
  ROLLBACK_POSSIBLE=false
  lifecycle after-verify-blue

  lifecycle finalize force
  recordDeployment
  goodbye
}

initialize
main 2>&1
exit 0
