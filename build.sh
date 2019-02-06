#!/usr/bin/env bash

cd $(dirname $(readlink -f $0))/upgraderator


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
}

buildUpgraderator() {
  echo ------------------------------------------------------------
  echo "Building upgraderator"
  docker build -t "$IMAGE" .
  docker images | grep health-apis-upgraderator
}

dockerRun() {
  docker run \
    --rm --init \
    -e ENVIRONMENT="$ENVIRONMENT" \
    -e TEST_FUNCTIONAL="$TEST_FUNCTIONAL" \
    -e TEST_CRAWL="$TEST_CRAWL" \
    -e GITHUB_USERNAME_PASSWORD="$GITHUB_USERNAME_PASSWORD" \
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
    -e TOKEN=$ARGONAUT_TOKEN \
    -e REFRESH_TOKEN=$ARGONAUT_REFRESH_TOKEN \
    -e CLIENT_ID=$ARGONAUT_CLIENT_ID \
    -e CLIENT_SECRET=$ARGONAUT_CLIENT_SECRET \
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

blueGreen() {
 dockerRun --entrypoint /upgraderator/blue-green.sh $IMAGE $@
}

deleteOldVersions() {
  echo ------------------------------------------------------------
  echo Deleting old versions
  #
  # Delete all but the last few versions deployed (except if they are either blue or green)
  #
  local blue=$(blueGreen blue-version)
  local green=$(blueGreen green-version)
  local oldVersions=$(blueGreen list-versions | awk 'NR > 3')
  echo "Found old versions: $oldVersions"
  local deleted=
  for version in $oldVersions
  do
    [ "$version" == "$blue" ] && echo "Keeping blue version $version" && continue
    [ "$version" == "$green" ] && echo "Keeping green version $version" && continue
    deleteVersion $version
    deleted+=" $version"
  done
  echo "Deleted old versions:$deleted"
}

deleteVersion() {
  local version=$1
  local deleteMe="vasdvp/health-apis-upgraderator:$version"
  echo "Deleting $version"
  dockerRun --entrypoint /upgraderator/deleterator.sh $deleteMe
  echo "Deleted $version"
}

set -e
[ "$AUTO_UPGRADE_HEALTH_APIS" == true ] && updateToLatestHealthApis
configureUpgraderator
buildUpgraderator
set +e

ENVIRONMENT=qa
dockerRun $IMAGE
[ $? != 0 ] && echo "Oh noes... " && exit 1

deleteOldVersions
echo "All done!"
exit 0


