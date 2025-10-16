#!/bin/bash
set -euo pipefail

### Script values
scriptVersion="2.48"
scriptName="Audio"

#### Import Functions
source /app/functions.bash

#### Constants
readonly VARIOUS_ARTIST_ID="89ad4ac3-39f7-470e-963a-56509c546377"
readonly DEEMIX_CONFIG_PATH="/tmp/deemix_config.json"

# Levenshtein Distance in Pure Bash
LevenshteinDistance() {
    # $1 -> string 1
    # $2 -> string 2
    local s1="${1}"
    local s2="${2}"
    local len_s1=${#s1}
    local len_s2=${#s2}

    # If either string is empty, distance is the other's length
    if (( len_s1 == 0 )); then
        echo "${len_s2}"
        return
    fi
    if (( len_s2 == 0 )); then
        echo "${len_s1}"
        return
    fi

    # Initialize 2 arrays for the current and previous row
    local -a prev curr
    for ((j=0; j<=len_s2; j++)); do
        prev[j]=${j}
    done

    for ((i=1; i<=len_s1; i++)); do
        curr[0]=${i}
        local s1_char="${s1:i-1:1}"
        for ((j=1; j<=len_s2; j++)); do
            local s2_char="${s2:j-1:1}"
            local cost=$(( s1_char == s2_char ? 0 : 1 ))

            local del=$(( prev[j] + 1 ))
            local ins=$(( curr[j-1] + 1 ))
            local sub=$(( prev[j-1] + cost ))

            local min=${del}
            (( ins < min )) && min=${ins}
            (( sub < min )) && min=${sub}

            curr[j]=${min}
        done
        prev=("${curr[@]}")
    done

    echo "${curr[len_s2]}"
}

# Perform a Lidarr API request with error handling and retries
LidarrApiRequest() {
    # $1 = HTTP method (GET, POST, PUT, DELETE)
    # $2 = API path (e.g., /api/v1/command)
    # $3 = Optional JSON payload
    local method="${1}"
    local path="${2}"
    local payload="${3:-}"
    local response body httpCode

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
                "${lidarrUrl}${path}")
        else
            response=$(curl -s -w "\n%{http_code}" -X "${method}" \
                -H "X-Api-Key: ${lidarrApiKey}" \
                "${lidarrUrl}${path}")
        fi

        httpCode=$(tail -n1 <<<"${response}")
        body=$(sed '$d' <<<"${response}")

        case "${httpCode}" in
            200|201)
                # Successful request, return JSON body
                echo "${body}"
                return 0
                ;;
            000)
                # Connection failed — retry after waiting
                log "WARNING :: Lidarr unreachable — entering recovery loop..."
                while true; do
                    sleep 5
                    if curl -fs -H "X-Api-Key: ${lidarrApiKey}" "${lidarrUrl}/api/v1/system/status" >/dev/null 2>&1; then
                        log "INFO :: Lidarr connectivity restored, retrying previous request..."
                        break
                    fi
                done
                ;;
            *)
                # Any other HTTP error is fatal
                log "ERROR :: Lidarr API call failed (HTTP ${httpCode}) for ${path}"
                log "DEBUG :: Response body: ${body}"
                setUnhealthy
                exit 1
                ;;
        esac
    done
}

# Fetch Deezer album info with caching and retries
GetDeezerAlbumInfo () {
    # $1 -> Deezer Album ID
    local albumId="$1"
    local retries=0
    local maxRetries="${AUDIO_DEEZER_API_RETRIES}"
    local albumCacheFile="${AUDIO_WORK_PATH}/cache/album-${albumId}.json"
    local albumJson

    # Ensure cache directory exists
    mkdir -p "${AUDIO_WORK_PATH}/cache"

    while (( retries < maxRetries )); do
        # Fetch from Deezer if cache is missing
        if [ ! -f "${albumCacheFile}" ]; then
            # Curl with HTTP code capture
            httpCode=$(curl -sS -w "%{http_code}" -o "${albumCacheFile}" \
                --connect-timeout 5 --max-time ${AUDIO_DEEZER_API_TIMEOUT} \
                "https://api.deezer.com/album/${albumId}")

            if [[ "${httpCode}" -ne 200 ]]; then
                log "WARNING :: Deezer returned HTTP ${httpCode} for album ${albumId}, retrying..."
                rm -f "${albumCacheFile}"
                ((retries++))
                sleep 1
                continue
            fi
        fi

        # Validate JSON
        if albumJson=$(jq -e . <"${albumCacheFile}" 2>/dev/null); then
            echo "${albumJson}"
            return 0
        else
            log "WARNING :: Invalid JSON from Deezer for album ${albumId}, retrying... ($((retries+1))/${maxRetries})"
            rm -f "${albumCacheFile}"
            ((retries++))
            sleep 1
        fi
    done

    log "WARNING :: Failed to get valid album information after ${maxRetries} attempts for album ${albumId}"
    return 1
}

# Fetch Deezer artist's albums with caching and retries
GetDeezerArtistAlbums() {
    # $1 -> Deezer Artist ID
    local artistId="$1"
    local retries=0
    local maxRetries="${AUDIO_DEEZER_API_RETRIES}"
    local artistCacheFile="${AUDIO_WORK_PATH}/cache/artist-${artistId}-albums.json"
    local artistJson
    local httpCode

    mkdir -p "${AUDIO_WORK_PATH}/cache"

    while (( retries < maxRetries )); do
        # Fetch from Deezer if cache is missing
        if [ ! -f "${artistCacheFile}" ]; then
            # Curl with HTTP code capture
            httpCode=$(curl -sS -w "%{http_code}" -o "${artistCacheFile}" \
                --connect-timeout 5 --max-time ${AUDIO_DEEZER_API_TIMEOUT} \
                "https://api.deezer.com/artist/${artistId}/albums?limit=1000")

            if [[ "${httpCode}" -ne 200 ]]; then
                log "WARNING :: Deezer returned HTTP ${httpCode} for artist ${artistId} albums, retrying..."
                rm -f "${artistCacheFile}"
                ((retries++))
                sleep 1
                continue
            fi
        fi

        # Validate JSON
        if artistJson=$(jq -e . <"${artistCacheFile}" 2>/dev/null); then
            echo "${artistJson}"
            return 0
        else
            log "WARNING :: Invalid JSON for artist ${artistId} albums, retrying... ($((retries+1))/${maxRetries})"
            rm -f "${artistCacheFile}"
            ((retries++))
            sleep 1
        fi
    done

    log "WARNING :: Failed to get valid album list after ${maxRetries} attempts for artist ${artistId}"
    return 1
}

