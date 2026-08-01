#!/usr/bin/env bash
set -euo pipefail

# First-time setup for both trust boundaries in this repo: generates/restores
# the ansible AGE keypair (Key A) and the Komodo AGE keypair (Key B), backs
# each up to its own Bitwarden secure note, configures the matching
# .sops.yaml, and scaffolds per-host ansible secrets. Safe to re-run — skips
# steps that are already done.

ANSIBLE_AGE_KEY_FILE="$HOME/.config/sops/ansible/age/keys.txt"
KOMODO_AGE_KEY_FILE="$HOME/.config/sops/komodo/age/keys.txt"
ANSIBLE_SOPS_CONFIG="ansible/.sops.yaml"
KOMODO_SOPS_CONFIG="komodo/.sops.yaml"
ANSIBLE_HOSTS_FILE="ansible/hosts.yml"
ANSIBLE_BW_ITEM_NAME="Homelab SOPS Age Key"
KOMODO_BW_ITEM_NAME="Homelab Komodo SOPS Age Key"

cd "$(git rev-parse --show-toplevel)"

# `bw get item <name>` aborts with a non-JSON error if more than one item
# shares that name, so look items up by exact-name filter instead. If several
# match, let the user pick one (falls back to the most recent when non-interactive).
bw_find_item() {
    local name="$1"
    local matches count
    matches=$(bw list items --search "$name" 2>/dev/null \
        | jq -c --arg name "$name" '[.[] | select(.name == $name)]' 2>/dev/null) || matches="[]"
    count=$(echo "$matches" | jq 'length' 2>/dev/null || echo 0)

    if [ "$count" -gt 1 ] && [ -t 0 ]; then
        echo "==> Found $count Bitwarden items named '$name':" >&2
        local i=0
        while [ "$i" -lt "$count" ]; do
            local id date
            id=$(echo "$matches" | jq -r ".[$i].id")
            date=$(echo "$matches" | jq -r ".[$i].revisionDate")
            echo "    [$((i + 1))] id=$id  last modified=$date" >&2
            i=$((i + 1))
        done
        local choice
        read -rp "Which one do you want to use? [1-$count] " choice >&2
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
            echo "Invalid selection." >&2
            return 1
        fi
        echo "$matches" | jq ".[$((choice - 1))]"
        return 0
    fi

    if [ "$count" -gt 1 ]; then
        echo "==> Warning: found $count Bitwarden items named '$name'. Using the most recently modified one." >&2
        echo "    Consider deleting the duplicates in Bitwarden." >&2
    fi
    if [ "$count" -ge 1 ]; then
        echo "$matches" | jq 'sort_by(.revisionDate) | last'
    fi
}

# Restores or generates an age keypair, backs it up to Bitwarden, and writes
# its public key into a creation_rules-style .sops.yaml.
init_age_key() {
    local key_file="$1" sops_config="$2" bw_item_name="$3"
    local public_key restored=false

    if [ -f "$key_file" ]; then
        echo "==> Age key already exists at $key_file"
    else
        if [ -n "${BW_SESSION:-}" ]; then
            echo "==> No local age key found. Checking Bitwarden for an existing key..."
            local bw_item notes
            bw_item=$(bw_find_item "$bw_item_name")
            notes=$(echo "$bw_item" | jq -r '.notes // empty' 2>/dev/null || true)
            if [ -n "$notes" ]; then
                echo "==> Restoring age key from Bitwarden..."
                mkdir -p "$(dirname "$key_file")"
                echo "$notes" > "$key_file"
                chmod 600 "$key_file"
                restored=true
                echo "    Restored: $key_file"
            else
                echo "==> No age key found in Bitwarden ($bw_item_name)"
            fi
        else
            echo "==> BW_SESSION not set — cannot check Bitwarden for an existing key."
            echo "    export BW_SESSION=\$(bw unlock --raw)"
        fi

        if [ "$restored" = false ]; then
            read -rp "No age key found locally or in Bitwarden for '$bw_item_name'. Generate a new one? [y/N] " REPLY
            if [[ "$REPLY" =~ ^[Yy]$ ]]; then
                echo "==> Generating age keypair..."
                mkdir -p "$(dirname "$key_file")"
                age-keygen -o "$key_file" 2>&1
                chmod 600 "$key_file"
            else
                echo "Aborting. Restore your key manually, or set BW_SESSION and re-run."
                exit 1
            fi
        fi
    fi

    public_key=$(grep "public key:" "$key_file" | sed 's/.*public key: //')
    echo "    Public key: $public_key"

    if [ -z "${BW_SESSION:-}" ]; then
        echo ""
        echo "==> BW_SESSION not set. To back up the age key to Bitwarden, run:"
        echo "    export BW_SESSION=\$(bw unlock --raw)"
        echo "    Then re-run this script."
        echo ""
        echo "    Continuing without Bitwarden backup..."
        echo ""
    else
        local existing
        existing=$(bw_find_item "$bw_item_name" | jq -r '.id // empty' 2>/dev/null || true)
        if [ -n "$existing" ]; then
            echo "==> Age key already in Bitwarden ($bw_item_name)"
        else
            echo "==> Backing up age key to Bitwarden..."
            local key_content
            key_content=$(cat "$key_file")
            bw get template item | \
                jq --arg name "$bw_item_name" \
                   --arg notes "$key_content" \
                   '.type=2 | .name=$name | .notes=$notes | .secureNote={"type":0} | del(.login) | del(.folderId)' | \
                bw encode | bw create item > /dev/null
            echo "    Saved as Secure Note: $bw_item_name"
        fi
    fi

    local current_key
    current_key=$(grep -oP 'age1[a-z0-9]+' "$sops_config" 2>/dev/null || true)
    if [ "$current_key" = "$public_key" ]; then
        echo "==> $sops_config already has the correct public key"
    elif [ -n "$current_key" ]; then
        echo "==> $sops_config already has a different key: $current_key"
        echo "    Not overwriting. Edit manually if you want to change it."
    else
        echo "==> Updating $sops_config with public key..."
        mkdir -p "$(dirname "$sops_config")"
        cat > "$sops_config" <<EOF
creation_rules:
  - path_regex: \.sops\.ya?ml$
    age: >-
      $public_key
EOF
        echo "    Updated: $sops_config"
    fi

    printf '%s' "$public_key"
}

