# Collapsing the per-app CNPG clusters

> Status: **LITELLM + FORGEJO DONE · PAPERLESS AND HOME-ASSISTANT NEXT** · 2026-08-24 ·
> Owner: Josh · Author: Claude
>
> Six Postgres clusters and fourteen pods to serve six apps, on five small nodes. This collapses
> the ones that are just holding config into the shared cluster that already exists.

## The finding

**The pattern we want is already in this repo — it just stopped being used.** Authentik has no
CNPG cluster of its own. It gets a database and a role on the shared `database/postgres` cluster,
created by a `ghcr.io/home-operations/postgres-init` init container from a Bitwarden-held
credential. Every app added since gave itself a dedicated two- or three-instance cluster instead.

Where that left us:

| Cluster | Namespace | Instances | Verdict |
|---|---|---|---|
| `postgres` | `database` | 3 | **The shared one.** Already hosts `authentik` |
| `immich-database` | `default` | 3 | **Stays separate** — see below |
| `home-assistant-db` | `default` | 2 | Collapsible, last |
| `forgejo-database` | `productivity` | 2 | **Collapsed** (stood up 2026-08-22, no data yet) |
| `paperless-database` | `productivity` | 2 | Collapsible, next |
| `litellm-database` | `ai` | 2 | **Collapsed** (never deployed, so free) |

Fourteen pods → eight once forgejo and litellm are done, six if paperless and home-assistant
follow.

## Why immich stays separate

Not sentiment — it genuinely cannot share:

- It runs `ghcr.io/tensorchord/cloudnative-vectorchord`, not the stock CNPG image, for the
  embedding index.
- It loads `vchord.so` via `shared_preload_libraries`, which is a **server-wide** setting. Putting
  immich on the shared cluster means every other app's server loads it too.
- It is pinned to `amd64` by node selector, and sized differently (512MB shared buffers,
  `max_connections: 300`).

A shared server can host many databases; it can only have one set of preloaded libraries and one
binary. That is the line.

## What "shared" actually buys, and what it costs

Worth being straight about, because this is a real trade and not a free win.

**Buys:**
- Six fewer Postgres pods, and their memory reservations back.
- Fewer Postgres *versions* to upgrade — the per-app clusters already drifted (immich is on
  16.9, everything else on 16.0-10).
- Each collapsed app moves from a 2-instance cluster to a **3-instance** one, so per-app
  failover tolerance goes up, not down.
- One backup schedule and one restic/barman lineage instead of one per app.

**Costs:**
- **Blast radius.** `docs/ISSUES.md` #14 records `database/postgres` taking a full outage when
  its primary's disk died. More apps on it means one bad disk touches more apps. Mitigated by
  three instances rather than two, but real.
- **Backup granularity.** Barman PITR restores a *cluster*, not one app's database. Recovering
  just forgejo to a point in time becomes "restore the cluster somewhere else, `pg_dump` the one
  database out". Per-app `pg_dump` is the fine-grained tool now.
- **Noisy neighbour.** One app's runaway query competes for the same `shared_buffers` and
  connection pool as the others. `max_connections` is already 400, which is ample; the write
  volume to watch is home-assistant's recorder, which is why it goes last.

## The pattern

Three pieces per app, all of them already visible in `kubernetes/apps/security/authentik`:

1. **A Bitwarden login item `<app> pgcreds`** — username and password for that app's role.
2. **An `ExternalSecret`** that renders those into whatever the app expects, plus the
   `INIT_POSTGRES_*` variables.
3. **A `postgres-init` init container** that creates the database and role if absent and
   `ALTER ROLE`s the password to match on every start — so rotating the Bitwarden password
   actually takes effect instead of locking the app out.

The app then connects to `postgres-rw.database.svc.cluster.local:5432` as its own unprivileged
role, owning exactly one database. The superuser password is only ever seen by the init
container.

For chart-based apps with no hook for extra init containers — Forgejo is one; its `initContainers`
value only carries resource limits — the init container goes in through a Flux
`postRenderers.kustomize` patch at `initContainers/0`, ahead of the chart's own migration step.

## Done: litellm

Converted before it ever deployed, so there is nothing to migrate. Its `app/database/` directory,
its `ObjectStore`, its `ScheduledBackup` and its `minio-litellm-pgsql` credential are all gone;
`DATABASE_URL` is assembled in the ExternalSecret against the shared cluster.

One detail worth keeping: the DSN is built with `urlquery` on both halves of the credential. A
generated password containing `@`, `:`, `/` or `#` would otherwise produce a DSN that parses
into the wrong host and fails in a way that looks like a network problem.

Needs one new Bitwarden item: **`litellm pgcreds`** (login: username + password).

## Done: forgejo

Forgejo went in on 2026-08-22 and has nothing in its database yet, so this is the same free
conversion litellm got — no dump, no restore, no merge gate. `postgres-init` creates the role and
the empty database, and the chart's `configure-gitea` migrates a fresh schema into it on first
start, exactly as it did against the old cluster.

**One ordering requirement remains, and it is small:** create the Bitwarden login item
**`forgejo pgcreds`** (username `forgejo`, generated password) before this reaches `main`. Without
it the `ExternalSecret` never syncs, `forgejo-pg-secret` never exists, and the deployment cannot
start — it mounts that secret with both `secretKeyRef` and `envFrom`. Nothing is damaged; Forgejo
just sits unready until the item shows up.