# Generic Deezer API call with retries and error handling
CallDeezerAPI() {
    # $1 -> Deezer API URL
    local url="${1}"
    local maxRetries="${AUDIO_DEEZER_API_RETRIES}"
    local retries=0
    local httpCode
    local response

    while (( retries < maxRetries )); do
        # Capture HTTP code and output
        response=$(curl -sS -w "\n%{http_code}" --connect-timeout 5 --max-time ${AUDIO_DEEZER_API_TIMEOUT} "${url}")
		httpCode=$(tail -n1 <<< "$response")
		echo "${response}"  # return JSON body

        if [[ "${httpCode}" -eq 200 ]]; then
            # Success, return the JSON
            return 0
        else
            log "WARNING :: Deezer API returned HTTP ${httpCode} for URL ${url}, retrying ($((retries+1))/${maxRetries})..."
            ((retries++))
            sleep 1
        fi
    done

    log "WARNING :: Failed to get a valid response from Deezer API after ${maxRetries} attempts for URL ${url}"
    return 1
}

# Add custom tags if they don't already exist
AddLidarrTags () {
	local response tagCheck, httpCode

	# Fetch existing tags once
	response=$(LidarrApiRequest "GET" "/api/v1/tag")

	# Split comma-separated AUDIO_TAGS into array
	IFS=',' read -ra tags <<< "$AUDIO_TAGS"

	for tag in "${tags[@]}"; do
		tag=$(echo "$tag" | xargs)  # Trim whitespace
		log "INFO :: Processing tag: $tag"

		# Check if tag already exists
		tagCheck=$(echo "$response" | jq -r --arg TAG "$tag" '.[] | select(.label==$TAG) | .label')

		if [ -z "$tagCheck" ]; then
			log "INFO :: Tag not found, creating tag: $tag"
			response=$(LidarrApiRequest "POST" "/api/v1/tag" "{\"label\":\"${tag}\"}")
		else
			log "INFO :: Tag already exists: $tag"
		fi
	done
}

# Add custom download client if it doesn't already exist
AddLidarrDownloadClient() {
	local downloadClientsData downloadClientCheck httpCode

	# Get list of existing download clients
	downloadClientsData=$(LidarrApiRequest "GET" "/api/v1/downloadclient")

	# Check if our custom client already exists
	downloadClientCheck=$(echo "${downloadClientsData}" | jq -r '.[]?.name' | grep -Fx "${AUDIO_DOWNLOADCLIENT_NAME}" || true)

	if [ -z "${downloadClientCheck}" ]; then
		log "INFO :: ${AUDIO_DOWNLOADCLIENT_NAME} client not found, creating it..."

		# Build JSON payload
		read -r -d '' payload <<EOF
{
  "enable": true,
  "protocol": "usenet",
  "priority": 10,
  "removeCompletedDownloads": true,
  "removeFailedDownloads": true,
  "name": "${AUDIO_DOWNLOADCLIENT_NAME}",
  "fields": [
    {"name": "nzbFolder", "value": "${AUDIO_SHARED_LIDARR_PATH}"},
    {"name": "watchFolder", "value": "${AUDIO_SHARED_LIDARR_PATH}"}
  ],
  "implementationName": "Usenet Blackhole",
  "implementation": "UsenetBlackhole",
  "configContract": "UsenetBlackholeSettings",
  "infoLink": "https://wiki.servarr.com/lidarr/supported#usenetblackhole",
  "tags": []
}
EOF

		# Submit to API
		LidarrApiRequest "POST" "/api/v1/downloadclient" "${payload}"

		log "INFO :: Successfully added ${AUDIO_DOWNLOADCLIENT_NAME} download client."
	else
		log "INFO :: ${AUDIO_DOWNLOADCLIENT_NAME} download client already exists, skipping creation."
	fi
}

# Clean up old notfound entries to allow retries
NotFoundFolderCleaner () {
	if [ -d "${AUDIO_DATA_PATH}/notfound" ]; then
		# check for notfound entries older than AUDIO_RETRY_NOTFOUND_DAYS days
		if find "${AUDIO_DATA_PATH}/notfound" -mindepth 1 -type f -mtime +${AUDIO_RETRY_NOTFOUND_DAYS} | read; then
			log "INFO :: Removing prevously notfound lidarr album ids older than ${AUDIO_RETRY_NOTFOUND_DAYS} days to give them a retry..."
			# delete notfound entries older than AUDIO_RETRY_NOTFOUND_DAYS days
			find "${AUDIO_DATA_PATH}/notfound" -mindepth 1 -type f -mtime +${AUDIO_RETRY_NOTFOUND_DAYS} -delete
		fi
	fi
}

# Given a MusicBrainz release JSON object, return the title with disambiguation if present
GetReleaseTitleDisambiguation() {
	# $1 -> JSON object for a MusicBrainz release
	local release_json="$1"
	local releaseTitle releaseDisambiguation
	releaseTitle=$(echo "$release_json" | jq -r '.title')
	releaseDisambiguation=$(echo "$release_json" | jq -r '.disambiguation')
	if [ -z "$releaseDisambiguation" ] || [ "$releaseDisambiguation" == "null" ]; then
		releaseDisambiguation=""
	else
		releaseDisambiguation=" ($releaseDisambiguation)"
	fi
	echo "${releaseTitle}${releaseDisambiguation}"
}