# ── Ansible (Key A) ──────────────────────────────────────────────────

echo "=== Ansible age key (Key A) ==="
ANSIBLE_PUBLIC_KEY=$(init_age_key "$ANSIBLE_AGE_KEY_FILE" "$ANSIBLE_SOPS_CONFIG" "$ANSIBLE_BW_ITEM_NAME")

echo ""
echo "=== Scaffolding ansible host secrets ==="
export SOPS_AGE_KEY_FILE="$ANSIBLE_AGE_KEY_FILE"
ANSIBLE_HOSTS=$(grep -oP '^\s{4}\S+(?=:)' "$ANSIBLE_HOSTS_FILE" | sed 's/^ *//' || true)

if [ -z "$ANSIBLE_HOSTS" ]; then
    echo "==> No hosts found in $ANSIBLE_HOSTS_FILE"
else
    echo "==> Checking secret files for hosts: $(echo $ANSIBLE_HOSTS | tr '\n' ' ')"
    for HOST in $ANSIBLE_HOSTS; do
        SECRET_FILE="ansible/host_vars/$HOST/secrets.sops.yml"
        if [ -f "$SECRET_FILE" ]; then
            echo "    $HOST: secrets.sops.yml already exists"
        else
            echo "    $HOST: creating from template..."
            mkdir -p "ansible/host_vars/$HOST"
            TEMPLATE="ansible/host_vars/secrets.sops.yml.tpl"
            cp "$TEMPLATE" "/tmp/secrets.sops.yml"
            sops --encrypt --age "$ANSIBLE_PUBLIC_KEY" --input-type yaml --output-type yaml "/tmp/secrets.sops.yml" > "$SECRET_FILE"
            rm "/tmp/secrets.sops.yml"
        fi
    done
fi

# ── Komodo (Key B) ───────────────────────────────────────────────────

echo ""
echo "=== Komodo age key (Key B) ==="
init_age_key "$KOMODO_AGE_KEY_FILE" "$KOMODO_SOPS_CONFIG" "$KOMODO_BW_ITEM_NAME" > /dev/null

# ── Done ──────────────────────────────────────────────────────────────

echo ""
echo "==> Setup complete!"
echo ""
echo "    Next steps:"

NEEDS_EDIT=false
for HOST in $ANSIBLE_HOSTS; do
    SECRET_FILE="ansible/host_vars/$HOST/secrets.sops.yml"
    if SOPS_AGE_KEY_FILE="$ANSIBLE_AGE_KEY_FILE" sops -d "$SECRET_FILE" 2>/dev/null | grep -q "CHANGEME"; then
        NEEDS_EDIT=true
        break
    fi
done

if [ "$NEEDS_EDIT" = true ]; then
    echo "    1. Edit ansible secrets for each host:"
    for HOST in $ANSIBLE_HOSTS; do
        echo "       just ansible-secrets $HOST"
    done
    echo "    2. Commit: git add ansible/.sops.yaml ansible/host_vars/ && git commit -m 'feat(ansible): add SOPS-encrypted host secrets'"
    echo "    3. Test:   just ping"
else
    echo "    All ansible secrets already configured. Test: just ping"
fi
echo "    Edit Komodo secrets: just catalog-secrets"
echo "    Commit:              git add komodo/.sops.yaml && git commit -m 'chore(komodo): configure SOPS age key'"
