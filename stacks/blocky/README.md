# Blocky DNS

DNS blocker replacing PiHole. Single Go binary, ~20-50MB RAM, pure YAML config.

## Architecture

Two identical instances, same `config.yml`:

- **FeelsNoSponsorMan** (Pi Zero 2 W) — deployed via Komodo
- **MikroTik Router** — deployed manually via SCP

Monitoring via built-in `/metrics` endpoint (port 4000), scraped directly by Alloy.

## Container Images

Both registries are official (same CI pipeline):

- **GHCR**: `ghcr.io/0xerr0r/blocky:v0.35.0` (used by Pi Zero via compose.yml)
- **Docker Hub**: `spx01/blocky:latest` (used by MikroTik, no registry change needed — Docker Hub only has `latest` tag, not versioned tags)

## MikroTik Deployment (RouterOS 7.16+)

### 1. Network Interface

```
/interface/veth add name=veth-blocky address=172.17.0.2/24 gateway=172.17.0.1
/interface/bridge/port add bridge=dockers interface=veth-blocky
```

### 2. Environment Variables

```
/container/envs add list=blocky_envs key=TZ value=Europe/Berlin
```

### 3. Mounts

```
/container/mounts add list=blocky_mounts src=disk1/blocky/config.yml dst=/app/config.yml
/container/mounts add list=blocky_mounts src=disk1/blocky/cache dst=/app/cache
```

Create the cache directory:

```
/file mkdir disk1/blocky/cache
```

### 4. Copy Config

```bash
scp stacks/blocky/config.yml admin@<mikrotik-ip>:/disk1/blocky/config.yml
```

### 5. Create Container

```
/container add \
  remote-image=spx01/blocky:latest \
  interface=veth-blocky \
  root-dir=disk1/blocky/root \
  envlist=blocky_envs \
  mountlists=blocky_mounts \
  logging=yes \
  start-on-boot=yes \
  restart-policy=on-failure \
  restart-max-count=5 \
  restart-interval=00:01:00 \
  stop-signal=15 \
  memory-high=256000000 \
  memory-max=512000000 \
  hostname=blocky \
  dns=9.9.9.9 \
  healthcheck-cmd="/app/blocky healthcheck" \
  healthcheck-interval=00:00:30 \
  healthcheck-retries=3 \
  healthcheck-start-period=00:01:00 \
  healthcheck-timeout=00:00:05 \
  comment="Blocky DNS blocker"
```

### 6. MikroTik DNS Forwarder

```
/ip dns set servers=172.17.0.2 allow-remote-requests=yes cache-size=0
```

Setting `cache-size=0` disables the MikroTik DNS cache so Blocky handles all caching and metrics reflect real query counts.

### 7. Firewall — Metrics Port for Alloy

```
/ip/firewall/filter add chain=input dst-port=4000 protocol=tcp src-address=<FeelsAlertsMan-IP> action=accept comment="Blocky metrics for Alloy"
```

### Verify

```
/container print detail where tag~"blocky"
/tool dns-test name=google.com server=172.17.0.2
/tool dns-test name=ads.google.com server=172.17.0.2
```

The second test should return `0.0.0.0` (blocked).

Check health status:

```
/container print proplist=name,status,healthcheck-status where tag~"blocky"
```

### Update Config

```bash
scp stacks/blocky/config.yml admin@<mikrotik-ip>:/disk1/blocky/config.yml
```

Then on MikroTik:

```
/container restart [find tag~"blocky"]
```

### Update Image

```
/container stop [find tag~"blocky"]
/container repull [find tag~"blocky"]
/container start [find tag~"blocky"]
```

## Local DNS

Local DNS records (clustercontroller.local, ds218.nas, ds418.nas) are managed via MikroTik static DNS entries, not in Blocky config.

## Blocklist Management

All blocklists, whitelists, and blacklists are defined in `config.yml`. Changes go through Git, then:

- **Pi Zero**: Komodo auto-deploys on commit
- **MikroTik**: Manual SCP + container restart
