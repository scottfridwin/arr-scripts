#!/bin/bash
set -euo pipefail

### Script values
scriptName="entrypoint"

#### Import Functions
source /app/functions.bash

### Preamble ###

log "INFO :: Starting ${scriptName}"

### Validation ###

log "DEBUG :: LIDARR_CONFIG_PATH=${LIDARR_CONFIG_PATH}"
log "DEBUG :: LOG_LEVEL=${LOG_LEVEL}"
log "DEBUG :: LIDARR_HOST=${LIDARR_HOST}"
log "DEBUG :: LIDARR_PORT=${LIDARR_PORT}"

# Start with healthy status
setHealthy

# Validate environment variables
validateEnvironment

# Verify Lidarr API access
verifyLidarrApiAccess

### Main ###

# Run all services
for script in /app/services/*.bash; do
  bash "$script" &
done
wait

# If we reach here, all of the services have exited
# This means something went wrong
# The container should be marked as unhealthy
setUnhealthy
