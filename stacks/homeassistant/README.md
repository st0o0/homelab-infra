# Home Assistant

Smart home stack with Home Assistant, Mosquitto MQTT, Zigbee2MQTT, Matter.js, and Njord weather forecasting.

```
 host
┌──────────────────────────────────────────────────┐
│  ┌────────────────┐                              │
│  │ Home Assistant  │ :8123                       │
│  │  /dev/serial1   │ Zigbee coordinator          │
│  │  vlan88        │ IoT network                 │
│  └───────┬────────┘                              │
│          │                                       │
│  ┌───────▼────┐  ┌──────────────┐                │
│  │ Mosquitto   │  │ Zigbee2MQTT  │               │
│  │ MQTT :8124  │◄─│  :8125       │               │
│  └────────────┘  └──────────────┘                │
│                                                  │
│  ┌──────────────┐  ┌──────────┐                  │
│  │ Matter.js     │  │  Njord   │                 │
│  │ (host network)│  │  :9090   │                 │
│  └──────────────┘  └──────────┘                  │
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
| `HA_VLAN_IP` | no | `10.44.88.254` | HA IP on IoT VLAN |
| `MQTT_PORT` | no | `8124` | Mosquitto MQTT port |
| `Z2M_PORT` | no | `8125` | Zigbee2MQTT web UI |
| `NJORD_LOCATION_NAME` | no | `vreden` | Weather location |
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
    rest_commands.yaml                .storage/
```

- `configuration.yaml` is a minimal bootstrap that loads packages and includes HA-managed files
- `packages/` contains all infrastructure config grouped by concern
- To add a new package: create a `.yaml` file in `packages/`, restart HA (no compose change needed)
- Automations, scripts, and scenes are managed through the HA UI and stay in the data volume

## Verify

- Home Assistant: `http://localhost:8123`
- Zigbee2MQTT: `http://localhost:8125`
- Njord: `http://localhost:9090`
