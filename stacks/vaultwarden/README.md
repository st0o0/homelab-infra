# Vaultwarden

Lightweight Bitwarden-compatible password manager server.

```
 host
┌──────────────────────────────────────┐
│  ┌─────────────┐                     │
│  │ Vaultwarden  │ :3002              │
│  │  /data       │ vault storage      │
│  └─────────────┘                     │
└──────────────────────────────────────┘
```

## Quick start

```bash
cp .env .env.local   # set DOMAIN and DATABASE_URL if using external DB
mkdir -p data
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `VAULTWARDEN_PORT` | no | `3002` | Web UI port |
| `VAULTWARDEN_DOMAIN` | no | — | Public domain for the vault |
| `DATABASE_URL` | no | — | External database URL (default: SQLite) |
| `DISABLE_ADMIN_TOKEN` | no | `true` | Disable admin panel |
| `SIGNUPS_ALLOWED` | no | `false` | Allow new user signups |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

Open `http://localhost:3002` — the Vaultwarden login page should load.
