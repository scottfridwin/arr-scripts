declare -A LOG_PRIORITY=( ["DEBUG"]=0 ["INFO"]=1 ["WARNING"]=2 ["ERROR"]=3 )

log () {
    local msg="$1"

    # Ensure message starts with a valid level
    if [[ ! "$msg" =~ ^(DEBUG|INFO|WARNING|ERROR) ]]; then
        echo "CRITICAL :: $scriptName :: v$scriptVersion :: Invalid log message format: '$msg'" >&2
        exit 1
    fi

    # Extract the level from the message
    local level="${msg%% *}"  # first word

    # Compare priorities
    if (( LOG_PRIORITY[$level] >= LOG_PRIORITY[$LOG_LEVEL] )); then
        echo "$scriptName :: v$scriptVersion :: $msg"
    fi
}

setHealthy () {
  echo "healthy" > /tmp/health
}

setUnhealthy () {
  echo "unhealthy" > /tmp/health
  exit 1
}

validateEnvironment() {
  [[ "${LOG_LEVEL}" =~ ^(DEBUG|INFO|WARNING|ERROR)$ ]] || {
      echo "CRITICAL :: $scriptName :: v$scriptVersion :: Invalid LOG_LEVEL value: '${LOG_LEVEL}'. Must be one of: DEBUG, INFO, WARNING, ERROR" >&2
      setUnhealthy
      exit 1
  }
  [[ -f "${LIDARR_CONFIG_PATH}" ]] || { 
      log "ERROR :: File not found at '${LIDARR_CONFIG_PATH}'"
      setUnhealthy
      exit 1
  }
}

getLidarrApiKey() {
  local apiKey=""
  apiKey="$(cat "${LIDARR_CONFIG_PATH}" | xq | jq -r .Config.ApiKey)"
  if [ -z "$apiKey" ] || [ "$apiKey" == "null" ]; then
    log "ERROR :: Unable to retrieve Lidarr API key from configuration file: $LIDARR_CONFIG_PATH"
    setUnhealthy
  fi

  echo "$apiKey"
}

getLidarrUrl() {
  local lidarrUrl=""

  # Get Lidarr base URL. Usually blank, but can be set in Lidarr settings.
  local lidarrUrlBase="$(cat "${LIDARR_CONFIG_PATH}" | xq | jq -r .Config.UrlBase)"
  if [ "$lidarrUrlBase" == "null" ]; then
    lidarrUrlBase=""
  else
    lidarrUrlBase="/$(echo "$lidarrUrlBase" | sed "s/\///")"
  fi

  # If an external port is provided, use it. Otherwise, get the port from the config file.
  local lidarrPort="${LIDARR_PORT}"
  if [ -z "$lidarrPort" ] || [ "$lidarrPort" == "null" ]; then
    lidarrPort="$(cat "${LIDARR_CONFIG_PATH}" | xq | jq -r .Config.Port)"
  fi
    
  # Construct and return the full URL
  arrUrl="http://${LIDARR_HOST}:${lidarrPort}${lidarrUrlBase}"

  echo "$arrUrl"
}

verifyApiAccess() {
  local url="$1"
  local key="$2"

  if [ -z "$url" ] || [ -z "$key" ]; then
    log "ERROR :: verifyApiAccess requires both URL and API key"
    return 1
  fi

  local apiTest=""
  local apiVersion=""

  until [ -n "$apiTest" ]; do
    # # Try v3 first
    # apiVersion="v3"
    # apiTest="$(curl -s "${url}/api/${apiVersion}/system/status?apikey=${key}" | jq -r .instanceName)"

    # Fall back to v1 if v3 failed
    if [ -z "$apiTest" ]; then
      apiVersion="v1"
      apiTest="$(curl -s "${url}/api/${apiVersion}/system/status?apikey=${key}" | jq -r .instanceName)"
    fi

    if [ -z "$apiTest" ]; then
      log "INFO :: Lidarr is not ready, sleeping until valid response..."
      sleep 5
    fi
  done

  if [ "$apiVersion" -ne "v1" ]; then
    log "ERROR :: Only Lidarr v1 API is supported."
    setUnhealthy
  fi

  # Return the working API version
  echo "$apiVersion"
}
