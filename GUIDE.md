# Setup Guide: from empty homelab to GitOps deploys

Step-by-step walkthrough for wiring this repo into a real Komodo instance
and deploying stacks through it. README.md has the condensed Quick Start;
this is the same flow with the "why" and the gotchas filled in.

## 0. Prerequisites

- `sops`, `age`, `jq` installed locally (for editing secrets)
- A GitHub account with access to `st0o0/homelab-infra` (or your fork)
- Docker + Docker Compose on every host that will run a stack
- `just` installed locally (wraps all the commands below)

## 1. Generate your SOPS age key

```bash
just setup
```

This runs `scripts/init-secrets.sh`: generates (or restores from Bitwarden,
if `BW_SESSION` is set) age keypairs for both trust boundaries, including
one at `~/.config/sops/komodo/age/keys.txt`, and writes the Komodo public
key into `komodo/.sops.yaml` so future secrets get encrypted for it. Commit
that file once it's updated.

## 2. Fill in shared secrets

```bash
just k secrets
```

Opens `komodo/secrets.sops.yaml` (created from `komodo/secrets.example.yaml`
on first run) in `$EDITOR`, decrypted. Fill in every key the stacks you plan
to deploy actually need — `komodo/resources/stacks.toml` lists which
`[[SECRET_NAME]]` each stack references, and its header comment enumerates
all of them. Save and quit; `sops` re-encrypts automatically.

## 3. Add per-host secrets

Every host needs at least a `host_ip` secret so Komodo can reach its
Periphery agent:

```bash
just k secrets FeelsStrongMan   # repeat for each host in servers.toml
```

This copies `komodo/hosts/secrets.sops.yaml.tpl` into
`komodo/hosts/<hostname>/secrets.sops.yaml` and opens it for editing. A
`host_ip` key here becomes available as `[[<hostname>_host_ip]]` in
`servers.toml`.

`komodo/resources/servers.toml` already lists this homelab's hosts
(`FeelsCozyMan`, `FeelsDataMan`, `FeelsStrongMan`, ...) — use those names,
or add your own `[[server]]` entries if your topology differs.

## 4. Deploy Komodo Core

Pick the host that will run Komodo Core — `servers.toml` calls it
`FeelsCozyMan` by convention (Core also runs its own local Periphery agent).
Two ways to get it running there:

**Option A — manual `docker compose`**, on that host:

```bash
git clone https://github.com/st0o0/homelab-infra.git
cd homelab-infra/stacks/komodo
cp .env.example .env
# edit .env: set KOMODO_DATABASE_USERNAME/PASSWORD, KOMODO_INIT_ADMIN_PASSWORD,
# KOMODO_JWT_SECRET, KOMODO_WEBHOOK_SECRET, and KOMODO_FIRST_SERVER_NAME=FeelsCozyMan
docker compose up -d
```

`KOMODO_FIRST_SERVER_NAME` matters: without it, Core's local Periphery
auto-registers as a server named `local`, which won't match the
`FeelsCozyMan` entry already declared in `servers.toml`.

**Option B — this repo's `ansible/` `komodo` role.** It renders
`compose.yml` and `.env` into `/docker/komodo/` on the target host from
Ansible variables — nothing needs to be cloned separately onto the Core
host for this path, since ansible provisioning and this catalog now live
in the same checkout. `core.secrets.toml` is handled as part of the same
role (see step 5), included automatically on first provisioning. Run with
the `komodo` tag against the Core host's inventory group.

Either way, Komodo Core and `komodo-periphery` are **not** managed through
Komodo itself (no `[[stack]]` entry in `stacks.toml`) — there's no safe way
for a broken Core to redeploy itself. Update both manually going forward:
`docker compose pull && docker compose up -d` (Option A) or the
`update_komodo` role's `update_komodo` tag (Option B), Core first, then
Periphery everywhere else.

## 5. Get secrets into Core's config

Core needs a `core.secrets.toml` with every `[[SECRET_NAME]]` value that
`komodo/resources/stacks.toml` references, so it can resolve them when
deploying stacks. How that file gets there depends on which option you
used in step 4.

**Option A — manual `docker compose`.** On the Core host, after cloning
this repo there too (or syncing `komodo/secrets.sops.yaml` +
`komodo/hosts/` to it):

```bash
just k decrypt   # writes /etc/komodo/core.secrets.toml, chmod 600
```

Then point Core at it — uncomment and set in `stacks/komodo/.env`:

```
KOMODO_SECRETS_FILE=/etc/komodo/core.secrets.toml
```

Restart Core to pick it up: `docker compose restart` in `stacks/komodo/`.
Every time you rotate a secret, repeat: edit → push → `git pull` on Core →
`just k decrypt` → restart Core.

**Option B — this repo's `ansible/` `komodo` role.** No second copy
of secrets to maintain: this role reads `komodo/secrets.sops.yaml` and any
`komodo/hosts/<hostname>/secrets.sops.yaml` directly from this same
checkout (no fetch, no ref/branch, no "must be pushed first" — even
locally edited, uncommitted changes are picked up), decrypts them **on the
Ansible controller**, assembles `core.secrets.toml`, and pushes it to the
Core host. The AGE private key never touches the target host.

