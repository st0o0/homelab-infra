# UPS Monitor

UPS monitoring for a host running NUT (Network UPS Tools). A Prometheus NUT exporter scrapes the local `upsd` and Alloy ships the metrics — along with standard host metrics and logs — to the central [observability stack](../observability/README.md).

```
 Pi / UPS host
┌──────────────────────────────────────────────┐
│                                              │
│  upsd (:3493)                                │
│    ▲                                         │
│    │ NUT protocol                            │
│  ┌─┴──────────────┐   ┌───────────────────┐  │
│  │ NUT Exporter   │◄──│      Alloy        │  │    central server
│  │ :9199 /nut     │   │                   │──────► VictoriaMetrics
│  └────────────────┘   │  host metrics     │──────► VictoriaLogs
│                       │  docker logs      │  │
│                       │  system logs      │  │
│                       └───────────────────┘  │
└──────────────────────────────────────────────┘
```

## Prerequisites

- **NUT / peanut** running on the host with `upsd` listening on port `3493`
- The central observability stack reachable from this host (set `VM_BIND_IP` / `VLOGS_BIND_IP` on the central stack if needed)

## Quick start

1. Deploy the stack with at minimum:

   ```
   HOST_HOSTNAME=ups-pi
   REMOTE_WRITE_URL=http://<central-host>:8428/api/v1/write
   LOGS_PUSH_URL=http://<central-host>:9428/insert/loki/api/v1/push
   ```

2. Verify in Grafana on the central server:
   - **Explore → VictoriaMetrics**: `nut_ups_status{host="ups-pi"}` — should return UPS status flags
   - **Explore → VictoriaMetrics**: `nut_battery_charge{host="ups-pi"}` — battery charge percentage

### Recommended dashboard (Dashboards → New → Import)

| ID | Dashboard | Datasource |
|---|---|---|
| `14371` | NUT UPS Dashboard | VictoriaMetrics |

## UPS metrics

The NUT exporter exposes metrics prefixed with `nut_`, including:

| Metric | Description |
|---|---|
| `nut_battery_charge` | Battery charge (0–100%) |
| `nut_battery_runtime_seconds` | Estimated runtime on battery |
| `nut_ups_status` | UPS status flags (OL = online, OB = on battery, LB = low battery) |
| `nut_input_voltage` | Input voltage |
| `nut_output_voltage` | Output voltage |
| `nut_ups_load` | UPS load (0–100%) |

### Useful PromQL queries

```promql
# Battery charge percentage
nut_battery_charge{host="ups-pi"}

# Remaining runtime in minutes
nut_battery_runtime_seconds{host="ups-pi"} / 60

# Is the UPS on battery? (1 = yes)
nut_ups_status{host="ups-pi", flag="OB"}

# Load percentage
nut_ups_load{host="ups-pi"}
```

### Alerting

Grafana → Alerting → New alert rule, query VictoriaMetrics:

- **On battery**: `nut_ups_status{flag="OB"} == 1` → alert immediately
- **Low battery**: `nut_battery_charge < 30` → alert on low charge
- **High load**: `nut_ups_load > 80` → alert when UPS is heavily loaded

## Graceful shutdown of other servers

NUT has a built-in mechanism for this: run `upsmon` in **slave mode** on each server that should shut down when the UPS reaches low battery. The slaves connect to `upsd` on the Pi and trigger a host shutdown automatically.

Install on each server (Debian/Ubuntu):

```bash
sudo apt install nut-client
```

Configure `/etc/nut/upsmon.conf`:

```
MONITOR ups@<pi-ip> 1 <user> <password> slave
SHUTDOWNCMD "/sbin/shutdown -h now"
FINALDELAY 5
```

And `/etc/nut/nut.conf`:

```
MODE=netclient
```

Then `sudo systemctl enable --now nut-client`. When `upsd` on the Pi signals low battery, all slaves shut down gracefully before the UPS runs out.

**This should be a host-level package, not a Docker container** — if Docker is down, the shutdown must still work.

## Configuration

| Variable | Default | Purpose |
|---|---|---|
| `HOST_HOSTNAME` | — (required) | `host` label on all metrics/logs |
| `REMOTE_WRITE_URL` | — (required) | Central VictoriaMetrics remote write endpoint |
| `LOGS_PUSH_URL` | — (required) | Central VictoriaLogs push endpoint (Loki protocol) |
| `NUT_EXPORTER_TARGET` | `nut-exporter:9199` | Alloy scrape target for the NUT exporter (host:port) |
| `NUT_SERVER` | `host.docker.internal` | NUT server address (`upsd` host) |
| `NUT_PORT` | `3493` | NUT server port |
| `NUT_USER` | — | NUT username (if `upsd` requires auth) |
| `NUT_PASSWORD` | — | NUT password |
| `SCRAPE_INTERVAL` | `30s` | Metrics scrape interval |
| `TZ` | `Europe/Berlin` | Timezone |

## Notes

- The NUT exporter connects to `upsd` via the NUT protocol (not SNMP) — no agent needed on the UPS itself.
- `host.docker.internal` resolves to the Docker host on Linux (via `extra_hosts` in compose) — if `upsd` runs on the same machine, the default works.
- Alloy runs as root inside its container to read host logs — that is expected.
- The docker socket is mounted read-only for container log discovery.
