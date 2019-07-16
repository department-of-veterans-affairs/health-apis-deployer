#!/usr/bin/env bash
set -euo pipefail

#
# Selectively make some of the deployer's tools available in the toolkit
#

cd $(dirname "${BASH_SOURCE[0]}")

if [ -f bin/ryan-secrets ]; then rm bin/ryan-secrets; fi
for tool in ryan-secrets; do
  cp -r ../bin/$tool bin/$tool
done

if [ -f bin/cluster-fox ]; then rm bin/cluster-fox; fi
for tool in cluster-fox; do
  cp -r ../bin/$tool bin/$tool
done

docker build -t vasdvp/deployer:latest ..
docker build --no-cache -t vasdvp/deployer-toolkit-base:latest . -f Dockerfile.toolkit-base
