# Per-host, non-secret variables. Copied to
# komodo/resources/hosts/<hostname>/variables.toml by `just k vars <hostname>`.
#
# Not secret, so this file is plain TOML — no sops involved, unlike
# komodo/hosts/<hostname>/secrets.sops.yaml. It still lives under
# komodo/resources/ (rather than komodo/hosts/) because that's the only
# path Komodo's ResourceSync watches — see README.md.
#
# Name every entry with a "<hostname>_" prefix so it can't collide with
# komodo/resources/variables.toml or another host's file, and reference it
# from komodo/resources/stacks.toml as [[<hostname>_VARIABLE_NAME]] — same
# convention as per-host secrets ([[<hostname>_host_ip]]).
#
# Example:
# [[variable]]
# name = "FeelsStrongMan_PAPERLESS_DBHOST"
# value = "paperless-db"
# description = "Postgres service name for paperless on FeelsStrongMan"
