#!/bin/sh
set -e

# Source .env written by Komodo (contains resolved secrets)
if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

# --- Seekarr config ---
SEEKARR_CFG="${SEEKARR_PATH_CONFIG:-./data/seekarr/config.yml}"
rm -rf "${SEEKARR_CFG}"
mkdir -p "$(dirname "${SEEKARR_CFG}")"

cat > "${SEEKARR_CFG}" <<EOF
instances:
  - name: sonarr
    type: sonarr
    url: ${SONARR_API_URL:-http://sonarr:8989}
    apiKey: ${SONARR_API_KEY}
    searchMode: ${SEEKARR_SEARCH_MODE:-both}
    monitoredOnly: true
    limit: ${SEEKARR_SONARR_LIMIT:-10}
    dryRun: false
    searchFrequencyHours: ${SEEKARR_FREQUENCY_HOURS:-1}

  - name: radarr
    type: radarr
    url: ${RADARR_API_URL:-http://radarr:7878}
    apiKey: ${RADARR_API_KEY}
    searchMode: ${SEEKARR_SEARCH_MODE:-both}
    monitoredOnly: true
    limit: ${SEEKARR_RADARR_LIMIT:-15}
    dryRun: false
    searchFrequencyHours: ${SEEKARR_FREQUENCY_HOURS:-1}

schedule:
  intervalMinutes: ${SEEKARR_INTERVAL_MINUTES:-60}
EOF
