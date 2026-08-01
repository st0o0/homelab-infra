# Observability Stack

Grafana + VictoriaMetrics + VictoriaLogs + Grafana Alloy — low-footprint metrics and logs for a homelab, without Prometheus.

```
                          ┌──────────────────┐
        metrics (remote   │  VictoriaMetrics │◄──┐
        write, PromQL-    │  :8428           │   │
        compatible)       └──────────────────┘   │
                                   ▲             │
┌─────────┐   queries              │             │
│ Grafana │───────────────────────►┤       ┌─────┴─────┐   /proc /sys /rootfs (host metrics)
│ :3000   │───────────────────┐    │       │   Alloy   │◄── /var/log (auth, syslog, kernel)
└─────────┘                   ▼    │       │  :12345   │◄── docker.sock (container logs)
                     ┌─────────────┴──┐    └─────┬─────┘
                     │ VictoriaLogs   │◄─────────┘
                     │ :9428          │  logs (Loki push protocol)
                     └────────────────┘
```

## Why this stack (and not Prometheus/Loki)

- **VictoriaMetrics** is a drop-in Prometheus replacement: it speaks PromQL, accepts Prometheus `remote_write`, and Grafana talks to it through the standard Prometheus datasource — but it needs a fraction of the RAM and disk, which matters on homelab hardware. Retention is a single flag (`VM_RETENTION`, default 90d).
- **VictoriaLogs** is the log store from the same team: ~50–100 MB RAM (vs. Loki's 150–300 MB), a single binary with zero config files, full-text search without label-cardinality worries, and it **ingests the Loki push protocol** — so standard collectors work unchanged. Queried with [LogsQL](https://docs.victoriametrics.com/victorialogs/logsql/).
- **Grafana Alloy** is the single collector. It replaces node-exporter (built-in `prometheus.exporter.unix`) and Promtail (log tailing + docker discovery) — one container instead of three.

Total idle footprint of the whole stack: roughly **0.4–0.7 GB RAM**, near-zero CPU.

## Containers

| Container | Image | Purpose |
|---|---|---|
| grafana | grafana/grafana | Dashboards & alerting UI, port `3000` |
| victoriametrics | victoriametrics/victoria-metrics | Metrics store (PromQL), port `8428` |
| victorialogs | victoriametrics/victoria-logs | Log store (LogsQL), port `9428` |
| alloy | grafana/alloy | Collector: host metrics, docker logs, system logs |

Only Grafana is published to the host. VictoriaMetrics and VictoriaLogs are bound to `127.0.0.1` by default — set `VM_BIND_IP` / `VLOGS_BIND_IP` to the host's WireGuard IP to accept remote [observability agents](../observability-agent/README.md).

## Quick start

1. Deploy the stack (via Komodo or `docker compose up -d`). The only **required** variable is `GRAFANA_ADMIN_PASSWORD`. Set `HOST_HOSTNAME` to the machine's name — it becomes the `host` label on every metric and log line, so a second host deployed later stays distinguishable. (Grafana installs the `victoriametrics-logs-datasource` plugin on first start, so it needs internet access once.)
2. Open `http://<host>:3000`, log in with `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD`.
3. Datasources **VictoriaMetrics** (default) and **VictoriaLogs** are already provisioned — nothing to configure.
4. Verify data is flowing: **Explore → VictoriaMetrics** and run `node_load1`, then **Explore → VictoriaLogs** and run `{job="docker"}`.

### Recommended dashboard (Dashboards → New → Import)

| ID | Dashboard | Datasource |
|---|---|---|
| `1860` | Node Exporter Full | VictoriaMetrics |

Alloy's `prometheus.exporter.unix` emits the exact same `node_*` metrics as node-exporter, so Node Exporter Full works unmodified. For logs, VictoriaLogs also ships its own web UI at `http://127.0.0.1:9428/select/vmui/` on the host.

## Host log integration

Alloy mounts the host's `/var/log` read-only and tails:

| File | `job` field |
|---|---|
| `/var/log/auth.log` | `auth` |
| `/var/log/syslog` | `syslog` |
| `/var/log/kern.log` | `kernel` |

### Useful LogsQL queries

```logsql
# Failed SSH logins from auth.log
{job="auth"} "Failed password"

# Kernel messages
{job="kernel"}

# All logs from this host
{host="homelab"}
```

## Configuration & tuning

| Variable | Default | Purpose |
|---|---|---|
| `GRAFANA_ADMIN_PASSWORD` | — (required) | Initial Grafana admin password |
| `GRAFANA_ADMIN_USER` | `admin` | Initial Grafana admin user |
| `GRAFANA_PORT` | `3000` | Published Grafana port |
| `VM_RETENTION` | `90d` | Metrics retention |
| `VL_RETENTION` | `31d` | Logs retention |
| `VL_MAX_DISK_GB` | `0` (off) | Hard disk-usage cap for logs — safety net on small disks |
| `SCRAPE_INTERVAL` | `30s` | Host metrics scrape interval (also VM dedup window) |
| `GRAFANA_ROOT_URL` | — | Public URL when Grafana runs behind a reverse proxy |
| `GRAFANA_DB_TYPE` | `sqlite3` | Grafana config DB: `sqlite3` (embedded) or `postgres` |
| `GRAFANA_DB_HOST` | — | PostgreSQL `host:port` (only with `GRAFANA_DB_TYPE=postgres`) |
| `GRAFANA_DB_NAME` / `_USER` / `_PASSWORD` | `grafana` / — / — | PostgreSQL connection (only with `postgres`) |
| `GRAFANA_DB_SSL_MODE` | `disable` | PostgreSQL SSL mode (`disable`, `require`, `verify-full`) |
| `HOST_HOSTNAME` | `homelab` | `host` label on all metrics/logs |
| `VM_BIND_IP` | `127.0.0.1` | Bind IP for VictoriaMetrics `:8428` (set to WireGuard IP for agents) |
| `VLOGS_BIND_IP` | `127.0.0.1` | Bind IP for VictoriaLogs `:9428` (set to WireGuard IP for agents) |
| `TZ` | `Europe/Berlin` | Grafana timezone |

- **Low-power tuning**: the scrape interval defaults to `30s` — set `SCRAPE_INTERVAL=60s` to halve write load again, or `15s` for finer resolution.
- **Defaults already applied**: Grafana runs without analytics/phone-home/news feed and with SQLite WAL mode; all containers use log rotation (10 MB × 3 files); VictoriaMetrics self-monitors (`vm_*` metrics) and deduplicates at the scrape interval.
- **Non-Debian hosts** (RHEL/Alpine): adjust the paths in the `local.file_match "system"` block of `alloy/config.alloy` (e.g. `/var/log/secure` instead of `auth.log`).
- **More scrape targets** (e.g. an app exposing `/metrics`): add a `prometheus.scrape` block in `alloy/config.alloy` pointing at the target, forwarding to `prometheus.remote_write.victoriametrics.receiver`.
- **Alloy debug UI**: Alloy serves its component graph on port `12345` (not published by default) — useful to see whether each pipeline is healthy.
- **Image tags are pinned deliberately** (no `latest`): Grafana majors can break dashboards/plugins, Alloy's config syntax evolves between minors, and central + agents should run matching collector versions. Bump the pins consciously — check the release notes, update, redeploy.

## Using an external PostgreSQL for Grafana

Grafana's **config DB** (users, dashboards, settings — *not* the metrics/logs, those live in VictoriaMetrics/VictoriaLogs, which are their own storage engines and cannot use an external DB) defaults to embedded SQLite. If you already run a central PostgreSQL, you can point Grafana at it:

1. On the PostgreSQL server, create the database and user:

   ```sql
   CREATE USER grafana WITH PASSWORD '...';
   CREATE DATABASE grafana OWNER grafana;
   ```

2. Deploy with:

   ```
   GRAFANA_DB_TYPE=postgres
   GRAFANA_DB_HOST=db.lan:5432
   GRAFANA_DB_USER=grafana
   GRAFANA_DB_PASSWORD=...
   ```

Grafana creates its schema on first start. Two caveats:

- **Switch before first use** (or accept starting fresh): there is no automatic SQLite→PostgreSQL migration — dashboards/users created under SQLite don't carry over.
- Grafana now depends on the PostgreSQL server being up; metrics/logs collection (Alloy → VM/VL) keeps running regardless, only the UI is affected.

## Monitoring other servers

Deploy the **Observability Agent** stack (`stacks/observability-agent/`) on each additional server. It runs the same Alloy pipelines and pushes metrics/logs to this stack through a Bifrost WireGuard tunnel. On this host, set `VM_BIND_IP` and `VLOGS_BIND_IP` to the WireGuard IP (e.g. `10.77.32.1`) so the agents can reach VictoriaMetrics and VictoriaLogs. Every series carries a `host` label, so dashboards work fleet-wide. See [observability-agent/README.md](../observability-agent/README.md).

## Notes

- Alloy runs as root inside its container so it can read root-owned host logs (`auth.log` is `640 root:adm`) — that is expected.
- The docker socket is mounted read-only for container log discovery.
- VictoriaLogs and VictoriaMetrics have no auth; they are loopback-bound by default. If you open them up via the `*_BIND_IP` variables, bind them to a WireGuard/VPN IP only — never a public interface.
