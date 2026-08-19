# Arr Stack

Media automation stack with Sonarr, Radarr, Prowlarr, Seerr, and supporting services.

```
 host
┌───────────────────────────────────────────────────────────┐
│                                                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐                │
│  │  Sonarr   │  │  Radarr   │  │ Prowlarr  │               │
│  │  :8989    │  │  :7878    │  │  :9696    │               │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘               │
│        │              │              │                    │
│        └──────┬───────┴──────┬───────┘                    │
│               ▼              ▼                            │
│  ┌──────────────────┐  ┌──────────────────┐               │
│  │   Configarr       │  │   Exportarr x3   │              │
│  │   (TRaSH sync)    │  │   (metrics)      │              │
│  └──────────────────┘  └──────────────────┘               │
│                                                           │
│  ┌──────────┐  ┌──────────┐                               │
│  │  Seerr    │  │ Seekarr   │                              │
│  │  :5055    │  │           │                              │
│  └──────────┘  └──────────┘                               │
│                                                           │
│  ┌──────────┐  ┌──────────┐                               │
│  │ Youtarr   │  │Youtarr-DB │                              │
│  │  :3087    │  │ (MariaDB) │                              │
│  └──────────┘  └──────────┘                               │
│                                                           │
│  Networks: arr-net, media-net (external)                  │
│  Volumes:  media_smb (CIFS)                               │
│  DB:       external PostgreSQL (Sonarr/Radarr/Prowlarr/   │
│            Seerr), local MariaDB (Youtarr)                │
└───────────────────────────────────────────────────────────┘
```

## Prerequisites

- `media-net` Docker network, created by the `media` stack (deployed first via Komodo `after` ordering)
- CIFS volume mount configured for `media_smb`
- External PostgreSQL with databases for Sonarr, Radarr, Prowlarr, and Seerr

## Quick start

```bash
cp .env.example .env.local   # set API keys, DB credentials, and CIFS config
docker compose up -d
```

## Services

| Service | Image | Port | Purpose |
|---|---|---|---|
| Sonarr | `home-operations/sonarr` | 8989 | TV show management |
| Radarr | `home-operations/radarr` | 7878 | Movie management |
| Prowlarr | `home-operations/prowlarr` | 9696 | Indexer management |
| Seerr | `seerr-team/seerr` | 5055 | Media request UI |
| Seekarr | `scottrobertson/seekarr` | — | Search automation |
| Configarr | `raydak-labs/configarr` | — | TRaSH guide sync (run-once) |
| Exportarr | `onedr0p/exportarr` x3 | — | Prometheus metrics for Sonarr/Radarr/Prowlarr |
| Youtarr | `dialmaster/youtarr` | 3087 | YouTube downloader |
| Youtarr-DB | `mariadb:10.11` | — | MariaDB for Youtarr |

## Environment variables

See `.env.example` for the full list. Key groups:

| Variable | Required | Purpose |
|---|---|---|
| `SONARR_API_KEY` | yes | Sonarr API key |
| `RADARR_API_KEY` | yes | Radarr API key |
| `PROWLARR_API_KEY` | yes | Prowlarr API key |
| `*_POSTGRES_HOST/USER/PASS` | yes | External PostgreSQL credentials per service |
| `SEERR_DB_HOST/USER/PASS` | yes | Seerr PostgreSQL credentials |
| `YOUTARR_DB_ROOT_PASSWORD` | yes | MariaDB root password |
| `YOUTARR_DB_PASSWORD` | yes | MariaDB app password |
| `CIFS_MEDIA_*` | yes | SMB share for media files |
| `*_PORT` | no | Published port overrides |
| `*_PATH_CONFIG` | no | Config directory overrides |
| `TZ` | no | Timezone (default: `Europe/Berlin`) |
| `PUID` / `PGID` | no | User/group mapping (default: 1000) |
