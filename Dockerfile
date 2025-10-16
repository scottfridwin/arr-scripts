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
ENV ARLUPDATE_INTERVAL=24h

# Audio settings
ENV AUDIO_APPLY_REPLAYGAIN=true
ENV AUDIO_CACHE_MAX_AGE_DAYS=30
ENV AUDIO_DATA_PATH=/data
ENV AUDIO_DEEMIX_CUSTOM_CONFIG=
ENV AUDIO_DEEZER_API_RETRIES=3
ENV AUDIO_DEEZER_API_TIMEOUT=30
ENV AUDIO_DEEMIX_ARL_FILE=/run/secrets/deemix_arl
ENV AUDIO_DOWNLOADCLIENT_NAME=lidarr-deemix-sidecar
ENV AUDIO_DOWNLOAD_ATTEMPT_THRESHOLD=10
ENV AUDIO_DOWNLOAD_CLIENT_TIMEOUT=10m
ENV AUDIO_FAILED_ATTEMPT_THRESHOLD=6
ENV AUDIO_IGNORE_INSTRUMENTAL_RELEASES=true
ENV AUDIO_INSTRUMENTAL_KEYWORDS="Instrumental,Score"
ENV AUDIO_INTERVAL=15m
ENV AUDIO_LYRIC_TYPE=prefer-explicit
ENV AUDIO_MATCH_DISTANCE_THRESHOLD=3
ENV AUDIO_PREFER_SPECIAL_EDITIONS=true
ENV AUDIO_REQUIRE_QUALITY=true
ENV AUDIO_RETRY_NOTFOUND_DAYS=90
ENV AUDIO_SHARED_LIDARR_PATH=/sidecar-import
ENV AUDIO_TAGS=deemix
ENV AUDIO_TEST_DOWNLOAD_ID=197472472
ENV AUDIO_WORK_PATH=/work

# AutoConfig settings
ENV AUTOCONFIG_MEDIA_MANAGEMENT=true
ENV AUTOCONFIG_MEDIA_MANAGEMENT_JSON=/app/config/media_management.json
ENV AUTOCONFIG_METADATA_CONSUMER=false
ENV AUTOCONFIG_METADATA_CONSUMER_JSON=/app/config/metadata_consumer.json
ENV AUTOCONFIG_METADATA_PROVIDER=true
ENV AUTOCONFIG_METADATA_PROVIDER_JSON=/app/config/metadata_provider.json
ENV AUTOCONFIG_LIDARR_UI=false
ENV AUTOCONFIG_LIDARR_UI_JSON=/app/config/lidarr_ui.json
ENV AUTOCONFIG_METADATA_PROFILE=true
ENV AUTOCONFIG_METADATA_PROFILE_JSON=/app/config/metadata_profile.json
ENV AUTOCONFIG_TRACK_NAMING=true
ENV AUTOCONFIG_TRACK_NAMING_JSON=/app/config/track_naming.json

# Entrypoint
CMD ["entrypoint.sh"]
