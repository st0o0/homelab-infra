#!/bin/sh
set -e

# --- Source .env ---
ENV_FILE=""
for f in .env .env.stack compose.env; do
  [ -f "$f" ] && ENV_FILE="$f" && break
done

if [ -n "$ENV_FILE" ]; then
  echo "[pre-deploy] sourcing $ENV_FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    case "$line" in \#*|'') continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    export "$key=$value"
  done < "$ENV_FILE"
else
  echo "[pre-deploy] no .env file found, using shell environment"
fi

NZBGET_DIR="${NZBGET_PATH_CONFIG:-./nzbget/config}"
CONF="${NZBGET_DIR}/nzbget.conf"
IMAGE="ghcr.io/nzbgetcom/nzbget:v26.2"

echo "[pre-deploy] config dir: ${NZBGET_DIR}"

# --- Helper: patch a key in the full config ---
patch_key() {
  key="$1"
  value="$2"
  if grep -q "^${key}=" "$CONF"; then
    old_val="$(grep "^${key}=" "$CONF" | head -1 | cut -d= -f2- | tr -d '\r')"
    if [ "$old_val" != "$value" ]; then
      sed -i "s|^${key}=.*|${key}=${value}|" "$CONF"
      echo "[pre-deploy]   ${key}: ${old_val} -> ${value}"
    fi
  else
    printf '%s=%s\n' "$key" "$value" >> "$CONF"
    echo "[pre-deploy]   ${key}: <added> ${value}"
  fi
}

# --- First run: extract full default config from image ---
mkdir -p "${NZBGET_DIR}"
LINES=0
if [ -f "$CONF" ]; then
  LINES="$(wc -l < "$CONF")"
fi

if [ "$LINES" -lt 200 ]; then
  echo "[pre-deploy] config missing or incomplete (${LINES} lines), extracting default from image"
  docker run --rm "${IMAGE}" cat /app/nzbget/share/nzbget/nzbget.conf > "$CONF"
fi

echo "[pre-deploy] patching nzbget.conf ($(wc -l < "$CONF") lines)"

# Paths
patch_key "MainDir"  "${NZBGET_MAIN_DIR:-/config}"
patch_key "DestDir"  "${NZBGET_DEST_DIR:-/data/completed}"
patch_key "InterDir" "${NZBGET_INTER_DIR:-/data/intermediate}"
patch_key "TempDir"  "${NZBGET_TEMP_DIR:-/data/tmp}"
patch_key "NzbDir"   "${NZBGET_NZB_DIR:-/config/nzb}"
patch_key "QueueDir" "${NZBGET_QUEUE_DIR:-/config/queue}"

# Auth
patch_key "ControlIP"       "0.0.0.0"
patch_key "ControlPort"     "6789"
patch_key "ControlUsername"  "${NZBGET_USER:-nzbget}"
if [ -n "${NZBGET_PASS:-}" ]; then
  patch_key "ControlPassword" "${NZBGET_PASS}"
fi

# Server
if [ -n "${NZBGET_SERVER1_HOST:-}" ]; then
  patch_key "Server1.Active"         "yes"
  patch_key "Server1.Host"           "${NZBGET_SERVER1_HOST}"
  patch_key "Server1.Port"           "${NZBGET_SERVER1_PORT:-563}"
  patch_key "Server1.Encryption"     "yes"
  patch_key "Server1.CertVerification" "strict"
  patch_key "Server1.Connections"    "${NZBGET_SERVER1_CONNECTIONS:-20}"
  if [ -n "${NZBGET_SERVER1_USERNAME:-}" ]; then
    patch_key "Server1.Username" "${NZBGET_SERVER1_USERNAME}"
  fi
  if [ -n "${NZBGET_SERVER1_PASSWORD:-}" ]; then
    patch_key "Server1.Password" "${NZBGET_SERVER1_PASSWORD}"
  fi
fi

# Bandwidth
patch_key "DownloadRate" "${NZBGET_DOWNLOAD_RATE:-0}"

# Logging
patch_key "WriteLog"  "rotate"
patch_key "RotateLog" "3"

# Post-Processing
patch_key "DirectUnpack"     "yes"
patch_key "ArticleCache"     "250"
patch_key "ContinuePartial"  "yes"

# Categories
IDX=1
ORDER=1
while true; do
  eval "CAT_NAME=\${NZBGET_CAT_${IDX}_NAME:-}"
  [ -z "$CAT_NAME" ] && break
  eval "CAT_DIR=\${NZBGET_CAT_${IDX}_DIR:-}"
  eval "CAT_UNPACK=\${NZBGET_CAT_${IDX}_UNPACK:-yes}"
  eval "CAT_ALIASES=\${NZBGET_CAT_${IDX}_ALIASES:-}"
  patch_key "Category${ORDER}.Name"    "$CAT_NAME"
  patch_key "Category${ORDER}.DestDir" "$CAT_DIR"
  patch_key "Category${ORDER}.Unpack"  "$CAT_UNPACK"
  patch_key "Category${ORDER}.Aliases" "$CAT_ALIASES"
  ORDER=$((ORDER + 1))
  IDX=$((IDX + 1))
done

# Tasks
IDX=1
while true; do
  eval "TASK_TIME=\${NZBGET_TASK_${IDX}_TIME:-}"
  [ -z "$TASK_TIME" ] && break
  eval "TASK_WEEKDAYS=\${NZBGET_TASK_${IDX}_WEEKDAYS:-1-7}"
  eval "TASK_COMMAND=\${NZBGET_TASK_${IDX}_COMMAND:-PauseDownload}"
  eval "TASK_PARAM=\${NZBGET_TASK_${IDX}_PARAM:-}"
  patch_key "Task${IDX}.Time"     "$TASK_TIME"
  patch_key "Task${IDX}.WeekDays" "$TASK_WEEKDAYS"
  patch_key "Task${IDX}.Command"  "$TASK_COMMAND"
  patch_key "Task${IDX}.Param"    "$TASK_PARAM"
  IDX=$((IDX + 1))
done

chown -R "${PUID:-1000}:${PGID:-1000}" "${NZBGET_DIR}" 2>/dev/null || true

echo "[pre-deploy] done"
