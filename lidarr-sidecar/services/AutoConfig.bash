#!/bin/bash
set -euo pipefail

### Script values
scriptVersion="3.2"
scriptName="AutoConfig"

#### Import Functions
source /app/functions

### Preamble ###

log "INFO :: Starting $scriptName version $scriptVersion"

log "DEBUG :: AUTOCONFIG_MEDIA_MANAGEMENT=${AUTOCONFIG_MEDIA_MANAGEMENT}"
log "DEBUG :: AUTOCONFIG_MEDIA_MANAGEMENT_JSON=${AUTOCONFIG_MEDIA_MANAGEMENT_JSON}"
log "DEBUG :: AUTOCONFIG_METADATA_CONSUMER=${AUTOCONFIG_METADATA_CONSUMER}"
log "DEBUG :: AUTOCONFIG_METADATA_CONSUMER_JSON=${AUTOCONFIG_METADATA_CONSUMER_JSON}"
log "DEBUG :: AUTOCONFIG_METADATA_PROVIDER=${AUTOCONFIG_METADATA_PROVIDER}"
log "DEBUG :: AUTOCONFIG_METADATA_PROVIDER_JSON=${AUTOCONFIG_METADATA_PROVIDER_JSON}"
log "DEBUG :: AUTOCONFIG_LIDARR_UI=${AUTOCONFIG_LIDARR_UI}"
log "DEBUG :: AUTOCONFIG_LIDARR_UI_JSON=${AUTOCONFIG_LIDARR_UI_JSON}"
log "DEBUG :: AUTOCONFIG_METADATA_PROFILE=${AUTOCONFIG_METADATA_PROFILE}"
log "DEBUG :: AUTOCONFIG_METADATA_PROFILE_JSON=${AUTOCONFIG_METADATA_PROFILE_JSON}"
log "DEBUG :: AUTOCONFIG_TRACK_NAMING=${AUTOCONFIG_TRACK_NAMING}"
log "DEBUG :: AUTOCONFIG_TRACK_NAMING_JSON=${AUTOCONFIG_TRACK_NAMING_JSON}"

### Validation ###

# Nothing to validate

### Main ###

lidarrApiKey="$(getLidarrApiKey)" || setUnhealthy
lidarrUrl="$(getLidarrUrl)" || setUnhealthy

apiVersion=""
apiVersion="$(verifyApiAccess "$lidarrUrl" "$lidarrApiKey")"
if [ -z "$apiVersion" ]; then
  log "ERROR :: Unable to connect to Lidarr at $lidarrUrl with provided API key."
  setUnhealthy
fi

if [ "$AUTOCONFIG_MEDIA_MANAGEMENT" == "true" ]; then
  log "INFO :: Configuring Lidarr Media Management Settings"

  if [ -z "$AUTOCONFIG_MEDIA_MANAGEMENT_JSON" ] || [ ! -f "$AUTOCONFIG_MEDIA_MANAGEMENT_JSON" ]; then
    log "ERROR :: JSON config file not set or not found: $AUTOCONFIG_MEDIA_MANAGEMENT_JSON"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/mediamanagement" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$AUTOCONFIG_MEDIA_MANAGEMENT_JSON")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Media Management settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$AUTOCONFIG_METADATA_CONSUMER" == "true" ]; then
  log "INFO :: Configuring Lidarr Metadata Consumer Settings"

  if [ -z "$AUTOCONFIG_METADATA_CONSUMER_JSON" ] || [ ! -f "$AUTOCONFIG_METADATA_CONSUMER_JSON" ]; then
    log "ERROR :: JSON config file not set or not found: $AUTOCONFIG_METADATA_CONSUMER_JSON"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/metadata/1?" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$AUTOCONFIG_METADATA_CONSUMER_JSON")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Metadata Consumer settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$AUTOCONFIG_METADATA_PROVIDER" == "true" ]; then
  log "INFO :: Configuring Lidarr Metadata Provider Settings"

  if [ -z "$AUTOCONFIG_METADATA_PROVIDER_JSON" ] || [ ! -f "$AUTOCONFIG_METADATA_PROVIDER_JSON" ]; then
    log "ERROR :: JSON config file not set or not found: $AUTOCONFIG_METADATA_PROVIDER_JSON"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/metadataProvider" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$AUTOCONFIG_METADATA_PROVIDER_JSON")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Metadata Provider settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$AUTOCONFIG_LIDARR_UI" == "true" ]; then
  log "INFO :: Configuring Lidarr UI Settings"

  if [ -z "$AUTOCONFIG_LIDARR_UI_JSON" ] || [ ! -f "$AUTOCONFIG_LIDARR_UI_JSON" ]; then
    log "ERROR :: JSON config file not set or not found: $AUTOCONFIG_LIDARR_UI_JSON"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/ui" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$AUTOCONFIG_LIDARR_UI_JSON")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr UI settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$AUTOCONFIG_METADATA_PROFILE" == "true" ]; then
  log "INFO :: Configuring Lidarr Metadata Profile Settings"

  if [ -z "$AUTOCONFIG_METADATA_PROFILE_JSON" ] || [ ! -f "$AUTOCONFIG_METADATA_PROFILE_JSON" ]; then
    log "ERROR :: JSON config file not set or not found: $AUTOCONFIG_METADATA_PROFILE_JSON"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/metadataprofile/1?" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$AUTOCONFIG_METADATA_PROFILE_JSON")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Metadata Profile settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$AUTOCONFIG_TRACK_NAMING" == "true" ]; then
  log "INFO :: Configuring Lidarr Track Naming Settings"

  if [ -z "$AUTOCONFIG_TRACK_NAMING_JSON" ] || [ ! -f "$AUTOCONFIG_TRACK_NAMING_JSON" ]; then
    log "ERROR :: JSON config file not set or not found: $AUTOCONFIG_TRACK_NAMING_JSON"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/naming" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$AUTOCONFIG_TRACK_NAMING_JSON")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Track Naming settings, HTTP status $response"
      setUnhealthy
  fi
fi

log "INFO :: Auto Configuration Complete"
exit 0
