#!/usr/bin/env bash
set -euo pipefail

#
# Selectively make some tools available
#
if [ -d bin ]; then rm -rf bin; fi
mkdir bin
for tool in ryan-secrets deployment-git-secrets; do
  cp -r ../bin/$tool bin/$tool
done

docker build -t vasdvp/deployer:latest ..
docker build --no-cache -t vasdvp/deployer-toolkit . -f Dockerfile.toolkit
