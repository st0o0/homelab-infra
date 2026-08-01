# Backrest

Restic backup UI for managing and monitoring backups.

```
 host
┌─────────────────────────────────┐
│  ┌──────────┐                   │
│  │ Backrest  │ :9898 (UI)       │
│  │           │                  │
│  │ /config   │ config.json      │
│  │ /data     │ backup metadata  │
│  │ /docker   │ stacks (ro)      │
│  └──────────┘                   │
└─────────────────────────────────┘
```

## Quick start

```bash
cp .env .env.local   # edit if needed
mkdir -p backrest/config
docker compose up -d
```

The UI is available at `http://localhost:9898`.

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `BACKREST_PORT` | no | `9898` | Published port for the web UI |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Bifrost overlay

To access the Backrest UI through a WireGuard tunnel, deploy Bifrost first (`stacks/bifrost`), then stack the overlay:

```bash
docker compose -f compose.yml -f compose.bifrost.yml up -d
```

## Verify

Open `http://localhost:9898` — the Backrest dashboard should load.
