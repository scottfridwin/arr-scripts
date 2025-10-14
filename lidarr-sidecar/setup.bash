#!/usr/bin/with-contenv bash
scriptVersion="1.4.5"
SMA_PATH="/usr/local/sma"

if [ -f /config/setup_version.txt ]; then
  source /config/setup_version.txt
  if [ "$scriptVersion" == "$setupversion" ]; then
    if apk --no-cache list | grep installed | grep opus-tools | read; then
      echo "Setup was previously completed, skipping..."
      exit
    fi
  fi
fi
echo "setupversion=$scriptVersion" > /config/setup_version.txt

set -euo pipefail

echo "*** install packages ***" && \
apk add -U --upgrade --no-cache \
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
  npm && \

echo "*** install python packages ***" && \
uv pip install --system --upgrade --no-cache-dir --break-system-packages \
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
  apprise  && \

mkdir -p /custom-services.d/python /config/extended

export GITHUB_URL="https://raw.githubusercontent.com/scottfridwin/arr-scripts/main"
#!/usr/bin/env bash
set -euo pipefail

export GITHUB_URL="https://raw.githubusercontent.com/scottfridwin/arr-scripts/main"

declare -A files=(
  ["/custom-services.d/AutoConfig"]="${GITHUB_URL}/lidarr-sidecar/AutoConfig.service.bash"
  ["/custom-services.d/Audio"]="${GITHUB_URL}/lidarr-sidecar/Audio.service.bash"
  ["/custom-services.d/python/ARLChecker.py"]="${GITHUB_URL}/lidarr-sidecar/python/ARLChecker.py"
  ["/custom-services.d/ARLChecker"]="${GITHUB_URL}/lidarr-sidecar/ARLChecker"
  ["/config/extended/functions"]="${GITHUB_URL}/lidarr-sidecar/functions.bash"
)

# Ensure directories exist
mkdir -p /custom-services.d/python /config/extended

for dest in "${!files[@]}"; do
  src="${files[$dest]}"
  echo "Downloading ${src} -> ${dest}"
  curl -sfL "$src" -o "$dest" && echo "✅ Done: $dest" || echo "❌ Failed: $dest"
done


if [ ! -f /config/extended/deemix_config.json ]; then
  echo "Download Deemix config..."
  curl -sfL "$GITHUB_URL/lidarr-sidecar/deemix_config.json" -o /config/extended/deemix_config.json
  echo "Done"
fi

if [ ! -f /config/extended.conf ]; then
	echo "Download Extended config..."
	curl -sfL $GITHUB_URL/lidarr-sidecar/extended.conf -o /config/extended.conf
	chmod 777 /config/extended.conf
	echo "Done"
fi

chmod 777 -R /config/extended
chmod 777 -R /root

if [ -f /custom-services.d/scripts_init.bash ]; then
   # user misconfiguration detected, sleeping...
   sleep infinity
fi
exit
