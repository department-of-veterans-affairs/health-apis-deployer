#!/usr/bin/env bash

cd $(dirname $(readlink -f $0))/upgraderator
. upgrade.conf

env | sort
echo ------------------------------------------------------------

HASH=${GIT_COMMIT:0:7}
[ -z "$HASH" ] && HASH=DEV
VERSION="${BUILD_ID:-NONE}-$(echo ${HEALTH_APIS_VERSION}|tr . -)-${HASH}"
IMAGE="vasdvp/health-apis-upgraderator:$VERSION"
echo "Building upgraderator $VERSION"

cat <<EOF > build.conf
export VERSION="$VERSION"
export BUILD_DATE="$(date)"
export BUILD_HASH=$HASH
export BUILD_ID=${BUILD_ID:-NONE}
export BUILD_BRANCH_NAME=${BRANCH_NAME:-NONE}
export BUILD_URL="${BUILD_URL:-NONE}"
EOF

set -e

echo ------------------------------------------------------------
docker build -t "$IMAGE" .
docker images | grep health-apis-upgraderator


dockerRun() {
  docker run \
    --rm \
    -e ENVIRONMENT=qa \
    -e DOCKER_SOURCE_REGISTRY="$DOCKER_SOURCE_REGISTRY" \
    -e DOCKER_USERNAME="$DOCKER_USERNAME" \
    -e DOCKER_PASSWORD="$DOCKER_PASSWORD" \
    -e OPENSHIFT_USERNAME="$OPENSHIFT_USERNAME" \
    -e OPENSHIFT_PASSWORD="$OPENSHIFT_PASSWORD" \
    -e OPENSHIFT_API_TOKEN="$OPENSHIFT_API_TOKEN" \
    -e AWS_DEFAULT_REGION=us-gov-west-1 \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e QA_IDS_DB_USERNAME="$QA_IDS_DB_USERNAME" \
    -e QA_IDS_DB_PASSWORD="$QA_IDS_DB_PASSWORD" \
    -e PROD_IDS_DB_USERNAME="$PROD_IDS_DB_USERNAME" \
    -e PROD_IDS_DB_PASSWORD="$PROD_IDS_DB_PASSWORD" \
    -e LAB_IDS_DB_USERNAME="$LAB_IDS_DB_USERNAME" \
    -e LAB_IDS_DB_PASSWORD="$LAB_IDS_DB_PASSWORD" \
    -e QA_CDW_USERNAME="$QA_CDW_USERNAME" \
    -e QA_CDW_PASSWORD="$QA_CDW_PASSWORD" \
    -e PROD_CDW_USERNAME="$PROD_CDW_USERNAME" \
    -e PROD_CDW_PASSWORD="$PROD_CDW_PASSWORD" \
    -e LAB_CDW_USERNAME="$LAB_CDW_USERNAME" \
    -e LAB_CDW_PASSWORD="$LAB_CDW_PASSWORD" \
    -e HEALTH_API_CERTIFICATE_PASSWORD="$HEALTH_API_CERTIFICATE_PASSWORD" \
    -e PROD_HEALTH_API_CERTIFICATE_PASSWORD="$PROD_HEALTH_API_CERTIFICATE_PASSWORD" \
    --privileged \
    --group-add 497 \
    -v /etc/passwd:/etc/passwd:ro \
    -v /etc/group:/etc/group:ro \
    -v /var/lib/jenkins/.ssh:/root/.ssh \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/docker:/var/lib/docker \
    -v /etc/docker/daemon.json:/etc/docker/daemon.json \
    $@
}

echo ------------------------------------------------------------

blueGreen() {
 dockerRun --entrypoint /upgraderator/blue-green.sh $IMAGE $@
}

deleteOldVersions() {
  #
  # Delete all but the last 4 versions deployed (except if they are either blue or green)
  #
  local blue=$(blueGreen blue-version)
  local green=$(blueGreen green-version)
  local oldVersions=$(blueGreen list-versions | awk 'NR > 4')
  echo "Found old versions: $oldVersions"
  local deleted=
  for version in $oldVersions
  do
    [ "$version" == "$blue" ] && echo "Keeping blue version $version" && continue
    [ "$version" == "$green" ] && echo "Keeping green version $version" && continue
    deleteVersion $version
    deleted+=" $version"
  done
  echo "Deleted:$deleted"
}

deleteVersion() {
  local version=$1
  local deleteMe="vasdvp/health-apis-upgraderator:$version"
  echo "Deleting $version"
  dockerRun --entrypoint /upgraderator/deleterator.sh $deleteMe
}

[ -n "$SKIP_RUN" ] && exit 0

#
# Upgrade
#
#dockerRun $IMAGE


#
# Clean up
#
deleteOldVersions



