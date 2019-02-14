#!/usr/bin/env bash

which plantuml > /dev/null 2>&1
[ $? != 0 ] && echo "plantuml not found" && exit 1

export _JAVA_OPTIONS=-Djava.awt.headless=true
cd $(dirname $(readlink -f $0))

makeImage() {
  local uml=$1
  local png=${uml/.uml/.png}
  [[ -f $png && $(stat -c %Y $png) -ge $(stat -c %Y $uml) ]] && echo "Skipping $uml" && return
  echo "Making $uml"
  plantuml $uml 2>/dev/null
}

export -f makeImage

ls *.uml | xargs -I {} -P 4 bash -c "makeImage {}"
