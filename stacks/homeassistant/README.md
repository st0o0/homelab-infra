# Home Assistant

Smart home stack with Home Assistant, Mosquitto MQTT, Zigbee2MQTT and Matter.js.

```
 host
┌──────────────────────────────────────────────────┐
│  ┌────────────────┐                              │
│  │ Home Assistant  │ :8123                       │
│  │  /dev/serial1   │ Zigbee coordinator          │
│  │  iot (macvlan) │ IoT network                 │
│  └───────┬────────┘                              │
│          │                                       │
│  ┌───────▼────┐  ┌──────────────┐                │
│  │ Mosquitto   │  │ Zigbee2MQTT  │               │
│  │ MQTT :8124  │◄─│  :8125       │               │
│  └────────────┘  └──────────────┘                │
│                                                  │
│  ┌──────────────┐                                │
│  │ Matter.js     │                               │
│  │ (host network)│                               │
│  └──────────────┘                                │
└──────────────────────────────────────────────────┘
```

## Prerequisites

- Zigbee coordinator on `/dev/serial1`
- VLAN interface for IoT network (macvlan)

## Quick start

```bash
cp .env .env.local   # configure network and device paths
docker compose up -d
```

## Environment variables

| Variable | Required | Default | Purpose |
|---|---|---|---|
| `HA_PORT` | no | `8123` | Home Assistant web UI |
| `HA_SERIAL_DEVICE` | no | `/dev/serial1` | Zigbee coordinator device |
| `HA_IOT_IP` | yes | -- | HA IP on IoT VLAN |
| `HA_IOT_SUBNET` | yes | -- | IoT VLAN subnet |
| `HA_IOT_PARENT` | yes | -- | Host VLAN interface (macvlan parent) |
| `MQTT_PORT` | no | `8124` | Mosquitto MQTT port |
| `Z2M_PORT` | no | `8125` | Zigbee2MQTT web UI |
| `TZ` | no | `Europe/Berlin` | Timezone |

## Configuration

HA config is split between repo-managed (read-only) and HA-managed (writable) files:

```
repo (mounted :ro)                   HA data volume (writable)
homeassistant/                       automations.yaml
  configuration.yaml  ─── bootstrap  scripts.yaml
  packages/                          scenes.yaml
    performance.yaml  ─── recorder   secrets.yaml
    prometheus.yaml   ─── metrics    themes/
    helpers.yaml                      custom_components/ (HACS)
                                      .storage/ (dashboards, registries, auth, persons)
```

- `configuration.yaml` is a minimal bootstrap that loads packages and includes HA-managed files
- `packages/` contains infrastructure config grouped by concern
- To add a new package: create a `.yaml` file in `packages/`, restart HA (no compose change needed)
- Dashboards, automations, scripts, scenes and registries are managed through the HA UI and live in the data volume (`.storage/`), not in the repo -- back up the data volume
- `HA_RECORDER_DB_URL` defaults to the local SQLite file; set it to a PostgreSQL URL to switch

## Migrating an existing instance

1. Stop the old HA and back up its config directory
2. Copy the whole directory to `HA_PATH_CONFIG`, preserving ownership (`cp -a` / `rsync -a`)
3. Reuse the old MAC and IP as `HA_BRIDGE_MAC`, `HA_IOT_MAC`, `HA_IOT_IP` (see `docker inspect homeassistant`)
4. Validate first: `docker compose run --rm --no-deps homeassistant python -m homeassistant --script check_config -c /config`
5. `docker compose up -d`; the mounted `configuration.yaml` and `packages/` overlay the copied ones

## Verify

- Home Assistant: `http://localhost:8123`
- Zigbee2MQTT: `http://localhost:8125`
