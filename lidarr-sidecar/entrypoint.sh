#!/bin/bash
set -euo pipefail

### Script values
scriptVersion="1.0"
scriptName="entrypoint"

#### Import Functions
source /app/functions.bash

# Start with healthy status
setHealthy

# Validate environment variables
validateEnvironment

# Ensure Lidarr connectivity
verifyLidarrApiAccess

# Run all services
for script in /app/services/*.bash; do
  bash "$script" &
done
wait

# If we reach here, all of the services have exited
# This means something went wrong
# The container should be marked as unhealthy
setUnhealthy
