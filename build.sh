#!/usr/bin/env bash


cd $(dirname $(readlink -f $0))
. upgraderator/upgrade.conf

HASH=$(git rev-parse --short HEAD)
TAG=${HEALTH_APIS_VERSION}-${HASH}

echo "Building upgraderator $TAG"

cat <<EOF > upgraderator/build.conf
BUILD_DATE="$(date)"
BUILD_HASH=$HASH
EOF
docker build -t vasdvp/health-apis-upgraderator:$TAG .
