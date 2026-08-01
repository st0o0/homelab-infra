# NUT UPS Daemon + Peanut

Network UPS Tools (NUT) server for USB-connected UPS devices with Peanut web dashboard.

```
 host
┌───────────────────────────────────────┐
│  ┌───────────┐     ┌──────────┐      │
│  │ nut-upsd  │ ◄── │  Peanut  │      │
│  │ :3493     │     │  :8080   │      │
│  │           │     │  (Web UI)│      │
│  │ /dev/bus  │     └──────────┘      │
│  │ USB UPS   │                       │
│  └───────────┘                       │
└───────────────────────────────────────┘
```

## Quick start

```bash
cp .env .env.local   # set NUT_DRIVER and NUT_API_PASSWORD
mkdir -p peanut
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `NUT_DRIVER` | yes | — | UPS driver (e.g. `usbhid-ups`) |
| `NUT_API_PASSWORD` | yes | — | Password for the NUT API user |
| `NUT_NAME` | no | `ups` | UPS identifier |
| `NUT_PORT` | no | `auto` | UPS device port |
| `NUT_POLLINTERVAL` | no | `15` | Poll interval in seconds |
| `NUT_API_USER` | no | `upsmon` | NUT API username |
| `NUT_BIND` | no | `3493` | Published NUT port |
| `PEANUT_PORT` | no | `8080` | Peanut web UI port |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

- NUT: `docker exec nut-upsd upsc ups@localhost`
- Peanut: `http://localhost:8080`
