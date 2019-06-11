#!/usr/bin/env bash
set -euo pipefail

#
# Selectively make some tools available
#
if [ -f bin/ryan-secrets ]; then rm ryan-secrets; fi
for tool in ryan-secrets do
  cp -r ../bin/$tool bin/$tool
done

docker build -t vasdvp/deployer:latest ..
docker build --no-cache -t vasdvp/deployer-toolkit:latest . -f Dockerfile.toolkit