# Download album using deemix
DownloadProcess () {
	# stdin - JSON data from Deezer API for the album
	# $1 -> MusicBrainz album id
	# $2 -> MusicBrainz release group id
	local mbAlbumId="${1}"
	local mbReleaseGroupId="${2}"

	local deezerAlbumJson
    deezerAlbumJson=$(cat)  # read JSON object from stdin

	# Create Required Directories	
	if [ ! -d "${AUDIO_WORK_PATH}/staging" ]; then
		mkdir -p "${AUDIO_WORK_PATH}"/staging
	else
		rm -rf "${AUDIO_WORK_PATH}"/staging/*
	fi
	
	if [ ! -d "${AUDIO_WORK_PATH}/complete" ]; then
		mkdir -p "${AUDIO_WORK_PATH}"/complete
	else
		rm -rf "${AUDIO_WORK_PATH}"/complete/*
	fi
	
	if [ ! -d "${AUDIO_WORK_PATH}/cache" ]; then
		mkdir -p "${AUDIO_WORK_PATH}"/cache
	else
		# Delete only files (and empty directories) older than $AUDIO_CACHE_MAX_AGE_DAYS
    	find "${AUDIO_WORK_PATH}/cache" -mindepth 1 -mtime +"$AUDIO_CACHE_MAX_AGE_DAYS" -exec rm -rf {} +
	fi

	if [ ! -d "${AUDIO_DATA_PATH}/downloaded" ]; then
		mkdir -p "${AUDIO_DATA_PATH}"/downloaded
	fi

	if [ ! -d "${AUDIO_DATA_PATH}/failed" ]; then
		mkdir -p "${AUDIO_DATA_PATH}"/failed
	fi

	if [ ! -d "${AUDIO_SHARED_LIDARR_PATH}" ]; then
		log "ERROR :: Shared Lidarr Path not found: ${AUDIO_SHARED_LIDARR_PATH}"
		setUnhealthy
	fi

	local deezerAlbumId deezerAlbumTitle deezerAlbumTitleClean deezerAlbumTrackCount deezerArtistName deezerArtistNameClean downloadedReleaseDate downloadedReleaseYear
	deezerAlbumId=$(echo "${deezerAlbumJson}" | jq -r ".id")
	deezerAlbumTitle=$(echo "${deezerAlbumJson}" | jq -r ".title" | head -n1)
	deezerAlbumTitleClean="$(echo "${deezerAlbumTitle}" | sed -e "s%[^[:alpha:][:digit:]._' ]% %g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g')"
 	deezerAlbumTrackCount="$(echo "${deezerAlbumJson}" | jq -r .nb_tracks)"
	deezerArtistName=$(jq -r '.artist.name' <<<"${deezerAlbumJson}")
	deezerArtistNameClean="$(echo "${deezerArtistName}" | sed -e "s%[^[:alpha:][:digit:]._' ]% %g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g')"
	downloadedReleaseDate=$(jq -r .release_date <<<"${deezerAlbumJson}")
	downloadedReleaseYear="${downloadedReleaseDate:0:4}"

	# Check if previously downloaded or failed download
	if [ -f "${AUDIO_DATA_PATH}/downloaded/${deezerAlbumId}" ]; then
		log "WARNING :: Album \"${deezerAlbumTitle}\" previously downloaded (${deezerAlbumId})...Skipping..."
		return 1
	fi
	if [ -f "${AUDIO_DATA_PATH}/failed/${deezerAlbumId}" ]; then
		log "WARNING :: Album \"${deezerAlbumTitle}\" previously failed to download ($deezerAlbumId)...Skipping..."
		return 1
	fi
	
	local downloadTry=0
	while true; do
		downloadTry=$(( $downloadTry + 1 ))

		# Stop trying after too many attempts
		if (( downloadTry >= AUDIO_DOWNLOAD_ATTEMPT_THRESHOLD )); then
			log "WARNING :: Album \"${deezerAlbumTitle}\" failed to download after ${downloadTry} attempts...Skipping..."
			return 1
		fi

		log "INFO :: Download attempt #${downloadTry} for album \"${deezerAlbumTitle}\""
		DEEMIX_ARL="${DEEMIX_ARL}" \
		deemix \
			-c ${DEEMIX_CONFIG_PATH} \
			-b "${deemixQuality}" \
			-p "${AUDIO_WORK_PATH}/staging" \
			"https://www.deezer.com/album/${deezerAlbumId}" 2>&1

		# Clean up any temporary deemix data
		rm -rf /tmp/deemix-imgs 2>/dev/null || true

		# Check if any audio files were downloaded
		local clientTestDlCount
		clientTestDlCount=$(find "${AUDIO_WORK_PATH}/staging" -type f \( -iname "*.flac" -o -iname "*.opus" -o -iname "*.m4a" -o -iname "*.mp3" \) | wc -l)
		if (( clientTestDlCount <= 0 )); then
			log "WARNING :: No audio files downloaded for album \"${deezerAlbumTitle}\" on attempt #${downloadTry}"
			continue
		fi

		# Verify all downloaded FLAC files
		find "${AUDIO_WORK_PATH}/staging" -type f -iname "*.flac" -print0 |
		while IFS= read -r -d '' file; do
			if audioFlacVerification "$file"; then
				log "INFO :: File \"${file}\" passed FLAC verification"
			else
				log "WARNING :: File \"${file}\" failed FLAC verification. Removing"
				rm -f "$file"
			fi
		done

		# Check if full album downloaded
		local downloadedCount
		downloadedCount=$(find "${AUDIO_WORK_PATH}/staging" -type f \( -iname "*.flac" -o -iname "*.opus" -o -iname "*.m4a" -o -iname "*.mp3" \) | wc -l)
		if (( downloadedCount != deezerAlbumTrackCount )); then
			log "WARNING :: Album \"${deezerAlbumTitle}\" did not download expected number of tracks"
			sleep 1
			continue
		else
			break
		fi
	done

	# Consolidate files to a single folder and delete empty folders
	log "INFO :: Consolidating files to single folder"
	{
		shopt -s nullglob
		for f in "${AUDIO_WORK_PATH}"/staging/*/*; do
			mv "$f" "${AUDIO_WORK_PATH}/staging/"
		done
		shopt -u nullglob
	}
	# Remove now-empty subdirectories
	find "${AUDIO_WORK_PATH}/staging/" -type d -mindepth 1 -maxdepth 1 -exec rm -rf {} \; 2>/dev/null

	# Add the musicbrainz album id to the files
	{
		shopt -s nullglob
		# TODO: Tag more than just FLAC files if needed
		for file in "${AUDIO_WORK_PATH}"/staging/*.{flac}; do
			[ -f "$file" ] || continue  # extra safety in case glob expands to nothing
			metaflac --set-tag=MUSICBRAINZ_ALBUMID="$mbAlbumId" "$file"
			metaflac --set-tag=MUSICBRAINZ_RELEASEGROUPID="$mbReleaseGroupId" "$file"		
		done
		shopt -u nullglob
	}

	# Log Completed Download
	log "INFO :: Album \"${deezerAlbumTitle}\" successfully downloaded"
	touch "${AUDIO_DATA_PATH}/downloaded/${deezerAlbumId}"

	
	if [ "$enableReplaygainTags" == "true" ]; then
		AddReplaygainTags "${AUDIO_WORK_PATH}/staging"
	else
		log "INFO :: Replaygain tagging disabled"
	fi
	
	local downloadedAlbumFolder="${deezerArtistNameClean}-${deezerAlbumTitleClean:0:100} (${downloadedReleaseYear})"

	mkdir -p "${AUDIO_SHARED_LIDARR_PATH}/${downloadedAlbumFolder}"
	find "${AUDIO_WORK_PATH}/staging" -type f -regex ".*/.*\.\(flac\|m4a\|mp3\|flac\|opus\)" -exec mv {} "${AUDIO_SHARED_LIDARR_PATH}/${downloadedAlbumFolder}"/ \;

	NotifyLidarrForImport "${AUDIO_SHARED_LIDARR_PATH}/${downloadedAlbumFolder}"
	lidarrDownloadImportNotfication="true"
	LidarrTaskStatusCheck

	# Clean up incomplete folder
	rm -rf "${AUDIO_WORK_PATH}/staging"/*
}

# Add ReplayGain tags to audio files in the specified folder
#TODO: replace with rsgain
AddReplaygainTags () {
    # $1 -> folder path containing audio files to be tagged
    log "INFO :: Adding ReplayGain Tags using r128gain"

    if ! r128gain -r -c 1 -a "$1" >/dev/null 2> /tmp/r128gain_errors.log; then
        log "WARNING :: r128gain encountered errors while processing $1. See /tmp/r128gain_errors.log for details."
    else
        rm -f /tmp/r128gain_errors.log
    fi
}

# Notify Lidarr to import the downloaded album
NotifyLidarrForImport() {
    # $1 -> folder path containing audio files for Lidarr to import
    local importPath="${1}"

    LidarrApiRequest "POST" "/api/v1/command" "{\"name\":\"DownloadedAlbumsScan\", \"path\":\"${importPath}\"}"

    log "INFO :: Sent notification to Lidarr to import downloaded album at path: ${importPath}"
}

# Set up Deemix client configuration
DeemixClientSetup() {
    log "INFO :: Setting up Deemix client"

    # 1️⃣ Determine ARL token
    if [[ -n "${AUDIO_DEEMIX_ARL_FILE}" && -f "${AUDIO_DEEMIX_ARL_FILE}" ]]; then
		DEEMIX_ARL="$(tr -d '\r\n' <"${AUDIO_DEEMIX_ARL_FILE}")"
    else
        log "ERROR :: No Deemix ARL token provided. Set AUDIO_DEEMIX_ARL_FILE."
		setUnhealthy
        exit 1
    fi

    # 2️⃣ Copy default config to /tmp
    DEFAULT_CONFIG="/app/config/default_deemix_config.json"

    if [[ ! -f "${DEFAULT_CONFIG}" ]]; then
        log "ERROR :: Default Deemix config not found at ${DEFAULT_CONFIG}"
        return 1
    fi

    cp -f "${DEFAULT_CONFIG}" "${DEEMIX_CONFIG_PATH}"

    # 3️⃣ Merge custom config if provided
    if [[ -n "${AUDIO_DEEMIX_CUSTOM_CONFIG}" ]]; then
        # AUDIO_DEEMIX_CUSTOM_CONFIG can be a path to JSON or raw JSON string
        if [[ -f "${AUDIO_DEEMIX_CUSTOM_CONFIG}" ]]; then
            CUSTOM_CONFIG_CONTENT="$(<"${AUDIO_DEEMIX_CUSTOM_CONFIG}")"
        else
            CUSTOM_CONFIG_CONTENT="${AUDIO_DEEMIX_CUSTOM_CONFIG}"
        fi

        # Merge default and custom config; custom overrides defaults
        TMP_CONFIG_CONTENT=$(jq -s '.[0] * .[1]' \
            <(cat "${DEEMIX_CONFIG_PATH}") \
            <(echo "${CUSTOM_CONFIG_CONTENT}"))

        echo "${TMP_CONFIG_CONTENT}" > "${DEEMIX_CONFIG_PATH}"
        log "INFO :: Custom Deemix config merged into /tmp/deemix_config.json"
    fi

    log "INFO :: Deemix client setup complete. ARL token stored in global DEEMIX_ARL variable."
}

# Retrieve and process Lidarr wanted list (missing or cutoff)
ProcessLidarrWantedList () {
    # $1 -> Type of list to process ("missing" or "cutoff")
    local listType=$1
    local searchOrder="releaseDate"
    local searchDirection="descending"
    local pageSize=1000

    log "INFO :: Retrieving ${listType} albums from Lidarr"

	# Get total count of albums
	local totalRecords
	totalRecords=$(LidarrApiRequest "GET" "/api/v1/wanted/${listType}?page=1&pagesize=1&sortKey=${searchOrder}&sortDirection=${searchDirection}" \
		| jq -r .totalRecords)
    log "INFO :: Found ${totalRecords} ${listType} albums"

    if (( totalRecords < 1 )); then
        log "INFO :: No ${listType} albums to process"
        return
    fi

    # Preload all notfound IDs into memory (only once)
    mapfile -t notfound < <(
        find "${AUDIO_DATA_PATH}/notfound/" -type f -printf "%f\n" | sed 's/--.*//' | sort
    )

    local totalPages=$(( (totalRecords + pageSize - 1) / pageSize ))

    for (( page=1; page<=totalPages; page++ )); do
        log "INFO :: Downloading page ${page} of ${totalPages} for ${listType} albums"

		# Fetch page of album IDs
		mapfile -t tocheck < <(
			LidarrApiRequest "GET" "/api/v1/wanted/${listType}?page=${page}&pagesize=${pageSize}&sortKey=${searchOrder}&sortDirection=${searchDirection}" \
				| jq -r '.records[].id' | sort
		)

        # Filter out already failed/notfound IDs
        mapfile -t toProcess < <(comm -13 <(printf "%s\n" "${notfound[@]}") <(printf "%s\n" "${tocheck[@]}"))

        local recordCount=${#toProcess[@]}
        log "INFO :: ${recordCount} ${listType} albums to process"

        if (( recordCount > 0 )); then
            log "INFO :: Starting search for ${recordCount} ${listType} albums"
            for lidarrRecordId in "${toProcess[@]}"; do
                SearchProcess "$lidarrRecordId"
            done
        fi
    done

    log "INFO :: Completed processing ${listType} albums"
}

