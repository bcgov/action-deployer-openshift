#!/bin/bash

ROUTE="https://httpbin.org"
HEALTHCHECKS="true"

 URL="$ROUTE"
 HEALTH_URL="/health"
        
if [ "$HEALTHCHECKS" == "true" ]; then
  URL=$URL$HEALTH_URL
  echo $HEALTHCHECKS
fi

echo $URL