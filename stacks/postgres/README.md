# PostgreSQL

Shared PostgreSQL database.

## Quick start

```bash
cp .env .env.local   # set POSTGRES_PASSWORD
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `POSTGRES_PASSWORD` | yes | — | Database password |
| `POSTGRES_USER` | no | `postgres` | Database user |
| `POSTGRES_DB` | no | `postgres` | Database name |
| `POSTGRES_PORT` | no | `5432` | Published port |
| `POSTGRES_BIND_IP` | no | `127.0.0.1` | Bind IP |
| `POSTGRES_DATA_PATH` | no | `/docker/postgres/data` | Database data directory |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

- PostgreSQL: `docker exec postgres pg_isready`
