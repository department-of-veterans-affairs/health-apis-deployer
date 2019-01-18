#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))

BUILD_INFO=$BASE/build.conf
CONF=$BASE/upgrade.conf

[ -z "$ENVIRONMENT" ] && echo "Environment not specified" && exit 1
[ -z "$BUILD_INFO" ] && echo "Build info file not found: $BUILD_INFO" && exit 1
[ ! -f "$CONF" ] && echo "Configuration file not found: $CONF" && exit 1
. $BUILD_INFO
. $CONF

VERSION=${HEALTH_APIS_VERSION}-${BUILD_HASH}

echo "Upgrading Health APIs in $ENVIRONMENT to $VERSION"

echo "Build info"
cat $BUILD_INFO | sort

echo "Configuration"
echo $CONF | sort

