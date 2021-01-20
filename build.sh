#!/usr/bin/env bash

#
# Disable debugging unless explicitly set
#
set +x
if [ -z "$DEBUG" ]; then DEBUG=false; fi
export DEBUG
if [ "${DEBUG}" == true ]; then
  set -x
  env | sort
fi

#
# Ensure that we fail fast on any issues.
#
set -euo pipefail

#
# Make our utilities available on the path and set up the caching mechanism
#
export PATH=$WORKSPACE/bin:$PATH
export CACHE_DIR=$(readlink -f $(mktemp -p . -d cache.XXXX ))


#
# Set up a mechanism to communicate job descriptions, etc. so that Jenkins provides more meaningful pages
#
JENKINS_DIR=$WORKSPACE/.jenkins
declare -x JENKINS_DESCRIPTION=$JENKINS_DIR/description
JENKINS_BUILD_NAME=$JENKINS_DIR/build-name
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"

#
# Set up the AWS region
#
export AWS_DEFAULT_REGION=us-gov-west-1
#
# Attempt to handle throttling on the client side:
# See https://github.com/aws/aws-cli/blob/develop/awscli/topics/config-vars.rst#general-options
# https://github.com/aws/aws-cli/blob/develop/awscli/topics/config-vars.rst#retry-configuration
#
export AWS_RETRY_MODE=adaptive
export AWS_MAX_ATTEMPTS=5

#
# Load the environment configuration
#
test -n "$ENVIRONMENT"
test -f "$WORKSPACE/environments/$ENVIRONMENT.conf"
. "$WORKSPACE/environments/$ENVIRONMENT.conf"
DEFAULT_CLUSTER_ID=$CLUSTER_ID
# Save and Source(TM) Custom Environment if exists
# This will overwrite any values set by the <env>.conf
if [ "$CUSTOM_CLUSTER_ID" != "default" ]
then
  echo "CUSTOM_CLUSTER_ID has been set. Skipping load balancer and rollback..."
  CLUSTER_ID="$CUSTOM_CLUSTER_ID"
  declare -x SKIP_LOAD_BALANCER=true
  ROLLBACK_ON_TEST_FAILURES=false
else
  declare -x SKIP_LOAD_BALANCER=false
fi

echo "Using cluster $CLUSTER_ID"
DEPLOYED_CLUSTER_ID=$CLUSTER_ID

echo "$DEFAULT_CLUSTER_ID $DEPLOYED_CLUSTER_ID" | jq -R 'split(" ")|{defaultClusterID:.[0], deployedToClusterID:.[1]}' > metadata.json

#
# List Load-Balancer Rules and check for problems
# Set +e so we don't fail here
#
set +e
LB_RULES=$(mktemp)
./list-load-balancer-rules > $LB_RULES
LB_RULES_STATUS=$?

INGRESS_RULES=$(mktemp)
./list-ingress-rules > $INGRESS_RULES
INGRESS_RULES_STATUS=$?
set -e

if [ -z "${PRODUCT:-}" ] || [ "$PRODUCT" == "none" ]
then
  deployment-status $DEFAULT_CLUSTER_ID
  echo "Deployer upgrade" >> $JENKINS_BUILD_NAME
  echo "Deployer upgraded. Nothing deployed." >> $JENKINS_DESCRIPTION
  echo "Building nothing."
  echo "Good day, sir."
  echo
  echo "I SAID GOOD DAY, SIR!"
  echo "============================================================"
  echo "Load Balancer Rules:"
  cat $LB_RULES
  echo "============================================================"
  echo "Ingress Rules:"
  cat $INGRESS_RULES
  echo "============================================================"
  [ $LB_RULES_STATUS != 0 ] \
    || [ $INGRESS_RULES_STATUS != 0 ] \
    && exit 1
  exit 0
fi

# If at any point we encounter a bad load-balancer rule or ingress rule  on a build with a valid product
# (new or otherwise) fail fast and make the rule discrepancy known.
[ $LB_RULES_STATUS != 0 ] && cat $LB_RULES && exit 1
[ $INGRESS_RULES_STATUS != 0 ] && cat $INGRESS_RULES && exit 1

#
# Load configuration. The following variables are expected
#
test -n "$PRODUCT"
test -f "$WORKSPACE/products/$PRODUCT.conf"
test -f "$WORKSPACE/products/$PRODUCT.yaml"
declare -x DU_ARTIFACT
declare -x DU_VERSION
declare -x DU_NAMESPACE
declare -x DU_DECRYPTION_KEY
declare -x DU_HEALTH_CHECK_PATH
declare -xA DU_LOAD_BALANCER_RULES # Associative array of priority to path
declare -x DU_PROPERTY_LEVEL_ENCRYPTION
declare -x DU_HEALTH_CHECK_STATUS

