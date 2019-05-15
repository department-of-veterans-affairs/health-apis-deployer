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
declare -x DU_LOAD_BALANCER_RULE_PATH
declare -x DU_MIN_PRIORITY
. $WORKSPACE/products/$PRODUCT.conf
test -n "$DU_ARTIFACT"
test -n "$DU_VERSION"
test -n "$DU_NAMESPACE"
test -n "$DU_DECRYPTION_KEY"
test -n "$DU_HEALTH_CHECK_PATH"
test -n "$DU_LOAD_BALANCER_RULE_PATH"
test -n "$DU_MIN_PRIORITY"

#
# Load the environment configuration
#
test -n "$ENVIRONMENT"
test -f "$WORKSPACE/environments/$ENVIRONMENT.conf"
. "$WORKSPACE/environments/$ENVIRONMENT.conf"
echo "Using cluster $CLUSTER_ID"

#
# Create a build ID based on product, version, Jenkins job, etc.
#
HASH=${GIT_COMMIT:0:7}
if [ -z "$HASH" ]; then HASH=DEV; fi
export BUILD_DATE="$(TZ=America/New_York date +%Y-%m-%d-%H%M-%Z)"
export BUILD_HASH=$HASH
export BUILD_ID=${BUILD_ID:-NONE}
export BUILD_BRANCH_NAME=${BRANCH_NAME:-NONE}
export BUILD_URL="${BUILD_URL:-NONE}"
export K8S_DEPLOYMENT_ID="${BUILD_ID}-$PRODUCT-$(echo ${DU_VERSION}|tr . -)-${HASH}"
echo "$K8S_DEPLOYMENT_ID" > $JENKINS_BUILD_NAME


#
# Make a place to collect logs
#
export LOG_DIR=$K8S_DEPLOYMENT_ID-logs
if [ -d $LOG_DIR ]; then rm -rf $LOG_DIR; fi
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

cat <<EOF
============================================================
Product ............... $PRODUCT
Deployment Unit ....... $DU_ARTIFACT ($DU_VERSION)
Environment ........... $ENVIRONMENT ($VPC_NAME VPC) ($CLUSTER_ID)
Availability Zones .... $AVAILABILITY_ZONES
Deployment ID ......... $K8S_DEPLOYMENT_ID
Build ................. $BUILD_ID $BUILD_HASH ($BUILD_DATE) [$BUILD_URL]
Currently Installed ... $PRIOR_DU_ARTIFACT ($PRIOR_DU_VERSION)
============================================================
EOF



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

  if ! execute-tests regression-test $GREEN_LOAD_BALANCER $AVAILABILITY_ZONE $DU_DIR $LOG_DIR
  then
    TEST_FAILURE=true
    echo "============================================================"
    echo "ERROR: REGRESSION TESTS HAVE FAILED IN $AVAILABILITY_ZONE"
    echo "Regression failure in $AVAILABILITY_ZONE" >> $JENKINS_DESCRIPTION
    gather-pod-logs $DU_NAMESPACE $LOG_DIR
    if [ $ROLLBACK_ON_TEST_FAILURES == true ]; then break; fi
  fi

  echo "SUCCESS! $AVAILABILITY_ZONE"
  detach-deployment-unit-from-lb green
  attach-deployment-unit-to-lb blue

  # TODO wait for LB to be ready
  sleep 30

  if ! execute-tests smoke-test $BLUE_LOAD_BALANCER $AVAILABILITY_ZONE $DU_DIR $LOG_DIR
  then
    echo "============================================================"
    echo "ERROR: BLUE SMOKE TESTS HAVE FAILED IN $AVAILABILITY_ZONE"
    echo "Blue smoke test failure in $AVAILABILITY_ZONE" >> $JENKINS_DESCRIPTION
    TEST_FAILURE=true
    gather-pod-logs $DU_NAMESPACE $LOG_DIR
    if [ $ROLLBACK_ON_TEST_FAILURES == true ]; then break; fi
  fi
done


if [ $TEST_FAILURE == true \
     -a $ROLLBACK_ON_TEST_FAILURES == true \
     -a $PRIOR_DU_ARTIFACT != "not-installed" ]
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

    if ! execute-tests smoke-test $GREEN_LOAD_BALANCER $AVAILABILITY_ZONE $DU_DIR $LOG_DIR
    then
      echo "============================================================"
      echo "ERROR: GREEN SMOKE TESTS HAVE FAILED IN $AVAILABILITY_ZONE ON ROLLBACK"
      echo "Green smoke test failure in $AVAILABILITY_ZONE on rollback" >> $JENKINS_DESCRIPTION
    fi
    detach-deployment-unit-from-lb green
    attach-deployment-unit-to-lb blue
  done

  # Restore the DU_* vars
  DU_ARTIFACT=$FAILED_DU_ARTIFACT
  DU_VERSION=$FAILED_DU_VERSION
  DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
fi

if [ $LEAVE_GREEN_ROUTES == false ]; then remove-all-green-routes; fi
echo "============================================================"
echo "Goodbye."
if [ $TEST_FAILURE == true ]; then exit 1; fi
exit 0
