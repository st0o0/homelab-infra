# Downloader

SABnzbd Usenet downloader routed through a Gluetun VPN tunnel (AirVPN/WireGuard).

```
 host
┌──────────────────────────────────────┐
│  ┌──────────┐     ┌──────────┐      │
│  │ SABnzbd  │────►│ Gluetun  │══════│══► VPN tunnel
│  │          │     │ :8079    │      │
│  │ network_ │     │ :8080    │      │
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
- CIFS volume mount configured for `sabnzbd_smb` (completed downloads, shared with the arr stack's mediathekarr volume)

## Quick start

```bash
cp .env .env.local   # set WireGuard keys
mkdir -p gluetun/config sabnzbd/config
docker compose up -d
```

SABnzbd UI: `http://localhost:8080`

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `WIREGUARD_PRIVATE_KEY` | yes | — | WireGuard private key |
| `WIREGUARD_ADDRESSES` | yes | — | WireGuard tunnel addresses |
| `VPN_SERVICE_PROVIDER` | no | `airvpn` | VPN provider |
| `SERVER_CITIES` | no | `Alblasserdam` | VPN server city |
| `SABNZBD_PORT` | no | `8080` | SABnzbd web UI port |
| `GLUETUN_PORT` | no | `8079` | Gluetun control port |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

```bash
docker exec gluetun wget -qO- https://ipinfo.io
```