# Given a Lidarr album ID, search for and attempt to download the album
SearchProcess () {
    # $1 -> Deezer album ID
    local wantedAlbumId="$1"
    if [ -z "$wantedAlbumId" ]; then
        log "WARNING :: No album ID provided to SearchProcess"
        return
    fi

	# Fetch album data from Lidarr
	local lidarrAlbumData
	lidarrAlbumData="$(LidarrApiRequest "GET" "/api/v1/album/${wantedAlbumId}")"
    if [ -z "$lidarrAlbumData" ]; then
        log "WARNING :: Lidarr returned no data for album ID ${wantedAlbumId}"
        return
    fi

	# Extract artist and album info
    local lidarrArtistData lidarrArtistName lidarrArtistId lidarrArtistForeignArtistId
    lidarrArtistData=$(echo "$lidarrAlbumData" | jq -r ".artist")
    lidarrArtistName=$(echo "$lidarrArtistData" | jq -r ".artistName")
    lidarrArtistId=$(echo "$lidarrArtistData" | jq -r ".artistMetadataId")
    lidarrArtistForeignArtistId=$(echo "$lidarrArtistData" | jq -r ".foreignArtistId")

    local lidarrAlbumTitle lidarrAlbumType lidarrAlbumForeignAlbumId
    lidarrAlbumTitle=$(echo "$lidarrAlbumData" | jq -r ".title")
    lidarrAlbumType=$(echo "$lidarrAlbumData" | jq -r ".albumType")
    lidarrAlbumForeignAlbumId=$(echo "$lidarrAlbumData" | jq -r ".foreignAlbumId")

    # Check if album was previously marked "not found"
    if [ -f "${AUDIO_DATA_PATH}/notfound/${wantedAlbumId}--${lidarrArtistForeignArtistId}--${lidarrAlbumForeignAlbumId}" ]; then
        log "INFO :: Album \"${lidarrAlbumTitle}\" by artist \"${lidarrArtistName}\" was previously marked as not found, skipping..."
        return
    fi

    # Release date check
    local releaseDate releaseDateClean currentDateClean albumIsNewRelease
    releaseDate=$(echo "${lidarrAlbumData}" | jq -r ".releaseDate")
    releaseDate=${releaseDate:0:10}  # YYYY-MM-DD
    releaseDateClean=$(echo "${releaseDate}" | sed -e 's/[^0-9]//g') # YYYYMMDD

    currentDateClean=$(date "+%Y%m%d")
	albumIsNewRelease="false"
    if [[ "${currentDateClean}" -lt "${releaseDateClean}" ]]; then
        log "INFO :: Album \"${lidarrAlbumTitle}\" by artist \"${lidarrArtistName}\" has not been released yet (${releaseDate}), skipping..."
        return
	elif (( currentDateClean - releaseDateClean < 8 )); then
		albumIsNewRelease="true"
    fi

	log "INFO :: Starting search for album \"${lidarrAlbumTitle}\" by artist \"${lidarrArtistName}\""

    # Extract artist links
    local deezerArtistUrl=$(echo "${lidarrArtistData}" | jq -r '.links[]? | select(.name=="deezer") | .url')
    if [ -z "${deezerArtistUrl}" ]; then
        log "WARNING :: Missing Deezer link for artist ${lidarrArtistName}, skipping..."
        return
    fi
	local deezerArtistIds=($(echo "${deezerArtistUrl}" | grep -o '[[:digit:]]+' | sort -u))

	# Sort releases based on preference for special editions
	# Sort parameter explanations:
	#  - Track count (descending)
	#  - Rank (0 for preferred editions, 1 for others)
	#  - Title length (ascending if prefer special editions, descending if not)

	# Debugging output
	# echo "$lidarrAlbumData" | jq -c '.releases[]' | while IFS= read -r release_json; do
	# 	log "DEBUG :: before sort :: $release_json"
	# done
	jq_filter_special="[.releases[]
	| .normalized_title = (.title | ascii_downcase)
	| .title_length = (.title | length)
	| .rank = (if (.normalized_title | test(\"deluxe|expanded|special|remaster\")) then 0 else 1 end)
	] | sort_by(-.trackCount, .rank, -.title_length)"

	jq_filter_normal="[.releases[]
	| .normalized_title = (.title | ascii_downcase)
	| .title_length = (.title | length)
	| .rank = (if (.normalized_title | test(\"deluxe|expanded|special|remaster\")) then 1 else 0 end)
	] | sort_by(-.trackCount, .rank, .title_length)"

	local sorted_releases
	if [ "${AUDIO_PREFER_SPECIAL_EDITIONS}" == "true" ]; then
		sorted_releases=$(echo "${lidarrAlbumData}" | jq -c "${jq_filter_special}")
	else
		sorted_releases=$(echo "${lidarrAlbumData}" | jq -c "${jq_filter_normal}")
	fi
	# Debugging output
	# echo "$sorted_releases" | jq -c '.[]' | while IFS= read -r release_json; do
	# 	log "DEBUG :: after sort :: $release_json"
	# done

	# Determine lyric filter for first pass
	local lyricFilter=()
	case "${AUDIO_LYRIC_TYPE}" in
		require-explicit)
			lyricFilter=( "Explicit" )
			;;
		require-clean)
			lyricFilter=( "Clean" )
			;;
		prefer-explicit)
			lyricFilter=( "Explicit" "Clean" )
			;;
		prefer-clean)
			lyricFilter=( "Clean" "Explicit" )
			;;
		*)
			log "WARNING :: Unknown AUDIO_LYRIC_TYPE='${AUDIO_LYRIC_TYPE}', defaulting to both"
			lyricFilter=( "Explicit" "Clean" )
			;;
	esac

	# Start search loop
	local matchFound="false"
	for lyricType in "${lyricFilter[@]}"; do
		log "INFO :: Searching with lyric filter: ${lyricType}"

		# Process each release from Lidarr in sorted order
		local releases
		mapfile -t releasesArray < <(jq -c '.[]' <<<"$sorted_releases")
		for release_json in "${releasesArray[@]}"; do
			lidarrReleaseTitle=$(GetReleaseTitleDisambiguation "${release_json}")
			lidarrReleaseTrackCount=$(echo "$release_json" | jq -r ".trackCount")
			lidarrReleaseForeignId=$(echo "$release_json" | jq -r ".foreignReleaseId")

			# TODO: Enhance this functionality to intelligently handle releases that are expected to have these keywords
			# Ignore instrumental-like releases if configured
			if [[ "${AUDIO_IGNORE_INSTRUMENTAL_RELEASES}" == "true" ]]; then
				# Convert comma-separated list into an alternation pattern for Bash regex
				IFS=',' read -r -a keywordArray <<< "${AUDIO_INSTRUMENTAL_KEYWORDS}"
				keywordPattern="($(IFS="|"; echo "${keywordArray[*]}"))" # join array with | for pattern matching

				if [[ "${lidarrAlbumTitle}" =~ ${keywordPattern} ]]; then
					log "INFO :: Album \"${lidarrAlbumTitle}\" matched instrumental keyword (${AUDIO_INSTRUMENTAL_KEYWORDS}), skipping..."
					continue
				elif [[ "${lidarrReleaseTitle,,}" =~ ${keywordPattern,,} ]]; then
					log "INFO :: Release \"${lidarrReleaseTitle}\" matched instrumental keyword (${AUDIO_INSTRUMENTAL_KEYWORDS}), skipping..."
					continue
				fi
			fi

			# First search through the artist's Deezer albums to find a match on album title and track count
			if [ "${lidarrArtistForeignArtistId}" != "${VARIOUS_ARTIST_ID}" ]; then # Skip various artists
				if [[ "$matchFound" == "false" ]]; then
					for dId in "${!deezerArtistIds[@]}"; do
						local deezerArtistId="${deezerArtistIds[$dId]}"
						ArtistDeezerSearch matchFound "${lyricType}" "${deezerArtistId}" "${lidarrReleaseTitle}" "${lidarrReleaseTrackCount}" "${lidarrReleaseForeignId}" "${lidarrAlbumForeignAlbumId}"
					done
				fi
			fi

			# Fuzzy search
			if [ "${matchFound}" == "false" ]; then
				FuzzyDeezerSearch matchFound "${lyricType}" "${lidarrArtistName}" "${lidarrReleaseTitle}" "${lidarrArtistForeignArtistId}" "${lidarrReleaseTrackCount}" "${lidarrReleaseForeignId}" "${lidarrAlbumForeignAlbumId}"
			fi

			# End search if a match was found
			if [ "${matchFound}" == "true" ]; then
				break
			fi
		done

		# End search if a match was found
		if [ "${matchFound}" == "true" ]; then
			break
		fi
	done

	log "INFO :: Search process complete..."

	if [ "${matchFound}" == "false" ]; then
		log "INFO :: Album not found"
		if [ "${albumIsNewRelease}" == "true" ]; then
			log "INFO :: Skip marking album as not found because it's a new release..."
		else
			log "INFO :: Marking album as not found"
			if [ ! -f "${AUDIO_DATA_PATH}/notfound/${wantedAlbumId}--${lidarrArtistForeignArtistId}--${lidarrAlbumForeignAlbumId}" ]; then
				touch "${AUDIO_DATA_PATH}/notfound/${wantedAlbumId}--${lidarrArtistForeignArtistId}--${lidarrAlbumForeignAlbumId}"
			fi
		fi
	fi
}

