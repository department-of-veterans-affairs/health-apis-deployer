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

date
env|sort
echo "kthxby"
