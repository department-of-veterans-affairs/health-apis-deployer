#!/usr/bin/env bash
set -euo pipefail

#
# Selectively make some of the deployer's tools available in the toolkit
#

cd $(dirname "$0")
for tool in ryan-secrets cluster-fox debug load-balancer fetch-deployment-unit extract-deployment-unit attach-deployment-unit-to-lb detach-deployment-unit-from-lb remove-all-green-routes wait-for-lb execute-tests set-test-label; do
  cp -r ../bin/$tool bin/$tool
done

docker build -t vasdvp/deployer:latest ..
docker build --no-cache -t vasdvp/deployer-toolkit-base:latest . -f Dockerfile.toolkit-base
