# databasement

Self-hosted database backup management via [databasement](https://github.com/David-Crty/databasement).

## Prerequisites

1. Create the shared Docker network on FeelsDataMan (one-time):
   ```bash
   docker network create db-net
   ```

2. Create the `databasement` database on the existing postgres instance:
   ```bash
   docker exec postgres psql -U postgres -c "CREATE DATABASE databasement;"
   ```

3. Add secrets to `komodo/secrets.sops.yaml` via `just secrets`:
   - `MONGO_ROOT_USERNAME` — MongoDB root username (match existing container)
   - `MONGO_ROOT_PASSWORD` — MongoDB root password (match existing container)
   - `DATABASEMENT_APP_KEY` — Laravel app key (generate with `php artisan key:generate --show` or `echo "base64:$(openssl rand -base64 32)"`)

## Deployment Order

1. Redeploy **postgres** stack (picks up db-net network)
2. Redeploy **immich-postgres** stack (picks up db-net network)
3. Deploy **mongodb** stack (formalizes existing container with db-net)
4. Deploy **databasement** stack

## Post-Deploy

Configure backup targets (postgres, immich-postgres, mongodb) in the databasement web UI at port 2226. The databases are reachable by their Docker DNS names on the `db-net` network.
