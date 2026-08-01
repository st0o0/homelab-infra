# Arr Stack

Media automation stack with Sonarr, Radarr, Prowlarr, Seerr, Tracearr, and supporting services.

```
 host
┌──────────────────────────────────────────────────────┐
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │  Sonarr   │  │  Radarr   │  │ Prowlarr  │          │
│  │  :1089    │  │  :1078    │  │  :1096    │          │
│  └─────┬────┘  └─────┬────┘  └─────┬────┘          │
│        │              │              │               │
│        └──────┬───────┘              │               │
│               ▼                      ▼               │
│  ┌──────────────────┐  ┌──────────────────┐          │
│  │   Recyclarr       │  │  FlareSolverr     │         │
│  │   (TRaSH sync)    │  │  (anti-captcha)   │         │
│  └──────────────────┘  └──────────────────┘          │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐   │
│  │  Seerr    │  │ Dashboard │  │  MediathekArr     │  │
│  │  :1055    │  │  :1005    │  │  :1007            │  │
│  └──────────┘  └──────────┘  └──────────────────┘   │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐           │
│  │ Tracearr  │  │TimescaleDB│  │  Redis   │          │
│  │  :3300    │  │  (pg16)   │  │  (cache) │          │
│  └──────────┘  └──────────┘  └──────────┘           │
│                                                      │
│  Networks: arr-net, media-net (external)             │
│  Volumes:  media_smb, mediathek_smb                  │
└──────────────────────────────────────────────────────┘
```

## Prerequisites

- `media-net` Docker network, created by the `media` stack (deployed first via Komodo `after` ordering — see `komodo/resources/stacks.toml`)
- CIFS volume mounts configured for `media_smb` and `mediathek_smb`

## Quick start

```bash
cp .env .env.local   # set API keys and secrets
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `SONARR_API_KEY` | yes | — | Sonarr API key for Recyclarr |
| `RADARR_API_KEY` | yes | — | Radarr API key for Recyclarr |
| `TRACEARR_JWT_SECRET` | yes | — | JWT signing secret |
| `TRACEARR_COOKIE_SECRET` | yes | — | Cookie encryption secret |
| `*_PORT` | no | various | Published ports (see `.env`) |
| `*_CONFIG_PATH` | no | `./data/<service>/config` | Config directory paths |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Verify

- Sonarr: `http://localhost:1089`
- Radarr: `http://localhost:1078`
- Prowlarr: `http://localhost:1096`
- Seerr: `http://localhost:1055`
- Dashboard: `http://localhost:1005`
- Tracearr: `http://localhost:3300`