# Search Deezer artist's albums for matches
ArtistDeezerSearch() {
	# $1 -> name of variable to set to "true" if a download is successful
    # $2 -> Lyric Type ("Clean" or "Explicit")
    # $3 -> Deezer Artist ID
	# $4 -> lidarr album title
	# $5 -> lidarr album track count
	# $6 -> MusicBrainz album id
	# $7 -> MusicBrainz release group id
	local matchVarName="${1}"
    local lyricType="${2}"
    local artistId="${3}"
    local albumTitle="${4}"
    local trackCount="${5}"
	local mbAlbumId="${6}"
	local mbReleaseGroupId="${7}"

    local explicitFilter="false"
    if [[ "${lyricType}" == "Explicit" ]]; then
        explicitFilter="true"
    fi

    log "INFO :: Artist searching..."

    # Get Deezer artist album list
    local artistAlbums filteredAlbums resultsCount
    if artistAlbums=$(GetDeezerArtistAlbums "${artistId}"); then
        # Filter albums by lyric type (true/false for explicit_lyrics)
        filteredAlbums=$(jq -c ".data | map(select(.explicit_lyrics == ${explicitFilter}))" <<<"${artistAlbums}")

        resultsCount=$(jq 'length' <<<"${filteredAlbums}")
        log "INFO :: Searching albums for Artist ${artistId} filtered by ${lyricType} lyrics (Total Albums: ${resultsCount} found)"

        # Pass filtered albums to the DownloadBestMatch function
        if (( resultsCount > 0 )); then
            echo "${filteredAlbums}" | DownloadBestMatch ${matchVarName} ${albumTitle} ${trackCount} "${mbAlbumId}" "${mbReleaseGroupId}"
        fi
    else
        log "WARNING :: Failed to fetch album list for Deezer artist ID ${artistId}"
        return 1
    fi
}

