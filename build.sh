#!/usr/bin/env bash

#
# Disable debugging unless explicitly set
#
set -x
if [ "${DEBUG:-false}" == true ]; then
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

test -n "$AVAILABILITY_ZONE"

cat <<EOF
============================================================
Product ............. $PRODUCT
Deployment Unit ..... $DU_ARTIFACT ($DU_VERSION)
Environment ......... $ENVIRONMENT
Availability Zone ... $AVAILABILITY_ZONE
============================================================
EOF


fetch-deployment-unit $DU_ARTIFACT $DU_VERSION
DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
extract-deployment-unit deployment-unit.tar.gz $DU_DIR $DU_DECRYPTION_KEY
validate-deployment-unit $DU_DIR
perform-substitution $DU_DIR
validate-yaml $DU_DIR/deployment.yaml $DU_NAMESPACE
cluster-fox copy-kubectl-config
cluster-fox kubectl us-gov-west-1a -- apply -f "$WORKSPACE/products/$PRODUCT.yaml"
cluster-fox kubectl us-gov-west-1a -- apply -f $DU_DIR/deployment.yaml
attach-deployment-unit-to-lb $CLUSTER_ID green $DU_HEALTH_CHECK_PATH \
                             $DU_LOAD_BALANCER_RULE_PATH $DU_MIN_PRIORITY


exit 0


# ======================================================================
# LEGACY CRAP BELOW DELETE ME LATER
#

configureUpgraderator() {
  echo ------------------------------------------------------------

  HASH=${GIT_COMMIT:0:7}
  [ -z "$HASH" ] && HASH=DEV
  VERSION="${BUILD_ID:-NONE}-$(echo ${PRODUCT_VERSION}|tr . -)-${HASH}"
  IMAGE="vasdvp/$PRODUCT_NAME-upgraderator:$VERSION"
  echo "Configuring $PRODUCT_NAME upgraderator $VERSION"

  cat <<EOF > build.conf
export PRODUCT_NAME="$PRODUCT_NAME"
export PRODUCT_VERSION="$PRODUCT_VERSION"
export UPGRADERATOR_IMAGE="$IMAGE"
export VERSION="$VERSION"
export BUILD_DATE="$(date)"
export BUILD_HASH=$HASH
export BUILD_ID=${BUILD_ID:-NONE}
export BUILD_BRANCH_NAME=${BRANCH_NAME:-NONE}
export BUILD_URL="${BUILD_URL:-NONE}"
EOF
  echo "$VERSION" > $JENKINS_DIR/build-name
}


configureUpgraderator
buildUpgraderator

echo ------------------------------------------------------------
echo "Upgraderator built!"
exit 0
