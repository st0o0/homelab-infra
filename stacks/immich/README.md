# Immich

Self-hosted photo and video backup with machine learning.

```
 host
┌──────────────────────────────────────────┐
│  ┌────────────┐     ┌──────────────┐    │
│  │ Immich      │     │ Machine      │    │
│  │  Server     │     │  Learning    │    │
│  │  :2283      │     │              │    │
│  └──────┬─────┘     └──────────────┘    │
│         │                                │
│  ┌──────▼─────┐     ┌──────────┐        │
│  │ PostgreSQL  │     │  Redis   │        │
│  │ pgvecto-rs  │     │  (cache) │        │
│  └────────────┘     └──────────┘        │
└──────────────────────────────────────────┘
```

## Quick start

```bash
cp .env .env.local   # set DB_PASSWORD
mkdir -p data/upload
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `DB_PASSWORD` | yes | — | PostgreSQL password |
| `IMMICH_PORT` | no | `2283` | Web UI port |
| `UPLOAD_PATH` | no | `./data/upload` | Photo upload directory |
| `DB_USERNAME` | no | `postgres` | Database user |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

Open `http://localhost:2283` — the Immich setup wizard should load.
