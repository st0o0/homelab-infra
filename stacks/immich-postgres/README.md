# Immich PostgreSQL

Standalone PostgreSQL with vectorchord extensions for Immich. Use when running the database separately from the Immich stack.

## Quick start

```bash
cp .env .env.local   # set POSTGRES_PASSWORD
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `POSTGRES_PASSWORD` | yes | — | Database password |
| `POSTGRES_USER` | no | `immich` | Database user |
| `POSTGRES_DB` | no | `immich` | Database name |
| `POSTGRES_PORT` | no | `5433` | Published port |
| `POSTGRES_BIND_IP` | no | `127.0.0.1` | Bind IP |
| `TZ` | no | `Europe/Berlin` | Timezone |
