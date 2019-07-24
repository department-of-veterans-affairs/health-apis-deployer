#!/usr/bin/env bash
set -euo pipefail

#
# Selectively make some of the deployer's tools available in the toolkit
#

cd $(dirname "$0")
for tool in ryan-secrets cluster-fox debug; do
  cp -r ../bin/$tool bin/$tool
done

docker build -t vasdvp/deployer:latest ..
docker build --no-cache -t vasdvp/deployer-toolkit-base:latest . -f Dockerfile.toolkit-base
