#!/bin/bash

case "$PLUTO_VERB:$1" in
up-client:)
  ;;
down-client:)
  /usr/bin/send-metric.sh session
  ;;
esac