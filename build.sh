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
export BUILD_DATE="$(date)"
export BUILD_HASH=$HASH
export BUILD_ID=$BUILD_ID
export BUILD_BRANCH_NAME=$BRANCH_NAME
export BUILD_URL="$BUILD_URL"
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
       -e OPENSHIFT_API_TOKEN="$OPENSHIFT_API_TOKEN" \
       --privileged \
       --group-add 497 \
       -v /etc/passwd:/etc/passwd:ro \
       -v /etc/group:/etc/group:ro \
       -v /var/lib/jenkins/.ssh:/root/.ssh \
       -v /var/run/docker.sock:/var/run/docker.sock \
       -v /var/lib/docker:/var/lib/docker \
       -v /etc/docker/daemon.json:/etc/docker/daemon.json \
       $IMAGE
      
