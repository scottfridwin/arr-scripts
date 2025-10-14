#!/usr/bin/env bash
scriptVersion="3.2"
scriptName="AutoConfig"

### Import Settings
source /config/extended.conf
#### Import Functions
source /config/extended/functions

logfileSetup

if [ "$enableAutoConfig" != "true" ]; then
	log "Script is not enabled, enable by setting enableAutoConfig to \"true\" by modifying the \"/config/extended.conf\" config file..."
	log "Sleeping (infinity)"
	sleep infinity
fi


getArrAppInfo
verifyApiAccess

if [ "$configureMediaManagement" == "true" ] || [ -z "$configureMediaManagement" ]; then
  log "Configuring Lidarr Media Management Settings"
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/config/mediamanagement" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{"autoUnmonitorPreviouslyDownloadedTracks": false,"recycleBin": "/recycle","recycleBinCleanupDays": 2,"downloadPropersAndRepacks": "preferAndUpgrade","createEmptyArtistFolders": true,"deleteEmptyFolders": true,"fileDate": "none","watchLibraryForChanges": false,"rescanAfterRefresh": "always","allowFingerprinting": "newFiles","setPermissionsLinux": true,"chmodFolder": "775","chownGroup": "","skipFreeSpaceCheckWhenImporting": false,"minimumFreeSpaceWhenImporting": 100,"copyUsingHardlinks": false,"enableMediaInfo": true,"useScriptImport": false,"scriptImportPath": "","importExtraFiles": true,"extraFileExtensions": ".srt,.nfo,lrc","id": 1}')
fi

if [ "$configureMetadataConsumerSettings" == "true" ] || [ -z "$configureMetadataConsumerSettings" ]; then
  log "Configuring Lidarr Metadata ConsumerSettings"
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/metadata/1?" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{"enable":true,"name":"Kodi (XBMC) / Emby","fields":[{"name":"artistMetadata","value":true},{"name":"albumMetadata","value":true},{"name":"artistImages","value":true},{"name":"albumImages","value":true}],"implementationName":"Kodi (XBMC) / Emby","implementation":"XbmcMetadata","configContract":"XbmcMetadataSettings","infoLink":"https://wiki.servarr.com/lidarr/supported#xbmcmetadata","tags":[],"id":1}')
fi

if [ "$configureMetadataProviderSettings" == "true" ] || [ -z "$configureMetadataProviderSettings" ]; then
  log "Configuring Lidarr Metadata Provider Settings"
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/config/metadataProvider" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{"metadataSource": "","writeAudioTags": "sync","scrubAudioTags": false,"embedCoverArt": false,"id": 1}')
fi

if [ "$configureLidarrUiSettings" == "true" ] || [ -z "$configureLidarrUiSettings" ]; then
  log "Configuring Lidarr UI Settings"
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/config/ui" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{"firstDayOfWeek":0,"calendarWeekColumnHeader":"ddd M/D","shortDateFormat":"MMM D YYYY","longDateFormat":"dddd, MMMM D YYYY","timeFormat":"h(:mm)a","showRelativeDates":true,"enableColorImpairedMode":true,"uiLanguage":1,"expandAlbumByDefault":true,"expandSingleByDefault":true,"expandEPByDefault":true,"expandBroadcastByDefault":true,"expandOtherByDefault":true,"theme":"auto","id":1}')
fi

if [ "$configureMetadataProfileSettings" == "true" ] || [ -z "$configureMetadataProfileSettings" ]; then
  log "Configuring Lidarr Standard Metadata Profile"
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/metadataprofile/1?" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{ "name": "Standard", "primaryAlbumTypes": [ { "albumType": { "id": 2, "name": "Single" }, "allowed": false }, { "albumType": { "id": 4, "name": "Other" }, "allowed": false }, { "albumType": { "id": 1, "name": "EP" }, "allowed": false }, { "albumType": { "id": 3, "name": "Broadcast" }, "allowed": false }, { "albumType": { "id": 0, "name": "Album" }, "allowed": true } ], "secondaryAlbumTypes": [ { "albumType": { "id": 0, "name": "Studio" }, "allowed": true }, { "albumType": { "id": 3, "name": "Spokenword" }, "allowed": false }, { "albumType": { "id": 2, "name": "Soundtrack" }, "allowed": false }, { "albumType": { "id": 7, "name": "Remix" }, "allowed": false }, { "albumType": { "id": 9, "name": "Mixtape/Street" }, "allowed": false }, { "albumType": { "id": 6, "name": "Live" }, "allowed": false }, { "albumType": { "id": 4, "name": "Interview" }, "allowed": false }, { "albumType": { "id": 8, "name": "DJ-mix" }, "allowed": false }, { "albumType": { "id": 10, "name": "Demo" }, "allowed": false }, { "albumType": { "id": 1, "name": "Compilation" }, "allowed": false }, { "albumType": { "id": 11, "name": "Audio drama" }, "allowed": false } ], "releaseStatuses": [ { "releaseStatus": { "id": 3, "name": "Pseudo-Release" }, "allowed": false }, { "releaseStatus": { "id": 1, "name": "Promotion" }, "allowed": false }, { "releaseStatus": { "id": 0, "name": "Official" }, "allowed": true }, { "releaseStatus": { "id": 2, "name": "Bootleg" }, "allowed": false } ], "id": 1 }')
fi


if [ "$configureTrackNamingSettings" == "true" ] || [ -z "$configureTrackNamingSettings" ]; then
  log "Configuring Lidarr Track Naming Settings"
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/config/naming" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{ "renameTracks": true, "replaceIllegalCharacters": true, "colonReplacementFormat": 4, "standardTrackFormat": "{Album CleanTitle} ({Release Year}) ({Album MbId})/{track:00} - {Track CleanTitle}", "multiDiscTrackFormat": "{Album CleanTitle} ({Release Year}) ({Album MbId})/{medium:00}-{track:00} - {Track CleanTitle}", "artistFolderFormat": "{Artist CleanName} ({Artist MbId})", "includeArtistName": false, "includeAlbumTitle": false, "includeQuality": false, "replaceSpaces": false, "id": 1 }')
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/config/naming" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{ "renameTracks": true, "replaceIllegalCharacters": true, "colonReplacementFormat": 4, "standardTrackFormat": "{Album CleanTitle} ({Release Year}) ({Album MbId})/{track:00} - {Track CleanTitle}", "multiDiscTrackFormat": "{Album CleanTitle} ({Release Year}) ({Album MbId})/{medium:00}-{track:00} - {Track CleanTitle}", "artistFolderFormat": "{Artist CleanName} ({Artist MbId})", "includeArtistName": false, "includeAlbumTitle": false, "includeQuality": false, "replaceSpaces": false, "id": 1 }')
  postSettingsToLidarr=$(curl -s "$arrUrl/api/v1/config/naming" -X PUT -H 'Content-Type: application/json' -H "X-Api-Key: ${arrApiKey}" --data-raw '{ "renameTracks": true, "replaceIllegalCharacters": true, "colonReplacementFormat": 4, "standardTrackFormat": "{Album CleanTitle} ({Release Year}) ({Album MbId})/{track:00} - {Track CleanTitle}", "multiDiscTrackFormat": "{Album CleanTitle} ({Release Year}) ({Album MbId})/{medium:00}-{track:00} - {Track CleanTitle}", "artistFolderFormat": "{Artist CleanName} ({Artist MbId})", "includeArtistName": false, "includeAlbumTitle": false, "includeQuality": false, "replaceSpaces": false, "id": 1 }')
fi


sleep infinity
exit $?