Decryption needs an AGE key on the controller. Rather than a separate copy
of it, the role restores the same key `just setup` (step 1)
already put in Bitwarden, from the Secure Note named `Homelab Komodo SOPS
Age Key` — one key, one source of truth for both the ansible and Komodo
sides of this repo. Before running:

```bash
export BW_SESSION=$(bw unlock --raw)
```

Controller-side requirements: `bw` (Bitwarden CLI), plus `sops` and `jq`
(already prerequisites per step 0).

In practice this means step 2/3 here (`just k secrets`) is the
*only* place secret values get edited for this option too — same as
Option A. To pick up a change without a full redeploy, run just the
secrets task standalone:

```bash
cd ansible && ansible-playbook run.yml --tags komodo_secrets -l <core-host>
```

The `komodo` role also runs it automatically the first time it
provisions Core, so a fresh `--tags komodo` run needs no separate step.

## 6. Deploy Periphery on every other host

For each host other than Core (`FeelsDataMan`, `FeelsStrongMan`, ...):

```bash
git clone https://github.com/st0o0/homelab-infra.git
cd homelab-infra/stacks/komodo-periphery
cp .env.example .env
# edit .env: set PERIPHERY_CORE_ADDRESS (Core's reachable URL) and
# PERIPHERY_CONNECT_AS (this host's address, as Core will reach it)
docker compose up -d
```

Optionally generate an **Onboarding Key** in the Komodo UI first
(Settings → Onboarding) and set `PERIPHERY_ONBOARDING_KEY` so the agent
auto-registers instead of needing manual approval in the UI.

## 7. Connect the Komodo UI to this repo

1. Open the Komodo UI (`http://<core-host>:9120` by default, or whatever
   `KOMODO_HOST`/`KOMODO_PORT` you set).
2. **Settings → Git Providers**: add a GitHub account/token with read access
   to this repo. Note the account name you give it.
3. Go through `komodo/resources/*.toml` and `stacks/*/compose.yml` and
   replace every `CONFIGURE_IN_KOMODO` placeholder for `git_account` with
   that account's name (or configure it as the default account so you don't
   have to touch every file).
4. **Resources → Resource Syncs → Create**: point it at this repo, with
   resource path `komodo/resources/`.
5. Run the sync in preview/dry-run first — Komodo shows you the diff
   (servers, stacks, variables it's about to create). Review it, then
   execute.

At this point Komodo has server definitions and stack definitions, but
hasn't deployed anything yet — ResourceSync only manages Komodo's own
resource state (which stacks exist, their config), not container state.

## 8. Deploy an individual stack via GitOps

Once a stack exists as a Komodo resource (via the sync above):

1. **Resources → Stacks → `<name>`**
2. Click **Deploy** (or **Pull** then **Deploy** if you only want to fetch
   the latest compose file first without restarting containers)
3. Komodo clones `run_directory` from the configured repo/branch, resolves
   `[[VARIABLE_NAME]]` / `[[SECRET_NAME]]` from `variables.toml` and your
   decrypted secrets, writes the resulting `.env`, and runs
   `docker compose up -d` on the assigned server's Periphery agent.

To **update** a stack after changing its compose file or `stacks.toml`
entry:

```bash
git add stacks/<service>/ komodo/resources/stacks.toml
git commit -m "feat(<service>): ..."
git push
```

Then in the UI: re-run the Resource Sync (to pick up `stacks.toml` changes
like new env vars or a server reassignment), and **Deploy** the stack again
(to pick up compose file changes and actually restart containers). A plain
compose-file edit with no `stacks.toml` change only needs the Deploy step —
Komodo re-pulls the file from git on deploy.

Stacks with an `after = [...]` dependency (e.g. `arr` and `downloader` both
declare `after = ["media"]`) should be deployed in that order the first
time; Komodo doesn't auto-sequence deploys, `after` only documents the
dependency for humans doing it in the UI.

## 9. Adding a brand-new stack

Covered in full in [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-stack):
create `stacks/<service>/compose.yml` + `.env.example`, validate locally
with `docker compose config`, add a `[[stack]]` block to
`komodo/resources/stacks.toml` assigning it to a server, add any new
secrets via `just k secrets`, commit, push, then repeat step 7's sync +
step 8's deploy for just that one stack.

## Troubleshooting

- **Server shows unreachable in Komodo UI**: check the `host_ip` secret for
  that host is set (`just k show-secrets <hostname>`) and Periphery is
  actually running there (`docker compose ps` in
  `stacks/komodo-periphery/`).
- **Stack deploy fails on a missing env var**: the compose file's
  `${VAR:?VAR is required}` guard is doing its job — the referenced
  `[[SECRET_NAME]]` or `[[VARIABLE_NAME]]` isn't resolving. Check it's
  spelled identically in `stacks.toml`/`variables.toml` and, for secrets,
  that it exists in `komodo/secrets.sops.yaml` (or the right per-host file)
  and Core's `/etc/komodo/core.secrets.toml` has been regenerated
  (`just k decrypt`) and Core restarted since.
- **Resource Sync shows unexpected deletions**: someone likely created a
  resource by hand in the UI instead of via `stacks.toml`/`servers.toml`.
  Resource Sync is authoritative — add it to the TOML instead of editing
  in the UI, or the next sync will try to remove it.
