# Shared secrets — available to all hosts
# Override per host in host_vars/<host>/secrets.sops.yaml
ups_host: "CHANGEME"
ups_password: "CHANGEME"

# Komodo Periphery — same for every host except ones reached via Bifrost
# (override agent_core_address in host_vars/<host>/secrets.sops.yaml for those)
agent_core_address: "ws://CHANGEME:9120"
agent_onboarding_key: ""
