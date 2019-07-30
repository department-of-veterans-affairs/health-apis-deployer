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
# Make our utilities available on the path
#
export PATH=$WORKSPACE/bin:$PATH

#
# Set up a mechanism to communicate job descriptions, etc. so that Jenkins provides more meaningful pages
#
JENKINS_DIR=$WORKSPACE/.jenkins
JENKINS_DESCRIPTION=$JENKINS_DIR/description
JENKINS_BUILD_NAME=$JENKINS_DIR/build-name
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"

#
# Set up the AWS region
#
export AWS_DEFAULT_REGION=us-gov-west-1

#
# Load the environment configuration
#
test -n "$ENVIRONMENT"
test -f "$WORKSPACE/environments/$ENVIRONMENT.conf"
. "$WORKSPACE/environments/$ENVIRONMENT.conf"

# Save and Source(TM) Custom Environment if exists
# This will overwrite any values set by the <env>.conf
if [ "$CUSTOM_CLUSTER_ID" != "default" ]
then
  echo "CUSTOM_CLUSTER_ID has been set. Skipping load balancer and rollback..."
  CLUSTER_ID="$CUSTOM_CLUSTER_ID"
  SKIP_LOAD_BALANCER=true
  ROLLBACK_ON_TEST_FAILURES=false
else
  SKIP_LOAD_BALANCER=false
fi

echo "Using cluster $CLUSTER_ID"

if [ -z "${PRODUCT:-}" ] || [ "$PRODUCT" == "none" ]
then
  deployment-status
  echo "Deployer upgrade" >> $JENKINS_BUILD_NAME
  echo "Deployer upgraded. Nothing deployed." >> $JENKINS_DESCRIPTION
  echo "Building nothing."
  echo "Good day, sir."
  echo
  echo "I SAID GOOD DAY, SIR!"
  exit 0
fi


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
declare -x WEAK_STRUCTURE_VALIDATION
declare -x DU_HEALTH_CHECK_STATUS

. $WORKSPACE/products/$PRODUCT.conf
test -n "$DU_ARTIFACT"
test -n "$DU_VERSION"
test -n "$DU_NAMESPACE"
test -n "$DU_DECRYPTION_KEY"
test -n "$DU_HEALTH_CHECK_PATH"
test -n "${#DU_LOAD_BALANCER_RULES[@]}"

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
if [ "$AVAILABILITY_ZONES" == "all" ]
then
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


UPDATED_AVAILABILITY_ZONES=
TEST_FAILURE=false
declare -x AVAILABILITY_ZONE
for AVAILABILITY_ZONE in $AVAILABILITY_ZONES
do
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
    [ "$SKIP_LOAD_BALANCER" == false ] && detach-deployment-unit-from-lb green
  fi

  echo "SUCCESS! $AVAILABILITY_ZONE"
  if [ "$SKIP_LOAD_BALANCER" == false ]
  then
    attach-deployment-unit-to-lb blue
    wait-for-lb blue
  fi
done

if ! execute-tests smoke-test "$BLUE_LOAD_BALANCER" all-azs "$DU_DIR" "$LOG_DIR"
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

if [ "$SKIP_LOAD_BALANCER" == false ]
then
  if [ "$LEAVE_GREEN_ROUTES" == false ]; then remove-all-green-routes; fi
  echo "============================================================"

  echo "Blue Load Balancer Rules"
  load-balancer list-rules --environment $VPC_NAME --cluster-id $CLUSTER_ID --color blue

  deployment-status
fi

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

if [ -z "${PRIOR_DU_S3_FOLDER:-}" ] || [ -z "${PRIOR_DU_S3_BUCKET:-}" ] || [ "$PRIOR_DU_VERSION" == "not-installed" ]
then
  echo "No previous S3 bucket. Skipping bucket deletion."
else
  # If we get here, then the build succeeded!!!!! We can delete the old du properties from s3!!!
  echo "Deleting previous deployments S3 bucket."
  bucket-beaver clean-up-properties --folder-name "$PRIOR_DU_S3_FOLDER" --bucket-name "$PRIOR_DU_S3_BUCKET"
fi

# If deployment is custom, let's use the clusterId not environment
if [ "$SKIP_LOAD_BALANCER" == 'true' ]
then
cat <<EOF >> $JENKINS_DESCRIPTION
  $PRODUCT deployed to CLUSTER_ID: $CLUSTER_ID ($DU_ARTIFACT $DU_VERSION)
  in availability zones: $AVAILABILITY_ZONES
EOF
else
cat <<EOF >> $JENKINS_DESCRIPTION
  $PRODUCT deployed to $ENVIRONMENT ($DU_ARTIFACT $DU_VERSION)
  in availability zones: $AVAILABILITY_ZONES
EOF
fi

echo "Goodbye."
exit 0
