# Kopia Server

Centralized backup repository server. Clients connect via gRPC to store
encrypted, deduplicated snapshots. Global dedup across all connected hosts.

```
 server host
┌──────────────────────────────────────────┐
│  ┌────────────────┐                      │
│  │  Kopia Server  │ :51515 (Web UI/gRPC) │
│  │                │                      │
│  │ /app/config    │ repository.config    │
│  │ /app/cache     │ dedup cache          │
│  │ /repository    │ backup data          │
│  └────────────────┘                      │
│         ▲                                │
│         │ gRPC (TLS)                     │
│  clients connect from other hosts        │
└──────────────────────────────────────────┘
```

## Quick start

```bash
cp .env.example .env.local   # set credentials
docker compose up -d
```

On first run, create the repository:

```bash
docker exec kopiaserver kopia repository create filesystem --path /repository
```

Web UI at `http://localhost:51515`.

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `KOPIA_SERVER_USER` | yes | — | Web UI / server control username |
| `KOPIA_SERVER_PASS` | yes | — | Web UI / server control password |
| `KOPIA_REPO_PASSWORD` | yes | — | Repository encryption password |
| `KOPIA_PORT` | no | `51515` | Published port for Web UI and gRPC |
| `TZ` | no | — | Timezone |

## Add a client

In the Web UI, go to server users and add a client with a hostname and
password. Use the server's TLS cert fingerprint to connect:

```bash
docker exec kopiaserver kopia server fingerprint
```

## Storage

Default: Docker volume `kopia-repository`. To use a bind mount:

```yaml
volumes:
  - /mnt/backups/kopia:/repository
```

For S3/B2 backends, replace `repository create filesystem` with:

```bash
docker exec kopiaserver kopia repository create s3 \
  --bucket=my-bucket --endpoint=s3.example.com
```
