#!/usr/bin/env bash

cd $(dirname $(readlink -f $0))/upgraderator
. upgrade.conf

env | sort
echo ------------------------------------------------------------

HASH=${GIT_COMMIT:0:7}
TAG=${HEALTH_APIS_VERSION}-${HASH}
IMAGE="vasdvp/health-apis-upgraderator:$TAG"
echo "Building upgraderator $TAG"

cat <<EOF > build.conf
BUILD_DATE="$(date)"
BUILD_HASH=$HASH
BUILD_ID=$BUILD_ID
BUILD_BRANCH_NAME=$BRANCH_NAME
BUILD_URL="$BUILD_URL"
EOF

set -ex

echo ------------------------------------------------------------
docker build -t "$IMAGE" .

docker images | grep health-apis-upgraderator

echo ------------------------------------------------------------
docker run \
       --rm \
       -e ENVIRONMENT=qa \
       -e DOCKER_SOURCE_REGISTRY="$DOCKER_SOURCE_REGISTRY" \
       -e DOCKER_USERNAME="$DOCKER_USERNAME" \
       -e DOCKER_PASSWORD="$DOCKER_PASSWORD" \
       -e OPENSHIFT_USERNAME="$OPENSHIFT_USERNAME" \
       -e OPENSHIFT_PASSWORD="$OPENSHIFT_PASSWORD" \
       -e OPENSHIFT_API_TOKEN="$OPENSHIFT_API_TOKEN"
       $IMAGE
      
