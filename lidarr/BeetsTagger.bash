#!/usr/bin/env bash
scriptVersion="1.8"
scriptName="BeetsTagger"

#### Import Settings
source /config/extended.conf
#### Import Functions
source /config/extended/functions
#### Create Log File
logfileSetup

# Ignore broken pipe errors globally
trap '' PIPE

SECONDS=0

if [ "$lidarr_eventtype" == "Test" ]; then
	log "Tested Successfully"
	exit 0	
fi

getArrAppInfo
verifyApiAccess

if [ -z "$lidarr_album_id" ]; then
	lidarr_album_id="$1"
fi

if [ "$enableBeetsTagging" != "true" ]; then
  log "Beets tagging is disabled, please enable by setting \"enableBeetsTagging=true\" in \"/config/extended.conf\""
  exit 0
fi
log "DEBUG :: Album API URL: $arrUrl/api/v1/album/$lidarr_album_id"

# --- Fetch album JSON ---
albumJson=$(mktemp)
if ! curl -s --fail "$arrUrl/api/v1/album/$lidarr_album_id" -H "X-Api-Key: ${arrApiKey}" -o "$albumJson"; then
    log "ERROR :: Failed to fetch album JSON from Lidarr API"
    exit 1
fi

getAlbumArtist="$(jq -r '.artist.artistName // empty' 2>/dev/null "$albumJson")"
getAlbumArtistPath="$(jq -r '.artist.path // empty' 2>/dev/null "$albumJson")"

if [ -z "$getAlbumArtist" ] || [ -z "$getAlbumArtistPath" ]; then
    log "ERROR :: Album JSON is empty or missing artist info :: album_id=$lidarr_album_id"
    exit 1
fi

# --- Fetch track files ---
trackJson=$(mktemp)
if ! curl -s --fail "$arrUrl/api/v1/trackFile?albumId=$lidarr_album_id" -H "X-Api-Key: ${arrApiKey}" -o "$trackJson"; then
    log "ERROR :: Failed to fetch trackFile JSON from Lidarr API"
    exit 1
fi

getTrackPath="$(jq -r '.[0]?.path // empty' 2>/dev/null "$trackJson")"
if [ -z "$getTrackPath" ]; then
    log "ERROR :: No track files found for album_id=$lidarr_album_id"
    exit 1
fi

getFolderPath="$(dirname "$getTrackPath")"
getAlbumFolderName="$(basename "$getFolderPath")"

#log "DEBUG :: getAlbumArtist=$getAlbumArtist"
#log "DEBUG :: getAlbumArtistPath=$getAlbumArtistPath"
#log "DEBUG :: getTrackPath=$getTrackPath"
#log "DEBUG :: getFolderPath=$getFolderPath"
#log "DEBUG :: getAlbumFolderName=$getAlbumFolderName"

# --- Verify folder path ---
if [[ "$getFolderPath" != *"$getAlbumArtistPath"* ]]; then
    log "ERROR :: $getAlbumArtistPath not found within \"$getFolderPath\" :: Exiting..."
    exit 1
fi

if [ ! -d "$getFolderPath" ]; then
    log "ERROR :: Folder \"$getFolderPath\" is missing :: Exiting..."
    exit 1
fi

log "Processing :: $getAlbumFolderName :: Processing Files..."

if echo "$getFolderPath" | grep "$getAlbumArtistPath" | read; then
	if [ ! -d "$getFolderPath" ]; then
		log "ERROR :: \"$getFolderPath\" Folder is missing :: Exiting..."
	fi
else 
	log "ERROR :: $getAlbumArtistPath not found within \"$getFolderPath\" :: Exiting..."
	exit
fi

ProcessWithBeets () {
	log "$1 :: Start Processing..."
	if find "$1" -type f -iname "*.flac"  | read; then
 		sleep 0.01
   	else
    	log "$1 :: ERROR :: Only supports flac files, exiting..." 
    	return
    fi
	SECONDS=0
	

	# Input
	# $1 Download Folder to process
	if [ -f /config/extended/library-lidarr.blb ]; then
		rm /config/extended/library-lidarr.blb
		sleep 0.5
	fi
	if [ -f /config/extended/extended/beets-lidarr.log ]; then 
		rm /config/extended/extended/beets-lidarr.log
		sleep 0.5
	fi

	if [ -f "/config/extended/beets-lidarr-match" ]; then 
		rm "/config/extended/beets-lidarr-match"
		sleep 0.5
	fi
	touch "/config/extended/beets-lidarr-match"
	sleep 0.5

        log "$1 :: Begin matching with beets!"
	beet -c /config/extended/beets-config-lidarr.yaml -l /config/extended/library-lidarr.blb -d "$1" import -qC "$1" 2>&1 | tee -a "/config/logs/$logFileName"
	# Fix tags
	log "$1 :: Fixing Tags..."
		
	# Fix flac tags
	fixed=0
	find "$1" -type f -iname "*.flac" -print0 | while IFS= read -r -d '' file; do
		if [ $fixed == 0 ]; then
			fixed=$(( $fixed + 1 ))
			log "$1 :: Fixing Flac Tags..."
		fi
		getArtistCredit="$(ffprobe -loglevel 0 -print_format json -show_format -show_streams "$file" | jq -r ".format.tags.ARTIST_CREDIT" | sed "s/null//g" | sed "/^$/d")"
		metaflac --remove-tag=ARTIST "$file"
		metaflac --remove-tag=ALBUMARTIST "$file"
		metaflac --remove-tag=ALBUMARTIST_CREDIT "$file"
		metaflac --remove-tag=ALBUMARTISTSORT "$file"
		metaflac --remove-tag=ALBUM_ARTIST "$file"
		metaflac --remove-tag="ALBUM ARTIST" "$file"
		metaflac --remove-tag=ARTISTSORT "$file"
		metaflac --remove-tag=COMPOSERSORT "$file"
		metaflac --set-tag=ALBUMARTIST="$getAlbumArtist" "$file"
		if [ ! -z "$getArtistCredit" ]; then
       			metaflac --set-tag=ARTIST="$getArtistCredit" "$file"
			else
			metaflac --set-tag=ARTIST="$getAlbumArtist" "$file"
		fi
	done
		
	log "$1 :: Fixing Tags Complete!"	
	

	if [ -f "/config/extended/beets-lidarr-match" ]; then 
		rm "/config/extended/beets-lidarr-match"
		sleep 0.5
	fi

	if [ -f /config/extended/library-lidarr.blb ]; then
		rm /config/extended/library-lidarr.blb
		sleep 0.5
	fi
	if [ -f /config/extended/logs/beets.log ]; then 
		rm /config/extended/logs/beets.log
		sleep 0.5
	fi

	duration=$SECONDS
	log "$1 :: Finished in $(($duration / 60 )) minutes and $(($duration % 60 )) seconds!"
}

ProcessWithBeets "$getFolderPath"
exit
