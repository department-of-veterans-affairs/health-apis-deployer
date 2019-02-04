#!/usr/bin/env bash

oc get dc \
  | awk '{print $1}' \
  | grep -- '-[0-9]\+-[0-9]\+-[0-9]\+-[0-9]\+-[a-z0-9]\+$' \
  | sed 's/^[-a-z]\+-//' \
  | sort -uV
