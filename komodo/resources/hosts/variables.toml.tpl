# Per-host, non-secret variables. Copied to
# komodo/resources/hosts/<hostname>/variables.toml by `just k vars <hostname>`.
#
# Not secret, so this file is plain TOML — no sops involved, unlike
# komodo/resources/hosts/<hostname>/secrets.sops.yaml.
#
# Name every entry with a "<hostname>_" prefix so it can't collide with
# komodo/resources/variables.toml or another host's file, and reference it
# from komodo/resources/stacks.toml as [[<hostname>_VARIABLE_NAME]] — same
# convention as per-host secrets ([[<hostname>_host_ip]]).