#!/usr/bin/env bash
# Parse stacks.toml and emit placeholder requirements per host.
#
# Usage: parse-stack-placeholders.sh [HOSTNAME]
#   Without HOSTNAME: emit for all hosts.
#   With HOSTNAME:    emit only for that host.
#
# Output: tab-separated lines (one per placeholder reference):
#   HOST<tab>STACK<tab>KEY<tab>SCOPE
#
# SCOPE is "per-host" (key stripped of HostName_ prefix) or "global".
# Literal values (no [[...]]) and PATH variables are excluded.
#
# Expects stacks.toml at: komodo/resources/stacks.toml (relative to repo root).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACKS_TOML="$REPO_ROOT/komodo/resources/stacks.toml"
FILTER_HOST="${1:-}"

if [ ! -f "$STACKS_TOML" ]; then
    echo "Error: $STACKS_TOML not found" >&2
    exit 1
fi

awk -v filter="$FILTER_HOST" '
BEGIN { stack=""; server=""; in_env=0; env_buf="" }

# Skip comment lines
/^[[:space:]]*#/ { next }

# New stack block
/^\[\[stack\]\]/ {
    stack = ""
    server = ""
    in_env = 0
    env_buf = ""
    next
}

# Stack name
/^name[[:space:]]*=/ {
    gsub(/^name[[:space:]]*=[[:space:]]*"/, "")
    gsub(/".*/, "")
    stack = $0
    next
}

# Server assignment
/^server[[:space:]]*=/ {
    gsub(/^server[[:space:]]*=[[:space:]]*"/, "")
    gsub(/".*/, "")
    server = $0
    next
}

# Start of environment block
/^environment[[:space:]]*=[[:space:]]*"""/ {
    in_env = 1
    next
}

# Inside environment block
in_env {
    # End of environment block
    if ($0 ~ /"""/) {
        in_env = 0

        if (filter != "" && server != filter) next
        if (server == "" || stack == "") next

        n = split(env_buf, lines, "\n")
        for (i = 1; i <= n; i++) {
            line = lines[i]
            # Extract [[PLACEHOLDER]] references without GNU awk extensions
            while (match(line, /\[\[[^\]]+\]\]/)) {
                raw = substr(line, RSTART + 2, RLENGTH - 4)
                if (index(raw, server "_") == 1) {
                    key = substr(raw, length(server) + 2)
                    scope = "per-host"
                } else {
                    key = raw
                    scope = "global"
                }
                printf "%s\t%s\t%s\t%s\n", server, stack, key, scope
                line = substr(line, RSTART + RLENGTH)
            }
        }
        next
    }
    env_buf = env_buf $0 "\n"
}
' "$STACKS_TOML"
