#!/usr/bin/env bash
scriptVersion="1.2"
scriptName="ArtworkExtractor"

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

# --- Process files ---
log "Processing :: $getAlbumFolderName :: Processing Files..."

if echo "$getFolderPath" | grep "$getAlbumArtistPath" | read; then
	if [ ! -d "$getFolderPath" ]; then
		log "ERROR :: \"$getFolderPath\" Folder is missing :: Exiting..."
	fi
else 
	log "ERROR :: $getAlbumArtistPath not found within \"$getFolderPath\" :: Exiting..."
	exit
fi

find "$getFolderPath" -type f -regex ".*/.*\.\(flac\|opus\|m4a\|mp3\)" -print0 | while IFS= read -r -d '' file; do
    fileName=$(basename -- "$file")
    fileExt="${fileName##*.}"

    if [ ! -f "$getFolderPath/folder.jpg" ] && [ ! -f "$getFolderPath/folder.jpeg" ]; then
        log "Processing :: $getAlbumFolderName :: $fileName :: Extracting Artwork..."
        ffmpeg -i "$file" -an -vcodec copy "$getFolderPath/folder.jpg" &> /dev/null

        if [ -f "$getFolderPath/folder.jpg" ]; then
            log "Processing :: $getAlbumFolderName :: Album Artwork Extracted to: $getFolderPath/folder.jpg"
            chmod 666 "$getFolderPath/folder.jpg"
        fi
    else
        log "Processing :: $getAlbumFolderName :: Album Artwork Exists, skipping..."
        break
    fi
done

duration=$SECONDS
log "Processing :: $getAlbumFolderName :: Finished in $(($duration / 60 )) minutes and $(($duration % 60 )) seconds!"
exit
