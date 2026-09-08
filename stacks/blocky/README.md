# Blocky DNS

DNS blocker replacing PiHole. Single Go binary, ~20-50MB RAM, pure YAML config.

## Architecture

Two identical instances, same `config.yml`:

- **FeelsNoSponsorMan** (Pi Zero 2 W) — deployed via Komodo
- **MikroTik Router** — deployed manually via SCP

Monitoring via built-in `/metrics` endpoint (port 4000), scraped directly by Alloy.

## MikroTik Deployment

### Initial Setup

1. Pull the container image:

```
/container/config set registry-url=https://ghcr.io tmpdir=disk1/pull
/container/envs add name=blocky_envs
/container add remote-image=0xerr0r/blocky:v0.25 interface=veth-blocky root-dir=disk1/blocky envlist=blocky_envs logging=yes
```

2. Copy config to the router:

```bash
scp stacks/blocky/config.yml admin@<mikrotik-ip>:/disk1/blocky/config.yml
```

3. Create the network interface:

```
/interface/veth add name=veth-blocky address=172.17.0.2/24 gateway=172.17.0.1
/interface/bridge/port add bridge=dockers interface=veth-blocky
```

4. Mount config and start:

```
/container/mounts add name=blocky-config src=disk1/blocky/config.yml dst=/app/config.yml
/container set [find tag~"blocky"] mounts=blocky-config
/container start [find tag~"blocky"]
```

5. Forward DNS traffic to Blocky:

```
/ip/firewall/nat add chain=dstnat dst-port=53 protocol=udp action=dst-nat to-addresses=172.17.0.2
/ip/firewall/nat add chain=dstnat dst-port=53 protocol=tcp action=dst-nat to-addresses=172.17.0.2
```

6. Open metrics port for Alloy scraping:

```
/ip/firewall/filter add chain=input dst-port=4000 protocol=tcp src-address=<FeelsAlertsMan-IP> action=accept comment="Blocky metrics for Alloy"
```

### Verify

```
/tool dns-test name=google.com server=172.17.0.2
```

### Update Config

```bash
scp stacks/blocky/config.yml admin@<mikrotik-ip>:/disk1/blocky/config.yml
```

Then on MikroTik:

```
/container stop [find tag~"blocky"]
/container start [find tag~"blocky"]
```

## Local DNS

Local DNS records (clustercontroller.local, ds218.nas, ds418.nas) are managed via MikroTik static DNS entries, not in Blocky config.

## Blocklist Management

All blocklists, whitelists, and blacklists are defined in `config.yml`. Changes go through Git, then:

- **Pi Zero**: Komodo auto-deploys on commit
- **MikroTik**: Manual SCP + container restart
