# PostgreSQL + CloudBeaver

PostgreSQL database with CloudBeaver web admin UI.

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
| `CLOUDBEAVER_PORT` | no | `8978` | CloudBeaver web UI port |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

- PostgreSQL: `docker exec postgres pg_isready`
- CloudBeaver: `http://localhost:8978`
