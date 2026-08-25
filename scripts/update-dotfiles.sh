#!/usr/bin/env bash
set -euo pipefail

CHEZMOI="$HOME/.local/bin/chezmoi"

if [ ! -x "$CHEZMOI" ]; then
    echo "==> chezmoi not installed yet, skipping dotfiles update (run postCreateCommand first)"
    exit 0
fi

if [ ! -d "$HOME/.local/share/chezmoi/.git" ]; then
    echo "==> chezmoi not initialized yet, skipping dotfiles update (run postCreateCommand first)"
    exit 0
fi

echo "==> Pulling latest dotfiles and re-applying..."
"$CHEZMOI" update --force

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if command -v age-keygen >/dev/null 2>&1; then
    bash "$SCRIPT_DIR/lib/validate-sops-keys.sh" || true
fi

COMBINED_AGE_KEY_FILE="$HOME/.config/sops/age/keys.txt"
if [ -f "$COMBINED_AGE_KEY_FILE" ] && command -v just >/dev/null 2>&1 && command -v ansible-inventory >/dev/null 2>&1; then
    echo "==> Syncing SSH config entries for hosts with a restored backup key..."
    just a sshsync || true
elif [ ! -f "$COMBINED_AGE_KEY_FILE" ]; then
    echo "==> AGE keys not set up yet — skipping SSH config sync (run 'just setup' first)"
fi
