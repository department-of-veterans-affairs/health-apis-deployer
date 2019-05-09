#!/usr/bin/env bash
set +x
set -euo pipefail
if [ "${DEBUG:-false}" == true ]; then
  set -x
  env | sort
fi
echo ------------------------------------------------------------
echo "$0 $*"

dockerRun() {
  docker run \
    --rm --init \
    -e DEBUG="${DEBUG:-false}" \
    -e ENVIRONMENT="$ENVIRONMENT" \
    -e GITHUB_USERNAME_PASSWORD="$GITHUB_USERNAME_PASSWORD" \
    -e DOCKER_SOURCE_REGISTRY="$DOCKER_SOURCE_REGISTRY" \
    -e DOCKER_USERNAME="$DOCKER_USERNAME" \
    -e DOCKER_PASSWORD="$DOCKER_PASSWORD" \
    -e AWS_DEFAULT_REGION=us-gov-west-1 \
    -e AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
    -e AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
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
