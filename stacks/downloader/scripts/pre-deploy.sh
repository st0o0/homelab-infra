#!/bin/sh
set -e

ENV_FILE=""
for f in .env .env.stack compose.env; do
  [ -f "$f" ] && ENV_FILE="$f" && break
done

if [ -n "$ENV_FILE" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    line="$(printf '%s' "$line" | tr -d '\r')"
    case "$line" in \#*|'') continue ;; esac
    key="${line%%=*}"
    value="${line#*=}"
    export "$key=$value"
  done < "$ENV_FILE"
fi

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

for dir in \
  "${NZBGET_PATH_CONFIG:-./nzbget/config}" \
  "${NZBGET_PATH_TMP:-./nzbget/tmp}" \
  "${NZBGET_PATH_INTERMEDIATE:-./nzbget/intermediate}" \
  "${FIREFOX_PATH_CONFIG:-./firefox/config}"; do
  mkdir -p "$dir"
  chown "${PUID}:${PGID}" "$dir" 2>/dev/null || true
done

echo "[pre-deploy] directories ready"
