#!/usr/bin/env bash
set +x -euo pipefail
export PATH=${WORKSPACE:-.}/bin:$PATH
export BANNER_DEFAULT_SIZE=158
export STAGE_PREFIX="${VPC:-} ${PRODUCT:-}"

#
# Attempt to handle throttling on the client side:
# See https://github.com/aws/aws-cli/blob/develop/awscli/topics/config-vars.rst#general-options
# https://github.com/aws/aws-cli/blob/develop/awscli/topics/config-vars.rst#retry-configuration
#
export AWS_RETRY_MODE=adaptive
export AWS_MAX_ATTEMPTS=5


cat <<EOF

************************************************************
*                                                          *
*                           TODO                           *
*                                                          *
************************************************************
- Move tools in bin to deploy-tools image
- Graceful failure for unknown product
- extract AWS account options into confs
  - execution/autoscale roles
  - load balancer names
************************************************************

EOF

#============================================================
onExit() {
  STATUS=$?
  banner h2 -m "Deployment"
  if ! cat .deployment/build-name 2>/dev/null; then echo "No build name"; fi
  if ! cat .deployment/description 2>/dev/null; then echo "No build description"; fi
  if [ $STATUS -eq 0 ]
  then
    slackNotifications "$(slackMessageOnSuccess)" "on-exit"
  else
    stage start -s "CRASH AND BURN"
    echo "OH NOES! SOMETHING BORKED!"
    echo "TERMINATING WITH STATUS: $STATUS"
    slackNotifications "$(slackMessageOnFailure)" "on-exit"
  fi
  stage end
  if [ $STATUS  == 99 ]; then echo ABORTED; fi
  echo "Status $STATUS"
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
slackBuildDescription() {
  local title="$1"
  local code='```'
  local tick='`'
  echo "$title"
  echo "Deployment ${tick}${DEPLOYMENT_ID}${tick}"
  echo "${JOB_NAME} ${BUILD_NUMBER} (<${BUILD_URL}|Open>)"
  if [ ! -f .deployment/description ]; then return; fi
  echo "$code"
  cat .deployment/description
  echo "$code"
}
slackMessageOnStart() {
  slackBuildDescription ":rocket:   Deploying *${PRODUCT}* to *${VPC}*"
}
slackMessageOnSuccess() {
  slackBuildDescription ":smiley:   Deployed *${PRODUCT}* to *${VPC}*"
}
slackMessageOnFailure() {
  slackBuildDescription ":x:   Failed to deploy *${PRODUCT}* to *${VPC}*"
}
initializeSlack() {
  SLACK_DESTINATIONS=()
  SLACK_DESTINATIONS+=( $SLACK_DESTINATION_ALWAYS )
  if [ "$ENVIRONMENT" == "production" -o "$ENVIRONMENT" == "lab" ]
  then
    SLACK_DESTINATIONS+=( $SLACK_DESTINATION_ALWAYS_FOR_SLA )
  fi
  if [ -n "${DU_SLACK_DESTINATION:-}" ]
  then
    SLACK_DESTINATIONS+=( $DU_SLACK_DESTINATION )
  fi
  slackNotifications "$(slackMessageOnStart)"
}
slackNotifications() {
  local message="$1"
  local track="${2:-}"
  for destination in ${SLACK_DESTINATIONS[@]}
  do
    if ! slack send -d "$destination" --message "$message"
    then
      echo "Failed to send Slack notifications to $destination"
      track=
    fi
  done
  if [ -n "${track:-}" ]; then echo "${track:-sent}" > .deployment/slack-notification; fi
}

#============================================================
initialize() {
  stage start -s "Initializing"
  export BUILD_TIMESTAMP="$(date)"
  printParameters
  export NEXUS_URL=https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases
  export ENVIRONMENT=$(vpc hyphenize -e "${VPC}")
  export DEPLOYMENT_ENVIRONMENT=$ENVIRONMENT
  setShortEnvironment
  export ENVIRONMENT_CONFIGURATION=$(readlink -f environments/$ENVIRONMENT.conf)
  . $ENVIRONMENT_CONFIGURATION
  export WORK=$(emptyDirectory work)
  export PRODUCT_CONFIGURATION_DIR=$(emptyDirectory $WORK/product-configuration)
  export DU_DIR=$(emptyDirectory $WORK/du)
  export LOG_DIR=$(emptyDirectory $WORK/logs)
  export PLUGIN_DIR=plugins
  export PLUGIN_LIB=$PLUGIN_DIR/.plugin
  export PLUGIN_SUBSTITION_DIR=$(emptyDirectory $WORK/substitions)
  export GREEN_LOAD_BALANCER_NAME=green-${ENVIRONMENT}-kubernetes
  export BLUE_LOAD_BALANCER_NAME=blue-${ENVIRONMENT}-kubernetes
  setDeploymentId
  echo "DEPLOYMENT_ID ..... $DEPLOYMENT_ID"
  export ECS_TASK_EXECUTION_ROLE="arn:aws-us-gov:iam::533575416491:role/project/project-jefe-role"
  export AUTOSCALE_ROLE_ARN="arn:aws-us-gov:iam::533575416491:role/project/project-jefe-role"
  setForceDeployment
}

printParameters() {
cat<<EOF
VPC ............... $VPC
PRODUCT ........... $PRODUCT
DEPLOYER_VERSION .. $DEPLOYER_VERSION
DEBUG ............. $DEBUG
BUILD_TIMESTAMP ... $BUILD_TIMESTAMP
EOF
}

emptyDirectory() {
  local d="$1"
  if [ -d "$d" ]; then rm -rf $d; fi
  mkdir -p $d
  readlink -f $d
}

setForceDeployment() {
  if [ "${DANGER_ZONE:-false}" == "true" ]
  then
    echo "Danger zone!"
    export FORCE_DEPLOYMENT=true
    return
  fi
  if [ "${ROLLBACK_ENABLED:-true}" == "false" ]
  then
    echo "Rollbacks disabled for $ENVIRONMENT"
    export FORCE_DEPLOYMENT=true
    return
  fi
  export FORCE_DEPLOYMENT=false
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
  if [ ! -f $DU_DIR/${ENVIRONMENT}.conf ]; then abort "Missing ${ENVIRONMENT}.conf"; fi
  . $DU_DIR/${ENVIRONMENT}.conf
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
  if [ "${FORCE_DEPLOYMENT}" == "true" ]
  then
    echo "Deployment is forced. Rollback request is ignored."
    return
  fi
  if isRollingBack
  then
    echo "An error has occurred while a rollback is in progress."
    return
  fi
  if [ $ROLLBACK_POSSIBLE == false ]
  then
    echo "Rollback is no longer possible."
    deployment add-build-info \
      -u "Stage $(stage current) requested a rollback after the point of no return"
    deployment add-build-info \
      -d "Stage $(stage current) requested a rollback after the point of no return"
    return
  fi
  deployment add-build-info \
    -d "Stage $(stage current) failed and triggered a rollback"
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
  stage start -s "$LIFECYCLE"
  LIFECYCLE_STATE[$LIFECYCLE]=started
  . $(product-configuration load-script -d $PRODUCT_CONFIGURATION_DIR)
  local status=complete
  for plugin in ${PLUGINS[@]}
  do
    if ! $PLUGIN_DIR/$plugin $LIFECYCLE | awk -v plugin=$plugin '{ print "[" plugin "] " $0 }'
    then
      echo "$plugin failed to execute lifecycle $LIFECYCLE"
      deployment add-build-info -d "$plugin failed to execute lifecycle $LIFECYCLE"
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
  if [ "${PROMOTION:-auto}" == "none" ]
  then
    echo "Promotion disabled"
    return
  fi
  echo "Promoting..."
  if [ "${GIT_BRANCH:-unknown}" != "d2" -a "${GIT_BRANCH:-unknown}" != "d2-ecs" ]
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
      -b "${GIT_BRANCH}" \
      -p VPC=$vpc,DEPLOYER_VERSION=$DEPLOYER_VERSION,PRODUCT=$PRODUCT
  done
  if [ ${#promotedTo[@]} -gt 0 ]
  then
    local msg="Promoted $PRODUCT to: ${promotedTo[@]}"
    echo "$msg"
    deployment add-build-info -d "$msg"
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
  if [ $errorCode -eq 0 ]
  then
    if ! promote
    then
      echo "Failed to promote deployment"
      deployment add-build-info -d "Failed to promote deployment"
      errorCode=1
    fi
  fi
  echo "Goodbye (status $errorCode)"
  exit $errorCode
}

main() {
  initDebugMode
  productConfiguration
  initializePlugins
  initializeSlack
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
