# Authentik upgrade: 2024.12 → 2026.5 (server) + provider

> Status: **PLAN — awaiting approval** · 2026-06-14 · Owner: Josh · Author: Luma (Claude)
>
> High blast radius: Grafana SSO and GitHub login now depend on Authentik. Staged,
> verify-between-hops migration. **Do not skip major versions** (Authentik's hard rule).

## Goal

Upgrade the Authentik **server** (Helm chart `2024.12.0` → latest **`2026.5.3`**) and the
**`goauthentik/authentik` terraform provider** (`2024.12.0` → matching `2026.5.x`), keeping
them in lockstep, with no loss of the SSO config we just built.

## Current state

- Server: Helm chart `authentik 2024.12.0` from `https://charts.goauthentik.io`
  (`kubernetes/apps/security/authentik`). Embedded outpost (no separate proxy outposts).
- DB: **shared CNPG cluster `postgres`** (`database` ns), PG 16, database `authentik`,
  reached at `postgres-rw.database.svc.cluster.local`. Barman Cloud plugin backups to MinIO
  (`postgres-objectstore`, serverName `postgres16-v3`) with WAL archiving.
- Redis: external **Dragonfly** (`dragonfly.database.svc.cluster.local`).
- Provider: `goauthentik/authentik 2024.12.0` (pinned to the server line, `terraform/authentik`).

## Hard constraints (from Authentik docs)

- **Must not skip major versions.** Upgrade one major at a time, letting migrations run
  between each. Sequence available in the chart repo:
  **2024.12 → 2025.2 → 2025.4 → 2025.6 → 2025.8 → 2025.10 → 2025.12 → 2026.2 → 2026.5**
  (target patch `2026.5.3`). That's **8 hops**.
- **No downgrade support.** A bad hop is recovered only by restoring the DB backup.
- **Outposts must match the core version.** Only the embedded outpost is in use here, which
  upgrades with the server — but confirm no external/proxy outposts exist before starting.
- Read the **release notes for each target version** before that hop (breaking changes,
  required actions, minimum PostgreSQL/Redis versions).

## Risks

- A migration fails mid-hop → Authentik down → **all SSO logins down** (Grafana, GitHub
  login). Mitigation: backup + verify gate after each hop; fix-forward or restore.
- **Helm chart values schema drift** across 8 majors — keys in our `helmrelease.yaml`
  (`global.env` list, `authentik.redis.host`, `server.initContainers`, `postgresql.enabled`,
  `redis.enabled`, ingress) may be renamed/removed. Must diff rendered manifests each hop.
- **PostgreSQL version floor** — confirm 2026.5 still supports PG 16 (CNPG cluster is
  `postgresql:16.0`). If a later Authentik requires PG ≥ 17, that's a separate CNPG upgrade.
- **Provider/server skew** (the bug we already hit): keep the provider pinned to the server
  line; only bump the provider **after** the server reaches the target.

## Pre-flight (once, before hop 1)

- [ ] Confirm there are **no external outposts** (only the embedded one) — Admin → Outposts.
- [ ] Verify **WAL archiving is healthy** on the `postgres` cluster (CNPG `Cluster` status:
  `ContinuousArchiving=True`, recent `lastSuccessfulBackup`).
- [ ] Take a **targeted logical backup of just the `authentik` DB** (cleanest restore unit,
  per the Immich lesson — a per-DB `pg_dump` beats cluster-wide for surgical recovery):
  ```sh
  kubectl -n database exec -ti postgres-1 -- \
    pg_dump -U postgres -d authentik -Fc -f /tmp/authentik-pre-2025.2.dump
  kubectl -n database cp postgres-1:/tmp/authentik-pre-2025.2.dump ./authentik-pre-upgrade.dump
  ```
  (and/or trigger an on-demand CNPG `Backup` CR for the whole cluster).
- [ ] Note the current working state: GitHub login + Grafana SSO both succeed (baseline).

## Per-hop procedure (repeat for each waypoint)

For hop N (e.g. `2025.2.0`):

1. **Read** the release notes for that version; note any required manual steps.
2. **Backup** the `authentik` DB (repeat the pg_dump above with the version in the name).
3. **Edit** `kubernetes/apps/security/authentik/app/helmrelease.yaml` →
   `spec.chart.spec.version: <waypoint>` (use the **latest patch** of that major).
4. **Render-check locally** before pushing — diff the rendered manifests so values-schema
   drift is caught early:
   ```sh
   task k8s:kubeconform                      # schema
   # flux-local diff helmrelease (as CI does) to see the rendered change
   ```
   If a value key changed/was removed, update `helmrelease.yaml` accordingly.
5. **Commit + push**; Flux reconciles. Watch the `authentik-server` + `authentik-worker`
   roll; the server runs DB migrations on start.
6. **Verify gate** (must pass before the next hop):
   - Pods healthy; no migration errors in `authentik-worker` logs.
   - `https://auth.<domain>/` loads; admin login works.
   - **GitHub login** still links to your user; **Grafana SSO** still works.
7. If broken: revert the chart version (Flux) — and if migrations already ran, **restore the
   pre-hop DB dump** (no downgrade), then retry after addressing the release-note actions.

Hops, in order: `2025.2 → 2025.4 → 2025.6 → 2025.8 → 2025.10 → 2025.12 → 2026.2 → 2026.5.3`.

## Provider upgrade (after the server reaches 2026.5.3)

1. `terraform/authentik/versions.tf`: `goauthentik/authentik` `2024.12.0` → `2026.5.x`
   (match the server). `tofu init -upgrade`, re-lock for darwin/linux.
2. Re-apply the **2026 API shape**: `authentik_group.parent` → `parents = [...]` (list) on the
   four groups — this is the change we reverted when pinning down; it comes back at 2026.x.
   Watch for any other `tofu validate` errors and reconcile against the 2026.5 provider schema.
3. `tofu plan` — expect **only in-place/no-op** changes (the server now matches). Investigate
   any destroy/replace before applying. Then `tofu apply`.
4. The `autocomplete` read errors should be gone (provider now matches the server).

## Rollback

- Per hop: revert chart version in git (Flux redeploys the prior image). If the failed hop's
  migrations already ran, the image revert is **not** enough — restore the pre-hop `authentik`
  DB dump into the `postgres` cluster, then the older image is consistent again.
- Keep every per-hop dump until the whole sequence is verified.

## After completion

- Update the SSO docs/Gotchas: provider is now `2026.5.x`, groups use `parents`.
- **Renovate:** keep the chart and the provider in lockstep going forward (don't let the
  provider bump ahead of the chart again — that caused the `autocomplete`/`parent` breakage).
  Consider a renovate rule grouping `goauthentik/authentik` (provider) with the `authentik`
  Helm chart, or pinning the provider with a comment (already noted in `versions.tf`).

## Open questions

- Do we want to land on `2026.5.3` now, or stop at a slightly older major and let it bake?
- Any external outposts in use (changes the "embedded upgrades automatically" assumption)?
- Acceptable maintenance window — each hop briefly bounces Authentik (all SSO logins).

## Session Log

- **2026-06-14** — Investigated: server chart `2024.12.0`, DB on shared CNPG `postgres`
  (Barman→MinIO), Dragonfly redis, embedded outpost, provider `2024.12.0`. Confirmed via
  Authentik docs that majors **cannot be skipped**; chart repo latest is `2026.5.3`. Wrote
  this staged plan (8 hops + provider bump). Awaiting approval before hop 1.
