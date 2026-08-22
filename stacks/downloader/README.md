# Downloader

NZBGet Usenet downloader and Firefox browser routed through a Gluetun VPN tunnel (AirVPN/WireGuard).

```
 host
+--------------------------------------+
|  +----------+     +----------+       |
|  | NZBGet   |----►| Gluetun  |=======|==> VPN tunnel
|  |          |     | :8079    |       |
|  | Firefox  |----►| :6789    |       |
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
- CIFS volume mount configured for `nzbget_smb_downloads` (completed downloads, shared with the arr stack)

## Quick start

```bash
cp .env.example .env   # set WireGuard keys + news server credentials
docker compose up -d
```

NZBGet UI: `http://localhost:6789`
Firefox UI: `http://localhost:5800`

## Volume layout

| NZBGet path | Container mount | Storage | Purpose |
|---|---|---|---|
| MainDir | /config | Host bind | Config, logs, nzb backups, queue |
| DestDir | /data/completed | CIFS/NAS | Completed downloads (arr import source) |
| InterDir | /data/intermediate | SSD bind | Unpack workspace |
| TempDir | /data/tmp | SSD bind | Download article chunks |
| NzbDir | /config/nzb | Host bind | NZB file backups |
| QueueDir | /config/queue | Host bind | Queue state persistence |

## Categories

Categories are configured dynamically via numbered `NZBGET_CAT_<N>_*` environment variables.
The `pre-deploy.sh` script seeds them into `nzbget.conf` on first deploy.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `NZBGET_CAT_<N>_NAME` | yes | - | Category name (also stops iteration when missing) |
| `NZBGET_CAT_<N>_DIR` | no | - | Download subdirectory under DestDir |
| `NZBGET_CAT_<N>_UNPACK` | no | `yes` | Unpack after download |
| `NZBGET_CAT_<N>_ALIASES` | no | - | Alternative category names |

Example:

```
NZBGET_CAT_1_NAME=sonarr
NZBGET_CAT_1_DIR=series
NZBGET_CAT_2_NAME=radarr
NZBGET_CAT_2_DIR=movies
```

## Schedule

Tasks are configured via `NZBGET_TASK_<N>_*` environment variables.

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `NZBGET_TASK_<N>_TIME` | yes | - | Time in HH:MM format |
| `NZBGET_TASK_<N>_WEEKDAYS` | no | `1-7` | Days (1=Mon, 7=Sun) |
| `NZBGET_TASK_<N>_COMMAND` | no | `PauseDownload` | NZBGet command |
| `NZBGET_TASK_<N>_PARAM` | no | - | Command parameter |

Example (pause at 23:30, resume at 02:00):

```
NZBGET_TASK_1_TIME=23:30
NZBGET_TASK_1_COMMAND=PauseDownload
NZBGET_TASK_2_TIME=02:00
NZBGET_TASK_2_COMMAND=UnpauseDownload
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `GLUETUN_WG_PRIVATE_KEY` | yes | - | WireGuard private key |
| `GLUETUN_WG_ADDRESSES` | yes | - | WireGuard tunnel addresses |
| `NZBGET_SERVER1_HOST` | yes | - | Usenet server hostname |
| `NZBGET_SERVER1_USERNAME` | yes | - | Usenet server username |
| `NZBGET_SERVER1_PASSWORD` | yes | - | Usenet server password |
| `CIFS_DOWNLOADS_HOST` | yes | - | CIFS/SMB server for downloads |
| `CIFS_DOWNLOADS_SHARE` | yes | - | CIFS share name |
| `CIFS_DOWNLOADS_USER` | yes | - | CIFS username |
| `CIFS_DOWNLOADS_PASS` | yes | - | CIFS password |
| `NZBGET_PORT` | no | `6789` | NZBGet web UI port (on gluetun) |
| `NZBGET_USER` | no | `nzbget` | Web UI username |
| `NZBGET_PASS` | no | - | Web UI password |
| `NZBGET_SERVER1_CONNECTIONS` | no | `20` | Number of connections |
| `GLUETUN_PORT` | no | `8079` | Gluetun control port |
| `FIREFOX_PORT` | no | `5800` | Firefox web UI port (on gluetun) |
| `FIREFOX_MEMORY` | no | `512MB` | Firefox memory limit |
| `FIREFOX_LANG` | no | `de_DE.UTF-8` | Firefox locale |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

```bash
docker exec gluetun wget -qO- https://ipinfo.io
```
