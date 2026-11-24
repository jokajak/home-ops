# Homepage (service directory)

**Date:** 2026-11-24
**References:** <https://gethomepage.dev/configs/kubernetes/>,
<https://gethomepage.dev/installation/k8s/>

---

## Context

The household runs ~25 web UIs and nobody remembers them all. We want one page —
`homepage.${SECRET_DOMAIN}` — that lists every service with a one-line synopsis, and that keeps
itself current.

**Homepage** (gethomepage.dev) was chosen over Glance, Homarr and the Authentik launcher because
it discovers services from **Ingress annotations** via the Kubernetes API. The synopsis then lives
in Git next to each app's HelmRelease (same locality as the per-app `gatus.yaml` ConfigMaps), and
deleting an app deletes its card. Glance would need a hand-written merge script; Homarr is
UI-configured (click-ops); Authentik only lists SSO-fronted apps.

It lands in `observability`, next to `gatus`.

## Current State

- No dashboard is deployed. Several ingresses still carry `hajimari.io/*` annotations from a
  long-removed Hajimari — dead metadata.
- Ingress classes: `internal` (LAN, nginx) and `external`. external-dns publishes `internal`
  hosts automatically; no DNS work is needed for a new host.
- No Authentik forward-auth is used on any ingress today.

## Target State

1. `kubernetes/apps/observability/homepage/` — `ks.yaml` + `app/{helmrelease.yaml,
   kustomization.yaml, rbac.yaml, config/*.yaml, gatus.yaml}` using bjw-s `app-template`
   (same chart version as gatus, `3.7.3`), wired into `observability/kustomization.yaml`.
2. Homepage in `kubernetes.yaml` `mode: cluster`, `ingress: true`, discovering services from
   `gethomepage.dev/*` annotations. `services.yaml` stays empty — **no hand-maintained list**.
3. Every user-facing ingress below gets `gethomepage.dev/*` annotations; all `hajimari.io/*`
   annotations are removed repo-wide.
4. `homepage.${SECRET_DOMAIN}` on the `internal` class, TLS via the wildcard cert like siblings.
5. A gatus endpoint for Homepage itself (copy `ai/n8n/app/gatus.yaml`).
6. `observability/README.md` table row; one-line convention added to `CLAUDE.md` § Conventions:
   *"Ingresses for user-facing apps carry `gethomepage.dev/{enabled,name,description,group,icon}`
   annotations so they appear on `homepage.${SECRET_DOMAIN}`."*

No widgets (API-key-backed live stats) in this change — see Future Work.

## Files Summary

| File | Change |
| --- | --- |
| `kubernetes/apps/observability/homepage/ks.yaml` | new Flux Kustomization `cluster-apps-homepage` |
| `.../homepage/app/helmrelease.yaml` | new app-template release |
| `.../homepage/app/rbac.yaml` | ServiceAccount + read-only ClusterRole/Binding |
| `.../homepage/app/config/{settings,kubernetes,services,widgets,bookmarks,docker}.yaml` | configMapGenerator inputs |
| `.../homepage/app/gatus.yaml` | gatus endpoint ConfigMap |
| `.../homepage/app/kustomization.yaml` | resources + `configMapGenerator` |
| `kubernetes/apps/observability/kustomization.yaml` | add `./homepage/ks.yaml` |
| ~22 app HelmReleases / Ingress manifests | add `gethomepage.dev/*`, drop `hajimari.io/*` |
| `kubernetes/apps/observability/README.md`, `CLAUDE.md` | docs |

## Key Design Decisions

- **Discovery, not a list.** All per-service data comes from annotations. The only central config
  is layout (`settings.yaml`: title, group order, columns).
- **No auth on the page.** It's on the `internal` class (LAN only) and holds only links and
  descriptions. Every target app enforces its own login. Trade-off accepted: anyone on the LAN
  sees the hostname list, which DNS already exposes.
- **Pod status badges via explicit `gethomepage.dev/pod-selector`.** Homepage's default selector
  (`app.kubernetes.io/name=<ingress name>`) won't match for every chart, and a mismatch renders a
  misleading "not found" badge. Set the selector per ingress to the pods' real labels; if a chart
  makes that awkward, set `gethomepage.dev/pod-selector: ""` to disable the badge. Gatus remains
  the source of truth for health.
- **Single replica, `Recreate`**, no PVC (config is all ConfigMaps; Homepage keeps no state).
- **Reloader** annotation (`reloader.stakater.com/auto: "true"`) so config edits restart the pod.

## Implementation brief (for the implementing agent)

