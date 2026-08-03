# Komodo secrets workflow

Secrets (host IPs, credentials, endpoints) are SOPS-encrypted with `age` and
committed to the repo. Komodo Core decrypts them into a `[secrets]` TOML
block on the host it runs on, and stacks reference values by name via
`[[SECRET_NAME]]` interpolation.

**Flow:** edit secrets → `sops -e` → git push → decrypt on Core host →
Komodo restart picks up changes.

## Layout

```
komodo/
├── .sops.yaml                    # age recipient(s) used to encrypt
├── secrets.sops.yaml             # encrypted shared secrets (committed)
└── resources/
    └── hosts/
        ├── secrets.sops.yaml.tpl     # template for per-host secrets
        ├── variables.toml.tpl        # template for per-host variables
        └── <hostname>/
            ├── secrets.sops.yaml     # encrypted per-host secrets (committed)
            └── variables.toml        # per-host variables (plain TOML)
```

Shared secrets are available as `[[SECRET_NAME]]`. Per-host secrets are
merged in prefixed with the hostname: a `host_ip` key under
`komodo/resources/hosts/nas-01/secrets.sops.yaml` becomes `[[nas-01_host_ip]]`.

## First-time setup

Generates (or restores) an age keypair and configures `.sops.yaml`. Backs
the private key up to Bitwarden as a secure note if `BW_SESSION` is set.

```bash
export BW_SESSION=$(bw unlock --raw)   # optional, enables Bitwarden backup
just setup
```

This runs `scripts/init-secrets.sh`, which:

1. Restores the age key from Bitwarden if one exists there, otherwise
   generates a new one at `~/.config/sops/komodo/age/keys.txt`
2. Backs the key up to Bitwarden (secure note "Homelab Komodo SOPS Age
   Key") if not already there
3. Writes the age public key into `komodo/.sops.yaml`

On the **Komodo Core host**, install `sops`, `age`, and `jq`, then place the
private key at `/etc/komodo/age.key` (or wherever `SOPS_AGE_KEY_FILE`
points). Restore it from the Bitwarden backup rather than generating a
new one, since a new key can't decrypt secrets encrypted for the old one.

## Editing secrets

```bash
just k secrets            # edit shared secrets (komodo/secrets.sops.yaml)
just k secrets nas-01     # edit per-host secrets (komodo/resources/hosts/nas-01/secrets.sops.yaml)
```

Opens the decrypted file in `$EDITOR` via `sops` and re-encrypts on save.
Creates the file from the matching template on first use.

```bash
just k show-secrets           # print decrypted shared secrets to stdout
just k show-secrets nas-01    # print decrypted per-host secrets to stdout
```

## Decrypting on the Core host

The `komodo` Ansible role handles secret provisioning automatically —
it decrypts all global and per-host secrets, merges them into a
`[secrets]` TOML block with per-host keys prefixed by hostname, and
deploys the result as `core.secrets.toml` on the Core host. Run:

```bash
just a deploy <core-host> --tags komodo
```

The Komodo Core stack mounts this file read-only via `KOMODO_SECRETS_FILE`
(see `stacks/komodo/.env.example`). Ansible restarts Core automatically
when secrets change.

## Rotating a secret

1. `just k secrets [TARGET]` — edit the value, save, it's re-encrypted automatically
2. Commit and push:
   ```bash
   git add komodo/secrets.sops.yaml   # or komodo/resources/hosts/<TARGET>/secrets.sops.yaml
   git commit -m "chore(komodo): rotate <secret-name>"
   git push
   ```
3. Re-run the Ansible `komodo` role against the Core host to deploy the updated secrets

## Adding a new host

```bash
mkdir -p komodo/resources/hosts/<hostname>
just k secrets <hostname>
```

`just k secrets <hostname>` copies `komodo/resources/hosts/secrets.sops.yaml.tpl` into
`komodo/resources/hosts/<hostname>/secrets.sops.yaml`, encrypts it, and opens it for
editing. Values end up available as `[[<hostname>_<key>]]`.

## Non-secret variables, shared or per-host

Non-secret values (`TZ`, `PUID`, hostnames that aren't credentials, ...)
don't go through `sops` — they live as plain TOML under
`komodo/resources/`, since that's the only path Komodo's ResourceSync
watches.

```bash
just k vars              # edit shared komodo/resources/variables.toml
just k vars nas-01        # edit/create komodo/resources/hosts/nas-01/variables.toml
```

Shared variables are available as `[[VARIABLE_NAME]]`. Per-host variables
follow the same naming convention as per-host secrets: a variable named
`nas-01_DBHOST` in `komodo/resources/hosts/nas-01/variables.toml` becomes
available as `[[nas-01_DBHOST]]` — the host prefix is part of the `name`
field itself, not applied automatically, so name entries accordingly (see
`komodo/resources/hosts/variables.toml.tpl` for the convention and an
example). Unlike secrets, no decrypt/restart step is needed — Resource
Sync picks these up directly.