declare -x WEAK_STRUCTURE_VALIDATION
. $WORKSPACE/products/$PRODUCT.conf
test -n "$DU_ARTIFACT"
test -n "$DU_VERSION"
test -n "$DU_NAMESPACE"
if [ "$DU_NAMESPACE" == "default" ]; then
  echo "Default namespace is not allowed. Please use a different namespace." && exit 1
fi
test -n "$DU_DECRYPTION_KEY"
test -n "$DU_HEALTH_CHECK_PATH"
test -n "${#DU_LOAD_BALANCER_RULES[@]}"


LEAVE_ON_GREEN=false

if [ "${DONT_REATTACH_TO_BLUE:-false}" == true ]; then

  # Please don't try to put all targets on the green load balancer...
  # That's never a good idea...
  [ "${AVAILABILITY_ZONES:-automatic}" == "automatic" ] \
    && echo "Failed to meet all criteria for DONT_REATTACH_TO_BLUE: TOO MANY AZs SELECTED" \
    && echo "Failed to meet all criteria for DONT_REATTACH_TO_BLUE" >> $JENKINS_DESCRIPTION \
    && exit 1

  # If only 3 targets (one AZs worth) is available on blue;
  # you'll get nothing and like it...
  RULE_ONE=$(echo "${DU_LOAD_BALANCER_RULES[@]}" | awk '{print $1}')

  HEALTHY_TARGET_COUNT=$(load-balancer rule-health --env $VPC_NAME --cluster-id $CLUSTER_ID --color blue --rule-path "$RULE_ONE" \
    | sed 's/ /\n/g' \
    | grep -c -E '^healthy$')

  if [ $HEALTHY_TARGET_COUNT -gt 3 ]
  then
    echo "Leaving everything attached to green in $AVAILABILITY_ZONES..."
    echo "Rollback has been disabled..."
    declare -x LEAVE_ON_GREEN=true
    ROLLBACK_ON_TEST_FAILURES=false
    touch ./.jenkins_unstable
  else
    echo "Failed to meet all criteria for DONT_REATTACH_TO_BLUE: NOT ENOUGH HEALTHY TARGETS ($HEALTHY_TARGET_COUNT)"
    echo "Failed to meet all criteria for DONT_REATTACH_TO_BLUE" >> $JENKINS_DESCRIPTION
    exit 1
  fi
fi

#
# Here's a sad work around ...
# Arrays can't be exported. To prevent tools for sourcing product conf files
# We'll save the load balancer rules to a well known file that can be sources
# by support scripts
#
export LOAD_BALANCER_RULES="$WORKSPACE/lb-rules.conf"
declare -p DU_LOAD_BALANCER_RULES > $LOAD_BALANCER_RULES

#
# If we're in the DANGER ZONE, DU_VERSION might have been overwritten, lets check.
#
test -n "$DANGER_ZONE_DU_VERSION"
if [ "$DANGER_ZONE_DU_VERSION" != "default" -a "$DANGER_ZONE" == "true" ]
then
  DU_VERSION="$DANGER_ZONE_DU_VERSION"
fi


#
# If we're in the DANGER ZONE, never roll back
#
test -n "$DANGER_ZONE"
if [ "$DANGER_ZONE" == "true" ]
then
  echo "You are now entering the danger zone... rollback on test failures is disabled!"
  ROLLBACK_ON_TEST_FAILURES=false
fi

#
# Create a build ID based on product, version, Jenkins job, etc.
#
HASH=${GIT_COMMIT:0:7}
if [ -z "$HASH" ]; then HASH=DEV; fi
export BUILD_DATE="$(TZ=America/New_York date --iso-8601=minutes | tr -d :)"
export BUILD_HASH=$HASH
export BUILD_ID=${BUILD_ID:-NONE}
export BUILD_BRANCH_NAME=${BRANCH_NAME:-NONE}
export BUILD_URL="${BUILD_URL:-NONE}"
export K8S_DEPLOYMENT_ID="${BUILD_ID}-$PRODUCT-$(echo ${DU_VERSION}|tr . -)-${HASH}"
echo "$K8S_DEPLOYMENT_ID" > $JENKINS_BUILD_NAME

export DU_S3_FOLDER="$K8S_DEPLOYMENT_ID"

#
# Make a place to collect logs
#
export LOG_DIR=$K8S_DEPLOYMENT_ID-logs
if [ -d "$LOG_DIR" ]; then rm -rf "$LOG_DIR"; fi
mkdir $LOG_DIR

