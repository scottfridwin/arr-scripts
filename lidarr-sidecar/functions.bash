declare -A LOG_PRIORITY=(["TRACE"]=0 ["DEBUG"]=1 ["INFO"]=2 ["WARNING"]=3 ["ERROR"]=4)

# Logs messages with levels and respects LOG_LEVEL setting
log() {
  # $1 -> the log message, starting with level (TRACE, DEBUG, INFO, WARNING, ERROR)
  local msg="$1"

  # Ensure message starts with a valid level
  if [[ ! "$msg" =~ ^(TRACE|DEBUG|INFO|WARNING|ERROR) ]]; then
    echo "CRITICAL :: ${scriptName} :: Invalid log message format: '$msg'" >&2
    exit 1
  fi

  # Extract the level from the message
  local level="${msg%% *}" # first word

  # Compare priorities
  if ((LOG_PRIORITY[${level}] >= LOG_PRIORITY[${LOG_LEVEL}])); then
    echo "${scriptName} :: ${msg}" >&2
  fi
}

# Marks the container as healthy
setHealthy() {
  echo "healthy" >/tmp/health
}

# Marks the container as unhealthy and exits
setUnhealthy() {
  echo "unhealthy" >/tmp/health
  exit 1
}

# Validates essential environment variables
validateEnvironment() {
  log "TRACE :: Entering validateEnvironment..."
  [[ "${LOG_LEVEL}" =~ ^(TRACE|DEBUG|INFO|WARNING|ERROR)$ ]] || {
    echo "CRITICAL :: ${scriptName} :: Invalid LOG_LEVEL value: '${LOG_LEVEL}'. Must be one of: TRACE, DEBUG, INFO, WARNING, ERROR" >&2
    setUnhealthy
    exit 1
  }
  [[ -f "${LIDARR_CONFIG_PATH}" ]] || {
    log "ERROR :: File not found at '${LIDARR_CONFIG_PATH}'"
    setUnhealthy
    exit 1
  }
  log "TRACE :: Exiting validateEnvironment..."
}

# Retrieves the Lidarr API key from the config file
getLidarrApiKey() {
  log "TRACE :: Entering getLidarrApiKey..."
  if [[ -z "${lidarrApiKey}" ]]; then
    lidarrApiKey="$(cat "${LIDARR_CONFIG_PATH}" | xq | jq -r .Config.ApiKey)"
    if [ -z "$lidarrApiKey" ] || [ "$lidarrApiKey" == "null" ]; then
      log "ERROR :: Unable to retrieve Lidarr API key from configuration file: $LIDARR_CONFIG_PATH"
      setUnhealthy
      exit 1
    fi
    set_state "lidarrApiKey" "${lidarrApiKey}"
  fi
  log "TRACE :: Exiting getLidarrApiKey..."
}

# Constructs the Lidarr base URL from environment variables and config file
getLidarrUrl() {
  log "TRACE :: Entering getLidarrUrl..."
  if [[ -z "${lidarrUrl}" ]]; then
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
    set_state "lidarrUrl" "${lidarrUrl}"
  fi
  log "TRACE :: Exiting getLidarrUrl..."
}

# Perform a Lidarr API request with error handling and retries
LidarrApiRequest() {
  log "TRACE :: Entering LidarrApiRequest..."
  # $1 = HTTP method (GET, POST, PUT, DELETE)
  # $2 = API path (e.g., config/mediamanagement)
  # $3 = Optional JSON payload
  local method="${1}"
  local path="${2}"
  local payload="${3:-}"
  local response body httpCode

  local lidarrUrl=$(get_state "lidarrUrl")
  local lidartApiKey=$(get_state "lidarrApiKey")
  if [[ -z "$lidarrUrl" || -z "$lidarrApiKey" || -z "$lidarrApiVersion" ]]; then
    log "INFO :: Need to retrieve lidarr connection details in order to perform API requests"
    verifyLidarrApiAccess
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

    log "TRACE :: httpCode: ${httpCode}"
    log "TRACE :: body: ${body}"
    case "${httpCode}" in
    200 | 201 | 202 | 204)
      # Successful request, return JSON body
      echo "${body}"
      break
      ;;
    000)
      # Connection failed — retry after waiting
      log "WARNING :: Lidarr unreachable — entering recovery loop..."
      local statusResponse statusBody statusHttpCode
      while true; do
        sleep 5
        statusResponse=$(curl -s -w "\n%{http_code}" -X "GET" \
          -H "X-Api-Key: ${lidarrApiKey}" \
          "${lidarrUrl}/api/${lidarrApiVersion}/system/status")
        statusHttpCode=$(tail -n1 <<<"${statusResponse}")
        statusBody=$(sed '$d' <<<"${statusResponse}")
        log "DEBUG :: Lidarr status request (${lidarrUrl}/api/${lidarrApiVersion}/system/status) returned ${statusHttpCode} with body ${statusBody}"
        if [[ "${httpCode}" -eq "200" ]]; then
          log "INFO :: Lidarr connectivity restored, retrying previous request..."
          break
        fi
      done
      ;;
    *)
      # Any other HTTP error is fatal
      log "ERROR :: Lidarr API call failed (HTTP ${httpCode}) for ${method} ${path}"
      setUnhealthy
      exit 1
      ;;
    esac
  done
  log "TRACE :: Exiting LidarrApiRequest..."
}

