#!/usr/bin/env bash
# Validate that the combined SOPS age key file contains keys matching all
# expected recipients. Called from postStartCommand to catch stale/wrong keys
# early. If a key mismatches and BW_SESSION is set, re-fetches from Bitwarden.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/bw-item-names.sh"

COMBINED_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

validate_key() {
    local sops_config="$1" bw_item="$2" label="$3"

    local expected_recipient
    expected_recipient=$(grep -oP 'age1[a-z0-9]+' "$sops_config" | head -1)
    if [ -z "$expected_recipient" ]; then
        echo "    $label: no recipient found in $sops_config — skipping"
        return
    fi

    if [ ! -f "$COMBINED_AGE_KEY_FILE" ]; then
        echo "    $label: combined key file missing"
        restore_from_bw "$bw_item" "$label"
        return
    fi

    local actual_pubkeys
    actual_pubkeys=$(age-keygen -y "$COMBINED_AGE_KEY_FILE" 2>/dev/null || true)
    if echo "$actual_pubkeys" | grep -qF "$expected_recipient"; then
        echo "    $label: OK"
        return
    fi

    echo "    $label: MISMATCH (want $expected_recipient, not found in combined key file)"
    restore_from_bw "$bw_item" "$label"
}

restore_from_bw() {
    local bw_item="$1" label="$2"

    if [ -z "${BW_SESSION:-}" ]; then
        echo "    $label: no BW_SESSION — run 'unlock' then 'just validate-keys' to fix"
        return 1
    fi

    local age_key
    age_key=$(bw get item "$bw_item" 2>/dev/null | jq -r '.notes // empty' 2>/dev/null || true)
    if [ -z "$age_key" ]; then
        echo "    $label: not found in Bitwarden ($bw_item)"
        return 1
    fi

    mkdir -p "$(dirname "$COMBINED_AGE_KEY_FILE")"
    if [ -f "$COMBINED_AGE_KEY_FILE" ] && [ -s "$COMBINED_AGE_KEY_FILE" ]; then
        echo "" >> "$COMBINED_AGE_KEY_FILE"
    fi
    printf '%s\n' "$age_key" >> "$COMBINED_AGE_KEY_FILE"
    chmod 600 "$COMBINED_AGE_KEY_FILE"
    echo "    $label: restored from Bitwarden"
}

echo "==> Validating SOPS age keys..."
validate_key "$REPO_ROOT/ansible/.sops.yaml" "$HOMELAB_ANSIBLE_AGE_KEY_BW_ITEM" "ansible"
validate_key "$REPO_ROOT/komodo/.sops.yaml" "$HOMELAB_KOMODO_AGE_KEY_BW_ITEM" "komodo"