trap archiveLogs EXIT
archiveLogs() {
  zip -r $LOG_DIR.zip $LOG_DIR
  rm -rf $LOG_DIR
}


#
# Determine which Availability Zones to deploy into
#
if [ "$AVAILABILITY_ZONES" == "automatic" ]
then
  DEPLOYMENT_MODE="automatic"
  echo "Discovering availibility zones"
  AVAILABILITY_ZONES="$(cluster-fox list-availability-zones)"
  test -n "$AVAILABILITY_ZONES"
fi


#
# Determine what is previously installed
#
PRIOR_CONF=$K8S_DEPLOYMENT_ID-prior.conf
cluster-fox copy-kubectl-config
record-currently-installed-version ${AVAILABILITY_ZONES%% *} $PRIOR_CONF
. $PRIOR_CONF

export DEPLOYMENT_INFO_TEXT=deployment-info.txt

cat <<EOF >> $DEPLOYMENT_INFO_TEXT
============================================================
Product ............... $PRODUCT
Deployment Unit ....... $DU_ARTIFACT ($DU_VERSION)
Environment ........... $ENVIRONMENT ($VPC_NAME VPC) ($CLUSTER_ID)
Availability Zones .... $AVAILABILITY_ZONES
Deployment ID ......... $K8S_DEPLOYMENT_ID
Build ................. $BUILD_ID $BUILD_HASH ($BUILD_DATE) [$BUILD_URL]
Currently Installed ... $PRIOR_DU_ARTIFACT ($PRIOR_DU_VERSION)
Simulated Failures .... $SIMULATE_REGRESSION_TEST_FAILURE
============================================================
EOF

cat $DEPLOYMENT_INFO_TEXT

export DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
prepare-deployment-unit

callculon remove-all

UPDATED_AVAILABILITY_ZONES=
TEST_FAILURE=false
declare -x AVAILABILITY_ZONE
for AVAILABILITY_ZONE in $AVAILABILITY_ZONES
do
  #
  # If we are in automatic deployment mode,
  # And DU_AUTOMATIC_AVAILABILITY_ZONES is specified for the product,
  # we will only deploy to their request AZs.
  #
  if [ "${DEPLOYMENT_MODE:-}" == "automatic" ] && [ ! -z "${DU_AUTOMATIC_AVAILABILITY_ZONES:-}" ] && [[ "$DU_AUTOMATIC_AVAILABILITY_ZONES" != *${AVAILABILITY_ZONE: -1}* ]]
  then
   echo "Automatic Deployments are configured to skip $AVAILABILITY_ZONE"
   continue
  fi
  #
  # Capture deployed AZs for detailed jenkins description.
  #
  DEPLOYED_AVAILABILITY_ZONES="${DEPLOYED_AVAILABILITY_ZONES:-} $AVAILABILITY_ZONE"

  echo "============================================================"
  echo "Updating availability zone $AVAILABILITY_ZONE"
  UPDATED_AVAILABILITY_ZONES="$AVAILABILITY_ZONE $UPDATED_AVAILABILITY_ZONES"

  if [ "$SKIP_LOAD_BALANCER" == false ]
  then
    detach-deployment-unit-from-lb blue
    #
    # If we are in the danger zone, skip all non-essential deployment steps.
    #
    if [ "$DANGER_ZONE" == false ]
    then
      remove-all-green-routes
    fi
  fi

  apply-namespace-and-ingress $AVAILABILITY_ZONE $DU_DIR
  echo "---"
  cluster-fox kubectl $AVAILABILITY_ZONE -- get ns $DU_NAMESPACE -o yaml
  echo "============================================================"
  echo "Applying kubernetes configuration"
  cluster-fox kubectl $AVAILABILITY_ZONE -- apply -v 5 -f $DU_DIR/deployment.yaml

  #
  # If we are in the danger zone, skip all non-essential deployment steps.
  #
  if [ "$DANGER_ZONE" == false ]
  then
    if [ "$SKIP_LOAD_BALANCER" == false ]
    then
      attach-deployment-unit-to-lb green
      wait-for-lb green
    else
      timeout=$(($(date +%s) + 300))
      while [ $(date +%s) -lt $timeout ]
      do
        sleep 1
        podsReady='true'
        for podStatus in $(cluster-fox kubectl $AVAILABILITY_ZONE -- get pods -n $DU_NAMESPACE --no-headers=true | grep -v 'Completed' | awk '{print $2}')
        do
          if [ "$(echo "$podStatus" | rev )" != "$podStatus" ]
          then
            podsReady='false'
          fi
        done
        [ "$podsReady" == 'false' ] && echo "Pods not Ready ($DU_NAMESPACE)..." && continue
        echo "All pods marked as ready..."
        echo "sleeping 120"
        sleep 120
        break
      done
      [ "$podsReady" == 'false' ] \
        && echo "$PRODUCT timed out waiting for pods to become healthy" >> $JENKINS_DESCRIPTION \
        && echo "Timed out waiting for pods to be ready." \
        && exit 1
    fi

    set-test-label $AVAILABILITY_ZONE $DU_NAMESPACE "IN-PROGRESS"

    if ! execute-tests regression-test "$GREEN_LOAD_BALANCER" "$AVAILABILITY_ZONE" "$DU_DIR" "$LOG_DIR"
    then
      TEST_FAILURE=true
      echo "============================================================"
      echo "ERROR: REGRESSION TESTS HAVE FAILED IN $AVAILABILITY_ZONE"
      echo "$PRODUCT regression failure in $AVAILABILITY_ZONE" >> $JENKINS_DESCRIPTION
      gather-pod-logs $DU_NAMESPACE $LOG_DIR
      set-test-label $AVAILABILITY_ZONE $DU_NAMESPACE "FAILED"
      if [ "$ROLLBACK_ON_TEST_FAILURES" == true ]; then break; fi
    else
      set-test-label $AVAILABILITY_ZONE $DU_NAMESPACE "PASSED"
    fi

    [ "${LEAVE_ON_GREEN:-false}" == true ] \
      && echo "Leaving Targets attached to green, smoke tests ignored..." \
      && echo "TESTS_FAILED: ${TEST_FAILURE:-false}" \
      && exit 0

    [ "$SKIP_LOAD_BALANCER" == false ] \
      && [ "${LEAVE_ON_GREEN:-false}" == false ] \
      && detach-deployment-unit-from-lb green
  fi

  echo "SUCCESS! $AVAILABILITY_ZONE"
  if [ "$SKIP_LOAD_BALANCER" == false ]
  then
    attach-deployment-unit-to-lb blue
    wait-for-lb blue
  fi
