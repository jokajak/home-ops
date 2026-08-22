# Forgejo Git Forge

**Date:** 2026-08-22
**Reference:** <https://forgejo.org/docs/latest/> · <https://code.forgejo.org/forgejo-helm/forgejo-helm>

---

## Context

The cluster has no self-hosted git. Personal repositories, scratch projects, and mirrors of
the things this cluster depends on all live on GitHub only. A local forge gives a private
remote that survives an outage of, or a policy change at, a third party — and a place to
keep repositories that were never meant to leave the house.

Forgejo was chosen over Gitea and SourceHut:

- **vs Gitea** — same codebase genealogically (Forgejo forked Gitea in late 2022), so the
  feature set at this scale is indistinguishable. The tiebreaker is the migration
  asymmetry: Gitea → Forgejo is a supported drop-in, Forgejo → Gitea increasingly is not.
  Starting on Forgejo keeps both doors open. Forgejo is also stewarded by a non-profit
  (Codeberg e.V.) rather than a company with a CLA.
- **vs SourceHut** — excellent software, wrong shape for this cluster. It is six-plus
  services each wanting its own Postgres, distributed as distro packages with no official
  container images (a non-starter on Talos), requiring *inbound* mail routing for its
  patch workflow, and running CI in QEMU VMs rather than containers.

Forgejo fits the existing building blocks with nothing new at the infrastructure layer: it
wants Postgres (CNPG), a Redis-protocol cache (the shared dragonfly), a durable repository
tree (NFS on the NAS), and it speaks OIDC (Authentik).

It lands in the `productivity` namespace next to `mealie`, `paperless`, and `wallos`.

---

## Current State

- **Namespace**: `productivity` holds `mealie`, `paperless`, and `wallos`; its
  `namespace.yaml` already sets `volsync.backube/privileged-movers: "true"`.
- **Postgres**: a CNPG operator plus the barman-cloud plugin in `database`. An app's own
  Postgres is co-located with the app, not centralized (`paperless-database`,
  `immich-database`).
- **Cache**: one shared `Dragonfly` at `dragonfly.database.svc.cluster.local.:6379`, no
  auth, per-app DB index. Index 0 is authentik/open-webui, 1 is immich, 2 is paperless.
- **Storage**: static `Retain` NFS PVs with a per-app sentinel storage class
  (`nfs-mealie`, `nfs-paperless`, …) for durable data; `openebs-hostpath` for CNPG volumes.
- **Backups**: `kubernetes/components/volsync` (restic → the MinIO `backups` bucket) for
  PVCs; barman-cloud → the MinIO `databases` bucket for CNPG.
- **Routing**: nginx `internal` IngressClass, wildcard TLS. No Gateway API yet (see
  `2026-02-08-cilium-gateway-api-migration.md`) — this app uses `Ingress` like its peers
  and migrates with them.
- **Load balancers**: cilium L2 announcements; per-service `loadBalancerIP` fed by a
  `${LB_*_CIDR_V4}` substitution variable (`unifi`, `minecraft`).
- **Internal DNS**: `k8s-gateway` answers for `${SECRET_DOMAIN}`, resolving Ingress hosts
  and `LoadBalancer` Services annotated with `external-dns.alpha.kubernetes.io/hostname`.
  (`external-dns` itself only watches `crd` and `ingress` sources, so a Service annotation
  is served by k8s-gateway, not external-dns.)
- **SSO**: `terraform/authentik/application_<app>.tf` + the `oidc_creds` module, which
  mints the client credentials into Bitwarden as `authentik-client-<app>`.

---

## Target State

- Forgejo at `https://git.${SECRET_DOMAIN}`, behind the `internal` IngressClass.
- Git-over-SSH at `git@git-ssh.${SECRET_DOMAIN}:22`, on a dedicated cilium
  `LoadBalancer` address from `${LB_FORGEJO_CIDR_V4}`.
- Its own two-instance CNPG Postgres, backed up to MinIO by barman-cloud.
- Repository tree on a static `Retain` NFS PV, backed up hourly by VolSync.
- Cache, session, and queue on the shared dragonfly (indexes 3, 4, 5).
- Login via Authentik OIDC, with a local admin as the break-glass account.
- Gatus endpoints via the shared `guarded` template.

---

## Implementation Steps

### Step 1 — App skeleton

`kubernetes/apps/productivity/forgejo/ks.yaml`, a Flux `Kustomization` in the house style:
`targetNamespace: productivity`, the `volsync` component, and `dependsOn` covering
external-secrets, CNPG, the barman plugin, dragonfly, and the NFS CSI driver.