Removing `forgejo-database` from Git prunes the `Cluster`, and CNPG deletes its PVCs with it.
That is the intent here. Note only that Forgejo's *repository* tree is separate — it lives on the
`nfs-forgejo` PV, which is `Retain` — so if anything was ever pushed, the files survive while the
new empty database has no record of them. Fresh install, nothing to reconcile; worth knowing only
because the two halves of Forgejo's state are on different storage with different lifecycles.

## Migrating an app that *does* have data

Neither app above needed this. Paperless and home-assistant will. The ordering is the whole
procedure — get it wrong and the app migrates a fresh schema into an empty database while the old
one is being pruned out from under it.

⚠️ **Flux tracks `main`, so a feature branch is inert. That is the gate.** Do not merge the
repointing commit until the restore has happened.

### 1. Pre-flight

```sh
# How big is it really, and will it fit? The shared cluster's volume is 10Gi.
kubectl -n <ns> exec <app>-database-1 -- \
  psql -U postgres -d <app> -c "SELECT pg_size_pretty(pg_database_size('<app>'));"
kubectl -n database exec postgres-1 -- df -h /var/lib/postgresql/data
```

If the two together get close to 10Gi, grow `spec.storage.size` on the shared cluster and let it
reconcile **before** going further. CNPG expands a volume online; it will not shrink one.

### 2. Create the Bitwarden item

**`<app> pgcreds`** — a login item, username `<app>`, password freshly generated. This replaces the
credential the old CNPG cluster minted for itself (`<app>-database-app`), which does not carry
over.

### 3. Quiesce the app

```sh
kubectl -n <ns> scale deploy/<app> --replicas=0
```

Do not skip this. A dump taken while the app is writing is crash-consistent at best, and for an
app whose other half lives on NFS the two will not match.

### 4. Dump

```sh
kubectl -n <ns> exec <app>-database-1 -- \
  pg_dump -U postgres -d <app> -Fc --no-owner --no-acl > /tmp/<app>.dump
ls -lh /tmp/<app>.dump   # sanity-check it is not 0 bytes
```

### 5. Create the role + database on the shared cluster, and restore

```sh
kubectl -n database exec -i postgres-1 -- psql -U postgres <<'SQL'
CREATE ROLE <app> WITH LOGIN PASSWORD '<the password from Bitwarden>';
CREATE DATABASE <app> OWNER <app>;
SQL

kubectl -n database exec -i postgres-1 -- \
  pg_restore -U postgres -d <app> --no-owner --role=<app> < /tmp/<app>.dump

# Verify before trusting it — row counts should match the old cluster.
kubectl -n database exec postgres-1 -- psql -U postgres -d <app> -c "SELECT count(*) FROM <table>;"
kubectl -n <ns> exec <app>-database-1 -- psql -U postgres -d <app> -c "SELECT count(*) FROM <table>;"
```

`postgres-init` would create the role and database itself, but it only runs after the branch
merges — and the restore has to happen first. Creating them by hand here is the ordering fix;
postgres-init is a no-op afterwards.

### 6. Merge, verify, then let the old PVCs go

Flux repoints the app, injects `init-db`, and prunes the old cluster, its `ObjectStore` and its
`ScheduledBackup`. Exercise the app, then confirm:

```sh
kubectl -n <ns> get cluster,pvc | grep <app>-database   # expect nothing
```

Keep the dump until you have used the app for a few days. The old barman lineage under
`s3://databases/` also survives the prune — the `ObjectStore` resource goes away, the objects in
MinIO do not — so there is a second way back for as long as that retention window lasts.

### If it goes wrong

Revert the merge. The old `Cluster` comes back from Git, but **its PVCs do not** — CNPG
provisions empty ones and bootstraps a new empty database. Recovery is the dump from step 4, or
the barman lineage. This is why step 4 is not optional.

## Next: paperless, then home-assistant

Same shape, in this order:

- **paperless** — `paperless-database`, 2 instances, small, and it **does** have documents, so
  this is the first one that needs the migration procedure above. Its chart is `app-template`,
  which takes init containers natively, so no post-renderer needed. Use `documents_document` as
  the row-count check in step 5.
- **home-assistant** — `home-assistant-db`, 2 instances. Deliberately last: the recorder is the
  only genuinely write-heavy workload in the collapsible set, and it is the one that could make
  the shared cluster a noisy-neighbour problem. Do it once forgejo and paperless have been on
  the shared cluster long enough to see whether the write load is boring. Its recorder history
  is real data, so the migration procedure applies here too. If HA's recorder turns
  out to dominate, leaving it on its own cluster is a legitimate final answer rather than a
  failure.

## Open

- **Should the shared cluster grow?** It is 10Gi, 3 instances, `shared_buffers: 256MB`,
  `max_connections: 400`, requesting 500m CPU with a 4Gi memory limit. Fine for authentik alone;
  worth re-checking after each app lands rather than guessing now.
- **Per-database backup.** Cluster-level barman plus ad-hoc `pg_dump` is what we have. If
  per-app PITR turns out to matter, that is an argument for a scheduled logical dump per
  database into MinIO, not for going back to a cluster per app.
