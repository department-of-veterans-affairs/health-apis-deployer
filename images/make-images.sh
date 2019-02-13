#!/usr/bin/env bash

which plantuml > /dev/null 2>&1
[ $? != 0 ] && echo "plantuml not found" && exit 1

export _JAVA_OPTIONS=-Djava.awt.headless=true
cd $(dirname $(readlink -f $0))
ls *.uml | xargs -I {} -P 4 bash -c "echo Making {} ;  plantuml {} 2>/dev/null"
