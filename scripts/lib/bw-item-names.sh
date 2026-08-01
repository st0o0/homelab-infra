# Canonical Bitwarden Secure Note names for the two AGE key trust boundaries.
#
# Sourced by scripts/init-secrets.sh and scripts/install-dependencies.sh —
# the single place to change these if the Bitwarden items ever get renamed.
#
# ansible/roles/komodo_secrets/defaults/main.yml's `komodo_secrets_bw_item_name`
# can't source shell, so it duplicates HOMELAB_KOMODO_AGE_KEY_BW_ITEM's value —
# keep both in sync by hand.

HOMELAB_ANSIBLE_AGE_KEY_BW_ITEM="homelab_ansible_age_key"
HOMELAB_KOMODO_AGE_KEY_BW_ITEM="homelab_komodo_age_key"
