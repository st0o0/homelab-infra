#!/usr/bin/env bash
set -euo pipefail

git config --global --add safe.directory "$(pwd)"

# --------------------------------------------------------------------------
# Layer 1: Shell toolchain (zsh, tmux, starship, chezmoi, fzf, zoxide)
# --------------------------------------------------------------------------
# Owned by the dotfiles repo — single source of truth for shell tools.
echo "==> Installing shell toolchain via dotfiles/install.sh..."
curl -fsSL https://raw.githubusercontent.com/st0o0/dotfiles/main/install.sh \
    | bash -s -- --profile devcontainer

# --------------------------------------------------------------------------
# Layer 2: Infra tools (ansible provisioning + Komodo catalog toolchain)
# --------------------------------------------------------------------------
echo "==> Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq --no-install-recommends \
    sshpass \
    python3-pip \
    python3-venv \
    yamllint \
    jq \
    > /dev/null

echo "==> Installing Ansible via pip..."
pip install --break-system-packages -q ansible ansible-lint

echo "==> Installing Ansible collections..."
ansible-galaxy collection install -r ansible/requirements.yml --force-with-deps > /dev/null

echo "==> Installing dotenv-linter..."
DOTENV_VERSION="v3.3.0"
curl -fsSL "https://github.com/dotenv-linter/dotenv-linter/releases/download/${DOTENV_VERSION}/dotenv-linter-linux-x86_64.tar.gz" \
    | sudo tar -xz -C /usr/local/bin/

echo "==> Installing just..."
curl -fsSL https://just.systems/install.sh | sudo bash -s -- --to /usr/local/bin

echo "==> Installing commitlint dependencies..."
npm install --save-dev @commitlint/cli @commitlint/config-conventional --silent

echo "==> Installing Bitwarden CLI (latest)..."
npm install -g @bitwarden/cli --silent

echo "==> Configuring Bitwarden CLI..."
if [ -n "${BW_SERVER_URL:-}" ]; then
    CURRENT_URL=$(bw config server 2>/dev/null || true)
    if [ "$CURRENT_URL" != "$BW_SERVER_URL" ]; then
        bw logout 2>/dev/null || true
        bw config server "$BW_SERVER_URL"
        echo "    Server set: $BW_SERVER_URL"
    else
        echo "    Server already configured: $BW_SERVER_URL"
    fi
else
    echo "    No BW_SERVER_URL set — using Bitwarden cloud"
fi

BW_HOST_DIRS=(
    "/home/${USER:-vscode}/snap/bw/current/Bitwarden CLI"
    "/root/snap/bw/current/Bitwarden CLI"
)
BW_TARGET="$HOME/.config/Bitwarden CLI"
if [ ! -d "$BW_TARGET/data" ]; then
    for dir in "${BW_HOST_DIRS[@]}"; do
        if [ -d "$dir/data" ]; then
            echo "    Found host BW config at $dir — linking..."
            rm -rf "$BW_TARGET"
            ln -s "$dir" "$BW_TARGET"
            break
        fi
    done
fi

echo "==> Installing age..."
curl -fsSL "https://dl.filippo.io/age/latest?for=linux/amd64" -o /tmp/age.tar.gz
sudo tar -xzf /tmp/age.tar.gz -C /usr/local/bin/ --strip-components=1 age/age age/age-keygen
rm /tmp/age.tar.gz

echo "==> Installing glow (terminal markdown reader)..."
GLOW_VERSION="2.0.0"
curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v${GLOW_VERSION}/glow_${GLOW_VERSION}_Linux_x86_64.tar.gz" \
    | sudo tar -xz -C /usr/local/bin/ --strip-components=1 "glow_${GLOW_VERSION}_Linux_x86_64/glow"

echo "==> Installing Komodo CLI..."
curl -sSL https://raw.githubusercontent.com/moghtech/komodo/main/scripts/install-cli.py | sudo python3

echo "==> Installing SOPS..."
SOPS_VERSION="v3.9.4"
curl -fsSL "https://github.com/getsops/sops/releases/download/${SOPS_VERSION}/sops-${SOPS_VERSION}.linux.amd64" -o /tmp/sops
sudo install -m 0755 /tmp/sops /usr/local/bin/sops
rm /tmp/sops

echo "==> Generating Ansible SSH key (if not present)..."
if [ ! -f "$HOME/.ssh/id_ansible" ]; then
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ansible" -N "" -C "ansible-controller"
    echo "    New key generated. Public key:"
    echo ""
    echo "    $(cat "$HOME/.ssh/id_ansible.pub")"
    echo ""
else
    echo "    Key already exists (persistent volume)"
fi

echo "==> Restoring SOPS age keys from Bitwarden (if not present)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/bw-item-names.sh"
ANSIBLE_AGE_KEY_FILE="$HOME/.config/sops/ansible/age/keys.txt"
KOMODO_AGE_KEY_FILE="$HOME/.config/sops/komodo/age/keys.txt"
restore_age_key() {
    local key_file="$1" bw_item_name="$2"
    if [ -f "$key_file" ]; then
        echo "    $bw_item_name: age key already exists"
        return
    fi
    if [ -n "${BW_SESSION:-}" ]; then
        local age_key
        age_key=$(bw get item "$bw_item_name" 2>/dev/null | jq -r '.notes // empty' 2>/dev/null || true)
        if [ -n "$age_key" ]; then
            mkdir -p "$(dirname "$key_file")"
            printf '%s' "$age_key" > "$key_file"
            chmod 600 "$key_file"
            echo "    $bw_item_name: restored from Bitwarden"
        else
            echo "    $bw_item_name: not found in Bitwarden — run 'just setup' to create one"
        fi
    else
        echo "    $bw_item_name: no BW_SESSION — set it to auto-restore, or run 'just setup'"
    fi
}
restore_age_key "$ANSIBLE_AGE_KEY_FILE" "$HOMELAB_ANSIBLE_AGE_KEY_BW_ITEM"
restore_age_key "$KOMODO_AGE_KEY_FILE" "$HOMELAB_KOMODO_AGE_KEY_BW_ITEM"

