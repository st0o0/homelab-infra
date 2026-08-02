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

ANSIBLE_AGE_KEY_FILE="$HOME/.config/sops/ansible/age/keys.txt"
if [ -f "$ANSIBLE_AGE_KEY_FILE" ] && command -v just >/dev/null 2>&1 && command -v ansible-inventory >/dev/null 2>&1; then
    echo "==> Syncing SSH config entries for hosts with a restored backup key..."
    just a sshsync || true
elif [ ! -f "$ANSIBLE_AGE_KEY_FILE" ]; then
    echo "==> Ansible age key not set up yet — skipping SSH config sync (run 'just setup' first)"
fi
