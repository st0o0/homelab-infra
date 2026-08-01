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
2. Nothing to add under **Settings → Git Providers** for this step —
   `st0o0/homelab-infra` is public, and `komodo/resources/repos.toml`
   clones it over anonymous HTTPS without a `git_account`. Every stack
   sources its compose files via `linked_repo` (§11) pointing at that one
   Repo resource, so there's no per-stack git config either. Only add a
   Git Provider account here if you fork this repo private, or want
   authenticated (higher-rate-limit) HTTPS access — then set
   `git_account` in `repos.toml` to that account's name.
3. **Resources → Resource Syncs → Create**: point it at this repo, with
   resource path `komodo/resources/`.
4. Run the sync in preview/dry-run first — Komodo shows you the diff
   (servers, stacks, repos, procedures, variables it's about to create).
   Review it, then execute.

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

## 10. Migrating an existing stack — the env var walkthrough

Step 9 and [CONTRIBUTING.md](CONTRIBUTING.md#adding-a-stack) cover the
mechanical steps for adding a stack. This section walks through the part
that trips people up: deciding *where each environment variable should
live* and *how it actually reaches the running container*. Worked example:
migrating an existing `paperless-ngx` deployment that isn't in `stacks/`
yet.

### 10.1 Create the stack definition

```bash
mkdir stacks/paperless
```

`stacks/paperless/compose.yml` — host-agnostic, every configurable value
read from `${VAR}`, no server name, no real secret baked in:

```yaml
services:
  paperless:
    image: ghcr.io/paperless-ngx/paperless-ngx:latest
    environment:
      PAPERLESS_SECRET_KEY: ${PAPERLESS_SECRET_KEY:?PAPERLESS_SECRET_KEY is required}
      PAPERLESS_DBHOST: ${PAPERLESS_DBHOST}
      PAPERLESS_DBPASS: ${PAPERLESS_DBPASS:?PAPERLESS_DBPASS is required}
      PUID: ${PUID:-1000}
      PGID: ${PGID:-1000}
      TZ: ${TZ:-Europe/Berlin}
    volumes:
      - data:/usr/src/paperless/data
      - media:/usr/src/paperless/media
volumes:
  data:
  media:
```

`stacks/paperless/.env.example` documents every var from the compose file,
required ones first (see CONTRIBUTING.md Guidelines):

```
PAPERLESS_SECRET_KEY=
PAPERLESS_DBPASS=
PAPERLESS_DBHOST=
PUID=1000
PGID=1000
TZ=Europe/Berlin
```

This file is documentation only — Komodo never reads it. What Komodo
actually injects at deploy time comes from the `environment` block in
`stacks.toml` (next step).

### 10.2 Classify every variable

For each var in the compose file, decide which of four buckets it belongs
to:

| Bucket | Lives in | Referenced as | Example |
|---|---|---|---|
| Secret, shared across stacks/hosts | `komodo/secrets.sops.yaml` | `[[SECRET_NAME]]` | `POSTGRES_PASSWORD` |
| Secret, specific to one host | `komodo/hosts/<host>/secrets.sops.yaml` | `[[<host>_KEY]]` | `<host>_host_ip` |
| Non-secret, shared value | `komodo/resources/variables.toml` | `[[VARIABLE_NAME]]` | `TZ`, `PUID`, `PGID` |
| Non-secret, one-off value | written literally in `stacks.toml` | — | a fixed port, a hostname only this stack uses |

For the `paperless` example:

- `PAPERLESS_SECRET_KEY`, `PAPERLESS_DBPASS` → new secrets. Name them
  `PAPERLESS_SECRET_KEY` / `PAPERLESS_DB_PASSWORD`, following the existing
  `<STACK>_<KEY>` convention (`ARR_SONARR_API_KEY`,
  `AUTHENTIK_SECRET_KEY`, ...)
- `PAPERLESS_DBHOST` → not secret, but also not reused anywhere else —
  write it literally in the `stacks.toml` entry, or promote it to
  `variables.toml` if you expect a second paperless-like stack to need it
- `PUID`, `PGID`, `TZ` → already declared in `variables.toml`, just reuse
  them

### 10.3 Add the new secrets

```bash
just k secrets
```

Opens `komodo/secrets.sops.yaml` decrypted in `$EDITOR`. Add:

```yaml
PAPERLESS_SECRET_KEY: <generated-value>
PAPERLESS_DB_PASSWORD: <generated-value>
```

Save — `sops` re-encrypts on write. If a value needs to differ per host,
use `just k secrets <hostname>` instead; it lands there as
`[[<hostname>_PAPERLESS_DB_PASSWORD]]`.

### 10.4 Add a new shared or per-host variable (only if non-secret and reusable)

```bash
just k vars               # edit komodo/resources/variables.toml
```

```toml
[[variable]]
name = "PAPERLESS_DBHOST"
value = "paperless-db"
description = "Postgres service name in the paperless compose network"
```

If the value differs per host instead (e.g. paperless runs on two hosts
with different DB service names), use the per-host file instead:

```bash
just k vars FeelsStrongMan  # creates/edits komodo/resources/hosts/FeelsStrongMan/variables.toml
```

```toml
[[variable]]
name = "FeelsStrongMan_PAPERLESS_DBHOST"
value = "paperless-db"
description = "Postgres service name for paperless on FeelsStrongMan"
```

referenced in `stacks.toml` as `[[FeelsStrongMan_PAPERLESS_DBHOST]]` — same
prefix convention as per-host secrets. No `sops`/decrypt step needed here,
since it's not a secret; Resource Sync picks the file up directly.

Skip this step entirely if the value is truly one-off — literal values in
the `stacks.toml` entry are fine and keep `variables.toml` from
accumulating single-use entries.

### 10.5 Wire the stack into `stacks.toml`

```toml
[[stack]]
name = "paperless"
[stack.config]
server = "FeelsStrongMan"
run_directory = "stacks/paperless"
file_paths = ["compose.yml"]
linked_repo = "homelab-infra"
environment = """
PAPERLESS_SECRET_KEY=[[PAPERLESS_SECRET_KEY]]
PAPERLESS_DBPASS=[[PAPERLESS_DB_PASSWORD]]
PAPERLESS_DBHOST=[[PAPERLESS_DBHOST]]
PUID=[[PUID]]
PGID=[[PGID]]
TZ=[[TZ]]
"""
```

`[[NAME]]` is Komodo's own interpolation syntax — distinct from SOPS and
from Docker Compose's `${VAR}`. Core resolves it at deploy time by looking
up `NAME` first against `variables.toml`, then against the `[secrets]`
loaded from `core.secrets.toml`, and writes the result out as a plain
`.env` for the stack. The `${VAR}` references inside `compose.yml` are then
ordinary Compose behavior against that `.env`. Add `after = ["<stack>"]`
here too if this stack depends on another one's startup order (see `arr`
and `downloader`, both `after = ["media"]`).

### 10.6 How a secret actually reaches the running container

This is the part step 10.2–10.5 sets up but doesn't execute — the runtime
path is the same one described in step 5, worth restating end-to-end for
a newly-added secret:

1. `komodo/secrets.sops.yaml` and every `komodo/hosts/*/secrets.sops.yaml`
   live encrypted in git — nothing decrypted is ever committed.
2. On the Core host (or the Ansible controller, if using the `komodo`
   role — see step 5 Option B), `just k decrypt` merges both into one flat
   TOML `[secrets]` block, host secrets prefixed `<host>_`, written to
   `/etc/komodo/core.secrets.toml`, `chmod 600`.
3. The `stacks/komodo` compose service mounts that file read-only via
   `KOMODO_SECRETS_FILE`.
4. Komodo Core must be **restarted** to re-read it — only then does
   `[[PAPERLESS_SECRET_KEY]]` resolve to something instead of failing the
   deploy.
5. Only after that will a Resource Sync + Deploy of `paperless` succeed.

So the cycle for any new secret is always: edit → commit/push →
`git pull` on Core → `just k decrypt` → restart Core — *before* triggering
the stack's own deploy.

### 10.7 Deploy and verify

```bash
git add stacks/paperless/ komodo/resources/stacks.toml komodo/resources/variables.toml
git commit -m "feat(paperless): add paperless stack"
git push
```

Then, per step 7/8: re-run the Resource Sync (picks up the new
`stacks.toml` entry), then **Deploy** the `paperless` stack in the UI.

Sanity-check before and after:

```bash
just k show-secrets              # confirm the new secret values are actually set
just lint-compose                # confirm the new compose.yml is valid
```

In the Komodo UI, check the stack's logs for the container coming up with
real values — a literal `[[PAPERLESS_SECRET_KEY]]` string in the logs
means it didn't resolve (see Troubleshooting below).

## 11. Avoiding a full repo clone per stack (monorepo deploy pattern)

Step 8 said Komodo "clones `run_directory` from the configured repo" on
every Deploy. What that undersells: in git-repo mode, **each Stack clones
the entire repository separately by default** — not just `run_directory`,
and not shared between stacks. Confirmed by the Komodo maintainer directly:

> "Stacks in repo mode will clone the entire repo for each Stack, and is
> designed more with single stack repos in mind, not monorepos."
> — [moghtech/komodo discussion #264](https://github.com/moghtech/komodo/discussions/264)

There is **no sparse-checkout, no `.komodoignore`, no way to tell Komodo
"only fetch `stacks/<service>/`"**. Left as-is, every `[[stack]]` clones
all of `ansible/`, `openspec/`, every other `stacks/*/`, and full git
history, independently, into its own directory under each Periphery's
`PERIPHERY_ROOT_DIRECTORY`. On `FeelsStrongMan` alone (`arr`, `media`,
`authentik`, `immich`, `mealie`, `downloader` — 6 stacks) that's 6 full
copies of this repo side by side.

Fixing this is two separate, independent pieces — solving different
problems. Neither is implemented in this repo yet; both are additive, not
a breaking change to anything in steps 1–10.

### 11.1 `linked_repo` — the actual fix for "N clones per host"

A Stack can reference a shared `Repo` resource instead of configuring its
own `git_provider`/`git_account`/`repo`/`branch`. Per the maintainer
([discussion #605](https://github.com/moghtech/komodo/discussions/605)):

> "Repo Linking... multiple Stacks attached to the same Repo will share
> the same repo clone on individual hosts."

```toml
# komodo/resources/repos.toml (add to Resource Sync path)
[[repo]]
name = "homelab-infra"
[repo.config]
# No `server` here on purpose — see below. No `git_account` either: this
# repo is public, so Komodo clones it anonymously over HTTPS.
git_provider = "github.com"
repo = "st0o0/homelab-infra"
```

```toml
# komodo/resources/stacks.toml — each stack references the Repo instead of
# setting its own git fields:
[[stack]]
name = "paperless"
[stack.config]
server = "FeelsStrongMan"
linked_repo = "homelab-infra"    # instead of git_provider/git_account/repo/branch
run_directory = "stacks/paperless"
file_paths = ["compose.yml"]
environment = "..."
```

Mechanics, worth being precise about:

- **Sharing is per-server, not global.** All stacks on `FeelsStrongMan`
  that set `linked_repo = "homelab-infra"` share **one** clone on
  `FeelsStrongMan`. A stack on a different server linking the same `Repo`
  still gets its **own** clone on *that* server — going from 6 clones to 1
  on `FeelsStrongMan`, not from ~20 to 1 across the whole fleet.
- **Leave `server` unset on the `[[repo]]` resource itself.** Which
  server(s) actually end up with a clone falls out implicitly from which
  stacks (with which `server`) link to it — that's the maintainer's own
  workaround for repos used across multiple hosts.
- `run_directory`/`file_paths` on the Stack still work exactly as before,
  just resolved inside the one shared clone instead of a stack-private one.

### 11.2 Repo + Procedure — the trigger/deploy-scoping fix

A separate concern: even with one shared clone, a naive "redeploy
everything on push" webhook would still restart every stack on a push that
only touched one of them. `PullRepo` + `BatchDeployStackIfChanged` solve
that:

```toml
# e.g. komodo/resources/procedures.toml (new file)
[[procedure]]
name = "deploy-homelab-infra"
description = "Pull homelab-infra once, then redeploy only changed stacks"

[[procedure.config.stage]]
name = "Pull"
executions = [
  { execution.type = "PullRepo", execution.params.repo = "homelab-infra" }
]

[[procedure.config.stage]]
name = "Deploy changed stacks"
executions = [
  { execution.type = "BatchDeployStackIfChanged", execution.params.pattern = "*" }
]
```

- **`PullRepo`** updates the one shared clone on its server(s) — a `git
  pull`, not a fresh clone, and not a deploy by itself.
- **`BatchDeployStackIfChanged`** (pattern `*`, or a narrower glob/regex)
  walks matching stacks, compares each one's current compose content
  against what was last deployed, and redeploys only the ones that
  actually changed.
- Attach a **single** Git webhook to this Procedure instead of one per
  stack (Settings → Git Providers, or the Procedure's own webhook config).

### Put together: one push, end to end

1. Push changes `stacks/paperless/compose.yml`.
2. The one webhook on `deploy-homelab-infra` fires.
3. Stage "Pull": the shared clone on every server that has a `linked_repo
   = "homelab-infra"` stack gets `git pull`ed — no re-clone, no unrelated
   servers touched.
4. Stage "Deploy changed stacks": Komodo diffs every stack matching `*`
   against its last-deployed state, finds only `paperless` changed,
   redeploys only `paperless`. `arr`, `media`, `authentik`, etc. — sharing
   the same clone on `FeelsStrongMan` — are left running untouched.

### What this does *not* change

- `komodo/resources/{servers,stacks,variables}.toml` stays authoritative
  for *which* stacks/servers/variables exist and their config (per the
  design decision in
  `openspec/changes/archive/2026-08-01-komodo-gitops-charter`).
  `linked_repo` is just one more field per `[[stack]]` entry; the
  Procedure only changes *how* a deploy is triggered.
- A `stacks.toml` -only change (new env var, new server assignment, adding
  `linked_repo` itself) is not a compose-file change, so
  `BatchDeployStackIfChanged` won't pick it up — that still needs its own
  Resource Sync run, same as step 8 already describes.
- `komodo/resources/repos.toml`, `komodo/resources/procedures.toml` exist,
  and every `[[stack]]` entry in `stacks.toml` (including the commented-out
  `backrest` placeholder) sets `linked_repo = "homelab-infra"` instead of
  its own `git_account`/`repo` fields — the migration described above is
  done. `repos.toml` sets no `git_account` at all, since
  `st0o0/homelab-infra` is public and clones anonymously over HTTPS (step
  7.2). What's still manual: creating the `deploy-homelab-infra`
  Procedure's webhook in the Komodo UI — Resource Sync doesn't wire up
  webhooks itself.
- The exact mechanics above are triangulated from maintainer replies in
  GitHub Discussions, not a single authoritative reference page — official
  docs on `linked_repo`/`BatchDeployStackIfChanged` are thin. Verify
  against your actual Komodo version on one low-stakes stack before
  rolling it out fleet-wide.

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
