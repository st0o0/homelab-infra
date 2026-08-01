#!/usr/bin/env bash
set -euo pipefail

# Decrypt SOPS secrets into a Komodo Core config file.
# Merges shared secrets + per-host secrets (prefixed with hostname_).
#
# Run this on the Komodo Core host after git pull.
#
# Prerequisites:
#   - sops, jq, age installed
#   - SOPS_AGE_KEY_FILE set or age key at ~/.config/sops/age/keys.txt
#
# Usage:
#   ./decrypt.sh                          # writes to /etc/komodo/core.secrets.toml
#   ./decrypt.sh /custom/path/config.toml # custom output path

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOPS_CONFIG="${SCRIPT_DIR}/.sops.yaml"
GLOBAL_FILE="${SCRIPT_DIR}/secrets.sops.yaml"
OUTPUT_FILE="${1:-/etc/komodo/core.secrets.toml}"

if [ ! -f "$GLOBAL_FILE" ]; then
  echo "Error: $GLOBAL_FILE not found" >&2
  exit 1
fi

for cmd in sops jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd is not installed" >&2
    exit 1
  fi
done

echo "Decrypting secrets to $OUTPUT_FILE ..."

{
  echo "[secrets]"

  echo "# --- shared ---"
  sops -d --config "$SOPS_CONFIG" --output-type json "$GLOBAL_FILE" \
    | jq -r 'to_entries[] | "\(.key) = \"\(.value)\""'

  for host_dir in "${SCRIPT_DIR}"/hosts/*/; do
    [ -d "$host_dir" ] || continue
    HOST_SECRET="${host_dir}secrets.sops.yaml"
    [ -f "$HOST_SECRET" ] || continue
    HOST=$(basename "$host_dir")
    echo ""
    echo "# --- $HOST ---"
    sops -d --config "$SOPS_CONFIG" --output-type json "$HOST_SECRET" \
      | jq -r --arg h "$HOST" 'to_entries[] | "\($h)_\(.key) = \"\(.value)\""'
  done
} > "$OUTPUT_FILE"

chmod 600 "$OUTPUT_FILE"
echo "Done. Restart Komodo Core to pick up changes."
