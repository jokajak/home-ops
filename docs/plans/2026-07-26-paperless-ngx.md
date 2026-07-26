# Paperless-ngx Document Archive

**Date:** 2026-07-26
**Reference:** <https://docs.paperless-ngx.com/>

---

## Context

The cluster has no document management. Scans, statements, and receipts have nowhere to
live that is searchable, tagged, and backed up. Paperless-ngx fills that gap: it watches a
consume directory, OCRs whatever lands there, extracts a date and correspondent, and stores
the searchable result.

It is a good fit for the existing building blocks — it wants Postgres (CNPG), a Redis-protocol
broker (the shared dragonfly), a durable document tree (NFS on the NAS), and it speaks OIDC
(Authentik). Nothing new has to be introduced at the infrastructure layer.

It lands in the `productivity` namespace next to `mealie` and `wallos`.

---

## Current State

- **Namespace**: `productivity` holds `mealie` and `wallos`; its `namespace.yaml` already sets
  `volsync.backube/privileged-movers: "true"`.
- **Postgres**: a CNPG operator plus the barman-cloud plugin in `database`. Per
  `kubernetes/apps/database/README.md`, an app's own Postgres is co-located with the app, not
  centralized — `immich-database` and `home-assistant-db` both follow that.
- **Broker**: one shared `Dragonfly` at `dragonfly.database.svc.cluster.local.:6379`, no auth,
  per-app DB index. Index 0 is authentik/open-webui, index 1 is immich.
- **Storage**: static `Retain` NFS PVs with a per-app sentinel storage class (`nfs-mealie`,
  `nfs-immich`, …) for durable data; `openebs-hostpath` for CNPG volumes.
- **Backups**: `kubernetes/components/volsync` (restic → the shared MinIO `backups` bucket) for
  PVCs; barman-cloud → the MinIO `databases` bucket for CNPG.
- **Routing**: nginx `internal` IngressClass, wildcard TLS served by the controller's
  `default-ssl-certificate`. No Gateway API, no forward-auth — SSO is per-app OIDC.
- **SSO**: `terraform/authentik/application_<app>.tf` + the `oidc_creds` module, which puts the
  client credentials in Bitwarden as `authentik-client-<app>`.

Nothing named `paperless` existed anywhere in the repo before this change.

---

## Target State

- `https://paperless.${SECRET_DOMAIN}` serves paperless-ngx v3.
- Documents live on the NAS at `${SECRET_NFS_PATH}/paperless`, backed up hourly by VolSync.
- Its Postgres is a dedicated 2-instance CNPG cluster with daily backups to MinIO.
- Office documents and e-mail are consumable via Gotenberg + Tika sidecars.
- Login is either the local superuser or Authentik OIDC.

---

## Implementation Steps

### Step 1 — App skeleton

New files:

```
kubernetes/apps/productivity/paperless/
├── ks.yaml                     # Flux Kustomization, pulls in the volsync component
└── app/
    ├── kustomization.yaml      # namespace + common labels + resource list
    ├── externalsecret.yaml     # 4 ExternalSecrets (see Step 5)
    ├── pvc.yaml                # static NFS PV + PVC
    ├── helmrelease.yaml        # paperless-ngx itself
    ├── gotenberg.yaml          # Gotenberg sidecar service
    ├── tika.yaml               # Apache Tika sidecar service
    └── database/
        ├── kustomization.yaml
        ├── cluster.yaml
        ├── objectstore.yaml
        └── scheduledbackup.yaml
```

Modified files:

- `kubernetes/apps/productivity/kustomization.yaml` — add `./paperless/ks.yaml`.
- `kubernetes/apps/productivity/README.md` — add the app row.

The app is called **`paperless`** everywhere — directory, `APP`, hostname, PVC, restic repo,
Gatus endpoint — so `${APP}` flows through the volsync and Gatus templates untouched and no
`GATUS_SUBDOMAIN` or `VOLSYNC_CLAIM` override is needed.

`ks.yaml` depends on external-secrets, the CNPG operator, the barman plugin, the dragonfly
cluster, and the NFS CSI driver:

