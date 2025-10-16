#!/bin/bash
set -euo pipefail

### Script values
scriptVersion="3.2"
scriptName="AutoConfig"

#### Import Functions
source /app/functions

if [ "$ENABLE_AUTO_CONFIG" != "true" ]; then
	log "INFO :: Script is not enabled, enable by setting environment variable ENABLE_AUTO_CONFIG to \"true\"."
  exit 0
fi

lidarrApiKey="$(getLidarrApiKey)" || setUnhealthy
lidarrUrl="$(getLidarrUrl)" || setUnhealthy

apiVersion=""
apiVersion="$(verifyApiAccess "$lidarrUrl" "$lidarrApiKey")"
if [ -z "$apiVersion" ]; then
  log "ERROR :: Unable to connect to Lidarr at $lidarrUrl with provided API key."
  setUnhealthy
fi

if [ "$CONFIGURE_MEDIA_MANAGEMENT" == "true" ]; then
  log "INFO :: Configuring Lidarr Media Management Settings"

  if [ -z "$MEDIA_MANAGEMENT_CONFIG_FILE" ] || [ ! -f "$MEDIA_MANAGEMENT_CONFIG_FILE" ]; then
    log "ERROR :: JSON config file not set or not found: $MEDIA_MANAGEMENT_CONFIG_FILE"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/mediamanagement" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$MEDIA_MANAGEMENT_CONFIG_FILE")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Media Management settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$CONFIGURE_METADATA_CONSUMER_SETTINGS" == "true" ]; then
  log "INFO :: Configuring Lidarr Metadata Consumer Settings"

  if [ -z "$METADATA_CONSUMER_CONFIG_FILE" ] || [ ! -f "$METADATA_CONSUMER_CONFIG_FILE" ]; then
    log "ERROR :: JSON config file not set or not found: $METADATA_CONSUMER_CONFIG_FILE"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/metadata/1?" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$METADATA_CONSUMER_CONFIG_FILE")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Metadata Consumer settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$CONFIGURE_METADATA_PROVIDER_SETTINGS" == "true" ]; then
  log "INFO :: Configuring Lidarr Metadata Provider Settings"

  if [ -z "$METADATA_PROVIDER_CONFIG_FILE" ] || [ ! -f "$METADATA_PROVIDER_CONFIG_FILE" ]; then
    log "ERROR :: JSON config file not set or not found: $METADATA_PROVIDER_CONFIG_FILE"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/metadataProvider" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$METADATA_PROVIDER_CONFIG_FILE")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Metadata Provider settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$CONFIGURE_LIDARR_UI_SETTINGS" == "true" ]; then
  log "INFO :: Configuring Lidarr UI Settings"

  if [ -z "$LIDARR_UI_CONFIG_FILE" ] || [ ! -f "$LIDARR_UI_CONFIG_FILE" ]; then
    log "ERROR :: JSON config file not set or not found: $LIDARR_UI_CONFIG_FILE"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/ui" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$LIDARR_UI_CONFIG_FILE")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr UI settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$CONFIGURE_METADATA_PROFILE_SETTINGS" == "true" ]; then
  log "INFO :: Configuring Lidarr Metadata Profile Settings"

  if [ -z "$METADATA_PROFILE_CONFIG_FILE" ] || [ ! -f "$METADATA_PROFILE_CONFIG_FILE" ]; then
    log "ERROR :: JSON config file not set or not found: $METADATA_PROFILE_CONFIG_FILE"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/metadataprofile/1?" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$METADATA_PROFILE_CONFIG_FILE")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Metadata Profile settings, HTTP status $response"
      setUnhealthy
  fi
fi

if [ "$CONFIGURE_TRACK_NAMING_SETTINGS" == "true" ]; then
  log "INFO :: Configuring Lidarr Track Naming Settings"

  if [ -z "$TRACK_NAMING_CONFIG_FILE" ] || [ ! -f "$TRACK_NAMING_CONFIG_FILE" ]; then
    log "ERROR :: JSON config file not set or not found: $TRACK_NAMING_CONFIG_FILE"
    setUnhealthy
  fi

  response=$(curl -s -o /dev/null -w "%{http_code}" \
      "$lidarrUrl/api/${apiVersion}/config/naming" \
      -X PUT \
      -H 'Content-Type: application/json' \
      -H "X-Api-Key: ${lidarrApiKey}" \
      --data-binary @"$TRACK_NAMING_CONFIG_FILE")

  if [ "$response" -ne 200 ]; then
      log "ERROR :: Failed to update Lidarr Track Naming settings, HTTP status $response"
      setUnhealthy
  fi
fi

log "INFO :: Auto Configuration Complete"
exit 0
