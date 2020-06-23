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

/deployer/vpc id-for-environment -e $VPC

echo "kthxby"
