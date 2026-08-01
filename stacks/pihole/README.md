# Pi-hole

Network-wide ad blocker with Nebula Sync for multi-instance replication.

```
 host
┌──────────────────────────────────────┐
│  ┌──────────┐     ┌──────────────┐  │
│  │ Pi-hole   │ ◄── │ Nebula Sync  │  │
│  │ :53 DNS   │     │ (cron sync)  │  │
│  │ :1000 Web │     └──────────────┘  │
│  └──────────┘                        │
└──────────────────────────────────────┘
```

## Quick start

```bash
cp .env .env.local   # set PIHOLE_PASSWORD
mkdir -p data/{pihole,dnsmasq.d}
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `PIHOLE_PASSWORD` | yes | — | Admin web UI password |
| `PIHOLE_DNS_PORT` | no | `53` | DNS port |
| `PIHOLE_WEB_PORT` | no | `1000` | Web UI port |
| `NEBULA_PRIMARY` | no | — | Primary Pi-hole URL for sync |
| `NEBULA_REPLICAS` | no | — | Replica Pi-hole URLs |
| `NEBULA_CRON` | no | `0 23 * * *` | Sync schedule |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

- DNS: `dig @localhost google.com`
- Web UI: `http://localhost:1000/admin`
