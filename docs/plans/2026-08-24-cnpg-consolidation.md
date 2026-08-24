# Collapsing the per-app CNPG clusters

> Status: **LITELLM DONE · FORGEJO STAGED, NEEDS THE RUNBOOK BELOW BEFORE MERGE** · 2026-08-24 ·
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
| `forgejo-database` | `productivity` | 2 | **Collapsing now** |
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

## Forgejo: the runbook

⚠️ **The manifest change is staged on this branch and must not reach `main` until step 5 is
done.** Flux tracks `main`, so the branch itself is inert — that is the gate. If the repointed
manifests reconcile before the data is restored, Forgejo finds an empty database, migrates a
fresh schema into it, and you are then merging two schemas by hand.

The other reason ordering matters: removing `forgejo-database` from Git means Flux prunes the
`Cluster`, and **CNPG deletes its PVCs with it**. The dump has to exist first.

### 1. Pre-flight

```sh
# How big is it really, and will it fit? The shared cluster's volume is 10Gi.
kubectl -n productivity exec forgejo-database-1 -- \
  psql -U postgres -d forgejo -c "SELECT pg_size_pretty(pg_database_size('forgejo'));"
kubectl -n database exec postgres-1 -- df -h /var/lib/postgresql/data
```

If the two together get close to 10Gi, grow `spec.storage.size` on the shared cluster and let it
reconcile **before** going further. CNPG expands a volume online; it will not shrink one.

### 2. Create the Bitwarden item

**`forgejo pgcreds`** — a login item, username `forgejo`, password freshly generated. This
replaces the credential the old CNPG cluster minted for itself
(`forgejo-database-app`), which does not carry over.

### 3. Quiesce Forgejo

```sh
kubectl -n productivity scale deploy/forgejo --replicas=0
```

Do not skip this. A dump taken while Forgejo is writing is crash-consistent at best, and the
half of the state that lives on NFS (repositories, LFS) will not match it.

### 4. Dump

```sh
kubectl -n productivity exec forgejo-database-1 -- \
  pg_dump -U postgres -d forgejo -Fc --no-owner --no-acl > /tmp/forgejo.dump
ls -lh /tmp/forgejo.dump   # sanity-check it is not 0 bytes
```

### 5. Create the role + database on the shared cluster, and restore

```sh
# Use the password you just put in Bitwarden.
kubectl -n database exec -i postgres-1 -- psql -U postgres <<'SQL'
CREATE ROLE forgejo WITH LOGIN PASSWORD '<the password from Bitwarden>';
CREATE DATABASE forgejo OWNER forgejo;
SQL

kubectl -n database exec -i postgres-1 -- \
  pg_restore -U postgres -d forgejo --no-owner --role=forgejo < /tmp/forgejo.dump

# Verify before trusting it — row counts should match the old cluster.
kubectl -n database exec postgres-1 -- \
  psql -U postgres -d forgejo -c "SELECT count(*) FROM repository;"
kubectl -n productivity exec forgejo-database-1 -- \
  psql -U postgres -d forgejo -c "SELECT count(*) FROM repository;"
```

`postgres-init` would create the role and database itself on first boot, but it runs *after*
this branch merges — and the restore has to happen first. Creating them by hand here is the
ordering fix, and postgres-init is a no-op afterwards.

### 6. Merge this branch

Flux repoints Forgejo at `postgres-rw.database.svc.cluster.local`, injects `init-db`, and prunes
the old `forgejo-database` cluster, its `ObjectStore` and its `ScheduledBackup`.

### 7. Verify, then let the old PVCs go

Log in, open a repository, push a commit. Then confirm the old cluster is gone:

```sh
kubectl -n productivity get cluster,pvc | grep forgejo-database   # expect nothing
```

Keep `/tmp/forgejo.dump` somewhere real until you have used Forgejo for a few days. Its old
barman lineage (`forgejo-v1` under `s3://databases/`) also survives the prune — the ObjectStore
resource goes away, the objects in MinIO do not — so there is a second way back for as long as
that retention window lasts.

### If it goes wrong

Revert the merge. The old `Cluster` comes back from Git, but **its PVCs do not** — CNPG
provisions empty ones and bootstraps a new empty database. Recovery is the dump from step 4, or
the barman lineage. This is why step 4 is not optional.

## Next: paperless, then home-assistant

Same shape, in this order:

- **paperless** — `paperless-database`, 2 instances, small. Its chart is `app-template`, which
  takes init containers natively, so no post-renderer needed. Same runbook with the table name in
  step 5 changed to something paperless-specific (`documents_document`).
- **home-assistant** — `home-assistant-db`, 2 instances. Deliberately last: the recorder is the
  only genuinely write-heavy workload in the collapsible set, and it is the one that could make
  the shared cluster a noisy-neighbour problem. Do it once forgejo and paperless have been on
  the shared cluster long enough to see whether the write load is boring. If HA's recorder turns
  out to dominate, leaving it on its own cluster is a legitimate final answer rather than a
  failure.

## Open

- **Should the shared cluster grow?** It is 10Gi, 3 instances, `shared_buffers: 256MB`,
  `max_connections: 400`, requesting 500m CPU with a 4Gi memory limit. Fine for authentik alone;
  worth re-checking after each app lands rather than guessing now.
- **Per-database backup.** Cluster-level barman plus ad-hoc `pg_dump` is what we have. If
  per-app PITR turns out to matter, that is an argument for a scheduled logical dump per
  database into MinIO, not for going back to a cluster per app.
