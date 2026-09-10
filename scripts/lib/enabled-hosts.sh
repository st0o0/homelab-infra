#!/usr/bin/env bash
# Returns an ansible --limit pattern that excludes hosts with host_enabled=false.
# Usage:
#   source scripts/lib/enabled-hosts.sh
#   LIMIT=$(enabled_hosts_limit)
#   ansible -m ping all ${LIMIT:+--limit "$LIMIT"}

enabled_hosts_limit() {
    local disabled
    disabled=$(ansible-inventory --list 2>/dev/null \
        | jq -r '[._meta.hostvars | to_entries[] | select(.value.host_enabled == false) | .key] | map("!" + .) | join(":")')
    if [ -n "$disabled" ]; then
        echo "$disabled"
    fi
}