Work on branch `claude/relaxed-goldberg-el9z5c`. Read `CLAUDE.md` first; its secrets and
network-details rules are binding. Mirror `observability/gatus/` for layout, security context and
style.

1. **Image.** `ghcr.io/gethomepage/homepage`. Look up the latest stable release
   (`https://api.github.com/repos/gethomepage/homepage/releases/latest`) and pin that exact tag;
   it must be ≥ 2 weeks old. If the API is unreachable, say so and pick the newest tag you can
   verify from the docs — don't invent one.
2. **HelmRelease** (app-template 3.7.3):
   - container port `3000`; liveness/readiness `httpGet /api/healthcheck` on 3000 (confirm the
     path in the docs for the pinned version).
   - env: `HOMEPAGE_ALLOWED_HOSTS: homepage.${SECRET_DOMAIN:=internal}` (required since v1 —
     without it every request is rejected), `TZ: America/New_York`.
   - `serviceAccount: { create: false, name: homepage }` — the SA is in `rbac.yaml`
     (Homepage reads the API with the in-cluster token; `automountServiceAccountToken` must be
     true).
   - persistence: `emptyDir` at `/app/config` (Homepage writes `logs/` there), plus each
     ConfigMap file subPath-mounted read-only into `/app/config/<file>.yaml`. Homepage also writes
     to `/app/.next/cache`; either mount an `emptyDir` there and set `readOnlyRootFilesystem:
     true`, or leave it false — only claim the former if the docs confirm no other write paths.
   - run as non-root (`568:568`, `fsGroup: 568`), `capabilities: drop: [ALL]`,
     `allowPrivilegeEscalation: false`.
   - ingress `className: internal`, host `homepage.${SECRET_DOMAIN:=internal}`, TLS hosts as in
     siblings. Give Homepage itself a `gethomepage.dev/enabled: "false"` so it doesn't list itself.
3. **RBAC** — ClusterRole with only `get,list` on: `namespaces`, `pods`, `nodes` (core);
   `ingresses` (`networking.k8s.io`); `nodes`, `pods` (`metrics.k8s.io` — metrics-server is
   deployed). Check the docs' RBAC example for the pinned version and drop anything for Traefik
   or Gateway API (not used here); set the matching toggles off in `kubernetes.yaml`
   (`traefik: false`, `gateway: false`).
4. **Config files**: `kubernetes.yaml` (`mode: cluster`, `ingress: true`, the toggles above);
   `settings.yaml` (title "Home", `layout` ordering the groups below, sensible columns, `theme:
   dark`, `headerStyle: clean`); `services.yaml`, `bookmarks.yaml`, `docker.yaml` empty (`[]` or
   `{}` per the docs); `widgets.yaml` with only `kubernetes` (cluster CPU/mem) and `search`
   disabled or omitted — no external calls.
