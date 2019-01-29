#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
. $BASE/config.sh

deleteResources() {
  local type=$1
  local path=$2
  echo ============================================================
  echo "Deleting $VERSION $type"
  curl -k -X DELETE \
    -H "Authorization: Bearer $(oc whoami --show-token)" \
    $(oc whoami --show-server)$path?labelSelector=version=$VERSION
  
}

deleteServices() {
  #
  # Services delete doesn't support deleting by selector. We'll have to
  # search by label, then delete each individually
  #
  local path=/api/v1/namespaces/${OPENSHIFT_PROJECT}/services
  echo ============================================================
  echo "Deleting $VERSION services"
  curl -k -X DELETE \
    -H "Authorization: Bearer $(oc whoami --show-token)" \
    $(oc whoami --show-server)$path?labelSelector=version=$VERSION \
    | jq -c .items[].metadata.selfLink -r \
    | xargs -n 1 curl -k -X DELETE -H "Authorization: Bearer $(oc whoami --show-token)"
}


loginToOpenShift
deleteResources "routes" /oapi/v1/namespaces/${OPENSHIFT_PROJECT}/routes
deleteServices
deleteResources "deployment configurations" /oapi/v1/namespaces/${OPENSHIFT_PROJECT}/deploymentconfigs
deleteResources "replication controllers" /api/v1/namespaces/${OPENSHIFT_PROJECT}/replicationcontrollers
deleteResources "pods" /api/v1/namespaces/${OPENSHIFT_PROJECT}/pods

 
 
