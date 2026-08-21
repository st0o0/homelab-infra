# Downloader

SABnzbd Usenet downloader and Firefox browser routed through a Gluetun VPN tunnel (AirVPN/WireGuard).

```
 host
+--------------------------------------+
|  +----------+     +----------+       |
|  | SABnzbd  |----►| Gluetun  |=======|==> VPN tunnel
|  |          |     | :8079    |       |
|  | Firefox  |----►| :8080    |       |
|  |          |     | :5800    |       |
|  | network_ |     |          |       |
|  | mode:    |     | AirVPN   |       |
|  | service: |     | WireGuard|       |
|  | gluetun  |     |          |       |
|  +----------+     +----------+       |
|                                      |
|  Network: media-net (external)       |
+--------------------------------------+
```

## Prerequisites

- `media-net` Docker network, created by the `media` stack (deployed first via Komodo `after` ordering)
- CIFS volume mount configured for `sabnzbd_smb_downloads` (completed downloads, shared with the arr stack)

## Quick start

```bash
cp .env.example .env   # set WireGuard keys + news server credentials
docker compose up -d
```

SABnzbd UI: `http://localhost:8080`
Firefox UI: `http://localhost:5800`

## Categories

Categories are configured dynamically via numbered `SABNZBD_CAT_<N>_*` environment variables.
The `pre-deploy.sh` script seeds them into `sabnzbd.ini` on first deploy.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SABNZBD_CAT_<N>_NAME` | yes | - | Category name (also stops iteration when missing) |
| `SABNZBD_CAT_<N>_DIR` | no | `NAME` | Download subdirectory |
| `SABNZBD_CAT_<N>_PP` | no | `3` | Post-processing (0=none, 1=repair, 2=+unpack, 3=+delete) |
| `SABNZBD_CAT_<N>_SCRIPT` | no | `Default` | Post-processing script |
| `SABNZBD_CAT_<N>_PRIORITY` | no | `-100` | Priority (-100=default, -2=paused, -1=low, 0=normal, 1=high, 2=force) |

Example:

```
SABNZBD_CAT_1_NAME=sonarr
SABNZBD_CAT_2_NAME=radarr
SABNZBD_CAT_2_PP=1
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `GLUETUN_WG_PRIVATE_KEY` | yes | - | WireGuard private key |
| `GLUETUN_WG_ADDRESSES` | yes | - | WireGuard tunnel addresses |
| `SABNZBD_API_KEY` | yes | - | SABnzbd API key |
| `SABNZBD_NZB_KEY` | yes | - | SABnzbd NZB key |
| `SABNZBD_SERVER1_HOST` | yes | - | Usenet server hostname |
| `SABNZBD_SERVER1_USERNAME` | yes | - | Usenet server username |
| `SABNZBD_SERVER1_PASSWORD` | yes | - | Usenet server password |
| `CIFS_DOWNLOADS_HOST` | yes | - | CIFS/SMB server for downloads |
| `CIFS_DOWNLOADS_SHARE` | yes | - | CIFS share name |
| `CIFS_DOWNLOADS_USER` | yes | - | CIFS username |
| `CIFS_DOWNLOADS_PASS` | yes | - | CIFS password |
| `SABNZBD_PORT` | no | `8080` | SABnzbd web UI port (on gluetun) |
| `GLUETUN_PORT` | no | `8079` | Gluetun control port |
| `SABNZBD_SERVER1_CONNECTIONS` | no | `20` | Number of connections |
| `FIREFOX_PORT` | no | `5800` | Firefox web UI port (on gluetun) |
| `FIREFOX_MEMORY` | no | `512MB` | Firefox memory limit |
| `FIREFOX_LANG` | no | `de_DE.UTF-8` | Firefox locale |

| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

```bash
docker exec gluetun wget -qO- https://ipinfo.io
```
