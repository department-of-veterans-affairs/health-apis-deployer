#!/usr/bin/env bash
set +x
set -euo pipefail
if [ "${DEBUG:-false}" != true ]; then
  DEBUG=false
  set -x
  env | sort
fi
echo ------------------------------------------------------------
echo "$0 $*"

dockerRun() {
  docker run \
    --rm --init \
    -e DEBUG="$DEBUG" \
    -e ENVIRONMENT="$ENVIRONMENT" \
    -e GITHUB_USERNAME_PASSWORD="$GITHUB_USERNAME_PASSWORD" \
    -e DOCKER_SOURCE_REGISTRY="$DOCKER_SOURCE_REGISTRY" \
    -e DOCKER_USERNAME="$DOCKER_USERNAME" \
    -e DOCKER_PASSWORD="$DOCKER_PASSWORD" \
    -e AWS_DEFAULT_REGION=us-gov-west-1 \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
    -e QA_IDS_DB_USERNAME="$QA_IDS_DB_USERNAME" \
    -e QA_IDS_DB_PASSWORD="$QA_IDS_DB_PASSWORD" \
    -e PROD_IDS_DB_USERNAME="$PROD_IDS_DB_USERNAME" \
    -e PROD_IDS_DB_PASSWORD="$PROD_IDS_DB_PASSWORD" \
    -e LAB_IDS_DB_USERNAME="$LAB_IDS_DB_USERNAME" \
    -e LAB_IDS_DB_PASSWORD="$LAB_IDS_DB_PASSWORD" \
    -e QA_LAB_IDS_DB_USERNAME="$QA_LAB_IDS_DB_USERNAME" \
    -e QA_LAB_IDS_DB_PASSWORD="$QA_LAB_IDS_DB_PASSWORD" \
    -e QA_CDW_USERNAME="$QA_CDW_USERNAME" \
    -e QA_CDW_PASSWORD="$QA_CDW_PASSWORD" \
    -e PROD_CDW_USERNAME="$PROD_CDW_USERNAME" \
    -e PROD_CDW_PASSWORD="$PROD_CDW_PASSWORD" \
    -e LAB_CDW_USERNAME="$LAB_CDW_USERNAME" \
    -e LAB_CDW_PASSWORD="$LAB_CDW_PASSWORD" \
    -e HEALTH_API_CERTIFICATE_PASSWORD="$HEALTH_API_CERTIFICATE_PASSWORD" \
    -e PROD_HEALTH_API_CERTIFICATE_PASSWORD="$PROD_HEALTH_API_CERTIFICATE_PASSWORD" \
    -e TOKEN=$ARGONAUT_TOKEN \
    -e REFRESH_TOKEN=$ARGONAUT_REFRESH_TOKEN \
    -e CLIENT_ID=$ARGONAUT_CLIENT_ID \
    -e CLIENT_SECRET=$ARGONAUT_CLIENT_SECRET \
    -e LAB_CLIENT_ID="$LAB_CLIENT_ID" \
    -e LAB_CLIENT_SECRET="$LAB_CLIENT_SECRET" \
    -e LAB_USER_PASSWORD="$LAB_USER_PASSWORD" \
    -e KUBERNETES_NODE_SSH_KEY_FILE="/root/.ssh/${KUBERNETES_SSH_CERT}" \
    --privileged \
    --group-add 497 \
    -v /etc/passwd:/etc/passwd:ro \
    -v /etc/group:/etc/group:ro \
    -v /var/lib/jenkins/.ssh:/root/.ssh \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v /var/lib/docker:/var/lib/docker \
    -v /etc/docker/daemon.json:/etc/docker/daemon.json \
    $@
  return $?
}

#============================================================

cd $(dirname $(readlink -f $0))/upgraderator

JENKINS_DIR=$WORKSPACE/.jenkins
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"

[ ! -f build.conf ] && echo "build.conf missing! There is a problem with the build stage." && exit 1
. build.conf

ENVIRONMENT=$1
[ -z "$ENVIRONMENT" ] && echo "No environment specified" && exit 1

echo "Running $UPGRADERATOR_IMAGE"
dockerRun $UPGRADERATOR_IMAGE
[ $? != 0 ] && echo "Oh noes... " && exit 1

echo "Deployment done"
exit 0