5. **Annotate ingresses.** For app-template charts the annotations go under
   `ingress.<id>.annotations`; for raw `ingress.yaml` under `metadata.annotations`; for
   grafana/authentik follow their chart's ingress values. Each gets:

   ```yaml
   gethomepage.dev/enabled: "true"
   gethomepage.dev/name: <Name>
   gethomepage.dev/description: <one line, ≤ 60 chars>
   gethomepage.dev/group: <Group>
   gethomepage.dev/icon: <name>.svg   # dashboard-icons name, or mdi-*/si-* per docs
   gethomepage.dev/pod-selector: <labels matching the app's pods>
   ```

   Where an ingress has several hosts, Homepage uses the first; set `gethomepage.dev/href` when
   that's wrong. Verify every `pod-selector` against the **rendered** pod labels (`task k8s:flate`
   renders the HelmReleases), not by assumption.

   | Group | Name | Host prefix | Manifest | Draft description |
   | --- | --- | --- | --- | --- |
   | Home | Home Assistant | `home` | `default/home-assistant/app/helm-release.yaml` | Home automation hub |
   | Home | Z-Wave JS | `zwave` | `default/zwave-js-ui/...` | Z-Wave device management |
   | Home | ESPHome | `esphome` | `default/esphome/app/helm-release.yaml` | Firmware for ESP devices |
   | Home | Matter Hub | `matterhub` | `home-automation/home-assistant-matter-hub/...` | Exposes HA entities over Matter |
   | Home | Inventory | `inventory` | `productivity/homebox/...` | House inventory, warranties, manuals |
   | Media | Photos | `photos` | `default/immich/app/server/...` | Photo and video backup (Immich) |
   | Media | Jellyfin | `jellyfin` | `default/jellyfin/...` | Movies, shows and music |
   | Media | Books | `calibre` | `media/calibre/...` | E-book library (Calibre) |
   | Productivity | Recipes | `recipes` | `productivity/mealie/app/helm-release.yaml` | Recipes and meal planning |
   | Productivity | Tasks | `tasks` | `productivity/vikunja/...` | Shared tasks and checklists |
   | Productivity | Paperless | `paperless` | `productivity/paperless/...` | Scanned-document archive with OCR |
   | Productivity | Wiki | `wiki` | `productivity/outline/...` | Household knowledge base |
   | Productivity | Garage | `garage` | `productivity/mygarage/...` | Vehicle maintenance log |
   | Productivity | Subscriptions | `subs` | `productivity/wallos/app/helm-release.yaml` | Subscription and bill tracker |
   | Productivity | Git | `git` | `productivity/forgejo/...` | Git forge (Forgejo) |
   | AI | Assistant | `chatgpt` | `ai/hearthai/...` (Open WebUI ingress) | Household AI assistant |
   | AI | Chat | `chat` | `ai/mindroom/app/ingress.yaml` (`mindroom-chat`) | Mindroom chat (trial) |
   | AI | n8n | `n8n` | `ai/n8n/...` | Workflow automation |
   | Downloads | MeTube | `metube` | `downloads/metube/...` | Download video/audio via yt-dlp |
   | Downloads | qBittorrent | `qbittorrent` | `downloads/qbittorrent/...` | BitTorrent client (via VPN) |
   | Games | Minecraft RCON | `minecraft-rcon` | `games/minecraft-rcon-web/app/ingress.yaml` | Minecraft server admin |
   | Admin | Authentik | `auth` | `security/authentik/...` | Single sign-on |
   | Admin | Grafana | `grafana` | `observability/grafana/...` | Metrics and log dashboards |
   | Admin | Status | `status` | `observability/gatus/...` | Service health (Gatus) |
   | Admin | UniFi | `unifi` | `default/unifi/...` | Network controller |
   | Admin | MinIO | `minio` | `storage/minio/...` | Object storage console |
   | Admin | LiteLLM | `llm` | `ai/hearthai/...` (litellm ingress) | LLM router admin |
   | Admin | Mindroom | `mindroom-dashboard` | `ai/mindroom/app/ingress.yaml` | Mindroom runtime dashboard |

   **Do not annotate** (machine endpoints, not UIs): `echo-server`, `flux-webhook`, MinIO's `s3`
   host (same ingress as console — use `href`), `matrix`, the apex Matrix discovery ingress.

   Remove every `hajimari.io/*` annotation in the repo (`grep -rn hajimari kubernetes/`).
6. **Validate**: `task k8s:flate`, `yamllint .`, `pre-commit run --all-files`. All must pass;
   report output faithfully. Don't claim runtime verification — there's no cluster here.
7. **Commit and push** to `claude/relaxed-goldberg-el9z5c` in two commits (Homepage app;
   ingress annotations + docs). No PR.
8. **Report back**: pinned tag + how verified, any table row you changed or couldn't place, any
   ingress where you disabled the pod badge and why, and validation output.

Constraints: no hardcoded IPs/CIDRs/domains (use `${SECRET_DOMAIN:=internal}`); no HA machinery
(PDBs, replicas, anti-affinity); no secrets needed for this change.

## Owner Steps

None required. After merge: Flux reconciles, external-dns publishes the internal host.

## Verification

1. `flux get ks cluster-apps-homepage` Ready; pod Running.
2. `https://homepage.${SECRET_DOMAIN}` loads from the LAN and shows every service in the table,
   grouped, with descriptions.
3. Status badges show "running" — any "not found" means a wrong `pod-selector`.
4. Gatus shows the new Homepage endpoint green.

## Risks

- **`HOMEPAGE_ALLOWED_HOSTS` wrong** → page returns host-validation errors. Fix the env var.
- **RBAC too narrow** → discovery silently returns nothing; check pod logs for 403s.
- **Annotation churn** touches ~22 HelmReleases at once → each does a Helm upgrade. Only ingress
  metadata changes, so pods don't restart.

## Rollback

Revert the merge. Annotations are inert without Homepage, so a partial rollback (remove only the
app) is also safe.

## Future Work

- Widgets for Immich, Jellyfin, Paperless, etc. — each needs an API key via `ExternalSecret`
  (Bitwarden item per app) and is an owner step to mint.
- Optional Authentik forward-auth if the page ever goes on the `external` class.
