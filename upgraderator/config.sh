#
# config.sh is a library and configuration script to be sourced by
# top-level utilities.
#

export WORK=$BASE/work
[ ! -d $WORK ] && mkdir -p $WORK

BUILD_INFO=$BASE/build.conf
[ -z "$BUILD_INFO" ] && echo "Build info file not found: $BUILD_INFO" && exit 1
. $BUILD_INFO

export DOCKER_SOURCE_ORG=vasdvp