```yaml
  components:
    - ../../../../components/volsync
  postBuild:
    substitute:
      APP: paperless
      VOLSYNC_PUID: "1000"
      VOLSYNC_PGID: "1000"
  dependsOn:
    - name: cluster-apps-external-secrets
    - name: cluster-apps-cloudnative-pg
    - name: cluster-apps-cnpg-barman-plugin
    - name: dragonfly-cluster
    - name: cluster-apps-csi-driver-nfs
```

### Step 2 — Storage

One static `Retain` PV and one PVC, both named for the app, following `mealie/app/pvc.yaml`
(which keeps the NAS path behind `${SECRET_NFS_PATH}` rather than hardcoding a share):

```yaml
  nfs:
    server: ${SECRET_NFS_SERVER:=192.168.1.1}
    path: "${SECRET_NFS_PATH:=/data}/paperless"
```

The image declares four volumes; all four are served from this one claim by `subPath`:

| subPath | mount |
| --- | --- |
| `data` | `/usr/src/paperless/data` (search index, classification model) |
| `media` | `/usr/src/paperless/media` (the documents themselves) |
| `consume` | `/usr/src/paperless/consume` (drop zone) |
| `export` | `/usr/src/paperless/export` |

> **Gotcha:** `fsGroup` is not applied to NFS volumes. The four directories must exist on the
> NAS and be owned by `1000:1000` before the first reconcile, or the pod will crash-loop on
> permission errors.

VolSync backs the single claim up hourly to `s3://backups/volsync/paperless`.

### Step 3 — Database

A dedicated CNPG `Cluster` in `app/database/`, modelled on `home-assistant/app/database/` —
the simpler variant with **no** `managed.roles`, so CNPG mints `paperless-database-app`
carrying `host`/`port`/`dbname`/`username`/`password` and there is no externally-supplied DB
credential to manage:

```yaml
  plugins:
    - name: barman-cloud.cloudnative-pg.io
      isWALArchiver: true
      parameters:
        barmanObjectName: paperless-objectstore
        serverName: paperless-v1
  bootstrap:
    initdb:
      database: paperless
      owner: paperless
```

`ObjectStore` writes to `s3://databases/` with a 30d retention; `ScheduledBackup` runs
`@daily`. No new MinIO bucket — the shared `databases` bucket and its `minio-tf-databases`
credential already exist.

### Step 4 — Application

app-template `3.7.3`, one controller, one container. The upstream image runs the webserver,
celery worker and scheduler under s6, so no separate worker Deployment is needed.

```yaml
  strategy: Recreate      # single writer against NFS and the Tantivy index
  image:
    repository: ghcr.io/paperless-ngx/paperless-ngx
    tag: v3.0.3
```

The settings worth calling out:

```yaml
  PAPERLESS_REDIS: redis://dragonfly.database.svc.cluster.local.:6379/2
  PAPERLESS_CONSUMER_POLLING_INTERVAL: "60"
  PAPERLESS_TIKA_ENABLED: "1"
  PAPERLESS_TIKA_ENDPOINT: http://paperless-tika.productivity.svc.cluster.local:9998
  PAPERLESS_TIKA_GOTENBERG_ENDPOINT: http://paperless-gotenberg.productivity.svc.cluster.local:3000
  PAPERLESS_APPS: allauth.socialaccount.providers.openid_connect
```

> **Gotcha:** v3.0 removed `PAPERLESS_CONSUMER_POLLING` and replaced the inotify-based consumer
> with `watchfiles`. The replacement knob is **`PAPERLESS_CONSUMER_POLLING_INTERVAL`** (seconds,
> `0` = native notifications). It must be non-zero here: inotify does not work over NFS, so with
> the default the consume directory is silently never scanned.

DB connection values come from the CNPG-generated secret:

```yaml
  PAPERLESS_DBHOST:
    valueFrom:
      secretKeyRef:
        name: paperless-database-app
        key: host
```

