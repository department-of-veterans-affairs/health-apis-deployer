#!/usr/bin/env bash

BASE=$(dirname $(readlink -f $0))
BUILD_INFO=$BASE/build.conf
CONF=$BASE/upgrade.conf
[ -z "$BUILD_INFO" ] && echo "Build info file not found: $BUILD_INFO" && exit 1
[ ! -f "$CONF" ] && echo "Configuration file not found: $CONF" && exit 1
. $BUILD_INFO
. $CONF

cat <<EOF
BUILD_DATE ............ $BUILD_DATE
BUILD_HASH ............ $BUILD_HASH
HEALTH_APIS_VERSION ... $HEALTH_APIS_VERSION

EOF
