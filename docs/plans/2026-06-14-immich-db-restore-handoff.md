# Immich Database Restore — Handoff

**Date:** 2026-06-14  
**Status:** Paused mid-recovery  
**Branch:** all changes are on `main` (PRs #1079, #1080, #1081 merged via rebase)

---

## What broke originally

Immich failed with `FATAL: password authentication failed for user "postgres"` after the CNPG
cluster was reset. Root cause: CNPG generates random passwords in `immich-database-superuser`
on each cluster creation. If PVCs survive a cluster delete, the DB data files have the old
password; the new secret has a new random password → mismatch.

---

## What was changed in git (all merged to main)

| PR | Change |
|----|--------|
| #1079 | Added `managed.roles` to `cluster.yaml` + switched helmreleases to use `immich-pg-secret` (Bitwarden) instead of `immich-database-superuser` for DB_USERNAME/DB_PASSWORD |
| #1080 | Fixed managed role name from `app` → `immich`, added `superuser: true` |
| #1081 | Changed `bootstrap.initdb.database` and `owner` from `app` → `immich` (to match the backup's expected DB name) |

Current `cluster.yaml` summary:
- `managed.roles: name: immich, superuser: true, passwordSecret: immich-pg-secret`
- `bootstrap.initdb: database: immich, owner: immich`
- `postInitApplicationSQL: CREATE EXTENSION IF NOT EXISTS "vectors";`

Helmreleases (`immich-server`, `immich-microservices`):
- `DB_USERNAME` → `immich-pg-secret.username` (Bitwarden `pg_username` = `immich`)
- `DB_PASSWORD` → `immich-pg-secret.password` (Bitwarden `pg_password`)
- `DB_HOSTNAME` / `DB_PORT` → still from `immich-database-superuser` (stable cluster coords)
- `DB_DATABASE_NAME` → `immich-database-app.dbname` (CNPG auto-populates this)

---

## Leading hypothesis: Immich restore corrupted the database

The `immich` application database is missing despite initdb completing successfully. The most
likely explanation is that the Immich backup restore process — which runs a `pg_dumpall`-style
script via `psql` — **dropped and attempted to recreate the `immich` database** as part of its
role/schema setup, and left it in a partially-dropped or non-existent state when subsequent
steps failed (permission errors on role creation, etc.).

Evidence:
- The restore error log shows `NOTICE: database "immich" does not exist, skipping` in an
  earlier attempt — this is the pg_dumpall script trying to drop the DB before recreating it.
- The restore ran **twice** during this session (once while the DB was named `app`, once after
  it was renamed to `immich`). The second run had enough permissions to drop the DB but not
  enough to recreate it, leaving us with no application database.
- CNPG's initdb job completed without error, which means the DB existed right after init —
  the restore is the only thing that ran between then and the DB going missing.

**Test plan to confirm:** Do a clean cluster reinit, verify `immich` DB exists immediately
after, then check whether Immich starts cleanly WITHOUT running the restore. If it does, the
restore is the culprit.

---

## Current cluster state (as of pause)

The CNPG cluster is running and **healthy** (`immich-database-1/2/3` all Running). However:

1. **The `immich` database does NOT exist.** Only system databases (`postgres`, `template0`,
   `template1`) are present. The initdb ran but somehow did not create the application database.
   This is unexplained — `postInitApplicationSQL` works (`CREATE EXTENSION vectors` succeeds when
   run manually in `postgres` database), so the extension isn't the blocker.

2. **The `immich` role password is in an unknown state.** During recovery attempts, we ran
   `ALTER ROLE immich WITH PASSWORD '${PW}'` where `${PW}` was the Bitwarden password extracted
   via shell. If the Bitwarden password contains special characters (single quotes, backslash,
   etc.) the SQL may have set a garbled password. Neither the Bitwarden value from
   `immich-pg-secret` nor the CNPG-generated value from `immich-database-app` currently
   authenticates.

3. **`managed.roles` is unreliable in this CNPG version (1.29.1).** It reports `reconciled`
   but does NOT apply `superuser: true` — confirmed by `\du immich` showing no attributes.
   Password sync also appears intermittent.

4. **Immich pods are in CrashLoopBackOff** because they cannot connect to the database.

---

## What needs to happen to resume

### Step 0 — Test the corruption hypothesis first

Do a clean reinit and verify DB exists before touching the restore:

```bash
kubectl delete cluster immich-database -n default
kubectl delete pvc -n default -l 'cnpg.io/cluster=immich-database'
kubectl delete secret immich-database-superuser immich-database-app -n default 2>/dev/null || true
flux reconcile kustomization cluster-apps-immich -n flux-system --with-source

# Wait for all 3 DB pods Running, then:
kubectl exec -n default immich-database-1 -- psql -U postgres -c "\l"
```

**If `immich` database appears** → initdb works fine; the restore was corrupting it. Do NOT
run the Immich restore yet. Instead, let Immich start fresh (it will run its own migrations)
and confirm the pods reach Running. This confirms the hypothesis.

**If `immich` database is still missing** → there is a separate initdb bug to investigate
(possibly `postInitApplicationSQL` or a CNPG 1.29 behavior change with `initdb.database`).

### Step 1 — Clean slate on the CNPG cluster (if Step 0 confirms hypothesis)

Delete everything and let Flux reinitialize from scratch:

```bash
kubectl delete cluster immich-database -n default
kubectl delete pvc -n default -l 'cnpg.io/cluster=immich-database'
kubectl delete secret immich-database-superuser immich-database-app -n default 2>/dev/null || true
flux reconcile kustomization cluster-apps-immich -n flux-system --with-source
```

Wait for all 3 DB pods to be Running:
```bash
kubectl get pods -n default | grep immich-database
```

### Step 2 — Verify the `immich` database was actually created

```bash
kubectl exec -n default immich-database-1 -- psql -U postgres -c "\l"
```

If `immich` does NOT appear — the initdb database creation is silently failing. In that case,
create it manually:

```bash
kubectl exec -n default immich-database-1 -- psql -U postgres -c \
  "CREATE DATABASE immich OWNER immich;"
kubectl exec -n default immich-database-1 -- psql -U postgres -d immich -c \
  "CREATE EXTENSION IF NOT EXISTS vectors;"
```

### Step 3 — Fix the password situation

Check whether managed.roles set the correct password:

```bash
# Get Bitwarden password
BW_PW=$(kubectl get secret immich-pg-secret -n default -o jsonpath='{.data.password}' | base64 -d)
echo "Bitwarden pw length: ${#BW_PW}"

# Test auth
kubectl exec -n default immich-database-1 -- \
  env PGPASSWORD="${BW_PW}" psql -U immich -d immich -c "SELECT current_user;" 2>&1
```

If auth still fails, set the password properly (avoid shell interpolation into SQL):

```bash
BW_PW=$(kubectl get secret immich-pg-secret -n default -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n default immich-database-1 -- \
  env PGPASSWORD="${BW_PW}" psql -U postgres \
  -c "ALTER ROLE immich WITH SUPERUSER LOGIN PASSWORD '${BW_PW}';"
```

> ⚠️ If the Bitwarden password contains single quotes, use `$$dollar quoting$$` or escape them.
> The safer approach is to write the SQL to a file inside the pod.

### Step 4 — Confirm Immich starts

```bash
kubectl rollout restart deployment immich-server immich-microservices -n default
kubectl get pods -n default | grep -E "immich-(server|microservices)"
```

Both should reach `Running`.

### Step 5 — Retry the Immich restore

In the Immich web UI, retry the backup restore. The remaining errors from the last attempt:

- `ERROR: current user cannot be dropped` — harmless, pg_dumpall noise
- `ERROR: cannot drop role postgres` — harmless
- `ERROR: role "streaming_replica" cannot be dropped` — harmless
- `ERROR: role "immich" already exists` — harmless (role exists from initdb)
- `ERROR: permission denied to create role` — will be gone once `immich` has SUPERUSER
- `\connect: FATAL: password authentication failed` — was failing because `immich` DB didn't exist

With `immich` DB present + superuser + correct password, the restore should complete.

---

## Open questions / things to investigate

- **Why does `initdb.database: immich` not create the database?** The job completes and the
  cluster goes healthy, but only system databases exist. This might be a CNPG 1.29 behavior
  change, or an issue with `postInitApplicationSQL` running in a non-existent DB context.

- **Why does `managed.roles: superuser: true` not apply?** CNPG 1.29.1 might not support
  the `superuser` attribute in managed.roles, or it silently ignores it for roles that are
  already the database owner.

- **Long-term:** Once restore is working, consider whether `managed.roles` is actually
  providing value, or whether it's creating more problems than it solves. The original random
  password approach in `immich-database-superuser` would work fine as long as PVCs are always
  deleted with the cluster.