done

if [ "$SKIP_LOAD_BALANCER" == false ] && ! execute-tests smoke-test "$BLUE_LOAD_BALANCER" all-azs "$DU_DIR" "$LOG_DIR"
then
  echo "============================================================"
  echo "ERROR: SMOKE TESTS HAVE FAILED"
  echo "$PRODUCT smoke test failure" >> $JENKINS_DESCRIPTION
  TEST_FAILURE=true
  if [ "$DANGER_ZONE" == false ]; then set-test-label $AVAILABILITY_ZONE $DU_NAMESPACE "FAILED"; fi
  gather-pod-logs $DU_NAMESPACE $LOG_DIR
fi


if [ "$TEST_FAILURE" == true \
     -a "$ROLLBACK_ON_TEST_FAILURES" == true \
     -a "$PRIOR_DU_ARTIFACT" != "not-installed" ]
then
  echo "Affected availability zones: $UPDATED_AVAILABILITY_ZONES"
  #
  # Override the DU_ vars to make using the utilities much easier.
  # We'll restore them once we've rolled back.
  #
  FAILED_DU_ARTIFACT=$DU_ARTIFACT
  FAILED_DU_VERSION=$DU_VERSION
  DU_ARTIFACT=$PRIOR_DU_ARTIFACT
  DU_VERSION=$PRIOR_DU_VERSION
  DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
  prepare-deployment-unit
  for AVAILABILITY_ZONE in $UPDATED_AVAILABILITY_ZONES
  do
    echo "============================================================"
    echo "Rolling back $AVAILABILITY_ZONE"
    detach-deployment-unit-from-lb blue
    remove-all-green-routes
    apply-namespace-and-ingress $AVAILABILITY_ZONE $DU_DIR
    echo "---"
    cluster-fox kubectl $AVAILABILITY_ZONE -- get ns $DU_NAMESPACE -o yaml
    echo "============================================================"
    echo "Applying kubernetes configuration"
    cluster-fox kubectl $AVAILABILITY_ZONE -- apply -v 5 -f $DU_DIR/deployment.yaml
    attach-deployment-unit-to-lb green
    wait-for-lb green

    if ! execute-tests smoke-test "$GREEN_LOAD_BALANCER" "$AVAILABILITY_ZONE" "$DU_DIR" "$LOG_DIR"
    then
      echo "============================================================"
      echo "ERROR: GREEN SMOKE TESTS HAVE FAILED IN $AVAILABILITY_ZONE ON ROLLBACK"
      echo "$PRODUCT green smoke test failure in $AVAILABILITY_ZONE on rollback" >> $JENKINS_DESCRIPTION
    fi

    set-test-label $AVAILABILITY_ZONE $DU_NAMESPACE "ROLLBACK"
    detach-deployment-unit-from-lb green
    attach-deployment-unit-to-lb blue
  done

  # make sure we clean up the new propeties
  bucket-beaver clean-up-properties --folder-name "$DU_S3_FOLDER" --bucket-name "$DU_AWS_BUCKET_NAME"

  # Restore the DU_* vars
  DU_ARTIFACT=$FAILED_DU_ARTIFACT
  DU_VERSION=$FAILED_DU_VERSION
  DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