# --------------------------------------------------------------------------
# Layer 3: DevContainer shell customizations
# --------------------------------------------------------------------------
echo "==> Configuring system-wide tmux autostart..."
TMUX_AUTOSTART_MARKER="# homelab-infra: tmux autostart"
TMUX_AUTOSTART_SNIPPET="
${TMUX_AUTOSTART_MARKER}
if [ -z \"\${NO_AUTOSTART:-}\" ] && [ -z \"\${TMUX:-}\" ] && [ -n \"\${PS1:-}\" ] && command -v tmux >/dev/null 2>&1; then
    exec tmux new-session -A -s main
fi
"
for rc in /etc/bash.bashrc /etc/zsh/zshrc /etc/profile /etc/zsh/zprofile; do
    sudo mkdir -p "$(dirname "$rc")"
    sudo touch "$rc"
    if ! sudo grep -q "$TMUX_AUTOSTART_MARKER" "$rc"; then
        printf '%s\n' "$TMUX_AUTOSTART_SNIPPET" | sudo tee -a "$rc" > /dev/null
        echo "    Added to $rc"
    else
        echo "    Already present in $rc"
    fi
done

echo "==> Configuring host-aware 'just' completions (deploy/bootstrap/vars/ansible-secrets/komodo-secrets/trust/rename)..."
JUST_COMPLETION_MARKER="# homelab-infra: just completions"
REPO_ROOT="$(pwd)"
JUST_COMPLETION_SNIPPET="
${JUST_COMPLETION_MARKER}
if command -v just >/dev/null 2>&1; then
    eval \"\$(just --completions zsh)\"
    [ -f \"${REPO_ROOT}/.devcontainer/completions/just.zsh\" ] && source \"${REPO_ROOT}/.devcontainer/completions/just.zsh\"
fi
"
sudo mkdir -p /etc/zsh
sudo touch /etc/zsh/zshrc
if ! sudo grep -q "$JUST_COMPLETION_MARKER" /etc/zsh/zshrc; then
    printf '%s\n' "$JUST_COMPLETION_SNIPPET" | sudo tee -a /etc/zsh/zshrc > /dev/null
    echo "    Added to /etc/zsh/zshrc"
else
    echo "    Already present in /etc/zsh/zshrc"
fi

echo "==> Setting up devcontainer-specific shell aliases..."
ALIAS_DIR="$HOME/.bash_aliases.d"
mkdir -p "$ALIAS_DIR"
DEVCONTAINER_ALIASES="$ALIAS_DIR/00-devcontainer.sh"
cat > "$DEVCONTAINER_ALIASES" <<'ALIASES'
# Bitwarden unlock — sets BW_SESSION for the current shell
unlock() {
    export BW_SESSION=$(bw unlock --raw)
    echo "Bitwarden unlocked."
}

# Wrap km to add 'setup' and 'edit' subcommands
km() {
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || echo /workspaces/homelab-infra)"
    local sops_config="$repo_root/komodo/.sops.yaml"
    local src="$repo_root/komodo/cli.sops.toml"
    local example="$repo_root/komodo/cli.example.toml"
    export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE_KOMODO:-$HOME/.config/sops/komodo/age/keys.txt}"
    case "${1:-}" in
        setup)
            if [ ! -f "$src" ]; then
                echo "Error: $src not found. Run 'km edit' first to create it."
                return 1
            fi
            local dest_dir="$HOME/.config/komodo"
            mkdir -p "$dest_dir"
            sops -d --config "$sops_config" "$src" > "$dest_dir/komodo.cli.toml"
            chmod 600 "$dest_dir/komodo.cli.toml"
            echo "Decrypted CLI config to $dest_dir/komodo.cli.toml"
            echo "Test with: km version"
            ;;
        edit)
            if [ ! -f "$src" ]; then
                echo "Creating $src from example..."
                cp "$example" "$src"
                sops --config "$sops_config" -e -i "$src"
            fi
            sops --config "$sops_config" "$src" || true
            ;;
        *)
            command km "$@"
            ;;
    esac
}
ALIASES
echo "    Added aliases: unlock, km setup, km edit"

# --------------------------------------------------------------------------
# Verify
# --------------------------------------------------------------------------
echo "==> Verifying installations..."
ansible --version | head -1
yamllint --version
dotenv-linter --version
docker compose version
just --version
pwsh --version | head -1
bw --version
age --version
sops --version
km --version
glow --version
tmux -V
zsh --version
fzf --version
starship --version | head -1
chezmoi --version | head -1
echo "    SSH key:      $([ -f "$HOME/.ssh/id_ansible" ] && echo 'present' || echo 'missing')"
echo "    Ansible key:  $([ -f "$ANSIBLE_AGE_KEY_FILE" ] && echo 'present' || echo 'missing')"
echo "    Komodo key:   $([ -f "$KOMODO_AGE_KEY_FILE" ] && echo 'present' || echo 'missing')"

echo "==> Done."
