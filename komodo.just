# --- Secrets management ---

# Komodo's AGE key (Key B) lives at a different path than the container-wide
# SOPS_AGE_KEY_FILE default (which points at the ansible key, Key A) — every
# recipe below overrides it explicitly rather than relying on the ambient env.
komodo_age_key_file := if os() == "windows" { env_var('USERPROFILE') / ".config/sops/komodo/age/keys.txt" } else { env_var('HOME') / ".config/sops/komodo/age/keys.txt" }

# Edit encrypted secrets ('all' for shared, or a hostname for host-specific)
secrets TARGET="all":
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    if [ "{{TARGET}}" = "all" ]; then
        SECRET="komodo/secrets.sops.yaml"
        TEMPLATE="komodo/secrets.example.yaml"
    else
        SECRET="komodo/hosts/{{TARGET}}/secrets.sops.yaml"
        TEMPLATE="komodo/hosts/secrets.sops.yaml.tpl"
    fi
    if [ ! -f "$SECRET" ]; then
        mkdir -p "$(dirname "$SECRET")"
        cp "$TEMPLATE" /tmp/secrets.sops.yaml
        sops --config komodo/.sops.yaml --encrypt /tmp/secrets.sops.yaml > /tmp/secrets.sops.yaml.out
        mv /tmp/secrets.sops.yaml.out "$SECRET"
        rm /tmp/secrets.sops.yaml
        echo "Created $SECRET"
    fi
    sops --config komodo/.sops.yaml "$SECRET" || true

# Decrypt all secrets (shared + per-host) into Komodo Core config
decrypt OUTPUT="/etc/komodo/core.secrets.toml":
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    SOPS_CONFIG="komodo/.sops.yaml"
    GLOBAL="komodo/secrets.sops.yaml"
    if [ ! -f "$GLOBAL" ]; then
        echo "Error: $GLOBAL not found. Run 'just k secrets' first."
        exit 1
    fi
    echo "Decrypting to {{OUTPUT}} ..."
    {
        echo "[secrets]"
        sops -d --config "$SOPS_CONFIG" --output-type json "$GLOBAL" \
            | jq -r 'to_entries[] | "\(.key) = \"\(.value)\""'
        for host_dir in komodo/hosts/*/; do
            HOST_SECRET="${host_dir}secrets.sops.yaml"
            if [ -f "$HOST_SECRET" ]; then
                HOST=$(basename "$host_dir")
                sops -d --config "$SOPS_CONFIG" --output-type json "$HOST_SECRET" \
                    | jq -r --arg h "$HOST" 'to_entries[] | "\($h)_\(.key) = \"\(.value)\""'
            fi
        done
    } > "{{OUTPUT}}"
    chmod 600 "{{OUTPUT}}"
    echo "Done. Restart Komodo Core to pick up changes."

# Show decrypted secrets (stdout only, does not write files)
show-secrets TARGET="all":
    #!/usr/bin/env bash
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    if [ "{{TARGET}}" = "all" ]; then
        sops -d --config komodo/.sops.yaml komodo/secrets.sops.yaml
    else
        sops -d --config komodo/.sops.yaml "komodo/hosts/{{TARGET}}/secrets.sops.yaml"
    fi

# --- Variables management ---

# Edit non-secret variables ('all' for shared, or a hostname for host-specific)
vars TARGET="all":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{TARGET}}" = "all" ]; then
        VARS="komodo/resources/variables.toml"
    else
        VARS="komodo/resources/hosts/{{TARGET}}/variables.toml"
        TEMPLATE="komodo/resources/hosts/variables.toml.tpl"
        if [ ! -f "$VARS" ]; then
            mkdir -p "$(dirname "$VARS")"
            cp "$TEMPLATE" "$VARS"
            echo "Created $VARS"
        fi
    fi
    "${EDITOR:-vi}" "$VARS"

# --- Linting & Validation ---

# Lint all compose files, env files, and YAML
lint: lint-yaml lint-compose lint-env

# YAML lint (all yml/yaml files)
lint-yaml:
    yamllint .

# Validate all Docker Compose files
lint-compose:
    #!/usr/bin/env bash
    set -euo pipefail
    errors=0
    while IFS= read -r file; do
        dir="$(dirname "$file")"
        base="$dir/compose.yml"
        if [ "$file" = "$base" ]; then
            args=(-f "$file")
        else
            args=(-f "$base" -f "$file")
        fi
        if docker compose "${args[@]}" config -q 2>/dev/null; then
            echo "  ok  $file"
        else
            echo "  FAIL $file"
            errors=$((errors + 1))
        fi
    done < <(find stacks -name 'compose*.yml' | sort)
    if [ "$errors" -gt 0 ]; then
        echo ""
        echo "$errors compose file(s) failed validation"
        exit 1
    fi
    echo ""
    echo "All compose files valid"

# Lint all .env files
lint-env:
    dotenv-linter --recursive --skip UnorderedKey --skip LowercaseKey stacks
