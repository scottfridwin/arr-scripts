#!/bin/bash
set -euo pipefail

### Script values
scriptVersion="2.0"
scriptName="ARLChecker"

#### Import Functions
source /app/functions

if [ -z "$ARL_UPDATE_INTERVAL" ] || ! [[ "$ARL_UPDATE_INTERVAL" =~ ^[0-9]+[smhd]$ ]]; then
    log "ERROR :: ARL_UPDATE_INTERVAL is not set or invalid"
    setUnhealthy
fi

for (( ; ; )); do
    log "INFO :: Running ARL Token Check..."
    # run py script
    python python/ARLChecker.py -c

    log "ARL Token Check Complete. Sleeping for ${ARL_UPDATE_INTERVAL}."
    sleep ${ARL_UPDATE_INTERVAL}
done
