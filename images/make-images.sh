#!/usr/bin/env bash

which plantuml > /dev/null 2>&1
[ $? != 0 ] && echo "plantuml not found" && exit 1

cd $(dirname $(readlink -f $0))
ls *.uml | xargs -n 1 plantuml
