# Kopia Client

Backup client that connects to a centralized Kopia repository server.
Runs snapshots on schedule and sends deduplicated data to the server.

```
 client host                           server host
┌───────────────────────────┐       ┌──────────────────┐
│  ┌───────────────┐        │ gRPC  │                  │
│  │  Kopia Client │────────│──────>│  Kopia Server    │
│  │               │        │ TLS   │                  │
│  │ /docker (ro)  │        │       │  /repository     │
│  │ /restore (rw) │        │       │                  │
│  └───────────────┘        │       └──────────────────┘
└───────────────────────────┘
```

## Quick start

1. Add a server user in Kopia Server UI for this host
2. Get the server TLS fingerprint: `docker exec kopiaserver kopia server fingerprint`

```bash
cp .env.example .env.local   # set KOPIA_HOSTNAME and credentials
docker compose up -d
```

Connect to the repository server:

```bash
docker exec kopiaclient kopia repository connect server \
  --url=https://kopiaserver:51515 \
  --server-cert-fingerprint=FINGERPRINT \
  --override-hostname=$KOPIA_HOSTNAME \
  --override-username=$KOPIA_HOSTNAME \
  --password=CLIENT_PASSWORD_FROM_SERVER
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `KOPIA_HOSTNAME` | yes | — | Hostname shown in Kopia Server UI |
| `KOPIA_REPO_PASSWORD` | yes | — | Repository encryption password |
| `KOPIA_CLIENT_USER` | yes | — | Local web UI username |
| `KOPIA_CLIENT_PASS` | yes | — | Local web UI password |
| `TZ` | no | — | Timezone |

## Volumes

| Mount | Mode | Purpose |
|---|---|---|
| `/docker` | ro | Docker stacks and configs to back up |
| `/restore` | rw | Target directory for file restores |
| `/app/config` | rw | Repository connection config and cache |

Add more source paths by extending the `volumes` section in `compose.yml`.
Mount at the same path inside and outside the container so snapshot paths
match host paths.

## Pre-snapshot hooks

To dump PostgreSQL before a snapshot:

```bash
docker exec kopiaclient kopia policy set /docker \
  --before-snapshot-root-action="docker exec postgres pg_dumpall -U postgres > /docker/postgres/backup.sql"
```
