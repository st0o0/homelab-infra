# homelab-infra

Provisioning and GitOps for this homelab, in one repo:

- **`ansible/`** — takes a fresh Debian server (IP + user + password) and
  makes it production-ready: SSH hardened, Docker installed, monitoring
  agent running, visible in Dockhand.
- **repo root (`stacks/`, `komodo/`)** — a Komodo GitOps catalog. Every
  service is a Docker Compose stack under `stacks/<service>/`, deployed and
  kept in sync across hosts by [Komodo](https://komo.do/) — no manual
  `docker compose up`, no separate catalog UI.

Everything runs from one DevContainer — no local tool installation needed.
The two halves keep separate trust boundaries by design: separate AGE keys
for ansible secrets (`ansible/host_vars/**/*.sops.yml`) and Komodo secrets
(`komodo/**/*.sops.yaml`), and Komodo's GitOps sync only ever looks at
`komodo/resources/` and each stack's `run_directory` — an ansible-only
commit can't trigger a stack redeploy.

**Related repos:** [dotfiles](https://github.com/st0o0/dotfiles) (shell toolchain)

## How it's organized

```
ansible/                      Server provisioning (see ansible/README.md)
├── roles/                      hostname, base, docker, ssh, node_agent, ...
├── host_vars/<hostname>/       per-host vars + SOPS-encrypted secrets (Key A)
├── hosts.yml                   flat inventory
└── run.yml                     main playbook

stacks/<service>/             WHAT is deployable — compose file, .env.example,
                               optional README. Host-agnostic: nothing in here
                               says which server it runs on.

komodo/resources/             WHERE and WITH WHAT VALUES — ResourceSync TOML:
├── servers.toml                every host Komodo manages
├── stacks.toml                 which stack runs on which server, with which
│                                 variables/secrets
└── variables.toml              shared non-secret values (TZ, PUID/PGID, ...)

komodo/                       Secrets, SOPS-encrypted and committed (Key B):
├── secrets.sops.yaml            shared secrets, available as [[SECRET_NAME]]
├── hosts/<host>/
│   └── secrets.sops.yaml        per-host secrets, available as [[<host>_KEY]]
└── decrypt.sh                   merges both into Komodo Core's config
```

A stack's server assignment lives in `komodo/resources/stacks.toml`, not in
its directory path — reassigning a stack to a different host is a one-line
TOML edit, not a file move. See [ROADMAP.md](ROADMAP.md) for what's still
being built out and [komodo/README.md](komodo/README.md) for the full
Komodo secrets workflow.

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
stack's `.env.example`). Once running, decrypt secrets into its config:

```bash
just k decrypt           # writes /etc/komodo/core.secrets.toml on the Core host
```

Or run the `komodo` ansible role against that host, which handles this
(including secret provisioning) automatically — see
[GUIDE.md](GUIDE.md) for the full walkthrough of both options.

### 5. Point Komodo at this repo

In the Komodo UI, add a ResourceSync pointed at `komodo/resources/` in this
repo. Komodo reads `servers.toml`, `stacks.toml`, and `variables.toml` and
shows you the resulting sync plan — review it, then execute.

### 6. Deploy `komodo-periphery` to remaining hosts

Every host other than Core needs a `komodo-periphery` agent so Core can
manage it — deploy `stacks/komodo-periphery/` there manually (see that
stack's `.env.example`).

`stacks/komodo/` and `stacks/komodo-periphery/` are deliberately **not**
declared in `komodo/resources/stacks.toml` — Komodo has no native
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
| `just lint` | Ansible-lint, YAML, `.env`, and Compose checks — one command, no sub-checks |
| `just a ping` / `just a deploy HOST` / `just a run` | Ansible: connectivity + convergence |
| `just setup` | First-time/re-run setup: both age keys, SSH backup keys, host secrets |
| `just a secrets HOST` | Ansible secrets (Key A) |
| `just k secrets [TARGET]` | Komodo secrets (Key B) |
| `just k decrypt` / `just k show-secrets [TARGET]` | Komodo: assemble/inspect `core.secrets.toml` |

Ansible's day-to-day recipes (`ping`, `check`, `run`, `deploy`, `bootstrap`,
`update`, `new-host`, `trust`, `vars`, `sshsync`, `show-key`) work
unprefixed from the repo root — no need to `cd ansible/` first.

## Guidelines

- Pin image tags where possible (e.g. `jellyfin:10.11` not `jellyfin:latest`) for reproducibility
- Always support a `TZ` env var so timezone is configurable
- Use `/data/<service-name>` as the default host bind path convention
- Guard required env vars in compose with `${VAR:?VAR is required}` so `docker compose config` fails loudly instead of deploying with an empty value

See [CONTRIBUTING.md](CONTRIBUTING.md) for additional details.
