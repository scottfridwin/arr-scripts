# Use latest Alpine as base
FROM alpine:latest

# Install system dependencies
RUN apk add --no-cache \
    tidyhtml \
    musl-locales \
    musl-locales-lang \
    flac \
    jq \
    git \
    gcc \
    ffmpeg \
    imagemagick \
    opus-tools \
    opustags \
    python3-dev \
    libc-dev \
    uv \
    parallel \
    chromaprint \
    npm \
    curl \
    bash

# Install atomicparsley from edge/testing
RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing atomicparsley

# Install Python packages
RUN uv pip install --system --upgrade --no-cache-dir --break-system-packages \
    jellyfish \
    beautifulsoup4 \
    yt-dlp \
    beets \
    yq \
    pyxDamerauLevenshtein \
    pyacoustid \
    requests \
    colorama \
    python-telegram-bot \
    pylast \
    mutagen \
    r128gain \
    tidal-dl \
    deemix \
    langdetect \
    apprise

# Copy all scripts and config files
COPY lidarr-sidecar/ /app/

# Set working directory
WORKDIR /app

### Variable defaults ###

# Connection details
ENV LIDARR_PORT=
ENV ENABLE_AUTO_CONFIG=true
ENV LIDARR_CONFIG_PATH=/lidarr/config.xml
ENV LIDARR_HOST=lidarr

# ARLChecker settings
ENV ARL_UPDATE_INTERVAL=24h

# Audio settings
ENV AUDIO_INTERVAL=15m
ENV AUDIO_DATA_PATH=/data
ENV AUDIO_WORK_PATH=/work
ENV AUDIO_REQUIRE_QUALITY=true
ENV AUDIO_PREFER_SPECIAL_EDITIONS=true
ENV AUDIO_LYRIC_TYPE=prefer-explicit
ENV AUDIO_TAGS=deemix
ENV AUDIO_DOWNLOADCLIENT_NAME=lidarr-deemix-sidecar
ENV AUDIO_ATTEMPT_THRESHOLD=10
ENV AUDIO_FAILED_ATTEMPT_THRESHOLD=6
ENV AUDIO_TEST_DOWNLOAD_ID=197472472
ENV AUDIO_IGNORE_INSTRUMENTAL_RELEASES=true
ENV AUDIO_INSTRUMENTAL_KEYWORDS="Instrumental,Score"
ENV AUDIO_DOWNLOAD_CLIENT_TIMEOUT=10m
ENV AUDIO_RETRY_NOTFOUND_DAYS=90
ENV AUDIO_SHARED_LIDARR_PATH=/sidecar-import
ENV AUDIO_APPLY_REPLAYGAIN=true
ENV AUDIO_CACHE_MAX_AGE_DAYS=30
ENV AUDIO_DEEZER_API_RETRIES=3
ENV AUDIO_DEEZER_API_TIMEOUT=30
ENV AUDIO_MATCH_DISTANCE_THRESHOLD=3
ENV AUDIO_DEEMIX_CUSTOM_CONFIG=

# AutoConfig settings
ENV CONFIGURE_MEDIA_MANAGEMENT=true
ENV MEDIA_MANAGEMENT_CONFIG_FILE=/app/config/media_management.json
ENV CONFIGURE_METADATA_CONSUMER_SETTINGS=false
ENV METADATA_CONSUMER_CONFIG_FILE=/app/config/metadata_consumer.json
ENV CONFIGURE_METADATA_PROVIDER_SETTINGS=true
ENV METADATA_PROVIDER_CONFIG_FILE=/app/config/metadata_provider.json
ENV CONFIGURE_LIDARR_UI_SETTINGS=false
ENV LIDARR_UI_CONFIG_FILE=/app/config/lidarr_ui.json
ENV CONFIGURE_METADATA_PROFILE_SETTINGS=true
ENV METADATA_PROFILE_CONFIG_FILE=/app/config/metadata_profile.json
ENV CONFIGURE_TRACK_NAMING_SETTINGS=true
ENV TRACK_NAMING_CONFIG_FILE=/app/config/track_naming.json

# Entrypoint
CMD ["entrypoint.sh"]