# Fuzzy search Deezer for albums matching title and artist
FuzzyDeezerSearch() {
	# $1 -> name of variable to set to "true" if a download is successful
    # $2 -> Lyric Type ("true" = explicit, "false" = clean)
	# $3 -> lidarr artist name
	# $4 -> lidarr album title
	# $5 -> lidarr artist foreign artist id (to check for various artists)
	# $6 -> lidarr album track count
	# $7 -> MusicBrainz album id
	# $8 -> MusicBrainz release group id

	local matchVarName="${1}"
    local lyricFlag="${2}"
    local artistName="${3}"
    local albumTitle="${4}"
    local artistForeignArtistId="${5}"
	local trackCount="${6}"
	local mbAlbumId="${7}"
	local mbReleaseGroupId="${8}"
    local type
    local deezerSearch
    local resultsCount
    local albumsJson
    local url

    if [[ "${lyricFlag}" == "true" ]]; then
        type="Explicit"
    else
        type="Clean"
    fi

    log "INFO :: Fuzzy searching for '${albumTitle}' by '${artistName}' (${type} lyrics)..."

	# Prepare search terms
	local albumTitleSearch albumArtistNameSearch lidarrAlbumReleaseTitleSearchClean lidarrArtistNameSearchSanitized
	lidarrAlbumReleaseTitleSearchClean="$(echo "$albumTitle" | sed -e "s%[^[:alpha:][:digit:]]% %g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g')"
	lidarrArtistNameSearchSanitized="$(echo "$artistName" | sed -e "s%[^[:alpha:][:digit:]]% %g" -e "s/  */ /g")"
	albumTitleSearch="$(jq -R -r @uri <<<"${lidarrAlbumReleaseTitleSearchClean}")"
	albumArtistNameSearch="$(jq -R -r @uri <<<"${lidarrArtistNameSearchSanitized}")"

    # Build search URL
    if [[ "${artistForeignArtistId}" == "${VARIOUS_ARTIST_ID}" ]]; then
        url="https://api.deezer.com/search?q=album:%22${albumTitleSearch}%22&strict=on&limit=20"
    else
        url="https://api.deezer.com/search?q=artist:%22${albumArtistNameSearch}%22%20album:%22${albumTitleSearch}%22&strict=on&limit=20"
    fi

    # Call Deezer API
    if deezerSearch=$(CallDeezerAPI "${url}"); then
        resultsCount=$(jq 'map(.album.id) | unique | length' <<<"${deezerSearch}")
        log "INFO :: ${resultsCount} search results found for '${albumTitle}' by '${artistName}'"

        if [[ -n "${deezerSearch}" ]]; then
            albumsJson=$(jq '[.[].album] | unique_by(.id)' <<<"${deezerSearch}")
            echo "${albumsJson}" | DownloadBestMatch ${matchVarName} ${albumTitle} ${trackCount} "${mbAlbumId}" "${mbReleaseGroupId}"
        else
            log "INFO :: No results found via Fuzzy Search for '${albumTitle}' by '${artistName}'"
        fi
    else
        log "WARNING :: Deezer Fuzzy Search failed for '${albumTitle}' by '${artistName}'"
    fi
}

