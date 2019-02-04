#!/usr/bin/env bash

usage() {
cat <<EOF

$0 [options] <command>

Configure blue green roll out of services.

Options
 -h, --help                     Print this help and exit
 -b, --blue-version <version>   The desired blue version
 -g, --green-version <version>  The desired green version
 -p, --green-percent <number>   A number between 0 and 100 representing the
                                percentage of traffic to direct to the green 
                                deployment


Commands
 blue-route [--blue-version b] --green-version g --green-percent p
   Set the deployments and percetanges used the blue route. If --blue-version is not specified
   the current blue deployment is used.
 blue-version
   Print the blue version
 green-route --green-version g
   Set deployment for the green route
 green-version
   Print the green version
 list-versions
   List all currently deployed versions
 pull
   Pull route configuration for both blue and green deployments

$1
EOF
exit 1
}

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh
[ -z "$WORK" ] && WORK=.
BLUE="blue"
GREEN="green"

pullRoute() {
  local color=$1
  local status=$(curl -sk -H "Authorization: Bearer $TOKEN" \
    -o $color.json \
    -w "%{http_code}" \
    $OPENSHIFT/oapi/v1/namespaces/$OPENSHIFT_PROJECT/routes/$color)
  [ "$status" != 200 ] && echo "Failed to pull $color route ($status)" && cat $color.json && exit 0
  return 0
}

updateRoute() {
  local color=$1
  local status=$(curl -sk -H "Authorization: Bearer $TOKEN" \
     -o $color-update-response.json \
     -w "%{http_code}" \
     -X PUT \
     -H "Content-Type: application/json" \
     -d @$color-update.json \
     $OPENSHIFT/oapi/v1/namespaces/$OPENSHIFT_PROJECT/routes/$color)
  [ "$status" != 200 ] && echo "Failed to update $color route ($status)" && cat $color-update-response.json && exit 0
  return 0
}

extractDeploymentVersion() {
  local color=$1
  jq -r .spec.to.name $color.json | sed 's/^[^-]*-//' 
}

extractUid() {
  local color=$1
  jq -r .metadata.uid $color.json
}

extractResourceVersion() {
  local color=$1
  jq -r .metadata.resourceVersion $color.json
}

extractRouteIp() {
  local color=$1
  jq -r .spec.host $color.json
}

extractIngressHost() {
  local color=$1
  jq -r .status.ingress[0].host $color.json
}


doPull() {
  echo "Pulling route definitions"
  pullRoute blue
  pullRoute green
  echo "Blue .... $(extractDeploymentVersion blue) ($(readlink -f blue.json))"
  echo "Green ... $(extractDeploymentVersion green) ($(readlink -f green.json))"
}

doGreenRoute() {
  [ -z "$GREEN_VERSION" ] && usage "Green version not specified"
  pullRoute green
  export GREEN_ROUTE_UID=$(extractUid green)
  export GREEN_ROUTE_RESOURCE_VERSION=$(extractResourceVersion green)
  export GREEN_ROUTE_IP=$(extractRouteIp green)
  export GREEN_INGRESS_HOST=$(extractIngressHost green)
  cat $BASE/green.json.template | envsubst > green-update.json
  updateRoute green && echo "Green route updated to $GREEN_VERSION"
}

doBlueRoute() {
  [ -z "$GREEN_VERSION" ] && usage "Green version not specified"
  [ -z "$GREEN_PERCENT" ] && usage "Green percentage not specified"
  [ $GREEN_PERCENT -lt 0 -o $GREEN_PERCENT -gt 100 ] && usage "Green percent must be between 0 and 100"
  pullRoute blue
  [ -z "$BLUE_VERSION" ] && export BLUE_VERSION=$(extractDeploymentVersion blue)
  export BLUE_ROUTE_UID=$(extractUid blue)
  export BLUE_ROUTE_RESOURCE_VERSION=$(extractResourceVersion blue)
  export BLUE_ROUTE_IP=$(extractRouteIp blue)
  export BLUE_INGRESS_HOST=$(extractIngressHost blue)
  export BLUE_PERCENT=$((100-$GREEN_PERCENT))
  cat $BASE/blue.json.template | envsubst > blue-update.json
  updateRoute blue && \
    echo "Blue route updated to $BLUE_VERSION (${BLUE_PERCENT}%), $GREEN_VERSION (${GREEN_PERCENT}%)"  
}

doListVersions() {
  oc get dc \
    | awk '{print $1}' \
    | grep -- '-[0-9]\+-[0-9]\+-[0-9]\+-[0-9]\+-[a-z0-9]\+$' \
    | sed 's/^[-a-z]\+-//' \
    | sort -urV
}

doPrintVersion() {
  local color=$1
  pullRoute $color
  extractDeploymentVersion $color
}

ARGS=$(getopt -n $(basename $0) \
    -l "blue-version:,debug,green-percent:,green-version:,help" \
    -o "b:g:hp:" -- "$@")
[ $? != 0 ] && usage
eval set -- "$ARGS"

while true
do
  case "$1" in
    --debug) set -x;;
    -g|--green-version) export GREEN_VERSION="$2";;
    -p|--green-percent) export GREEN_PERCENT="$2";;
    -b|--blue-version) export BLUE_VERSION="$2";;
    -h|--help) usage;;
    --) shift; break;;
  esac
  shift
done

[ $# == 0 ] && usage "No command specified"
COMMAND=$1

loginToOpenShift > /dev/null
OPENSHIFT=$(oc whoami --show-server)
TOKEN=$(oc whoami --show-token)

case $COMMAND in
  blue-route) doBlueRoute;;
  blue-version) doPrintVersion "blue";;
  green-route) doGreenRoute;;
  green-version) doPrintVersion "green";;
  list-versions) doListVersions;;
  pull) doPull;;
  *) usage "Unknown command: $COMMAND";;
esac

exit 0
