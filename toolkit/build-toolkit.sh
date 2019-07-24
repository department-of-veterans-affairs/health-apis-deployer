#!/usr/bin/env bash

./../toolkit-base/build-toolkit-base.sh
docker build --no-cache -t vasdvp/deployer-toolkit:latest . -f Dockerfile.toolkit