fi


#
# Create timers
#
for timer in $(find $DU_DIR -name "timer-*json")
do
  callculon create --configuration $timer
done



#============================================================
#
# Let's do some post install activities
#
if [ "$SKIP_LOAD_BALANCER" == false ]
then
  [ "${LEAVE_ON_GREEN:-false}" == false ] && remove-all-green-routes
  echo "============================================================"

  echo "Fetching blue load balancer rules"
  load-balancer list-rules --environment $VPC_NAME --cluster-id $CLUSTER_ID --color blue > all-rules 2>&1 &
  ALL_RULES_PID=$!

fi

echo "Determining deployment status"
deployment-status $DEFAULT_CLUSTER_ID > deployment-status 2>&1 &
DEPLOYMENT_STATUS_PID=$!


if [ -z "${PRIOR_DU_S3_FOLDER:-}" ] || [ -z "${PRIOR_DU_S3_BUCKET:-}" ] || [ "$PRIOR_DU_VERSION" == "not-installed" ]
then
  echo "No previous S3 bucket. Skipping bucket deletion."
else
  # If we get here, then the build succeeded!!!!! We can delete the old du properties from s3!!!
  echo "Deleting previous deployments S3 buckets"
  bucket-beaver clean-up-properties --folder-name "$PRIOR_DU_S3_FOLDER" --bucket-name "$PRIOR_DU_S3_BUCKET" > old-buckets 2>&1 &
  OLD_BUCKETS_PID=$!
fi


BACKGROUND_TASK_FAILURES=0
waitForIt() {
  local pid="$1"
  local log="$2"
  if [ -z "$pid" ]; then return 0; fi
  if ! wait $pid
  then
    cat $log
    echo "Background process failed ($log)"
    BACKGROUND_TASK_FAILURES=$(($BACKGROUND_TASK_FAILURES + 1))
    return 1
  fi
  cat $log
  return 0
}

echo "Waiting for background tasks to complete"
waitForIt "${ALL_RULES_PID:-}" all-rules
waitForIt "${DEPLOYMENT_STATUS_PID:-}" deployment-status
waitForIt "${OLD_BUCKETS_PID:-}" old-buckets
if [ $BACKGROUND_TASK_FAILURES != 0 ]
then
  echo "Background tasks failures: $BACKGROUND_TASK_FAILURES"
  exit 1
fi

#============================================================
#
# How'd we do?
#
if [ "$TEST_FAILURE" == true ]
then
  if [ "$ENVIRONMENT" == "qa" ]
  then
    touch ./.jenkins_unstable
    exit 0
  else
    exit 1
  fi
fi

#============================================================
#
# If deployment is custom, let's use the clusterId not environment
#
if [ "$CUSTOM_CLUSTER_ID" != "default" ]
then
cat <<EOF >> $JENKINS_DESCRIPTION
  $PRODUCT deployed to CLUSTER_ID: $CLUSTER_ID ($DU_ARTIFACT $DU_VERSION)
  in availability zones: $AVAILABILITY_ZONES
EOF
else
cat <<EOF >> $JENKINS_DESCRIPTION
  $PRODUCT deployed to $ENVIRONMENT ($DU_ARTIFACT $DU_VERSION)
  in availability zones: $DEPLOYED_AVAILABILITY_ZONES
EOF
fi


if [ "$SKIP_LOAD_BALANCER" == false ]; then
  # Check for repeated rules on the load-balancer
  duplicateRules=($(cat all-rules | awk '{print $2}' | uniq -d))
  if [ "${#duplicateRules[@]}" != "0" ]; then
    echo -e "\n  Found duplicate rules on the load-balancer: ${duplicateRules[@]}" \
      | tee -a $JENKINS_DESCRIPTION
    echo "Plz do remove and deploy again."
    touch ./.jenkins_unstable
  fi
fi

echo "Goodbye."
exit 0
