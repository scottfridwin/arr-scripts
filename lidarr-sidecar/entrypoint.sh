#!/bin/bash

#### Import Functions
source /app/functions

# Start with healthy status
setHealthy

# Run all services
for script in /app/services/*.bash; do
  bash "$script" &
done
wait

# If we reach here, all of the services have exited
# This means something went wrong
# The container should be marked as unhealthy
setUnhealthy
