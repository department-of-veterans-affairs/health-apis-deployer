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
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"

#
# Set up the AWS region
#
export AWS_DEFAULT_REGION=us-gov-west-1

#
# Load configuration. The following variables are expected
#
declare -x DU_ARTIFACT
declare -x DU_VERSION
declare -x DU_NAMESPACE
test -n "$PRODUCT"
test -f "$WORKSPACE/products/$PRODUCT.conf"
test -f "$WORKSPACE/products/$PRODUCT.yaml"
. $WORKSPACE/products/$PRODUCT.conf


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
echo "$K8S_DEPLOYMENT_ID" > $JENKINS_DIR/build-name


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



DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
fetch-deployment-unit $DU_ARTIFACT $DU_VERSION
extract-deployment-unit deployment-unit.tar.gz $DU_DIR $DU_DECRYPTION_KEY
validate-deployment-unit $DU_DIR
perform-substitution $DU_DIR
validate-yaml $DU_DIR/deployment.yaml $DU_NAMESPACE

UPDATED_AVAILABILITY_ZONES=
TEST_FAILURE=false
declare -x AVAILABILITY_ZONE
for AVAILABILITY_ZONE in $AVAILABILITY_ZONES
do
  echo "============================================================"
  echo "Updating availability zone $AVAILABILITY_ZONE"
  UPDATED_AVAILABILITY_ZONES="$AVAILABILITY_ZONE $UPDATED_AVAILABILITY_ZONES"
  load-balancer delete-all-rules --cluster-id $CLUSTER_ID --color green --env $VPC_NAME
  cluster-fox copy-kubectl-config
  apply-namespace-and-ingress $AVAILABILITY_ZONE $DU_DIR
  cluster-fox kubectl $AVAILABILITY_ZONE -- get ns $DU_NAMESPACE -o yaml
  echo "============================================================"
  echo "Applying kubernetes configuration"
  cluster-fox kubectl $AVAILABILITY_ZONE -- apply -v 5 -f $DU_DIR/deployment.yaml
  attach-deployment-unit-to-lb $CLUSTER_ID green $DU_HEALTH_CHECK_PATH \
    $DU_LOAD_BALANCER_RULE_PATH $DU_MIN_PRIORITY

  if ! execute-tests regression-test $AVAILABILITY_ZONE $DU_DIR $LOG_DIR
  then
    TEST_FAILURE=true
    echo "============================================================"
    echo "ERROR: REGRESSION TESTS HAVE FAILED IN $AVAILABILITY_ZONE"
    gather-pod-logs $DU_NAMESPACE $LOG_DIR
    if [ $ROLLBACK_ON_TEST_FAILURES == true ]; then break; fi
  else
    echo "SUCCESS! $AVAILABILITY_ZONE"
    # TODO ATTACH TO BLUE
  fi
done

# TODO If fail and rollback enabled, rollaback
if [ $TEST_FAILURE == true -a $ROLLBACK_ON_TEST_FAILURES == true ]
then
  echo "Rolling back $UPDATED_AVAILABILITY_ZONES"
  # TODO download old
  # TODO Load conf files
  for AVAILABILITY_ZONE in $UPDATED_AVAILABILITY_ZONES
  do
    echo "============================================================"
    echo "Rolling back $AVAILABILITY_ZONE"
    load-balancer delete-all-rules --cluster-id $CLUSTER_ID --color green --env $VPC_NAME
    apply-namespace-and-ingress $AVAILABILITY_ZONE $DU_DIR
    cluster-fox kubectl $AVAILABILITY_ZONE -- get ns $DU_NAMESPACE -o yaml
    cluster-fox kubectl $AVAILABILITY_ZONE -- apply -v 5 -f $DU_DIR/deployment.yaml
    attach-deployment-unit-to-lb $CLUSTER_ID green $DU_HEALTH_CHECK_PATH \
      $DU_LOAD_BALANCER_RULE_PATH $DU_MIN_PRIORITY

    if ! execute-tests smoke-test $AVAILABILITY_ZONE $DU_DIR $LOG_DIR
    then
      echo "============================================================"
      echo "ERROR: SMOKE TESTS HAVE FAILED IN $AVAILABILITY_ZONE"
      # TODO TRACK SMOKE TEST FAILURES FOR REPORT
    fi
    # TODO ATTACH TO BLUE
  done
fi

# TODO CLEAR GREEN
# TODO FAIL IF TEST_FAILURE exit 1



exit 0
