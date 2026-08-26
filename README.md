# homelab-infra

Provisioning and GitOps for this homelab, in one repo:

- **`ansible/`** — takes a fresh Debian server and makes it production-ready
- **`stacks/`** — Docker Compose stacks, one per service
- **`komodo/`** — GitOps catalog that ties stacks to servers via [Komodo](https://komo.do/)

Everything runs from one DevContainer, no local tool installation needed.

## Structure

```
ansible/                      Server provisioning (see ansible/README.md)
├── roles/                      hostname, base, docker, ssh, node_agent, ...
├── host_vars/<hostname>/       per-host vars + SOPS secrets (Key A)
└── run.yml                     main playbook

stacks/<service>/             Docker Compose stacks (host-agnostic)

komodo/resources/             Komodo ResourceSync TOMLs
├── servers.toml                hosts Komodo manages
├── stacks.toml                 stack → server assignments + variables
├── repos.toml                  shared git clones (linked_repo)
├── procedures.toml             deploy automation
├── hosts/<hostname>/           per-host overrides
└── variables.toml              shared values (TZ, PUID/PGID, ...)

komodo/                       SOPS-encrypted secrets (Key B)
├── secrets.sops.yaml           shared secrets ([[SECRET_NAME]])
└── hosts/<host>/secrets.sops.yaml  per-host secrets
```

Ansible and Komodo use separate AGE keys by design — an ansible-only commit can't trigger a stack redeploy.

## Quick Start

```bash
# 1. Open DevContainer in VS Code ("Reopen in Container")

# 2. Set up secrets
unlock                        # sets BW_SESSION
just setup                    # age keys, SSH backup keys, host secrets

# 3. Provision a server
just a new-host myserver
just a bootstrap myserver
just a deploy myserver

# 4. Deploy Komodo Core (see stacks/komodo/.env.example)
# 5. Point Komodo ResourceSync at this repo (komodo/resources/)
# 6. Deploy komodo-periphery on remaining hosts
```

See [ansible/README.md](ansible/README.md), [komodo/README.md](komodo/README.md), and [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## Commands

### Root

| Command | Description |
|---|---|
| `just up` / `down` / `rebuild` | Create, stop, or rebuild the DevContainer |
| `just shell` | Interactive shell inside the DevContainer |
| `just exec ARGS` | Run a command inside the DevContainer |
| `just lint` | Ansible-lint + YAML + Compose + Alloy checks |
| `just setup` | First-time setup (age keys, SSH backup keys, host secrets) |
| `just validate-keys` | Verify SOPS age keys match expected recipients |

### Ansible (`just a`)

| Command | Description |
|---|---|
| `just a ping` | Connectivity check (`ansible -m ping all`) |
| `just a deploy HOST [ARGS]` | Converge specific host(s), optional `--tags` |
| `just a run [TAGS] [ARGS]` | Converge all hosts, optional tag filter |
| `just a bootstrap HOST [USER]` | First run on a new host (as root with password) |
| `just a update [ARGS]` | System updates (all hosts or `--limit HOST`) |
| `just a update-komodo [ARGS]` | Update Komodo fleet (Core first, then Agents) |
| `just a sync-dotfiles [ARGS]` | Sync dotfiles on all hosts |
| `just a new-host HOST` | Scaffold host_vars + encrypted secrets |
| `just a rename OLD NEW` | Rename a host (host_vars, inventory, SSH keys, Bitwarden) |
| `just a secrets HOST` | Edit encrypted secrets (Key A) |
| `just a vars HOST` | Edit plaintext vars (`all` for shared) |
| `just a tags` | Show available deploy tags with descriptions |
| `just a show-key` | Print the container's SSH public key |
| `just a trust HOST` | Test SSH connectivity to a host |
| `just a sshsync` | Backfill `~/.ssh/config` from inventory |
| `just a check` | Show bootstrap status of all hosts |
| `just a localsshrename` | Fix SSH public-key comments to `backup-<hostname>` |
| `just a lint` | Run ansible-lint |

### Komodo (`just k`)

| Command | Description |
|---|---|
| `just k secrets [TARGET]` | Edit encrypted secrets (Key B), `all` or hostname |
| `just k show-secrets [TARGET]` | Show decrypted secrets (stdout only) |
| `just k vars [TARGET]` | Edit non-secret variables, `all` or hostname |
| `just k check [HOST]` | Audit that all `[[PLACEHOLDER]]` refs have matching values |
| `just k update-secrets [ARGS]` | Push secrets to Komodo Core host |
| `just k sync` | Sync resource definitions from git into Komodo |
| `just k pipeline [all]` | Deploy pipeline (sync + redeploy changed stacks, `all` to force) |
| `just k deploy STACK` | Deploy a single stack |
| `just k restart STACK` | Restart a running stack |
| `just k stop STACK` | Stop a stack |
| `just k destroy STACK` | Destroy a stack (prompts for confirmation) |
| `just k ssh SERVER` | Open a shell on a server via Periphery |
| `just k exec CONTAINER [SHELL]` | Shell into a running container |
| `just k prune SERVER` | Docker system prune on a server |
| `just k backup` | Backup the Komodo database |
| `just k lint` | YAML + Compose + Alloy validation |

## Updating Komodo

Komodo Core and Periphery (Agent) are **not** managed through Komodo's own GitOps to avoid chicken-and-egg issues. Update them via Ansible:

```bash
just a update-komodo                    # all hosts (Core first, then Agents)
just a update-komodo --limit HOST       # single host
```

This pulls the latest images, recreates containers, and waits for health checks to pass (Core accepting connections, Agent containers running).

## Guidelines

See [CONTRIBUTING.md](CONTRIBUTING.md).