# Checks Lidarr for any active tasks and waits for them to complete
LidarrTaskStatusCheck() {
  log "TRACE :: Entering LidarrTaskStatusCheck..."
  local alerted="no"
  local taskList taskCount

  while true; do
    # Fetch all commands from Lidarr
    taskList=$(LidarrApiRequest "GET" "command")

    # Count active tasks
    taskCount=$(jq -r '.[] | select(.status=="started") | .name' <<<"${taskList}" | wc -l)

    if ((taskCount >= 1)); then
      if [[ "${alerted}" == "no" ]]; then
        alerted="yes"
        log "INFO :: LIDARR BUSY :: Pausing/waiting for all active Lidarr tasks to end..."
      fi
      sleep 2
    else
      break
    fi
  done
  log "TRACE :: Exiting LidarrTaskStatusCheck..."
}

# Ensures connectivity to Lidarr and determines API version
verifyLidarrApiAccess() {
  log "TRACE :: Entering verifyLidarrApiAccess..."
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
  set_state "lidarrApiVersion" "${lidarrApiVersion}"

  log "INFO :: Lidarr API access verified (URL: ${lidarrUrl}, API Version: ${lidarrApiVersion})"
  log "TRACE :: Exiting verifyLidarrApiAccess..."
}

# Normalizes a string by replacing smart quotes and normalizing spaces
normalize_string() {
  # $1 -> the string to normalize

  # Converts the right single quotation mark (’, Unicode U+2019) → straight apostrophe (', ASCII U+0027).
  # Converts the left single quotation mark (‘, Unicode U+2018) → ' (ASCII apostrophe).
  # Converts left double quotation mark (“, Unicode U+201C) → plain double quote (", ASCII U+0022).
  # Converts right double quotation mark (”, Unicode U+201D) → ".
  # Converts any sequence of whitespace characters (tabs, newlines, multiple spaces) into a single space.
  # Converts non-breaking spaces (U+00A0) to regular spaces (U+0020).
  # Converts en dashes (–, Unicode U+2013) to hyphens (-, ASCII U+002D).
  # Removes leading and trailing spaces.
  echo "$1" |
    sed -e "s/’/'/g" \
      -e "s/‘/'/g" \
      -e 's/“/"/g' -e 's/”/"/g' \
      -e 's/–/-/g' \
      -e 's/\xA0/ /g' \
      -e 's/[[:space:]]\+/ /g' \
      -e 's/^ *//; s/ *$//'
}

# Create a named associative array: auto-named using shell PID
init_state() {
  local name=$(_get_state_name)

  # Check if the variable already exists
  if declare -p "$name" &>/dev/null; then
    log "ERROR :: State object '$name' already exists."
    setUnhealthy
    exit 1
  fi

  # Create the global associative array
  eval "declare -gA ${name}=()"
}

# Internal helper to resolve current state object name
_get_state_name() {
  echo "state_$$"
}

# Generic setter: set_state <key> <value>
set_state() {
  local name=$(_get_state_name)
  local -n obj="$name"
  local key="$1"
  local value="$2"
  obj["$key"]="$value"
}

# Generic getter: get_state <key>
get_state() {
  local key="$1"
  local name=$(_get_state_name)

  # Check if the state object exists
  if ! declare -p "$name" &>/dev/null; then
    echo "Error: State object '$name' not found" >&2
    return 1
  fi

  local -n obj="$name"
  echo "${obj[$key]}"
}
