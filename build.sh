#!/usr/bin/env bash
set +x -euo pipefail
export PATH=${WORKSPACE:-.}/bin:$PATH

cat <<EOF


--- TODO ---
- Default to 'latest' deploy-tools image
- Promotion

EOF

#============================================================
onExit() {
  STATUS=$?
  if [ $STATUS -ne 0 ]
  then
    deployment add-build-info \
      -d "Stage \"$(stage current)\" failed with status $STATUS"
    stage start -s "CRASH AND BURN"
    echo "OH NOES! SOMETHING BORKED!"
    echo "TERMINATING WITH STATUS: $STATUS"
  fi
  stage end
  if [ $STATUS  == 99 ]; then echo ABORTED; fi
  exit $STATUS
}
trap onExit EXIT

abort() {
cat <<EOF
============================================================
ABORTING

An unrecoveralble error condition is preventing this deployment.

${1:-}
============================================================
EOF
exit 99
}


#============================================================
initialize() {
  stage start -s "Initializing"
  export NEXUS_URL=https://tools.health.dev-developer.va.gov/nexus/repository/health-apis-releases
  if [ -z "${VPC:-}" ]; then VPC=Dev; fi
  export ENVIRONMENT=$(vpc hyphenize -e "${VPC}")
  export BUILD_TIMESTAMP="$(date)"
  export ENVIRONMENT_CONFIGURATION=$(readlink -f environments/$ENVIRONMENT.conf)
  . $ENVIRONMENT_CONFIGURATION
  export WORK=$(emptyDirectory work)
  export PRODUCT_CONFIGURATION_DIR=$(emptyDirectory $WORK/product-configuration)
  export DU_DIR=$(emptyDirectory $WORK/du)
  PLUGIN_DIR=plugins
  export PLUGIN_LIB=$PLUGIN_DIR/.plugin
  export PLUGIN_SUBSTITION_DIR=$(emptyDirectory $WORK/substitions)
  setDeploymentId
}

emptyDirectory() {
  local d="$1"
  if [ -d "$d" ]; then rm -rf $d; fi
  mkdir -p $d
  echo $d
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

productConfiguration() {
  stage start -s "product configuration"
  product-configuration fetch -e $ENVIRONMENT -p $PRODUCT -d $PRODUCT_CONFIGURATION_DIR
  echo ---
  cat $(product-configuration load-script -d $PRODUCT_CONFIGURATION_DIR)
  echo ---
  . $(product-configuration load-script -d $PRODUCT_CONFIGURATION_DIR)
  deployment-unit fetch -c $DU_COORDINATES -d $DU_DIR
  if [ $DEBUG == true ]
  then
    find $PRODUCT_CONFIGURATION_DIR
    find $DU_DIR
  fi
}

initializePlugins() {
  stage start -s "plugin initialization"
  PLUGINS=()
  local pluginOrder=$WORK/plugins
  for plugin in $(find $PLUGIN_DIR -type f -name "[a-z]*")
  do
    if $plugin initialize
    then
      echo "$($plugin priority) $(basename $plugin)" >> $pluginOrder
    else
      if [ $? != 86 ]; then abort "$plugin failed to initialize"; fi
    fi
  done
  for plugin in $(sort -n $pluginOrder|awk '{print $2}')
  do
    PLUGINS+=( $(basename $plugin) )
  done
  echo "Enabled plugins: ${PLUGINS[@]}"
}

main() {
  initDebugMode
  deployment add-build-info \
    -b "$DEPLOYMENT_ID" \
    -d "ENVIRONMENT ... $(vpc hyphenize -e "$VPC")"
  productConfiguration
  initializePlugins
}

initialize
main 2>&1
exit 0