Wire `./forgejo/ks.yaml` into `kubernetes/apps/productivity/kustomization.yaml`.

### Step 2 — Storage

A static `Retain` NFS `PersistentVolume` (`nfs-forgejo`) and a matching `PersistentVolumeClaim`
(`forgejo`), following `nfs-paperless`. One claim holds everything Forgejo puts under
`/data`: the bare repositories, LFS objects, attachments, avatars, and the indexers.

The NFS export must be owned `1000:1000` — the rootless image runs as uid/gid 1000 with no
internal remapping.

### Step 3 — Database

A CNPG `Cluster` (`forgejo-database`), an `ObjectStore` pointing at the shared MinIO
`databases` bucket, and a daily `ScheduledBackup` — a direct copy of the paperless trio.
No `managed.roles` block, so CNPG mints the `forgejo-database-app` secret itself and no
externally-supplied DB credential is needed.

### Step 4 — Application

The official Forgejo chart, pulled from its OCI registry via a `HelmRepository` of
`type: oci`. Chart 17.x removed the bundled Postgres/Valkey subcharts entirely, so there is
nothing to disable — it expects exactly the external-services layout this cluster already has.

Notable values:

- `image.rootless: true` (the chart default), so `SSH_LISTEN_PORT` is 2222 inside the pod
  while the Service still publishes 22.
- `service.ssh` as a `LoadBalancer` on `${LB_FORGEJO_CIDR_V4}`, annotated with its own
  `git-ssh.${SECRET_DOMAIN}` hostname for k8s-gateway.
- Database host/name inline; `USER` and `PASSWD` injected as `FORGEJO__DATABASE__*`
  environment variables from the CNPG-minted secret via `gitea.additionalConfigFromEnvs`.
- `gitea.oauth` with `existingSecret`, which the chart turns into `GITEA_OAUTH_KEY_0` /
  `GITEA_OAUTH_SECRET_0` and feeds to `forgejo admin auth add-oauth` on startup.

The chart's top-level values key is still `gitea:` — an inherited name, not a mistake.

### Step 5 — Secrets

Three `ExternalSecret`s, matching the paperless layout:

| Secret | Store | Bitwarden item | Purpose |
| --- | --- | --- | --- |
| `minio-forgejo-pgsql` | `bitwarden-login` | `minio-tf-databases` | barman-cloud S3 credentials |
| `forgejo-admin-secret` | `bitwarden-login` | `forgejo credentials` | local break-glass admin |
| `forgejo-oidc-secret` | `bitwarden-login` | `authentik-client-forgejo` | Authentik client id/secret |

Both Bitwarden items are created by OpenTofu (Step 6) — there is no manual item to populate.

### Step 6 — OpenTofu

- `terraform/bitwarden/main.tf` — a `forgejo credentials` item with a generated admin
  password, following the paperless block.
- `terraform/authentik/application_forgejo.tf` — the `oidc_creds` module, an
  `authentik_provider_oauth2` named `forgejo-provider`, the application, and a policy
  binding granting the `users` group access.

The redirect URI is `https://git.${SECRET_DOMAIN}/user/oauth2/authentik/callback`, where the
`authentik` path segment is the auth-source name registered by the chart's `gitea.oauth[0].name`.

---

## Files Summary

| File | Purpose |
| --- | --- |
| `kubernetes/apps/productivity/forgejo/ks.yaml` | Flux Kustomization + volsync component |
| `.../forgejo/app/kustomization.yaml` | resource list + gatus template |
| `.../forgejo/app/helmrepository.yaml` | OCI HelmRepository for the chart |
| `.../forgejo/app/helmrelease.yaml` | the chart and its values |
| `.../forgejo/app/externalsecret.yaml` | MinIO, admin, and OIDC secrets |
| `.../forgejo/app/pvc.yaml` | static NFS PV + PVC |
| `.../forgejo/app/database/*.yaml` | CNPG Cluster, ObjectStore, ScheduledBackup |
| `kubernetes/apps/productivity/kustomization.yaml` | wire in the app |
| `kubernetes/apps/productivity/README.md` | document the app |
| `terraform/authentik/application_forgejo.tf` | Authentik provider/application/binding |
| `terraform/bitwarden/main.tf` | `forgejo credentials` item |

---

## Key Design Decisions

**The official chart, not `app-template`.** Forgejo is a single container, which would
normally argue for `app-template` and the house convention. But the chart's real work is
generating `app.ini` from structured values, wiring the OAuth source through
`forgejo admin auth add-oauth` on startup, and handling the rootless SSH port shim. All
three are fiddly to reproduce by hand and easy to get subtly wrong. Chart 17.x also dropped
its bundled databases, which removes the usual objection to upstream forge charts.

