#!/usr/bin/env bash
# Parse stack TOML files and emit placeholder requirements per host.
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
# Reads all .toml files under komodo/resources/stacks/ (relative to repo root).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STACKS_DIR="$REPO_ROOT/komodo/resources/stacks"
FILTER_HOST="${1:-}"

if [ ! -d "$STACKS_DIR" ]; then
    echo "Error: $STACKS_DIR not found" >&2
    exit 1
fi

find "$STACKS_DIR" -name '*.toml' -print0 | sort -z | xargs -0 awk -v filter="$FILTER_HOST" '
BEGIN { stack=""; server=""; in_block=0; block_buf="" }

# Skip comment lines
/^[[:space:]]*#/ { next }

# New stack block — reset state
/^\[\[stack\]\]/ {
    stack = ""
    server = ""
    in_block = 0
    block_buf = ""
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

# Start of environment or contents block (triple-quoted)
/^(environment|contents)[[:space:]]*=[[:space:]]*"""/ {
    in_block = 1
    block_buf = ""
    next
}

# Inside a triple-quoted block
in_block {
    if ($0 ~ /"""/) {
        in_block = 0

        if (filter != "" && server != filter) next
        if (server == "" || stack == "") next

        n = split(block_buf, lines, "\n")
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
    block_buf = block_buf $0 "\n"
}
'
