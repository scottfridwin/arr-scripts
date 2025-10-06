#!/usr/bin/with-contenv bash
set -euo pipefail

GITHUB_URL="https://raw.githubusercontent.com/scottfridwin/arr-scripts/main"
curl -sfL $GITHUB_URL/lidarr/setup.bash | bash
exit
