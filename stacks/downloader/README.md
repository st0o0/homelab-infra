# Downloader

NZBGet Usenet downloader routed through a Gluetun VPN tunnel (AirVPN/WireGuard).

```
 host
┌──────────────────────────────────────┐
│  ┌──────────┐     ┌──────────┐      │
│  │ NZBGet   │────►│ Gluetun  │══════│══► VPN tunnel
│  │          │     │ :8079    │      │
│  │ network_ │     │ :6789    │      │
│  │ mode:    │     │          │      │
│  │ service: │     │ AirVPN   │      │
│  │ gluetun  │     │ WireGuard│      │
│  └──────────┘     └──────────┘      │
│                                      │
│  Network: media-net (external)       │
└──────────────────────────────────────┘
```

## Prerequisites

- `media-net` Docker network, created by the `media` stack (deployed first via Komodo `after` ordering — see `komodo/resources/stacks.toml`)
- CIFS volume mount configured for `nzbget_smb` (completed downloads, shared with the arr stack)

## Quick start

```bash
cp .env .env.local   # set WireGuard keys + news server credentials
docker compose up -d
```

NZBGet UI: `http://localhost:6789`

## Categories

Pre-configured categories for Sonarr/Radarr/Mediathekarr integration:

| Category | Destination | Used by |
|---|---|---|
| `sonarr` | `/data/complete/sonarr` | Sonarr |
| `radarr` | `/data/complete/radarr` | Radarr |
| `mediathek` | `/data/complete/mediathek` | Mediathekarr |

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `GLUETUN_WG_PRIVATE_KEY` | yes | — | WireGuard private key |
| `GLUETUN_WG_ADDRESSES` | yes | — | WireGuard tunnel addresses |
| `NZBOP_SERVER1_HOST` | yes | — | Usenet server hostname |
| `NZBOP_SERVER1_USERNAME` | yes | — | Usenet server username |
| `NZBOP_SERVER1_PASSWORD` | yes | — | Usenet server password |
| `NZBGET_PORT` | no | `6789` | NZBGet web UI port |
| `GLUETUN_PORT` | no | `8079` | Gluetun control port |
| `NZBOP_SERVER1_CONNECTIONS` | no | `10` | Number of connections |
| `TZ` | no | `Europe/Berlin` | Timezone |

All NZBGet config options can be set via `NZBOP_*` environment variables.

## Verify

```bash
docker exec gluetun wget -qO- https://ipinfo.io
```
