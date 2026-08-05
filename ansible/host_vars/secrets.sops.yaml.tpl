ansible_host: "CHANGEME"
ansible_user: "CHANGEME"

# Komodo Core (Core host only)
komodo_bind_ip: "CHANGEME"
# MongoDB runs manually deployed on a separate host — host:port here
komodo_database_address: "CHANGEME:27017"
komodo_db_username: "CHANGEME"
komodo_db_password: "CHANGEME"
komodo_admin_password: "CHANGEME"
komodo_jwt_secret: "CHANGEME"
komodo_webhook_secret: "CHANGEME"
komodo_secrets: {}
# Real age keypair — generate with `age-keygen`, paste the AGE-SECRET-KEY-1... line here
komodo_age_key: ""

bifrost_private_key: "CHANGEME"
bifrost_address: "10.13.13.X/32"
bifrost_peer_public_key: "CHANGEME"
bifrost_peer_endpoint: "vpn.example.com:51820"
