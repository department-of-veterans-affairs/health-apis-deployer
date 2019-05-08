#!/usr/bin/env bash
set +x
set -euo pipefail
if [ "${DEBUG:-false}" == true ]; then
  set -x
  env | sort
fi

export PATH=$WORKSPACE:$PATH

JENKINS_DIR=$WORKSPACE/.jenkins
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"

test -n "$PRODUCT"
test -f "$WORKSPACE/products/$PRODUCT.conf"
. $WORKSPACE/products/$PRODUCT.conf


fetch-deployment-unit $DU_ARTIFACT $DU_VERSION

tar tf deployment-unit.tar.gz

exit 0


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
