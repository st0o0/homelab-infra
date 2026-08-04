# homelab-infra

Provisioning and GitOps for this homelab, in one repo:

- **`ansible/`**: takes a fresh Debian server (IP + user + password) and
  makes it production-ready — SSH hardened, Docker installed, monitoring
  agent running, visible in Dockhand.
- **repo root (`stacks/`, `komodo/`)**: a Komodo GitOps catalog. Every
  service is a Docker Compose stack under `stacks/<service>/`, deployed and
  kept in sync across hosts by [Komodo](https://komo.do/). No manual
  `docker compose up`, no separate catalog UI.

Everything runs from one DevContainer, no local tool installation needed.
The two halves keep separate trust boundaries by design: separate AGE keys
for ansible secrets (`ansible/host_vars/**/*.sops.yaml`) and Komodo secrets
(`komodo/**/*.sops.yaml`). Komodo's GitOps sync only ever looks at
`komodo/resources/` and each stack's `run_directory`, so an ansible-only
commit can't trigger a stack redeploy.

**Related repos:** [dotfiles](https://github.com/st0o0/dotfiles) (shell toolchain)

## How it's organized

```
ansible/                      Server provisioning (see ansible/README.md)
├── roles/                      hostname, base, docker, ssh, node_agent, ...
├── host_vars/<hostname>/       per-host vars + SOPS-encrypted secrets (Key A)
├── hosts.yml                   flat inventory
└── run.yml                     main playbook

stacks/<service>/             WHAT is deployable: compose file, .env.example,
                               optional README. Host-agnostic — nothing in
                               here says which server it runs on.

komodo/resources/             WHERE and WITH WHAT VALUES: ResourceSync TOML
├── servers.toml                every host Komodo manages
├── stacks.toml                 which stack runs on which server, with which
│                                 variables/secrets
├── repos.toml                  shared git clone(s) stacks attach to via
│                                 `linked_repo`, one clone per server instead
│                                 of one per stack
├── procedures.toml             deploy automation (pull once, redeploy only
│                                 changed stacks)
├── hosts/<hostname>/
│   └── variables.toml          per-host, non-secret overrides ([[<host>_KEY]])
└── variables.toml              shared non-secret values (TZ, PUID/PGID, ...)

komodo/                       Secrets, SOPS-encrypted and committed (Key B)
├── secrets.sops.yaml            shared secrets, available as [[SECRET_NAME]]
├── hosts/<host>/
│   └── secrets.sops.yaml        per-host secrets, available as [[<host>_KEY]]
└── decrypt.sh                   merges both into Komodo Core's config
```

A stack's server assignment lives in `komodo/resources/stacks.toml`, not in
its directory path, so reassigning a stack to a different host is a
one-line TOML edit, not a file move. See [ROADMAP.md](ROADMAP.md) for
what's still being built out and [komodo/README.md](komodo/README.md) for
the full Komodo secrets workflow.

## Quick Start

### 1. Open the DevContainer

Open this repo in VS Code and select **"Reopen in Container"**. Choose
**Windows** or **Linux** depending on your host OS. The container comes
with everything pre-installed: Ansible, SOPS, age, just, Bitwarden CLI,
yamllint, dotenv-linter.

### 2. Set up secrets

```bash
unlock                        # sets BW_SESSION for the current shell
just setup                    # both age keys (Key A + Key B), SSH backup keys, host secrets
```

See [ansible/README.md](ansible/README.md) for the full ansible secrets
workflow and [komodo/README.md](komodo/README.md) for the full Komodo
secrets workflow.

### 3. Provision a server

```bash
just a new-host myserver
just a bootstrap myserver
just a deploy myserver
```

See [ansible/README.md](ansible/README.md) for the complete provisioning
walkthrough (SSH key deployment, tags, daily commands).

### 4. Deploy Komodo Core

Deploy `stacks/komodo/` on the host that will run Komodo Core (see that
stack's `.env.example`). Run the `komodo` ansible role against that host
— it renders `compose.yml` and `.env` from Ansible variables and handles
secret provisioning (`core.secrets.toml`) automatically, so this path
needs no separate clone or manual `.env` edit.

### 5. Point Komodo at this repo

**Before syncing**, make sure every secret key referenced in
`komodo/resources/stacks.toml` actually exists — the file's header comment
lists them. Check with:

```bash
just k show-secrets            # shared secrets (komodo/secrets.sops.yaml)
just k show-secrets <host>     # per-host secrets, for every [[<host>_host_ip]] used
```

Add anything missing via `just k secrets [TARGET]` before continuing — a
sync with an unresolved `[[SECRET_NAME]]` fails to apply that resource.

In the Komodo UI:

1. **Resources → Resource Syncs → Create.**
2. Give it a name (e.g. `homelab-infra`).
3. **Git Provider**: leave as `github.com` (default). **Git Account**: leave
   empty — the repo is public, no account needed.
4. **Repo**: `st0o0/homelab-infra`. **Branch**: `main`.
5. **Resource Path**: `komodo/resources`. Komodo scans that folder
   recursively for `.toml` files, so `servers.toml`, `stacks.toml`,
   `variables.toml`, `repos.toml`, `procedures.toml`, and everything under
   `hosts/` (except the `.tpl` template, which isn't a `.toml` file) are all
   picked up from one path.
6. Save, then click **Refresh** (or **Execute Sync** — it previews first).
   Komodo computes a diff and shows every pending create/update: 1 Repo, 9
   Servers, ~16 Stacks, 1 Procedure. Review it — a server showing as
   unreachable just means its `komodo-periphery` isn't deployed yet (step
   6 below), that's expected on a first sync.
7. Confirm to execute. Re-running Refresh after any push to `main` shows
   only the incremental diff.
8. Optional: attach a Git webhook so pushes to `main` trigger a sync
   automatically instead of waiting for the poll interval — either on this
   Resource Sync directly, or via the `deploy-homelab-infra` Procedure's own
   webhook (see `komodo/resources/procedures.toml`), configured under
   **Settings → Git Providers**.

**Verifying secret/variable interpolation:** pick one already-deployed,
low-risk stack (e.g. `pihole`) and compare its resolved environment against
the source values:

```bash
just k show-secrets            # or `just k vars` for non-secret variables
```

then, on that stack's host:

```bash
docker exec <container-name> env | grep <VAR_NAME>
```

The container's actual value should match what `just k show-secrets`/`vars`
printed. If a container instead shows the literal `[[SECRET_NAME]]` string,
the key is missing from `secrets.sops.yaml`/`variables.toml` or was added
after the last sync — re-check step 5's pre-flight list and re-run the
sync.

### 6. Deploy `komodo-periphery` to remaining hosts

Every host other than Core needs a `komodo-periphery` agent so Core can
manage it. Deploy `stacks/komodo-periphery/` there manually (see that
stack's `.env.example`).

`stacks/komodo/` and `stacks/komodo-periphery/` are deliberately not
declared in `komodo/resources/stacks.toml`. Komodo has no native
self-update for either component, so managing its own control plane
through itself would be a chicken-and-egg risk. Deploy and update both
manually (`docker compose pull && docker compose up -d`, Core first, then
Periphery on every host), or via the `update_komodo` ansible role/playbook.

## Adding a Stack

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full walkthrough: creating a
`stacks/<service>/` directory, validating it locally, and wiring it into
`komodo/resources/stacks.toml`.

## Commands

Run `just --list` from the repo root to see every recipe. Highlights:

| Command | Description |
|---|---|
| `just up` / `down` / `rebuild` / `shell` / `exec` | DevContainer management |
| `just lint` | Ansible-lint, YAML, `.env`, and Compose checks in one command |
| `just a ping` / `just a deploy HOST` / `just a run` | Ansible: connectivity + convergence |
| `just setup` | First-time/re-run setup: both age keys, SSH backup keys, host secrets |
| `just a secrets HOST` | Ansible secrets (Key A) |
| `just k secrets [TARGET]` | Komodo secrets (Key B) |
| `just k show-secrets [TARGET]` | Komodo: inspect decrypted secrets |
| `just k check [HOST]` | Komodo: audit placeholder coverage per host |

Ansible's day-to-day recipes (`ping`, `check`, `run`, `deploy`, `bootstrap`,
`update`, `new-host`, `trust`, `vars`, `sshsync`, `show-key`) work
unprefixed from the repo root, no need to `cd ansible/` first.

## Guidelines

- Pin image tags where possible (e.g. `jellyfin:10.11` not `jellyfin:latest`) for reproducibility
- Always support a `TZ` env var so timezone is configurable
- Use `/data/<service-name>` as the default host bind path convention
- Guard required env vars in compose with `${VAR:?VAR is required}` so `docker compose config` fails loudly instead of deploying with an empty value

See [CONTRIBUTING.md](CONTRIBUTING.md) for additional details.