# Given a JSON array of Deezer albums, find the best match based on title similarity and track count
DownloadBestMatch() {
	# $1 -> name of variable to set to "true" if a download is successful
	# $2 -> title of Lidarr release
    # $3 -> track count of Lidarr release
	# $4 -> MusicBrainz album id
	# $5 -> MusicBrainz release group id
    # stdin -> JSON array containing list of Deezer albums to check

    local matchVarName="${1}"
    local releaseTitle="${2}"
    local trackCount="${3}"
	local mbAlbumId="${4}"
	local mbReleaseGroupId="${5}"
    local albums albumsCount bestMatchID bestMatchTitle bestMatchYear
    local bestMatchDistance bestMatchTrackDiff

    albums=$(cat)  # read JSON array from stdin
    albumsCount=$(jq 'length' <<<"${albums}")

    bestMatchID=""
    bestMatchTitle=""
    bestMatchYear=""
    bestMatchDistance=9999
    bestMatchTrackDiff=9999

	# Normalize Lidarr release title
	local releaseTitleClean
	releaseTitleClean=$(echo "$releaseTitle" | sed -e "s%[^[:alpha:][:digit:]]%%g" -e "s/  */ /g" | sed 's/^[.]*//' | sed  's/[.]*$//g' | sed  's/^ *//g' | sed 's/ *$//g')
	releaseTitleClean="${releaseTitleClean:0:130}"

	for ((i=0; i<albumsCount; i++)); do
        local deezerAlbumData deezerAlbumID deezerAlbumTitle deezerAlbumTitleClean
        local deezerAlbumTrackCount downloadedReleaseDate downloadedReleaseYear
        local trackNumberMatch diff trackDiff

        deezerAlbumData=$(jq -c ".[$i]" <<<"${albums}")
        deezerAlbumID=$(jq -r ".id" <<<"${deezerAlbumData}")
        deezerAlbumTitle=$(jq -r ".title" <<<"${deezerAlbumData}")

		# --- Normalize title ---
        deezerAlbumTitleClean=$(echo "${deezerAlbumTitle}" \
            | sed -e "s%[^[:alpha:][:digit:]]%%g" -e "s/  */ /g" \
            | sed 's/^[.]*//' | sed 's/[.]*$//' | sed 's/^ *//' | sed 's/ *$//')
        deezerAlbumTitleClean="${deezerAlbumTitleClean:0:130}"

		# Get album info from Deezer
        if deezerAlbumData=$(GetDeezerAlbumInfo "${deezerAlbumID}"); then
            deezerAlbumTrackCount=$(jq -r .nb_tracks <<<"${deezerAlbumData}")
            downloadedReleaseDate=$(jq -r .release_date <<<"${deezerAlbumData}")
            downloadedReleaseYear="${downloadedReleaseDate:0:4}"
        else
            log "WARNING :: Failed to fetch album info for Deezer album ID ${deezerAlbumID}, skipping..."
            continue
        fi

		# Check if number of tracks matches exactly
		trackNumberMatch=0
		(( deezerAlbumTrackCount == trackCount )) && trackNumberMatch=1

        # Compute Levenshtein distance
        diff=$(LevenshteinDistance "${releaseTitleClean,,}" "${deezerAlbumTitleClean,,}")
        trackDiff=$(( trackCount > deezerAlbumTrackCount ? trackCount - deezerAlbumTrackCount : deezerAlbumTrackCount - trackCount ))

        log "INFO :: DL Dist=${diff} TrackDiff=${trackDiff} (${deezerAlbumTrackCount} tracks)"

        if (( diff <= ${AUDIO_MATCH_DISTANCE_THRESHOLD} )); then
            log "INFO :: Potential match found :: ${deezerAlbumTitle} (${downloadedReleaseYear}) :: Distance=${diff} TrackDiff=${trackDiff}"
        else
			log "INFO :: Album does not meet matching threshold, skipping..."
		fi

        # Perfect match
        if (( diff == 0 && trackNumberMatch == 1 )); then
            bestMatchID="${deezerAlbumID}"
            bestMatchTitle="${deezerAlbumTitle}"
            bestMatchYear="${downloadedReleaseYear}"
            log "INFO :: Perfect match found :: ${bestMatchTitle} (${bestMatchYear})"
            break
        fi

        # Track best match so far
        if (( diff < bestMatchDistance )) || (( diff == bestMatchDistance && trackDiff < bestMatchTrackDiff )); then
            bestMatchID="${deezerAlbumID}"
            bestMatchTitle="${deezerAlbumTitle}"
            bestMatchYear="${downloadedReleaseYear}"
            bestMatchDistance="${diff}"
            bestMatchTrackDiff="${trackDiff}"
        fi
	done

    # After loop — use best match
    if [[ -n "${bestMatchID}" ]]; then
        log "INFO :: Using best match :: ${bestMatchTitle} (${bestMatchYear}) :: Distance=${bestMatchDistance} TrackDiff=${bestMatchTrackDiff}"

        if deezerAlbumData=$(GetDeezerAlbumInfo "${bestMatchID}"); then
            echo "${deezerAlbumData}" | DownloadProcess "${mbAlbumId}" "${mbReleaseGroupId}"
			eval "$matchVarName=true"
        else
            log "WARNING :: Failed to fetch album info for Deezer album ID ${bestMatchID}. Unable to download..."
        fi
    else
        log "INFO :: No suitable match found."
    fi
}

