#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh

deleteResources() {
  local type=$1
  local path=$2
  echo ============================================================
  echo "Deleting $VERSION $type"
  curl \
    -k \
    -X DELETE \
    -H "Authorization: Bearer $(oc whoami --show-token)" \
    $(oc whoami --show-server)$path?labelSelector=version=$VERSION
  
}

loginToOpenShift
deleteResources "routes" /oapi/v1/namespaces/${OPENSHIFT_PROJECT}/routes
deleteResources "services" /api/v1/namespaces/${OPENSHIFT_PROJECT}/services
deleteResources "deployment configurations" /oapi/v1/namespaces/${OPENSHIFT_PROJECT}/deploymentconfigs
deleteResources "replication controllers" /api/v1/namespaces/${OPENSHIFT_PROJECT}/replicationcontrollers
deleteResources "pods" /api/v1/namespaces/${OPENSHIFT_PROJECT}/pods

 
 
