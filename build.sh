#!/usr/bin/env bash

#
# Disable debugging unless explicitly set
#
set +x
if [ -z "$DEBUG" ]; then DEBUG=false; fi
export DEBUG
if [ "${DEBUG}" == true ]; then
  set -x
  env | sort
fi


export PATH=/deployer:$PATH

#
# Ensure that we fail fast on any issues.
#
set -euo pipefail

cat <<EOF
============================================================
VPC ........ $VPC
ARTIFACT ... $ARTIFACT
============================================================
EOF


ENVIRONMENT=$(vpc hyphenize -e "$VPC")

deployment add-build-info -d "ENVIRONMENT ... $ENVIRONMENT"
deployment add-build-info -d "ARTIFACT ...... $ARTIFACT"
lambda deploy-java \
  -e $VPC \
  -a "$ARTIFACT"

echo "kthxby"