# Checks Lidarr for any active tasks and waits for them to complete
LidarrTaskStatusCheck() {
    local alerted="no"
    local taskList taskCount

    while true; do
        # Fetch all commands from Lidarr
        taskList=$(LidarrApiRequest "GET" "/api/v1/command")

        # Count active tasks
        taskCount=$(jq -r '.[] | select(.status=="started") | .name' <<<"$taskList" | wc -l)

        if (( taskCount >= 1 )); then
            if [[ "$alerted" == "no" ]]; then
                alerted="yes"
                log "STATUS :: LIDARR BUSY :: Pausing/waiting for all active Lidarr tasks to end..."
            fi
            sleep 2
        else
            break
        fi
    done
}

# Verify a FLAC file for corruption
audioFlacVerification() {
  # $1 = path to FLAC file
  flac --totally-silent -t "$1" >/dev/null 2>&1
}

###### Script Execution #####

### Preamble ###

log "INFO :: Starting $scriptName version $scriptVersion"

log "DEBUG :: AUDIO_APPLY_REPLAYGAIN=${AUDIO_APPLY_REPLAYGAIN}"
log "DEBUG :: AUDIO_CACHE_MAX_AGE_DAYS=${AUDIO_CACHE_MAX_AGE_DAYS}"
log "DEBUG :: AUDIO_DATA_PATH=${AUDIO_DATA_PATH}"
log "DEBUG :: AUDIO_DEEMIX_CUSTOM_CONFIG=${AUDIO_DEEMIX_CUSTOM_CONFIG}"
log "DEBUG :: AUDIO_DEEZER_API_RETRIES=${AUDIO_DEEZER_API_RETRIES}"
log "DEBUG :: AUDIO_DEEZER_API_TIMEOUT=${AUDIO_DEEZER_API_TIMEOUT}"
log "DEBUG :: AUDIO_DEEMIX_ARL_FILE=${AUDIO_DEEMIX_ARL_FILE}"
log "DEBUG :: AUDIO_DOWNLOADCLIENT_NAME=${AUDIO_DOWNLOADCLIENT_NAME}"
log "DEBUG :: AUDIO_DOWNLOAD_ATTEMPT_THRESHOLD=${AUDIO_DOWNLOAD_ATTEMPT_THRESHOLD}"
log "DEBUG :: AUDIO_DOWNLOAD_CLIENT_TIMEOUT=${AUDIO_DOWNLOAD_CLIENT_TIMEOUT}"
log "DEBUG :: AUDIO_FAILED_ATTEMPT_THRESHOLD=${AUDIO_FAILED_ATTEMPT_THRESHOLD}"
log "DEBUG :: AUDIO_IGNORE_INSTRUMENTAL_RELEASES=${AUDIO_IGNORE_INSTRUMENTAL_RELEASES}"
log "DEBUG :: AUDIO_INSTRUMENTAL_KEYWORDS=${AUDIO_INSTRUMENTAL_KEYWORDS}"
log "DEBUG :: AUDIO_INTERVAL=${AUDIO_INTERVAL}"
log "DEBUG :: AUDIO_LYRIC_TYPE=${AUDIO_LYRIC_TYPE}"
log "DEBUG :: AUDIO_MATCH_DISTANCE_THRESHOLD=${AUDIO_MATCH_DISTANCE_THRESHOLD}"
log "DEBUG :: AUDIO_PREFER_SPECIAL_EDITIONS=${AUDIO_PREFER_SPECIAL_EDITIONS}"
log "DEBUG :: AUDIO_REQUIRE_QUALITY=${AUDIO_REQUIRE_QUALITY}"
log "DEBUG :: AUDIO_RETRY_NOTFOUND_DAYS=${AUDIO_RETRY_NOTFOUND_DAYS}"
log "DEBUG :: AUDIO_SHARED_LIDARR_PATH=${AUDIO_SHARED_LIDARR_PATH}"
log "DEBUG :: AUDIO_TAGS=${AUDIO_TAGS}"
log "DEBUG :: AUDIO_WORK_PATH=${AUDIO_WORK_PATH}"

### Validation ###

if ! [[ "$ARL_UPDATE_INTERVAL" =~ ^[0-9]+[smhd]$ ]]; then
    log "ERROR :: ARL_UPDATE_INTERVAL is invalid"
    setUnhealthy
fi

### Main ###

# Connect to Lidarr
lidarrApiKey="$(getLidarrApiKey)" || setUnhealthy
lidarrUrl="$(getLidarrUrl)" || setUnhealthy

# Create Lidarr entities
AddLidarrTags
AddLidarrDownloadClient

# Setup Deemix
DeemixClientSetup

log "INFO :: Lift off in..."; sleep 0.5
log "INFO :: 5"; sleep 1
log "INFO :: 4"; sleep 1
log "INFO :: 3"; sleep 1
log "INFO :: 2"; sleep 1
log "INFO :: 1"; sleep 1
for (( ; ; )); do
	# Cleanup old markers for albums previously marked as not found
	NotFoundFolderCleaner

    ProcessLidarrWantedList "missing"
    ProcessLidarrWantedList "cutoff"

	log "Script sleeping for ${AUDIO_INTERVAL}..."
	sleep ${AUDIO_INTERVAL}
done

exit 0
