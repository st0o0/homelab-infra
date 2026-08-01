# Authentik

Identity provider and SSO platform. Server handles HTTP/HTTPS requests, Worker processes background tasks.

```
 host
┌──────────────────────────────────────┐
│  ┌────────────────┐                  │
│  │ authentik       │                  │
│  │  server  :9000  │ HTTP             │
│  │          :9443  │ HTTPS            │
│  └────────────────┘                  │
│  ┌────────────────┐                  │
│  │ authentik       │                  │
│  │  worker         │ background tasks │
│  └────────────────┘                  │
│           │                          │
│           ▼                          │
│  PostgreSQL (external)               │
└──────────────────────────────────────┘
```

## Prerequisites

- PostgreSQL database (use the `postgres` stack or an external instance)

## Quick start

```bash
cp .env .env.local   # set secret key and DB password
mkdir -p media certs custom-templates
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `AUTHENTIK_SECRET_KEY` | yes | — | Secret key for session signing |
| `PG_PASS` | yes | — | PostgreSQL password |
| `PG_HOST` | no | `authentik-db` | PostgreSQL hostname |
| `PG_USER` | no | `authentik` | PostgreSQL user |
| `PG_DB` | no | `authentik` | PostgreSQL database |
| `AUTHENTIK_PORT_HTTP` | no | `9000` | HTTP port |
| `AUTHENTIK_PORT_HTTPS` | no | `9443` | HTTPS port |

## Verify

Open `http://localhost:9000` — the Authentik setup wizard should load.
