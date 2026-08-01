# Roadmap: Prepare Repo for Komodo GitOps

What needs to change in this repo so all stacks can be deployed and managed via Komodo across multiple hosts.

## Work order

Sections are largely independent; this order resolves dependencies so later
sections can reference earlier decisions (secrets, network ownership, file
paths) instead of guessing at them.

1. **§7 Secrets** — foundation; already started, finish first so `[[SECRET]]`
   references are stable for everything below.
2. **§2 + §3 CIFS volumes & `media-net`** (arr, downloader, media) — fixes
   active `compose up` blockers, independent of the rest.
3. **§6 Commit missing config directories** — independent, quick, prevents
   deploy failures across several stacks.
4. **§4 Alloy `extras/` → `modules/` refactor** — independent, Alloy only.
5. **§5 Compose override pattern** (alloy) — builds on the new Alloy
   module layout from §4.
6. **§1 Finish Komodo stacks** — verify `stacks/komodo` and
   `stacks/komodo-periphery` are complete.
7. **§8 ResourceSync** (`servers.toml`, `variables.toml`, `stacks.toml`) —
   the centerpiece; comes last because it references every decision made
   above.

Dockhand and its only dependent (`stacks/hawser/`, which existed solely to
report to a Dockhand server) have already been removed. This repo now has
a single deployment mechanism: Komodo.

## 1 — Add Komodo stacks

- [x] `stacks/komodo/` — Core + MongoDB + local Periphery agent
- [x] `stacks/komodo-periphery/` — standalone Periphery agent for remote hosts
- [x] `.env.example` for both with all configurable values

## 2 — Fix CIFS volumes (arr, downloader, media)

The CIFS volume definitions are incomplete — missing `device` and `o` (mount options). They would fail on `docker compose up` as-is.

- [x] Add `device` and `o` driver opts using env vars so Komodo can inject them per host — consolidated to 3 shares (media, downloads, audios) across arr/downloader/media
- [ ] Verify volumes work with `docker compose up` from a clean clone — **manual follow-up**: needs the real NAS/Samba server to confirm the `o=` mount option string (vers, uid/gid, charset) and real `CIFS_*` secret values

## 3 — Resolve external network `media-net` (arr, downloader, media)

Three stacks share `media-net` as an external network. Komodo deploys stacks independently, so the network must exist before any of them start.

- [x] Pick one stack (`media`) to own and create the network
- [x] Keep `external: true` on the other two (`arr`, `downloader`)
- [x] Document the deploy order dependency — `after = ["media"]` on the `arr` and `downloader` entries in `komodo/resources/stacks.toml`, plus README prerequisites

## 4 — Refactor Alloy feature toggles

The current `cp extras/*.alloy alloy/` workflow is a manual step that doesn't work with GitOps.

- [x] Move `extras/*.alloy` → `modules/*.alloy` as `declare` blocks
- [x] Add env-var guards (`enabled` argument) so modules no-op when not configured
- [x] Wire up `import.file "modules"` in main config
- [x] Remove `extras/` directory and copy instructions from `.env.example`
- [x] Test: Alloy starts cleanly with and without optional env vars — verified against `grafana/alloy:v1.17.1` in Docker; `prometheus_scrape_targets_gauge` for the nut module reads `0` by default and `1` with `NUT_ENABLED=true`

## 5 — Resolve compose override pattern (alloy)

Alloy uses "copy `compose.override.*.yaml` → `compose.override.yaml`" for mode selection (e.g. Bifrost routing). Komodo can't do manual file copies, but it supports multiple `file_paths`.

- [ ] Keep override files as-is in the repo
- [ ] Use Komodo's `file_paths` to select which compose files to apply per host:
  ```toml
  # host without bifrost
  file_paths = ["stacks/alloy/compose.yml"]
  # host with bifrost
  file_paths = ["stacks/alloy/compose.yml", "stacks/alloy/compose.override.bifrost.yaml"]
  ```
- [ ] Update `.env.example` to document both modes without requiring file copies

## 6 — Commit missing config directories

Several stacks mount `./subdirectory` paths that don't exist in the repo. Docker auto-creates them empty, but stacks expecting config files will fail.

- [x] `authentik/` — add `.gitkeep` to `media/`, `certs/`, `custom-templates/`
- [x] `backrest/` — add `.gitkeep` to `backrest/config/` (Backrest bootstraps `config.json` itself on first run; no default content needed)
- [x] `downloader/` — add `.gitkeep` to `gluetun/config/`, `sabnzbd/config/`
- [x] `nut-upsd/` — add `.gitkeep` to `nut/` and `peanut/` (both images bootstrap their own config on first run; no default content needed)
- [x] `homeassistant/` — add `.gitkeep` to `data/`, `mosquitto/{config,data,log}/`, `zigbee2mqtt/data/`, `matter/data/`

## 7 — Secret management with SOPS

All sensitive values (IPs, credentials, endpoints) are SOPS-encrypted in the repo. Komodo Core reads them from a mounted config file after decryption.

**Flow:** edit secrets → `sops -e` → git push → decrypt on Core host → Komodo restart picks up changes

- [x] Install SOPS + AGE on development machine and Core host
- [x] Generate AGE keypair, store private key on Core host at `/etc/komodo/age.key`
- [x] Create `.sops.yaml` in repo root with encryption rules
- [x] Create `komodo/secrets.sops.yaml` with all sensitive values (IPs, passwords, endpoints)
- [x] Add `komodo/decrypt.sh` — decrypts `secrets.sops.yaml` → `core.config.toml` `[secrets]` block
- [x] Mount decrypted config into Komodo Core container
- [x] Add unencrypted `komodo/secrets.yaml` to `.gitignore`
- [x] Document secret rotation workflow in README

**What goes into SOPS (secrets):**
- Host IPs / WireGuard addresses
- Database credentials
- Admin passwords
- API tokens / webhook secrets
- Service endpoints (VictoriaMetrics, Loki URLs)

**What stays in plain TOML (variables):**
- Timezone, scrape intervals, image tags
- Container names, port mappings
- Feature flags (NUT enabled, Bifrost mode)

## 8 — Create ResourceSync definitions

The TOML files that tell Komodo which stacks to deploy where, with which env vars. Secrets are referenced via `[[SECRET_NAME]]` and resolved by Core at deploy time.

- [x] `komodo/resources/servers.toml` — server inventory for all 9 hosts
- [x] `komodo/resources/variables.toml` — non-sensitive shared variables
- [x] `komodo/resources/stacks.toml` — per-host stack assignments with env overrides using `[[SECRET]]` references (`backrest` still unassigned — no confirmed host yet)
- [ ] Point Komodo ResourceSync at this repo
- [ ] Verify: secrets interpolate correctly into stack environments

---

## Stacks ready (no repo changes needed)

immich, immich-postgres, observability, postgres, ups-monitor, vaultwarden, bifrost, mealie, pihole, authentik, backrest, nut-upsd, homeassistant

## Stacks needing changes

| Stack | Changes | Section |
|-------|---------|---------|
| arr | Fix CIFS volumes, external network | 2, 3 |
| downloader | Fix CIFS volume, external network | 2, 3 |
| media | Fix CIFS volumes, external network | 2, 3 |
| alloy | Compose override pattern | 5 |
