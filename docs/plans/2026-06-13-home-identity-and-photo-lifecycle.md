# Home Identity (SSO) + Photo Lifecycle Plan

**Date:** 2026-06-13
**Status:** Draft / not yet started

---

## Goal

Build a home services stack that a non-operator (my wife) could take over and keep running,
with two near-term pillars:

1. **Self-hosted photos & videos** via Immich, with data on the Synology NAS (RAID 1, NFS).
2. **No local accounts** — sign in with a Google account. Authentik is the identity broker:
   Google federates *into* Authentik, and apps (starting with Immich) trust Authentik via OIDC.

> **Why broker through Authentik instead of pointing Immich straight at Google?**
> A single broker means one place to manage users, groups, and which apps a person can reach.
> It keeps app config uniform (every app speaks OIDC to Authentik), lets us add non-Google
> login methods later without touching each app, and gives a clean "who can log in" story for
> someone inheriting the system. It also lets us invite family members who don't have Google
> accounts later if needed.

### Success criteria

- Authentik is healthy, backed up, and reachable at `auth.${SECRET_DOMAIN}`.
- A Google account can log into Authentik and, through it, into Immich — no local Immich account.
- Immich photos/videos are stored on the NAS and survive a cluster rebuild.
- The photo lifecycle (wife's phone → shared storage → Immich) is documented and at least
  partially automated.

---

## Identity architecture (target)

```
Google account
   │  (OAuth — Google is a federated "Source" in Authentik)
   ▼
Authentik  (auth.${SECRET_DOMAIN})  ── identity broker / user + group store
   │  (OIDC — Authentik is the "Provider", one per app)
   ▼
Immich (photos.${SECRET_DOMAIN})   [and later: Grafana, etc.]
```

- **Authentik Sources** = inbound identity (Google, GitHub).
- **Authentik Providers + Applications** = outbound trust to each app (Immich today).
- **Authentik Groups** = authorization (who may reach which app).
- Terraform (`terraform/authentik/`) manages all of the above declaratively and stores the
  generated per-app OIDC client id/secret in Bitwarden via the `oidc_creds` module.

---

## Current state assessment (from the manifests)

What already exists in the repo:

| Area | State |
|------|-------|
| Authentik deploy | `kubernetes/apps/security/authentik` — Helm chart `2024.12.0`, external Postgres (CNPG `postgres-rw`) + dragonfly redis, secret via ExternalSecret → Bitwarden. Ingress `auth.${SECRET_DOMAIN}` (class `external`). |
| Authentik config (TF) | Flows, stages, prompts, brand, groups (`users`, `Home`, `Infrastructure`, `media`), a **GitHub** OAuth source, and an Immich OAuth2 provider/application. |
| Immich deploy | `kubernetes/apps/default/immich` — server (`api` worker) + microservices (non-`api` workers), v2.5.5, CNPG pgvecto.rs DB with MinIO backups, ML, NFS data PVC (`/volume1/immich`, 2 TB PV). Ingress `photos.${SECRET_DOMAIN}` (class `internal`). |
| Secrets | External Secrets via Bitwarden (`bitwarden-login`, `bitwarden-fields` ClusterSecretStores) + SOPS/age for Talos/TF state. **Owner-injected — not visible to AI agents.** |

### Findings / bugs to fix (discovered while reviewing)

1. **No Google source exists yet.** `terraform/authentik/main.tf` defines a GitHub
   `authentik_source_oauth` and a half-written `authentik_policy_expression.google_username`
   (its body is commented out and it `return False`s), but there is **no
   `authentik_source_oauth` of `provider_type = "google"`**. This is the core missing piece for
   the stated goal.

2. **`application_immich.tf` is copy-pasted from Grafana.** Several fields still point at
   Grafana and must be corrected:
   - `meta_icon` → a Grafana PNG (should be an Immich icon).
   - `meta_launch_url` → `https://grafana.${var.domain}/login/generic_oauth` (should be the
     Immich URL).
   - `slug` is set to the provider *name* (`immich-provider`) rather than a clean app slug.
   - `group = authentik_group.monitoring.name` — verify a `monitoring` group is actually
     defined (it is **not** in `directory.tf`; likely declared in `application_grafana.tf`).
     Immich should bind the `users`/`media` group, not `monitoring`.

3. **Hostname mismatch between Immich and its OAuth redirect URIs.** The Immich ingress serves
   `photos.${SECRET_DOMAIN}` (`immich/app/server/helmrelease.yaml`), but
   `application_immich.tf` registers redirect URIs against `https://immich.${var.domain}/...`.
   These must agree or OAuth login will fail. **Decision needed:** standardize on `photos.` or
   `immich.` (see Open Questions). The mobile-app redirect `app.immich://oauth-callback` is
   correct regardless.

4. **Stale Immich configmap.** `immich/app/configmap.yaml` still carries legacy keys that
   modern Immich (v2.x) ignores: `TYPESENSE_*`, `IMMICH_WEB_URL`, `IMMICH_SERVER_URL`,
   `IMMICH_MACHINE_LEARNING_URL`. Harmless but misleading; clean them up.

5. **Immich OAuth is configured in-app, not by env/configmap.** Immich reads its OAuth settings
   from the database (admin UI / system config), so after the Authentik provider exists, the
   OAuth issuer URL, client id, and client secret must be entered in Immich's admin settings
   (or pushed via Immich's config). Plan for a manual admin step here.

> **I cannot verify live state from this environment** (ephemeral container, no kubeconfig).
> Phase 0 below lists the checks for the owner to run; everything above is from static review.

---

## Phase 0 — Verify what's actually running (owner runs these)

Before changing anything, confirm the foundation. Run on a workstation with cluster access:

```bash
# Authentik up and reachable?
flux -n security get hr authentik
kubectl -n security get pods -l app.kubernetes.io/instance=authentik
kubectl -n security get ingress           # expect auth.<domain>
# DB + redis dependencies
kubectl -n database get cluster            # CNPG postgres healthy?
kubectl -n database get pods -l app=dragonfly

# Immich up?
flux -n default get hr immich-server immich-microservices immich-machine-learning
kubectl -n default get pods -l app.kubernetes.io/name=immich
kubectl -n default get pvc immich-data     # NFS bound?

# External Secrets resolving from Bitwarden?
kubectl -n security get externalsecret authentik
kubectl -n default get externalsecret
```

**Outcome decides the path:** if Authentik can't log in or its ExternalSecret/DB is unhealthy,
Phase 1 starts with debugging that; otherwise Phase 1 is purely additive (Google source).

---

## Phase 1 — Authentik: solid base + Google login

1. **Stabilize** (only if Phase 0 shows problems): resolve ExternalSecret/DB/redis issues so the
   admin UI logs in and `terraform plan` against Authentik works.
2. **Create the Google OAuth client** in Google Cloud Console (OAuth consent screen + Web
   client). Authorized redirect URI:
   `https://auth.${SECRET_DOMAIN}/source/oauth/callback/google/`.
   - **Secret handling:** store the client id + secret as a Bitwarden item (e.g.
     `google-oauth credentials`). I will only reference it by item/property in Terraform —
     **the owner creates and fills the Bitwarden item.**
3. **Add a Google source in Terraform** (`terraform/authentik/sources.tf`, new file or extend
   `main.tf`): an `authentik_source_oauth` with `provider_type = "google"`, wired to the
   enrollment/authentication flows, pulling `consumer_key`/`consumer_secret` from the Bitwarden
   item. Finish the `google_username` mapping (set username from the email local-part) instead
   of the current `return False` stub.
4. **Decide enrollment policy:** restrict sign-up to specific Google emails (you + wife) vs.
   open enrollment. Likely an allow-list policy bound to the enrollment flow.
5. `terraform apply`, then verify the Google button appears on `auth.${SECRET_DOMAIN}` and a
   Google login creates/links an Authentik user.

---

## Phase 2 — Immich SSO via Authentik

1. **Fix `application_immich.tf`** (finding #2): correct `meta_icon`, `meta_launch_url`, `slug`,
   and bind the right group (`users`/`media`, not `monitoring`).
2. **Reconcile the hostname** (finding #3): pick `photos.` or `immich.` and make the ingress
   host and the Authentik `allowed_redirect_uris` match. Keep `app.immich://oauth-callback`.
3. `terraform apply` to (re)create the Immich OAuth2 provider; the client id/secret land in
   Bitwarden via the `oidc_creds` module.
4. **Enable OAuth inside Immich** (finding #5): in Immich admin → Settings → OAuth, set issuer
   `https://auth.${SECRET_DOMAIN}/application/o/<immich-slug>/`, client id, client secret,
   button text, and enable auto-register. (Manual admin step — values come from the Bitwarden
   item created in step 3.)
5. **Test the full chain:** Google → Authentik → Immich web login, and the mobile app's
   "Login with OAuth" using `app.immich://oauth-callback`.

---

## Phase 3 — Immich manifest cleanup (low risk)

- Remove stale keys from `immich/app/configmap.yaml` (finding #4): `TYPESENSE_*`,
  `IMMICH_WEB_URL`, `IMMICH_SERVER_URL`, `IMMICH_MACHINE_LEARNING_URL`.
- Confirm the server/microservices `IMMICH_WORKERS_INCLUDE/EXCLUDE` split is still the intended
  topology for v2.x (it is valid; just confirm it's deliberate).
- Validate with `kubeconform` + `flux-local` the same way CI does before pushing.

---

## Phase 4 — Photo lifecycle (after identity is solid)

Target the wife's existing habit rather than replacing it. Today: phone → OneDrive → desktop →
manual organization. Previously Syncthing on her PC synced into a shared drive (not yet restored
on the NAS).

Proposed approach (to be detailed in its own plan doc when we get here):

1. **Restore Syncthing as the bridge to the NAS.** Run Syncthing (likely on the Synology, or as
   a cluster app writing to the NFS share) so her organized desktop folder syncs to a NAS
   directory — re-establishing the workflow she already knows.
2. **Expose that NAS directory to Immich as an External Library** (read-only import) so Immich
   indexes the curated photos without taking ownership of the files. This keeps her
   folder-based organization as the source of truth and Immich as the viewer/dedup/ML layer.
3. **Decide upload ownership:** her curated library via External Library vs. direct
   phone-upload into Immich. Likely: keep OneDrive→desktop→Syncthing→NAS for her, and use
   Immich mobile auto-backup only for accounts that want it.
4. Document the whole flow in `docs/` so it can be operated without me.

> Deferred deliberately — per the request, fix the Kubernetes services (Immich + Authentik)
> first, then build the lifecycle on the now-stable base.

---

## Secrets the owner must provision (I only reference them)

| Bitwarden item (suggested) | Used by | Notes |
|----------------------------|---------|-------|
| `google-oauth credentials` | Authentik Google source (Phase 1) | Google Cloud OAuth web-client id/secret. |
| `authentik-client-immich` | Immich OAuth2 (Phase 2) | **Auto-created** by the `oidc_creds` TF module; just used by Immich admin config. |

All other secrets (Authentik secret key, Postgres creds, MinIO) already exist as
ExternalSecret references and are owner-managed.

---

## Open questions for the owner

1. **Immich hostname:** standardize on `photos.${SECRET_DOMAIN}` (current ingress) or
   `immich.${SECRET_DOMAIN}` (current TF redirect URIs)?
2. **Who may enroll via Google** — allow-list specific emails, or open self-registration?
3. **GitHub source:** keep the existing GitHub login source, or remove it in favor of Google-only?
4. **Immich access exposure:** Immich ingress is class `internal` while Authentik is `external`.
   Should Immich stay LAN/VPN-only, or be reachable externally (changes the OAuth redirect and
   security posture)?
5. **Phase 4 Syncthing placement:** run on the Synology directly, or as a cluster app mounting
   the NFS share?
```