The v3 image supports true rootless operation — the process starts directly as the supplied
uid/gid with no internal remapping — so the pod runs `runAsNonRoot` as `1000:1000` and the
legacy `USERMAP_UID`/`USERMAP_GID` remapping variables are **not** set. (The one restriction is
that rootless is incompatible with extra OCR language packs via `PAPERLESS_OCR_LANGUAGES`;
`PAPERLESS_OCR_LANGUAGE: eng` is built in and unaffected.)

Ingress is `className: internal` on `paperless.${SECRET_DOMAIN}` with
`proxy-body-size: "0"` and `proxy-request-buffering: "off"`, the same treatment immich gets for
large uploads.

Gotenberg and Tika are two more small app-template HelmReleases in the same namespace. Because
each declares a single service, the bjw-s chart names the Service after the release, so they
resolve as `paperless-gotenberg` and `paperless-tika`. Gotenberg is configured exactly as
upstream's compose file recommends, passing the flags as **`args`** so the image's `tini`
entrypoint is preserved:

```yaml
  args:
    - gotenberg
    - --chromium-disable-javascript=true
    - --chromium-allow-list=file:///tmp/.*
```

### Step 5 — Secrets

Four `ExternalSecret`s. Two Bitwarden stores are involved because `bitwarden-login` reads an
item's username/password while `bitwarden-fields` reads its custom fields.

| ExternalSecret | Store | Bitwarden item | Produces |
| --- | --- | --- | --- |
| `minio-paperless-pgsql` | `bitwarden-login` | `minio-tf-databases` | S3 creds for the barman ObjectStore |
| `paperless-admin` | `bitwarden-login` | `paperless credentials` | `PAPERLESS_ADMIN_USER`, `PAPERLESS_ADMIN_PASSWORD` |
| `paperless-fields` | `bitwarden-fields` | `paperless credentials` → `secret_key` | `PAPERLESS_SECRET_KEY` |
| `paperless-oidc` | `bitwarden-login` | `authentik-client-paperless` | `PAPERLESS_SOCIALACCOUNT_PROVIDERS` |

django-allauth takes its whole provider configuration as one JSON blob, so that JSON is
assembled inside the ExternalSecret template — the client secret never appears in Git:

```yaml
  target:
    template:
      engineVersion: v2
      data:
        PAPERLESS_SOCIALACCOUNT_PROVIDERS: >-
          {"openid_connect": {"APPS": [{"provider_id": "authentik",
          "name": "Authentik",
          "client_id": "{{ .client_id }}",
          "secret": "{{ .client_secret }}",
          "settings": {"server_url":
          "https://auth.${SECRET_DOMAIN:=internal}/application/o/paperless-provider/.well-known/openid-configuration"}}]}}
```

### Step 6 — OpenTofu

New file `terraform/authentik/application_paperless.tf`, mirroring `application_wallos.tf`:
the `oidc_creds` module (which creates the Bitwarden item `authentik-client-paperless`), an
`authentik_provider_oauth2` named `paperless-provider`, the `authentik_application`, and a
`users` policy binding. The callback registered in `allowed_redirect_uris` is
`https://paperless.${var.domain}/accounts/oidc/authentik/login/callback/` — the `authentik`
path segment is the `provider_id` from the JSON above and the two must stay in sync.

Because `slug = authentik_provider_oauth2.paperless_oauth.name`, the issuer path is
`/application/o/paperless-provider/`.

`site_admin.tf` gains an `admins_paperless` binding (access only — see below).

`terraform/bitwarden/main.tf` gains a `paperless credentials` item: username `admin`, a random
password, and a hidden `secret_key` field. No Postgres credential is stored there — CNPG mints
its own.

---

## Files Summary

| Action | Path |
| --- | --- |
| CREATE | `kubernetes/apps/productivity/paperless/ks.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/kustomization.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/externalsecret.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/pvc.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/helmrelease.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/gotenberg.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/tika.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/database/kustomization.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/database/cluster.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/database/objectstore.yaml` |
| CREATE | `kubernetes/apps/productivity/paperless/app/database/scheduledbackup.yaml` |
| CREATE | `terraform/authentik/application_paperless.tf` |
| CREATE | `docs/plans/2026-07-26-paperless-ngx.md` |
| MODIFY | `kubernetes/apps/productivity/kustomization.yaml` |
| MODIFY | `kubernetes/apps/productivity/README.md` |
| MODIFY | `terraform/authentik/site_admin.tf` |
| MODIFY | `terraform/bitwarden/main.tf` |
| MODIFY | `docs/authentik-sso-integration.md` |

