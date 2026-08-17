[private]
default:
    @just --list k

# --- Secrets management ---

# Komodo's AGE key (Key B) lives at a different path than the container-wide
# SOPS_AGE_KEY_FILE default (which points at the ansible key, Key A) — every
# recipe below overrides it explicitly rather than relying on the ambient env.
komodo_age_key_file := if os() == "windows" { env_var('USERPROFILE') / ".config/sops/komodo/age/keys.txt" } else { env_var('HOME') / ".config/sops/komodo/age/keys.txt" }

# Edit encrypted secrets ('all' for shared, or a hostname for host-specific)
# For host-specific targets, auto-scaffolds missing keys from stacks/*.toml.
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
    TMP_YAML=""
    TMP_OUT=""
    cleanup() { rm -f "$TMP_YAML" "$TMP_OUT"; }
    trap cleanup EXIT

    TMP_YAML=$(mktemp --suffix=.sops.yaml)
    chmod 600 "$TMP_YAML"

    if [ -f "$SECRET" ]; then
        sops -d --config "$SOPS_CONFIG" "$SECRET" > "$TMP_YAML"
    else
        mkdir -p "$(dirname "$SECRET")"
        echo "# Host-specific secrets for $HOST" > "$TMP_YAML"
        echo "host_ip: \"changeme\"" >> "$TMP_YAML"
    fi

    BEFORE=$(sha256sum "$TMP_YAML" | cut -d' ' -f1)

    # Auto-scaffold missing keys from stacks
    required_keys=""
    parser_cache=""
    if [ -f "$PARSER" ]; then
        parser_cache=$(bash "$PARSER" "$HOST")
        required_keys=$(echo "$parser_cache" \
            | awk -F'\t' '$4 == "per-host" {print $3}' | sort -u)
    fi

    if [ -n "$required_keys" ]; then
        existing_keys=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' "$TMP_YAML" \
            | sed 's/:.*//' || true)

        var_keys=""
        VARS_FILE="komodo/resources/hosts/$HOST/variables.toml"
        if [ -f "$VARS_FILE" ]; then
            var_keys=$(grep -oP '(?<=^name = ")[^"]+' "$VARS_FILE" \
                | sed "s/^${HOST}_//" || true)
        fi

        missing=""
        for key in $required_keys; do
            if ! echo "$existing_keys" | grep -qx "$key" && \
               ! echo "$var_keys" | grep -qx "$key"; then
                stack=$(echo "$parser_cache" \
                    | awk -F'\t' -v k="$key" '$3 == k && $4 == "per-host" {print $2; exit}')
                missing="$missing $key:$stack"
            fi
        done

        if [ -n "$missing" ]; then
            for entry in $missing; do
                key="${entry%%:*}"
                echo "${key}: \"changeme\"" >> "$TMP_YAML"
            done
        fi
    fi
    "${EDITOR:-nano}" "$TMP_YAML"
    AFTER=$(sha256sum "$TMP_YAML" | cut -d' ' -f1)

    if [ "$BEFORE" = "$AFTER" ]; then
        echo "No changes — $SECRET left unchanged"
        exit 0
    fi

    TMP_OUT=$(mktemp --suffix=.sops.yaml)
    chmod 600 "$TMP_OUT"
    sops --config "$SOPS_CONFIG" --encrypt "$TMP_YAML" > "$TMP_OUT"
    mv "$TMP_OUT" "$SECRET"
    echo "Updated $SECRET"

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
# Opens a temporary flat YAML view for editing; on save, writes back to variables.toml.
vars TARGET="all":
    #!/usr/bin/env bash
    set -euo pipefail
    export SOPS_AGE_KEY_FILE="{{komodo_age_key_file}}"
    SOPS_CONFIG="komodo/.sops.yaml"
    PARSER="scripts/parse-stack-placeholders.sh"

    # --- helper: variables.toml → flat YAML (temp file) ---
    toml_to_yaml() {
        local toml="$1" prefix="$2"
        local tmp
        tmp=$(mktemp --suffix=.vars.yaml)
        chmod 600 "$tmp"
        if [ -f "$toml" ]; then
            local key="" value=""
            while IFS= read -r line; do
                if [[ "$line" =~ ^#\ DO\ NOT\ EDIT ]]; then
                    continue
                elif [[ "$line" =~ ^[[:space:]]*# ]]; then
                    echo "$line" >> "$tmp"
                elif [[ "$line" =~ ^name\ =\ \"(.*)\"$ ]]; then
                    key="${BASH_REMATCH[1]}"
                    [ -n "$prefix" ] && key="${key#"${prefix}"}"
                elif [[ "$line" =~ ^value\ =\ \"(.*)\"$ ]]; then
                    value="${BASH_REMATCH[1]}"
                    echo "${key}: \"${value}\"" >> "$tmp"
                    key=""
                fi
            done < "$toml"
        fi
        echo "$tmp"
    }

    # --- helper: flat YAML → variables.toml ---
    yaml_to_toml() {
        local yaml="$1" toml="$2" prefix="$3"
        {
            echo "# DO NOT EDIT — use 'just k vars' to edit as flat YAML"
            echo ""
            first=true
            while IFS= read -r line; do
                [[ -z "$line" ]] && continue
                if [[ "$line" =~ ^[[:space:]]*# ]]; then
                    echo "$line"
                    continue
                fi
                key=$(echo "$line" | sed 's/:.*//')
                value=$(echo "$line" | sed 's/^[^:]*:[[:space:]]*//' | sed 's/^"//; s/"$//')
                if [ "$first" = true ]; then first=false; else echo ""; fi
                echo "[[variable]]"
                echo "name = \"${prefix}${key}\""
                echo "value = \"${value}\""
            done < "$yaml"
        } > "$toml"
    }

    if [ "{{TARGET}}" = "all" ]; then
        TOML="komodo/resources/variables/_global.toml"
        TMP=$(toml_to_yaml "$TOML" "")
        trap 'rm -f "$TMP"' EXIT

        BEFORE=$(sha256sum "$TMP" | cut -d' ' -f1)
        "${EDITOR:-nano}" "$TMP"
        AFTER=$(sha256sum "$TMP" | cut -d' ' -f1)

        if [ "$BEFORE" = "$AFTER" ]; then
            echo "No changes — $TOML left unchanged"
            exit 0
        fi
        yaml_to_toml "$TMP" "$TOML" ""
        echo "Updated $TOML"
        exit 0
    fi

    HOST="{{TARGET}}"
    TOML="komodo/resources/hosts/$HOST/variables.toml"
    SECRET="komodo/resources/hosts/$HOST/secrets.sops.yaml"

    if [ ! -f "$TOML" ]; then
        touch "$TOML"
    fi

    TMP=$(toml_to_yaml "$TOML" "${HOST}_")
    trap 'rm -f "$TMP"' EXIT
    BEFORE=$(sha256sum "$TMP" | cut -d' ' -f1)

    # Auto-scaffold missing keys from stacks
    required_keys=""
    parser_cache=""
    if [ -f "$PARSER" ]; then
        parser_cache=$(bash "$PARSER" "$HOST")
        required_keys=$(echo "$parser_cache" \
            | awk -F'\t' '$4 == "per-host" {print $3}' | sort -u)
    fi

    if [ -n "$required_keys" ]; then
        var_keys=$(grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' "$TMP" \
            | sed 's/:.*//' || true)

        secret_keys=""
        if [ -f "$SOPS_AGE_KEY_FILE" ] && [ -f "$SECRET" ]; then
            secret_keys=$(sops -d --config "$SOPS_CONFIG" "$SECRET" 2>/dev/null \
                | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' | sed 's/:.*//' || true)
        fi

        missing=""
        for key in $required_keys; do
            if ! echo "$var_keys" | grep -qx "$key" && \
               ! echo "$secret_keys" | grep -qx "$key"; then
                stack=$(echo "$parser_cache" \
                    | awk -F'\t' -v k="$key" '$3 == k && $4 == "per-host" {print $2; exit}')
                missing="$missing $key:$stack"
            fi
        done

        if [ -n "$missing" ]; then
            for entry in $missing; do
                key="${entry%%:*}"
                echo "${key}: \"changeme\"" >> "$TMP"
            done
        fi
    fi
    "${EDITOR:-nano}" "$TMP"
    AFTER=$(sha256sum "$TMP" | cut -d' ' -f1)

    if [ "$BEFORE" = "$AFTER" ]; then
        echo "No changes — $TOML left unchanged"
        exit 0
    fi
    yaml_to_toml "$TMP" "$TOML" "${HOST}_"
    echo "Updated $TOML"

# --- Configuration audit ---

# Check that all [[PLACEHOLDER]] refs in stacks/*.toml have matching secrets/variables
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
    if [ -f "komodo/resources/variables/_global.toml" ]; then
        global_vars=$(grep -oP '(?<=^name = ")[^"]+' komodo/resources/variables/_global.toml || true)
    fi

    global_secrets=""
    if [ "$can_decrypt" = true ] && [ -f "komodo/secrets.sops.yaml" ]; then
        global_secrets=$(sops -d --config "$SOPS_CONFIG" komodo/secrets.sops.yaml 2>/dev/null \
            | grep -E '^[a-zA-Z_][a-zA-Z0-9_]*:' | sed 's/:.*//' || true)
    fi

    errors=0

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

        # Collect per-host variable keys (strip host prefix)
        local host_vars_file="komodo/resources/hosts/$host/variables.toml"
        if [ -f "$host_vars_file" ]; then
            host_vars=$(grep -oP '(?<=^name = ")[^"]+' "$host_vars_file" \
                | sed "s/^${host}_//" || true)
        fi

        # Collect duplicates
        local dupes=""
        if [ -n "$host_vars" ] && [ -n "$host_secrets" ]; then
            for key in $host_vars; do
                if echo "$host_secrets" | grep -qx "$key" 2>/dev/null; then
                    dupes="${dupes}${host}_${key}\tin both variables.toml and secrets.sops.yaml\n"
                fi
            done
        fi
        for key in $host_vars; do
            local prefixed="${host}_${key}"
            if echo "$global_vars" | grep -qx "$prefixed" 2>/dev/null; then
                dupes="${dupes}${prefixed}\tin both per-host variables.toml and global variables.toml\n"
            fi
            if echo "$global_secrets" | grep -qx "$prefixed" 2>/dev/null; then
                dupes="${dupes}${prefixed}\tin both per-host variables.toml and global secrets.sops.yaml\n"
            fi
        done
        for key in $host_secrets; do
            local prefixed="${host}_${key}"
            if echo "$global_vars" | grep -qx "$prefixed" 2>/dev/null; then
                dupes="${dupes}${prefixed}\tin both per-host secrets.sops.yaml and global variables.toml\n"
            fi
            if echo "$global_secrets" | grep -qx "$prefixed" 2>/dev/null; then
                dupes="${dupes}${prefixed}\tin both per-host secrets.sops.yaml and global secrets.sops.yaml\n"
            fi
        done

        # Get stacks for this host
        local stacks
        stacks=$(bash "$PARSER" "$host" | awk -F'\t' '{print $2}' | sort -u | tr '\n' ', ' | sed 's/,$//')

        echo "── $host ($stacks) ──"
        echo ""

        # Check each placeholder — print ok inline, collect problems
        local missing_lines=""
        while IFS=$'\t' read -r h stack key scope; do
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
            elif [ "$scope" = "per-host" ] && [ "$can_decrypt" = false ]; then
                printf "  ? %-40s (cannot check — no AGE key)\n" "$key"
            else
                missing_lines="${missing_lines}${key}\t${stack}\n"
            fi
        done < <(bash "$PARSER" "$host")

        # Print missing entries
        if [ -n "$missing_lines" ]; then
            echo ""
            echo "  Missing:"
            while IFS=$'\t' read -r key stack; do
                [ -z "$key" ] && continue
                printf "    ✗ %-40s (stack: %s)\n" "$key" "$stack"
                errors=$((errors + 1))
            done < <(echo -e "$missing_lines")
        fi

        # Print duplicates
        if [ -n "$dupes" ]; then
            echo ""
            echo "  Duplicates:"
            while IFS=$'\t' read -r key reason; do
                [ -z "$key" ] && continue
                printf "    ✗ %-40s (%s)\n" "$key" "$reason"
                errors=$((errors + 1))
            done < <(echo -e "$dupes")
        fi

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

    if [ "$errors" -gt 0 ]; then
        echo "$errors error(s) found" >&2
        exit 1
    fi

# --- Deployment ---

# Push secrets to FeelsCozyMan (decrypt + deploy core.secrets.toml, restart if changed)
[working-directory: 'ansible']
update-secrets *ARGS:
    ansible-playbook run.yml --limit FeelsCozyMan --tags komodo_secrets {{ ARGS }}

# --- Linting & Validation ---

# Lint all compose files, YAML, and Alloy configs
lint: lint-yaml lint-compose lint-alloy

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
        if docker compose "${args[@]}" config --no-interpolate -q; then
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

# Validate Alloy configs
lint-alloy:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Validating proxy stack config..."
    docker run --rm \
        -v "$PWD/stacks/proxy/alloy:/etc/alloy:ro" \
        -v "$PWD/alloy/modules:/etc/alloy/modules:ro" \
        -v "$PWD/alloy/pipelines:/etc/alloy/pipelines:ro" \
        grafana/alloy:v1.17.1 validate /etc/alloy/
    echo "  ok  proxy"
    echo "Validating generic stack config..."
    docker run --rm \
        -v "$PWD/stacks/alloy/alloy:/etc/alloy:ro" \
        -v "$PWD/alloy/modules:/etc/alloy/modules:ro" \
        grafana/alloy:v1.17.1 validate /etc/alloy/
    echo "  ok  generic"

# --- Remote operations (km CLI) ---

# Sync resource definitions from git into Komodo
sync:
    km x -y sync homelab-infra-sync

# Run full deploy pipeline (sync resources, then redeploy changed stacks)
pipeline:
    km x -y procedure deploy-homelab-infra

# Deploy a stack (docker compose up -d)
deploy STACK:
    km x -y stack {{STACK}}

# Restart a running stack (docker compose restart)
restart STACK:
    km x -y restart-stack {{STACK}}

# Stop a stack (docker compose stop)
stop STACK:
    km x -y stop-stack {{STACK}}

# Destroy a stack (docker compose down) — prompts for confirmation
destroy STACK:
    km x destroy-stack {{STACK}}

# Open a shell on a server via Periphery
ssh SERVER:
    km ssh {{SERVER}}

# Shell into a running container (e.g. just k exec traefik sh)
exec CONTAINER SHELL="sh" *ARGS="":
    km exec {{CONTAINER}} {{SHELL}} {{ARGS}}

# Docker system prune on a server (containers, images, networks, volumes)
prune SERVER:
    km x -y prune-system -s {{SERVER}}

# Backup the Komodo database
backup:
    km x -y backup
