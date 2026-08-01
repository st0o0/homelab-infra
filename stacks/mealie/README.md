# Mealie

Self-hosted recipe manager with OIDC authentication (Authentik). Uses an external PostgreSQL database.

```
 host
┌──────────────────────────────────────┐
│  ┌──────────┐                        │
│  │ Mealie   │ :9925                  │
│  │          │                        │
│  │ OIDC ───────► Authentik           │
│  │ DB   ───────► PostgreSQL          │
│  └──────────┘                        │
└──────────────────────────────────────┘
```

## Prerequisites

- PostgreSQL database (use the `postgres` stack or an external instance)
- Authentik (or another OIDC provider) for authentication

## Quick start

```bash
cp .env .env.local   # set DB password, server, and OIDC config
mkdir -p data
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `POSTGRES_PASSWORD` | yes | — | Database password |
| `POSTGRES_SERVER` | yes | — | Database hostname |
| `OIDC_CONFIGURATION_URL` | no | — | OIDC discovery URL |
| `OIDC_CLIENT_ID` | no | — | OIDC client ID |
| `OIDC_CLIENT_SECRET` | no | — | OIDC client secret |
| `MEALIE_PORT` | no | `9925` | Web UI port |
| `POSTGRES_USER` | no | `mealie` | Database user |
| `POSTGRES_DB` | no | `mealie` | Database name |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

Open `http://localhost:9925` — the Mealie login page should load.
