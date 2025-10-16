declare -A LOG_PRIORITY=( ["DEBUG"]=0 ["INFO"]=1 ["WARNING"]=2 ["ERROR"]=3 )
lidarrApiKey=""
lidarrUrl=""
lidarrApiVersion=""

# Logs messages with levels and respects LOG_LEVEL setting
log () {
    # $1 -> the log message, starting with level (DEBUG, INFO, WARNING, ERROR)
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
        echo "$scriptName :: v$scriptVersion :: $msg" >&2
    fi
}

# Marks the container as healthy
setHealthy () {
  echo "healthy" > /tmp/health
}

# Marks the container as unhealthy and exits
setUnhealthy () {
  echo "unhealthy" > /tmp/health
  exit 1
}

# Validates essential environment variables
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

# Retrieves the Lidarr API key from the config file
getLidarrApiKey() {
  [[ -n "$lidarrApiKey" ]] && return 0  # already set

  lidarrApiKey="$(cat "${LIDARR_CONFIG_PATH}" | xq | jq -r .Config.ApiKey)"
  if [ -z "$lidarrApiKey" ] || [ "$lidarrApiKey" == "null" ]; then
    log "ERROR :: Unable to retrieve Lidarr API key from configuration file: $LIDARR_CONFIG_PATH"
    setUnhealthy
    exit 1
  fi

  [[ -n "$lidarrApiKey" ]] && log "DEBUG :: lidarrApiKey successfully set"
}

# Constructs the Lidarr base URL from environment variables and config file
getLidarrUrl() {
  [[ -n "$lidarrUrl" ]] && return 0  # already set

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
  lidarrUrl="http://${LIDARR_HOST}:${lidarrPort}${lidarrUrlBase}"
  log "DEBUG :: lidarrUrl: ${lidarrUrl}"
}

# Perform a Lidarr API request with error handling and retries
LidarrApiRequest() {
    # $1 = HTTP method (GET, POST, PUT, DELETE)
    # $2 = API path (e.g., config/mediamanagement)
    # $3 = Optional JSON payload
    local method="${1}"
    local path="${2}"
    local payload="${3:-}"
    local response body httpCode

    if [[ -z "$lidarrUrl" || -z "$lidarrApiKey" || -z "$lidarrApiVersion" ]]; then
        log "ERROR :: LidarrApiRequest requires lidarrUrl, lidarrApiKey, and lidarrApiVersion to be set"
        setUnhealthy
        exit 1
    fi

    # If method is not GET, ensure Lidarr isn’t busy
    if [[ "${method}" != "GET" ]]; then
        LidarrTaskStatusCheck
    fi

    while true; do
        if [[ -n "${payload}" ]]; then
            response=$(curl -s -w "\n%{http_code}" -X "${method}" \
                -H "X-Api-Key: ${lidarrApiKey}" \
                -H "Content-Type: application/json" \
                -d "${payload}" \
                "${lidarrUrl}/api/${lidarrApiVersion}/${path}")
        else
            response=$(curl -s -w "\n%{http_code}" -X "${method}" \
                -H "X-Api-Key: ${lidarrApiKey}" \
                "${lidarrUrl}/api/${lidarrApiVersion}/${path}")
        fi

        httpCode=$(tail -n1 <<<"${response}")
        body=$(sed '$d' <<<"${response}")

        log "DEBUG :: LidarrApiRequest response code ${httpCode}"
        log "DEBUG :: LidarrApiRequest response body ${body}"
        case "${httpCode}" in
            200|201|202|204)
                # Successful request, return JSON body
                echo "${body}"
                return 0
                ;;
            000)
                # Connection failed — retry after waiting
                log "WARNING :: Lidarr unreachable — entering recovery loop..."
                while true; do
                    sleep 5
                    log "DEBUG :: Attempting to reconnect to Lidarr..."
                    # if curl -fs -H "X-Api-Key: ${lidarrApiKey}" "${lidarrUrl}/api/${lidarrApiVersion}/system/status" >/dev/null 2>&1; then
                    #     log "INFO :: Lidarr connectivity restored, retrying previous request..."
                    #     break
                    # fi
                    statusResponse=$(curl -s -w "\n%{http_code}" -X "GET" \
                        -H "X-Api-Key: ${lidarrApiKey}" \
                        "${lidarrUrl}/api/${lidarrApiVersion}/system/status")
                    httpCode=$(tail -n1 <<<"${statusResponse}")
                    body=$(sed '$d' <<<"${statusResponse}")
                    log "DEBUG :: Lidarr status request (${lidarrUrl}/api/${lidarrApiVersion}/system/status) returned ${httpCode} with body ${body}"
                    if [[ "${httpCode}" -eq "200" ]]; then
                        log "INFO :: Lidarr connectivity restored, retrying previous request..."
                        break
                    fi
                done
                ;;
            *)
                # Any other HTTP error is fatal
                log "ERROR :: Lidarr API call failed (HTTP ${httpCode}) for ${path}"
                setUnhealthy
                exit 1
                ;;
        esac
    done
}

# Checks Lidarr for any active tasks and waits for them to complete
LidarrTaskStatusCheck() {
    local alerted="no"
    local taskList taskCount

    while true; do
        # Fetch all commands from Lidarr
        taskList=$(LidarrApiRequest "GET" "command")

        # Count active tasks
        taskCount=$(jq -r '.[] | select(.status=="started") | .name' <<<"${taskList}" | wc -l)

        if (( taskCount >= 1 )); then
            if [[ "${alerted}" == "no" ]]; then
                alerted="yes"
                log "INFO :: LIDARR BUSY :: Pausing/waiting for all active Lidarr tasks to end..."
            fi
            sleep 2
        else
            break
        fi
    done
}

# Ensures connectivity to Lidarr and determines API version
verifyLidarrApiAccess() {
  getLidarrApiKey
  getLidarrUrl

  if [ -z "$lidarrUrl" ] || [ -z "$lidarrApiKey" ]; then
    log "ERROR :: verifyLidarrApiAccess requires both URL and API key"
    setUnhealthy
    exit 1
  fi

  local apiTest=""

  until [ -n "$apiTest" ]; do
    # # Try v3 first
    # lidarrApiVersion="v3"
    # apiTest="$(curl -s "${lidarrUrl}/api/${lidarrApiVersion}/system/status?apikey=${lidarrApiKey}" | jq -r .instanceName)"

    # Fall back to v1 if v3 failed
    if [ -z "$apiTest" ]; then
      lidarrApiVersion="v1"
      apiTest="$(curl -s "${lidarrUrl}/api/${lidarrApiVersion}/system/status?apikey=${lidarrApiKey}" | jq -r .instanceName)"
    fi

    if [ -z "$apiTest" ]; then
      log "INFO :: Lidarr is not ready, sleeping until valid response..."
      sleep 5
    fi
  done

  if [ "$lidarrApiVersion" != "v1" ]; then
    log "ERROR :: Only Lidarr v1 API is supported."
    setUnhealthy
    exit 1
  fi

  log "INFO :: Lidarr API access verified (URL: ${lidarrUrl}, API Version: ${lidarrApiVersion})"
  export lidarrApiKey
  export lidarrUrl
  export lidarrApiVersion
}