---

## Key Design Decisions

- **Dedicated CNPG cluster, not the shared `postgres`.** `kubernetes/apps/database/README.md`
  prescribes co-locating an app's database with the app to keep the blast radius local. Both
  immich and home-assistant already do this.
- **No `managed.roles`.** Letting CNPG generate `paperless-database-app` removes an entire
  Bitwarden item and ExternalSecret from the design, and the app reads host/port/dbname from
  the same secret it reads the password from.
- **One PVC with `subPath` mounts, not four PVCs.** The four directories are one logical
  archive, they back up as one restic repo, and the volsync component takes a single
  `VOLSYNC_CLAIM`. Splitting them would mean four ReplicationSources for no benefit.
- **`data/` on NFS rather than `openebs-hostpath`.** The search index could be rebuilt after a
  restore, but keeping it on the backed-up claim means a restore is complete without an
  out-of-band reindex. The cost is Tantivy over NFS, which is acceptable for a single writer.
- **Rootless rather than `USERMAP_*`.** v3 images start directly as the supplied uid/gid, so the
  repo's usual `runAsNonRoot` posture works without the image's privilege-dropping shim.
- **`strategy: Recreate`.** Two replicas would have two writers on the same NFS tree and the
  same Tantivy index; a rolling update would briefly do the same.
- **Local superuser kept alongside SSO.** Paperless cannot derive "superuser" from an OIDC
  claim, so the Bitwarden-backed local admin remains the only way to administer it — and the
  only way in if Authentik is down. `PAPERLESS_ACCOUNT_ALLOW_SIGNUPS` stays `false` so the
  regular login form cannot be used to self-register.
- **Shared dragonfly, index 2.** Consistent with immich (1) and authentik/open-webui (0); no
  per-app broker to run or back up.

---

## Verification

No cluster access from the authoring environment — these are the owner's steps after merge.

```bash
# 0. static checks, the way CI does them
task k8s:kubeconform
bash scripts/validate-ks-paths.sh kubernetes
yamllint .
(cd terraform/authentik && tofu fmt -check && tofu validate)

# 1. out-of-band prerequisites (nothing works before these)
(cd terraform/bitwarden && tofu apply)   # creates "paperless credentials"
(cd terraform/authentik && tofu apply)   # creates "authentik-client-paperless"
#    on the NAS: mkdir -p <nfs-path>/paperless/{data,media,consume,export}
#                chown -R 1000:1000 <nfs-path>/paperless

# 2. reconcile
flux reconcile ks cluster-apps --with-source
flux get ks cluster-apps-paperless                   # expect: Ready

# 3. secrets and database
kubectl -n productivity get externalsecret           # expect: 4x SecretSynced
kubectl -n productivity get cluster paperless-database   # expect: 2 instances healthy
kubectl -n productivity get backup                   # expect: first backup Completed

# 4. app
kubectl -n productivity get pods -l app.kubernetes.io/name=paperless
#    browse https://paperless.${SECRET_DOMAIN}
#      - local admin login works
#      - "Authentik" button completes the OIDC round-trip

# 5. consumption
#    drop a PDF into <nfs-path>/paperless/consume -> appears in the UI within ~60s
#    drop a .docx  -> also consumed (proves Tika + Gotenberg)

# 6. backups
kubectl -n productivity get replicationsource paperless   # expect: lastSyncTime set within the hour
#    Gatus shows `paperless` green in both `internal` and `internal-guarded`
```

---

## Rollback

Remove `./paperless/ks.yaml` from `kubernetes/apps/productivity/kustomization.yaml` and
reconcile; Flux prunes the namespace's paperless resources. The NFS PV is
`persistentVolumeReclaimPolicy: Retain`, the CNPG PVCs are not deleted with the Cluster, and
both the restic and barman repositories stay in MinIO — so the documents and the database
survive a teardown and a later re-apply re-binds to them.
