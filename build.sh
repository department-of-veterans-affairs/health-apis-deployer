#!/usr/bin/env bash
set +x -euo pipefail
export PATH=${WORKSPACE:-.}/bin:$PATH

cat <<EOF


--- TODO ---
- Default to 'latest' deploy-tools image


EOF

#============================================================
onExit() {
  STATUS=$?
  if [ $STATUS -ne 0 ]
  then
    STAGE="$(stage current)"
    deployment add-build-info \
      -d "Stage \"$STAGE\" failed with status $STATUS"
    stage start -s "CRASH AND BURN"
    echo "OH NOES! SOMETHING BORKED!"
    echo "TERMINATING WITH STATUS: $STATUS"
  fi
  exit $STATUS
}
trap onExit EXIT

#============================================================
initialize() {
  stage start -s "Initializing"
  export NEXUS_URL=https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases
  if [ -z "${VPC:-}" ]; then VPC=Dev; fi
  export ENVIRONMENT=$(vpc hyphenize -e "${VPC}")
  export BUILD_TIMESTAMP="$(date)"
  setDeploymentId
}

setDeploymentId() {
  local prefix=
  local short=
  if [ "${GIT_BRANCH:-unknown}" != master ]
  then
    local commit="${GIT_COMMIT:-0000000}"
    prefix="x-${commit:0:7}-"
    short="x${commit:0:4}"
  fi
  export DEPLOYMENT_ID="$prefix$ENVIRONMENT-$PRODUCT-$BUILD_NUMBER"
  export SHORT_DEPLOYMENT_ID="$short${ENVIRONMENT:0:1}${PRODUCT}${BUILD_NUMBER}"
}

#============================================================
initDebugMode() {
  if [ "${DEBUG:=false}" == true ]; then
    set -x
    env | sort
  fi
  export DEBUG
}

main() {
  initDebugMode
  deployment add-build-info \
    -b "$DEPLOYMENT_ID" \
    -d "ENVIRONMENT ... $(vpc hyphenize -e "$VPC")"
}

initialize
main 2>&1
exit 0
