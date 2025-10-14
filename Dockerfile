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
COPY lidarr-sidecar/ /lidarr-sidecar/

# Set working directory
WORKDIR /lidarr-sidecar

# Default command (can be changed as needed)
CMD ["bash"]
