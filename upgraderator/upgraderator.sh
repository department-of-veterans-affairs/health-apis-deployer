#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))

WORK=$BASE/work

BUILD_INFO=$BASE/build.conf
CONF=$BASE/upgrade.conf
ENV_CONF=
[ -z "$ENVIRONMENT" ] && echo "Environment not specified" && exit 1
case $ENVIRONMENT in
  qa) ENV_CONF=$BASE/qa.conf;;
  *) echo "Unknown environment: $ENVIRONMENT" && exit 1
esac

[ -z "$BUILD_INFO" ] && echo "Build info file not found: $BUILD_INFO" && exit 1
[ ! -f "$CONF" ] && echo "Configuration file not found: $CONF" && exit 1
. $BUILD_INFO
. $CONF
. $ENV_CONF

export VERSION=$(echo ${HEALTH_APIS_VERSION}|tr . -)-${BUILD_HASH}

echo "Upgrading Health APIs in $ENVIRONMENT to $VERSION"
cat $ENV_CONF | sort

echo "Build info"
cat $BUILD_INFO | sort

echo "Configuration"
cat $CONF | sort

echo ------------------------------------------------------------

set -x

[ -d $WORK ] && rm -rf $WORK
mkdir -p $WORK

oc login $OPENSHIFT_URL --token $OPENSHIFT_API_TOKEN --insecure-skip-tls-verify=true
oc project $OPENSHIFT_PROJECT

for TEMPLATE in $(find $BASE/deployment-configs -type f -name "*.yaml")
do
  DC=$WORK/$(basename $TEMPLATE)
  cat $TEMPLATE | envsubst > $DC
  echo ------------------------------------------------------------
  echo $DC
  cat $DC
  oc create -f $DC
  echo ------------------------------------------------------------
done

