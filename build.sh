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

HASH=${GIT_COMMIT:0:7}
if [ -z "$HASH" ]; then HASH=DEV; fi
export BUILD_DATE="$(TZ=America/New_York date +%Y-%m-%d-%H%M-%Z)"
export BUILD_HASH=$HASH
export BUILD_ID=${BUILD_ID:-NONE}
export BUILD_BRANCH_NAME=${BRANCH_NAME:-NONE}
export BUILD_URL="${BUILD_URL:-NONE}"
export K8S_DEPLOYMENT_ID="${BUILD_ID}-$PRODUCT-$(echo ${DU_VERSION}|tr . -)-${HASH}"
echo "$K8S_DEPLOYMENT_ID" > $JENKINS_DIR/build-name


cat <<EOF
============================================================
Product ............. $PRODUCT
Deployment Unit ..... $DU_ARTIFACT ($DU_VERSION)
Environment ......... $ENVIRONMENT
Availability Zone ... $AVAILABILITY_ZONE
Deployment ID ....... $K8S_DEPLOYMENT_ID
Build ............... $BUILD_ID $BUILD_HASH ($BUILD_DATE) [$BUILD_URL]
============================================================
EOF


DU_DIR=$WORKSPACE/$DU_ARTIFACT-$DU_VERSION
fetch-deployment-unit $DU_ARTIFACT $DU_VERSION
extract-deployment-unit deployment-unit.tar.gz $DU_DIR $DU_DECRYPTION_KEY
validate-deployment-unit $DU_DIR
perform-substitution $DU_DIR
validate-yaml $DU_DIR/deployment.yaml $DU_NAMESPACE
cluster-fox copy-kubectl-config
apply-namespace-and-ingress $DU_DIR
cluster-fox kubectl $AVAILABILITY_ZONE -- apply -f $DU_DIR/deployment.yaml


# TODO Test
# TODO If fail and rollback enabled, rollaback
# TODO capture logs from pods
# TODO publish artifacts


exit 0
