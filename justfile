import "ansible/justfile"
import "komodo.just"

set windows-shell := ["pwsh", "-NoProfile", "-Command"]

# --- Short aliases for the recipes typed most often ---
alias as := ansible-secrets
alias ks := komodo-secrets
alias dec := decrypt
alias ss := show-secrets

# --- DevContainer management ---
# On Linux: wraps .devcontainer/devcontainer.sh (VARIANT default: linux)
# On Windows: wraps .devcontainer/devcontainer.ps1 (Variant default: windows)

variant := env_var_or_default("VARIANT", if os() == "windows" { "windows" } else { "linux" })

# Create/start the dev container
[unix]
up:
    .devcontainer/devcontainer.sh --variant {{variant}} up

[windows]
up:
    devcontainer up --workspace-folder . --config .devcontainer/{{variant}}/devcontainer.json

# Stop the dev container
[unix]
down:
    .devcontainer/devcontainer.sh --variant {{variant}} down

[windows]
down:
    $p = $PWD.Path[0].ToString().ToLower() + $PWD.Path.Substring(1); $cid = docker ps -q --filter "label=devcontainer.local_folder=$p"; if ($cid) { docker stop $cid } else { Write-Host "No running devcontainer found." }

# Remove + rebuild the dev container from scratch (--no-cache)
[unix]
rebuild:
    .devcontainer/devcontainer.sh --variant {{variant}} rebuild

[windows]
rebuild:
    devcontainer up --workspace-folder . --config .devcontainer/{{variant}}/devcontainer.json --remove-existing-container --build-no-cache

# Open an interactive shell inside the dev container
[unix]
shell:
    .devcontainer/devcontainer.sh --variant {{variant}} shell

[windows]
shell:
    devcontainer exec --workspace-folder . --config .devcontainer/{{variant}}/devcontainer.json tmux new-session -A -s main

# Run a command inside the dev container, e.g.: just exec just ping
[unix]
exec *ARGS:
    .devcontainer/devcontainer.sh --variant {{variant}} exec {{ARGS}}

[windows]
exec *ARGS:
    devcontainer exec --workspace-folder . --config .devcontainer/{{variant}}/devcontainer.json {{ARGS}}

# --- Combined checks ---

# Run both the ansible-origin and komodo-origin lint checks
lint: ansible-lint komodo-lint

# First-time setup: both AGE keys, SSH backup keys, and host secrets scaffolding
[working-directory: 'ansible']
setup:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -z "${BW_SESSION:-}" ]; then
        echo "BW_SESSION not set. Run 'unlock' first."
        exit 1
    fi
    echo "=== Restoring/generating AGE keys (ansible + komodo) ==="
    bash ../scripts/init-secrets.sh
    echo ""
    echo "=== Restoring SSH backup keys ==="
    HOSTS=$(ansible-inventory --list 2>/dev/null | jq -r '._meta.hostvars | keys[]')
    for HOST in $HOSTS; do
        KEY_FILE="$HOME/.ssh/id_backup_$HOST"
        if [ -f "$KEY_FILE" ]; then
            echo "  ✓ $HOST — already present"
            continue
        fi
        BW_ITEM=$(bw get item "ssh-backup-$HOST" 2>/dev/null || true)
        if [ -n "$BW_ITEM" ]; then
            echo "$BW_ITEM" | python3 -c "import sys,json; print(json.load(sys.stdin)['sshKey']['privateKey'], end='')" > "$KEY_FILE"
            chmod 600 "$KEY_FILE"
            ssh-keygen -y -f "$KEY_FILE" > "$KEY_FILE.pub"
            echo "  ✓ $HOST — restored from Bitwarden"
        else
            echo "  ✗ $HOST — not found in Bitwarden"
        fi
    done
    echo ""
    echo "Done. Run 'just ping' to verify connectivity, 'just ansible-secrets <host>' or 'just komodo-secrets' to edit secrets."