**A separate hostname for SSH.** `git.${SECRET_DOMAIN}` resolves to the nginx ingress
controller, which does not listen on 22. Pointing the SSH `LoadBalancer` at the same name
would break one protocol or the other, so SSH gets `git-ssh.${SECRET_DOMAIN}` and
`SSH_DOMAIN` is set to match. Clone URLs shown in the UI are therefore
`git@git-ssh.${SECRET_DOMAIN}:owner/repo.git`. The alternative — a shared address with the
ingress controller doing TCP passthrough on 22 — buys a prettier URL for real added
complexity in a shared component.

**One NFS claim, not several.** Forgejo keeps repositories, LFS, attachments, avatars, and
indexers all under `/data`. Splitting them across claims would gain nothing: they share a
backup cadence and a failure domain.

**Local storage rather than MinIO for LFS and attachments.** The chart can put both in S3,
but that means another ExternalSecret and another bucket for data that is already on RAID
and already backed up by VolSync. Worth revisiting if LFS usage grows.

**Actions disabled.** Forgejo Actions is GitHub-Actions-compatible but needs a
`forgejo-runner` deployment, its own registration token, and a decision about privileged
container execution. Out of scope here; `actions.ENABLED` is explicitly `false` so turning
it on is a deliberate act rather than a default.

**No mailer.** There is no SMTP infrastructure in this cluster. Notification email and
self-service password reset are therefore unavailable; the local admin resets passwords.
`ENABLE_NOTIFY_MAIL` is explicitly false so the failure mode is "no mail" rather than
"queued mail retrying forever".

**GitHub stays the Flux source of truth.** This repository is what Flux reconciles, and it
is hosted on GitHub. Making the in-cluster forge the primary remote for `home-ops` would
mean the cluster could not reconcile itself while the forge that holds its manifests is
down. Forgejo is a mirror target and a home for other repositories, not the bootstrap root.

**Registration is external-only.** `DISABLE_REGISTRATION` stays false while
`ALLOW_ONLY_EXTERNAL_REGISTRATION` is true, so accounts can only be created through the
Authentik round-trip — the same posture as paperless (`ALLOW_SIGNUPS: false` +
`SOCIAL_AUTO_SIGNUP: true`).

---

## Owner Actions

Things that cannot be expressed in this repository and must be done out of band:

1. **Substitution variable** — add `LB_FORGEJO_CIDR_V4` to `cluster-secrets` with the
   address the SSH `LoadBalancer` should claim, inside the cilium L2 pool.
2. **NFS export** — `mkdir -p <nfs-path>/forgejo && chown -R 1000:1000 <nfs-path>/forgejo`
   on the NAS.
3. **OpenTofu apply** — `terraform/bitwarden` then `terraform/authentik`, so the
   `forgejo credentials` and `authentik-client-forgejo` items exist before Flux reconciles.

---

## Verification

```bash
# 0. static checks, the way CI does them
task k8s:flate
yamllint .
pre-commit run --all-files

# 1. out-of-band prerequisites (nothing works before these)
#    LB_FORGEJO_CIDR_V4 in cluster-secrets
#    on the NAS: mkdir -p <nfs-path>/forgejo && chown -R 1000:1000 <nfs-path>/forgejo
#    tofu apply in terraform/bitwarden and terraform/authentik

# 2. reconcile
flux reconcile kustomization cluster-apps-forgejo --with-source

# 3. secrets and database
kubectl -n productivity get externalsecret forgejo-admin forgejo-oidc minio-forgejo-pgsql
kubectl -n productivity get cluster forgejo-database
kubectl -n productivity get backup -l cnpg.io/cluster=forgejo-database

# 4. app
kubectl -n productivity rollout status deploy/forgejo
#    browse https://git.${SECRET_DOMAIN}
#      - local admin login works
#      - "Authentik" button completes the OIDC round-trip

# 5. ssh
kubectl -n productivity get svc forgejo-ssh   # EXTERNAL-IP == LB_FORGEJO_CIDR_V4
ssh -T git@git-ssh.${SECRET_DOMAIN}           # greets by username once a key is added
#    create a repo, push to it over both https and ssh

# 6. backups
kubectl -n productivity get replicationsource forgejo
#    Gatus shows `forgejo` green in both `internal` and `internal-guarded`
```

---

## Rollback

Remove `./forgejo/ks.yaml` from `kubernetes/apps/productivity/kustomization.yaml` and let
Flux prune. The NFS PV is `Retain` and the MinIO backups are untouched, so the repository
tree and database survive; re-adding the app re-binds the same claim.
