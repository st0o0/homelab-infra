[private]
default:
    @just --list k

# --- Secrets management ---

# Komodo's AGE key (Key B) lives at a different path than the container-wide
# SOPS_AGE_KEY_FILE default (which points at the ansible key, Key A) — every
# recipe below overrides it explicitly rather than relying on the ambient env.
komodo_age_key_file := if os() == "windows" { env_var('USERPROFILE') / ".config/sops/komodo/age/keys.txt" } else { env_var('HOME') / ".config/sops/komodo/age/keys.txt" }

# Edit encrypted secrets ('all' for shared, or a hostname for host-specific)
# For host-specific targets, auto-scaffolds missing keys from stacks.toml.
secrets TARGET="all":
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    SOPS_CONFIG="komodo/.sops.yaml"
    PARSER="scripts/parse-stack-placeholders.sh"

    if [ "{{TARGET}}" = "all" ]; then
        SECRET="komodo/secrets.sops.yaml"
        if [ ! -f "$SECRET" ]; then
            echo "Error: $SECRET not found. Run 'just setup' first."
            exit 1
        fi
        sops --config "$SOPS_CONFIG" "$SECRET" || true
        exit 0
    fi

    HOST="{{TARGET}}"
    SECRET="komodo/resources/hosts/$HOST/secrets.sops.yaml"
    VARS_FILE="komodo/resources/hosts/$HOST/variables.toml"
    TMP_YAML=""
    TMP_OUT=""
    cleanup() { rm -f "$TMP_YAML" "$TMP_OUT"; }
    trap cleanup EXIT

    # Collect required per-host keys from stacks.toml
    required_keys=""
    if [ -f "$PARSER" ]; then
        required_keys=$(bash "$PARSER" "$HOST" \
            | awk -F'\t' '$4 == "per-host" {print $3}' | sort -u)
    fi

    # Collect keys already in variables.toml (strip host prefix)
    var_keys=""
    if [ -f "$VARS_FILE" ]; then
        var_keys=$(grep -oP '(?<=^name = ")[^"]+' "$VARS_FILE" \
            | sed "s/^${HOST}_//" || true)
    fi

    if [ -f "$SECRET" ]; then
        # Existing file — check for missing keys and inject them
        if [ -n "$required_keys" ]; then
            existing_keys=$(sops -d --config "$SOPS_CONFIG" "$SECRET" 2>/dev/null \
                | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' | sed 's/:.*//' || true)

            missing=""
            for key in $required_keys; do
                if ! echo "$existing_keys" | grep -qx "$key" && \
                   ! echo "$var_keys" | grep -qx "$key"; then
                    missing="$missing $key"
                fi
            done

            if [ -n "$missing" ]; then
                TMP_YAML=$(mktemp --suffix=.sops.yaml)
                chmod 600 "$TMP_YAML"
                sops -d --config "$SOPS_CONFIG" "$SECRET" > "$TMP_YAML"
                echo "" >> "$TMP_YAML"
                for key in $missing; do
                    echo "$key: \"changeme\"" >> "$TMP_YAML"
                    echo "  + $key (added as \"changeme\")"
                done
                TMP_OUT=$(mktemp --suffix=.sops.yaml)
                chmod 600 "$TMP_OUT"
                sops --config "$SOPS_CONFIG" --encrypt "$TMP_YAML" > "$TMP_OUT"
                mv "$TMP_OUT" "$SECRET"
            fi
        fi
    else
        # New file — generate from required keys
        mkdir -p "$(dirname "$SECRET")"
        TMP_YAML=$(mktemp --suffix=.sops.yaml)
        chmod 600 "$TMP_YAML"
        echo "# Host-specific secrets for $HOST" > "$TMP_YAML"
        echo "host_ip: \"changeme\"" >> "$TMP_YAML"
        if [ -n "$required_keys" ]; then
            for key in $required_keys; do
                if ! echo "$var_keys" | grep -qx "$key"; then
                    echo "$key: \"changeme\"" >> "$TMP_YAML"
                fi
            done
        fi
        TMP_OUT=$(mktemp --suffix=.sops.yaml)
        chmod 600 "$TMP_OUT"
        sops --config "$SOPS_CONFIG" --encrypt "$TMP_YAML" > "$TMP_OUT"
        mv "$TMP_OUT" "$SECRET"
        echo "Created $SECRET"
    fi

    sops --config "$SOPS_CONFIG" "$SECRET" || true

# Show decrypted secrets (stdout only, does not write files)
show-secrets TARGET="all":
    #!/usr/bin/env bash
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    if [ "{{TARGET}}" = "all" ]; then
        sops -d --config komodo/.sops.yaml komodo/secrets.sops.yaml
    else
        sops -d --config komodo/.sops.yaml "komodo/resources/hosts/{{TARGET}}/secrets.sops.yaml"
    fi

# --- Variables management ---

# Edit non-secret variables ('all' for shared, or a hostname for host-specific)
# For host-specific targets, auto-scaffolds missing entries from stacks.toml.
vars TARGET="all":
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    SOPS_CONFIG="komodo/.sops.yaml"
    PARSER="scripts/parse-stack-placeholders.sh"

    if [ "{{TARGET}}" = "all" ]; then
        "${EDITOR:-nano}" "komodo/resources/variables.toml"
        exit 0
    fi

    HOST="{{TARGET}}"
    VARS="komodo/resources/hosts/$HOST/variables.toml"
    TEMPLATE="komodo/resources/hosts/variables.toml.tpl"
    SECRET="komodo/resources/hosts/$HOST/secrets.sops.yaml"

    if [ ! -f "$VARS" ]; then
        mkdir -p "$(dirname "$VARS")"
        cp "$TEMPLATE" "$VARS"
        echo "Created $VARS"
    fi

    # Collect required per-host keys from stacks.toml
    required_keys=""
    if [ -f "$PARSER" ]; then
        required_keys=$(bash "$PARSER" "$HOST" \
            | awk -F'\t' '$4 == "per-host" {print $3}' | sort -u)
    fi

    if [ -n "$required_keys" ]; then
        # Collect keys already in variables.toml (strip host prefix)
        var_keys=""
        if [ -f "$VARS" ]; then
            var_keys=$(grep -oP '(?<=^name = ")[^"]+' "$VARS" \
                | sed "s/^${HOST}_//" || true)
        fi

        # Collect keys already in secrets.sops.yaml
        secret_keys=""
        if [ -f "$SOPS_AGE_KEY_FILE" ] && [ -f "$SECRET" ]; then
            secret_keys=$(sops -d --config "$SOPS_CONFIG" "$SECRET" 2>/dev/null \
                | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' | sed 's/:.*//' || true)
        fi

        # Find which stack each key belongs to
        missing=""
        for key in $required_keys; do
            if ! echo "$var_keys" | grep -qx "$key" && \
               ! echo "$secret_keys" | grep -qx "$key"; then
                stack=$(bash "$PARSER" "$HOST" \
                    | awk -F'\t' -v k="$key" '$3 == k && $4 == "per-host" {print $2; exit}')
                missing="$missing $key:$stack"
            fi
        done

        if [ -n "$missing" ]; then
            {
                echo ""
                echo "# --- Missing entries (from stacks.toml) ---"
                echo "# Uncomment and set values for entries that should be variables."
                echo "# Entries that should be secrets: use 'just k secrets $HOST' instead."
                for entry in $missing; do
                    key="${entry%%:*}"
                    stack="${entry#*:}"
                    echo ""
                    echo "# [[variable]]"
                    echo "# name = \"${HOST}_${key}\""
                    echo "# value = \"changeme\""
                    echo "# description = \"from stack: $stack\""
                done
            } >> "$VARS"
        fi
    fi

    "${EDITOR:-nano}" "$VARS"

# --- Configuration audit ---

# Check that all [[PLACEHOLDER]] refs in stacks.toml have matching secrets/variables
check HOST="":
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    SOPS_CONFIG="komodo/.sops.yaml"
    PARSER="scripts/parse-stack-placeholders.sh"

    can_decrypt=true
    if [ ! -f "$SOPS_AGE_KEY_FILE" ]; then
        echo "Warning: AGE key not found at $SOPS_AGE_KEY_FILE — skipping secret checks" >&2
        can_decrypt=false
    fi

    # Collect defined keys from global sources
    global_vars=""
    if [ -f "komodo/resources/variables.toml" ]; then
        global_vars=$(grep -oP '(?<=^name = ")[^"]+' komodo/resources/variables.toml || true)
    fi

    global_secrets=""
    if [ "$can_decrypt" = true ] && [ -f "komodo/secrets.sops.yaml" ]; then
        global_secrets=$(sops -d --config "$SOPS_CONFIG" komodo/secrets.sops.yaml 2>/dev/null \
            | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' | sed 's/:.*//' || true)
    fi

    check_host() {
        local host="$1"
        local host_secrets=""
        local host_vars=""

        # Collect per-host secret keys
        local host_secret_file="komodo/resources/hosts/$host/secrets.sops.yaml"
        if [ "$can_decrypt" = true ] && [ -f "$host_secret_file" ]; then
            host_secrets=$(sops -d --config "$SOPS_CONFIG" "$host_secret_file" 2>/dev/null \
                | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' | sed 's/:.*//' || true)
        fi

        # Collect per-host variable keys (strip HostName_ prefix for comparison)
        local host_vars_file="komodo/resources/hosts/$host/variables.toml"
        if [ -f "$host_vars_file" ]; then
            host_vars=$(grep -oP '(?<=^name = ")[^"]+' "$host_vars_file" \
                | sed "s/^${host}_//" || true)
        fi

        # Get stacks for this host
        local stacks
        stacks=$(bash "$PARSER" "$host" | awk -F'\t' '{print $2}' | sort -u | tr '\n' ', ' | sed 's/,$//')

        local total=0 ok=0 missing=0

        echo "── $host ($stacks) ──"
        echo ""

        bash "$PARSER" "$host" | while IFS=$'\t' read -r h stack key scope; do
            total=$((total + 1))
            local found=""

            if [ "$scope" = "per-host" ]; then
                if echo "$host_secrets" | grep -qx "$key" 2>/dev/null; then
                    found="secrets.sops.yaml"
                elif echo "$host_vars" | grep -qx "$key" 2>/dev/null; then
                    found="variables.toml"
                fi
            else
                if echo "$global_vars" | grep -qx "$key" 2>/dev/null; then
                    found="variables.toml (global)"
                elif echo "$global_secrets" | grep -qx "$key" 2>/dev/null; then
                    found="secrets.sops.yaml (global)"
                fi
            fi

            if [ -n "$found" ]; then
                printf "  ✓ %-40s (%s)\n" "$key" "$found"
            else
                if [ "$scope" = "per-host" ] && [ "$can_decrypt" = false ]; then
                    printf "  ? %-40s (cannot check — no AGE key, stack: %s)\n" "$key" "$stack"
                else
                    printf "  ✗ %-40s MISSING (stack: %s)\n" "$key" "$stack"
                fi
            fi
        done

        echo ""
    }

    if [ -n "{{HOST}}" ]; then
        check_host "{{HOST}}"
    else
        hosts=$(bash "$PARSER" | awk -F'\t' '{print $1}' | sort -u)
        for host in $hosts; do
            check_host "$host"
        done
    fi

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
        if docker compose "${args[@]}" config --no-interpolate -q 2>/dev/null; then
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
