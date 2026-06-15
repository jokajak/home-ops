# Authentik upgrade: 2024.12 → 2026.5.3 via fresh-start rebuild

> Status: **PLAN — approach chosen (fresh-start), confirming pre-flight** · 2026-06-14 ·
> Owner: Josh · Author: Luma (Claude)
>
> High blast radius: Grafana SSO and GitHub login depend on Authentik. We're skipping the
> 8-hop sequential migration and instead **dropping the Authentik DB and rebuilding fresh on
> the latest version**, since all config is codified and app creds live outside the DB.

## Decision

Authentik forbids skipping major versions on an *existing* DB, so the in-place path would be
8 sequential hops (2024.12→2025.2→…→2026.5). Instead: **destroy the `authentik` database,
deploy 2026.5.3 fresh (initial schema, no cross-version migrations), and rebuild all config
with `tofu apply`.** Target server **chart `2026.5.3`**, provider **`goauthentik/authentik`
matching `2026.5.x`**.

## Why this is safe here (creds live outside the Authentik DB)

- **`akadmin`** recreated on first boot from `AUTHENTIK_BOOTSTRAP_PASSWORD`/`_TOKEN`
  (`authentik-secret`) → same login + same API token, so terraform can still auth.
- **App OIDC client_id/secret** (Grafana, Immich) come from the `oidc_creds` module =
  **terraform state + Bitwarden**, not the Authentik DB. We drop the DB, **not** terraform
  state → `tofu apply` recreates providers with identical creds → **no app-side change**.
- **site-admin** random creds: terraform state + Bitwarden → identical.
- flows/stages/apps/groups/sources/**users**/branding: all terraform → rebuilt.

## What is lost (acceptable / auto-recovers)

- GitHub↔user link (UserSourceConnection): re-created on next GitHub login via `email_link`.
- MFA/TOTP/WebAuthn enrollments: re-enroll (no lockout — bootstrap password still works).
- Sessions, audit/event history, and **any UI-only config not in `terraform/authentik/`**
  (confirm there is none that matters).

## Current state

- Server: chart `authentik 2024.12.0` (`kubernetes/apps/security/authentik`), embedded outpost
  only, ingress `auth.${SECRET_DOMAIN}`.
- DB: shared CNPG `postgres` (`database` ns), PG 16; **database `authentik`** at
  `postgres-rw.database.svc.cluster.local`, created by the `init-db` (postgres-init)
  initContainer. Other apps share this cluster in **separate databases** — we drop only
  `authentik`. Barman→MinIO backups exist (`postgres16-v3`).
- Redis: Dragonfly. Provider: `goauthentik/authentik 2024.12.0`.

## Pre-flight (confirm before executing)

- [ ] No Authentik config done only in the UI (everything is in `terraform/authentik/`).
- [ ] Only the embedded outpost is in use (confirmed).
- [ ] (Optional safety) one logical dump of the `authentik` DB before dropping:
  ```sh
  kubectl -n database exec -ti postgres-1 -- \
    pg_dump -U postgres -d authentik -Fc -f /tmp/authentik-pre-2026.5.dump
  kubectl -n database cp postgres-1:/tmp/authentik-pre-2026.5.dump ./authentik-pre-upgrade.dump
  ```

## Execution sequence (ordering matters — empty DB must precede 2026.5.3)

1. **Suspend Flux for authentik** so it won't deploy mid-operation:
   `flux suspend helmrelease authentik -n security`
2. **(optional) backup** — the pg_dump above.
3. **Drop + recreate the empty `authentik` DB** (no server connected now). As the CNPG
   superuser on the primary:
   ```sh
   kubectl -n database exec -ti postgres-1 -- psql -U postgres -c \
     "DROP DATABASE authentik WITH (FORCE);"
   ```
   The chart's `init-db` initContainer recreates the database + role on next start.
4. **Bump the chart** → `kubernetes/apps/security/authentik/app/helmrelease.yaml`
   `spec.chart.spec.version: 2026.5.3`. **Render-check first** for values-schema drift across
   the 8 majors (`task k8s:kubeconform`, `flux-local`/`helm template`); fix any renamed/removed
   keys. Commit + push.
5. **Resume Flux**: `flux resume helmrelease authentik -n security`. 2026.5.3 deploys,
   `init-db` recreates the empty DB, the server runs **fresh** migrations, bootstrap creates
   `akadmin`. Verify: pods healthy, `https://auth.<domain>/` up, `akadmin` login works.
6. **Bump the provider** → `terraform/authentik/versions.tf` `2024.12.0` → `2026.5.x`;
   re-introduce `parents = [...]` on the four groups (the 2026 API shape we reverted);
   `tofu init -upgrade`, re-lock for darwin/linux.
7. **Rebuild config**: `tofu apply`. State holds the old DB's object UUIDs; on refresh the
   provider should see them gone (404) and recreate (~61 creates, like the first apply). If
   refresh **errors** on missing resources instead, `tofu state rm` the `authentik_*`
   resources (keep `module.*_oidc_creds.*`, `random_*`, `bitwarden_item_login.*`) and re-apply.
8. **Re-link + verify**: log in via GitHub (re-creates the source link via `email_link`),
   confirm you land on your user; confirm **Grafana SSO** (Viewer/Admin per groups). Re-enroll
   MFA if desired.

## Rollback

- If 2026.5.3 won't come up healthy: re-suspend, restore the pre-upgrade `authentik` dump into
  a freshly recreated `authentik` DB, revert the chart bump in git, resume → back on 2024.12.
- Because we keep terraform state and Bitwarden, nothing about app creds changes either way.

## After completion

- Update SSO Gotchas: provider now `2026.5.x`, groups use `parents`.
- **Renovate:** keep chart + provider in lockstep going forward (the provider bumping ahead of
  the chart is what caused the `autocomplete`/`parent` breakage). Group them or pin with intent.

## Session Log

- **2026-06-14** — Investigated (server `2024.12.0`, shared CNPG `postgres`/db `authentik`,
  Dragonfly, embedded outpost, provider `2024.12.0`); confirmed majors can't be skipped and
  chart latest is `2026.5.3`. **Owner chose the fresh-start rebuild** over the 8-hop migration
  (everything is codified; app creds live in terraform state + Bitwarden, not the Authentik
  DB). Rewrote this plan to the fresh-start strategy. Awaiting pre-flight confirm before
  execution.
