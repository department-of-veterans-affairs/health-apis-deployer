#!/usr/bin/env bash

cd $(dirname $0)

./../toolkit-base/build-toolkit-base.sh
docker build --no-cache -t vasdvp/deployer-toolkit:latest . -f Dockerfile.toolkit
