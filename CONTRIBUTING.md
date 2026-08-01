# Contributing

## Commit convention

This repo uses [release-please](https://github.com/googleapis/release-please)
to generate CHANGELOGs and version tags. It parses commit messages on `main`
by walking the git log, so with this repo's rebase/merge workflow **every
individual commit** (not just a PR title) must follow
[Conventional Commits](https://www.conventionalcommits.org/):

```
<type>(<optional scope>): <description>

feat(arr): add tracearr service
fix(pihole): correct nebula-sync env var name
docs: clarify secrets rotation workflow
```

Common types: `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`,
`ci`, `chore`, `revert`. A CI check (`commitlint.yml`) lints every commit
in a PR against this format and fails if any of them don't match. Clean
these up (`git rebase -i`) before merging.

## Project Structure

```
stacks/                           Docker Compose stacks, one directory per service
├── <service>/
│   ├── compose.yml               Compose file
│   ├── .env.example              All configurable values, documented
│   └── README.md                 Stack-specific deployment notes (optional)
komodo/
├── resources/                    ResourceSync TOML: servers, stacks, variables
│   ├── servers.toml
│   ├── stacks.toml
│   └── variables.toml
├── secrets.sops.yaml             SOPS-encrypted shared secrets
├── hosts/<host>/secrets.sops.yaml  SOPS-encrypted per-host secrets
└── decrypt.sh                    Merges secrets into Komodo Core's config
.github/workflows/
├── validate.yml                  Validates every stacks/*/compose.yml on push/PR
├── release-please.yml            Manages release PRs + CHANGELOGs
└── commitlint.yml                Enforces Conventional Commits on every PR commit
```

## Adding a Stack

### 1. Create the directory

```
stacks/<service>/
├── compose.yml
└── .env.example
```

Use lowercase kebab-case for `<service>`, matching the container/project
name (e.g. `uptime-kuma`, `home-assistant`).

### 2. Write the compose file

- Guard required env vars with `${VAR:?VAR is required}` so `docker compose
  config` fails loudly instead of deploying with an empty value
- Give every optional var a sensible default: `${VAR:-default}`
- Document every var — required and optional — in `.env.example`

### 3. Validate locally

```bash
docker compose -f stacks/<service>/compose.yml --env-file stacks/<service>/.env.example config --quiet
```

CI runs the same check against every `stacks/*/compose.yml` on push/PR
(`validate.yml`).

### 4. Wire it into ResourceSync

Add a `[[stack]]` entry to `komodo/resources/stacks.toml` assigning the
new stack to a server declared in `komodo/resources/servers.toml`. Set
`linked_repo = "homelab-infra"` (the shared Repo resource in
`komodo/resources/repos.toml`) rather than the stack's own
`git_account`/`repo` fields. Every existing stack follows this
convention so they share one clone per server instead of cloning
independently.

Secret values go through `[[SECRET_NAME]]`, added via `just k secrets`
(see [komodo/README.md](komodo/README.md)). Never commit a real secret
value into `stacks.toml` directly.

### 5. Commit and push

```bash
git add stacks/<service>/ komodo/resources/stacks.toml
git commit -m "feat(<service>): add <service> stack"
git push
```

## Guidelines

- **Pin image tags** where possible (`jellyfin:10.11` not `jellyfin:latest`) for reproducibility
- **Always support `TZ`** as an env var so timezone is configurable
- **Use `/data/<service-name>`** as the default host bind path convention
- **Keep `.env.example` complete** — every var the compose file reads should appear there, required vars first
- **One stack per service** — even if services are related (e.g. Immich Server and its Postgres are separate stacks: `immich`, `immich-postgres`)
