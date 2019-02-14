#!/usr/bin/env bash

cd $(dirname $(readlink -f $0))/upgraderator

JENKINS_DIR=$WORKSPACE/.jenkins
[ -d "$JENKINS_DIR" ] && rm -rf "$JENKINS_DIR"
mkdir "$JENKINS_DIR"


#
# One of the following build cause environment variables will be set
# based on the trigger that initiated the build:
#
# - BUILD_BRANCH_EVENT_CAUSE
#   = Push event to branch x/upgraderator
# - BUILD_TIMER_TRIGGER_CAUSE
#   = Started by timer
# - BUILD_USER_ID_CAUSE
#   = Started by user bryan.schofield
# - BUILD_UPSTREAM_CAUSE
#   = Started by upstream project "department-of-veterans-affairs/health-apis/master" build number 6,993
#
# Automatically upgrade health APIs when the upstream health-apis project builds successfully.
[ -n "$BUILD_UPSTREAM_CAUSE" ] && echo "$BUILD_UPSTREAM_CAUSE. Enabling automatic upgrade of Health API applications." && AUTO_UPGRADE_HEALTH_APIS=true

updateToLatestHealthApis() {
  echo ------------------------------------------------------------
  echo "Determine latest version of Health APIs"
  local latest=$(curl \
    -s \
    -u "$DOCKER_USERNAME:$DOCKER_PASSWORD" \
    "https://registry.hub.docker.com/v1/repositories/vasdvp/health-apis-sentinel/tags" \
    | jq -r .[].name \
    | grep -E '([0-9]+.[0-9]+.[0-9]+)' \
    | sort -rV \
    | head -1)
  [ -z "$latest" ] && echo "Could not determine latest version" && exit 1
  . version.conf
  [ "$latest" == "$HEALTH_APIS_VERSION" ] && echo "Already configured to use $latest" && return 0
  echo "Updating to $latest"
  sed -i "s/HEALTH_APIS_VERSION=.*/HEALTH_APIS_VERSION=$latest/" version.conf
  #
  # This is annoying... Jenkins will checkout in a detached state. This means we
  # won't be able to push changes... They suggest a doing the following shell
  # step to check out the branch in an attached state. We'll also force our
  # local copy of the branch to be reset to match the Origin.
  #
  # https://support.cloudbees.com/hc/en-us/articles/227266408-current-Git-branch-is-HEAD-detached-at
  #
  git config http.sslVerify false
  git checkout -B ${BRANCH_NAME} origin/${BRANCH_NAME}
  #
  # We'll need to push tags and pom changes back to Github. We'll do that with a user with
  # elevated permissions. We'll compute a new "origin" that uses an access token. And for
  # good measure, we'll print a little debugging information.
  #
  ORIGIN=$(git remote show origin \
             | grep "Push *URL:" \
             | sed -s 's/^.*Push \+URL: //' \
             | sed "s|https://|https://$GITHUB_USERNAME_PASSWORD@|")
  git config --replace-all user.email 'vasdvp.jenkins@libertyits.com'
  git config --replace-all user.name 'jenkins'
  #
  # Now we can add our changes
  #
  git add version.conf
  git commit -m "Jenkins updated HEALTH_APIS_VERSION=$latest"
  git push $ORIGIN $BRANCH_NAME

  echo "Automatic upgrade" >> $JENKINS_DIR/description
}


configureUpgraderator() {
  echo ------------------------------------------------------------
  . version.conf
  env | sort

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

  echo "$VERSION" > $JENKINS_DIR/build-name
}

buildUpgraderator() {
  echo ------------------------------------------------------------
  echo "Building upgraderator"
  docker build -t "$IMAGE" .
  docker images | grep health-apis-upgraderator
}



set -e
[ "$AUTO_UPGRADE_HEALTH_APIS" == true ] && updateToLatestHealthApis
configureUpgraderator
buildUpgraderator
set +e

echo "Upgraderator Image built!"
exit 0
