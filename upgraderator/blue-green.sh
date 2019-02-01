#!/usr/bin/env bash

usage() {
cat <<EOF

$0 [options] <command>

Configure blue green roll out of services.

Options
 -h, --help              Print this help and exit
 -g, --green <version>   The green version

Commands
 TODO

$1
EOF
exit 1
}

BASE=$(dirname $(readlink -f $0))
[ -z "$WORK" ] && WORK=.
BLUE="blue"
GREEN="green"
export OPENSHIFT_PROJECT=$(oc project -q)
OPENSHIFT=$(oc whoami --show-server)
TOKEN=$(oc whoami --show-token)


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
  updateRoute green && echo "Green route updated"
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
  updateRoute blue && echo "Blue route updated"  
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

case $COMMAND in
  pull) doPull;;
  green-route) doGreenRoute;;
  blue-route) doBlueRoute;;
esac




exit 0
curl -k -H "Authorization: Bearer $(oc whoami --show-token)" $(oc whoami --show-server)/oapi/v1/namespaces/vasdvp/routes/green > green.json
sed -e 's/argonaut-1-0-161-2a3447a-79/--TMP--/' -e 's/argonaut-1-0-161-aa5f9e9-80/argonaut-1-0-161-2a3447a-79/' -e 's/--TMP--/argonaut-1-0-161-aa5f9e9-80/' green.json > green2.json

