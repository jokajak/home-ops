# Deploying hearthai as one release

> Status: **READY TO RECONCILE** · 2026-09-10 · Owner: Josh · Author: Claude
>
> Open WebUI, litellm, meridian and hearthmem were four app directories that only ever worked as
> a set. hearthai now packages them as one chart; this repo stops describing the product and
> supplies the site inputs — URLs, Secrets, claims, and Postgres.

## The finding

The four had one compatibility surface and four owners of it. Open WebUI only works against a
litellm that serves the model names its picker shows; litellm's `claude-*` routes only work
against a meridian it can reach, at an address hardcoded in a ConfigMap here; hearthmem is
hearthai's own service, versioned with hearthai. Every one of those relationships was expressed
as a string in a home-ops manifest — `OPENAI_API_BASE_URLS`, `api_base`, an image tag bumped by
Renovate on its own schedule — and nothing checked that the four agreed.

Upstream fixed this at the source: [`jokajak/hearthai`](https://github.com/jokajak/hearthai)
`deploy/charts/hearthai` bundles all four, generates the internal URLs from the release name, and
carries the model catalogue in the chart. The import is deliberately conservative —
`files/litellm-config.yaml` is this repo's ConfigMap value byte-for-byte, with a SHA-256
regression test, and the only rewrite is meridian's address.

So the question is not whether to adopt it, but what stays here. **A cluster supplies what only a
cluster can.**

## The split

| hearthai owns | home-ops owns |
| --- | --- |
| Images, tags, probes, resources, security contexts | Public URLs and the ingress class |
| The litellm model catalogue and its env contract | Every Secret (ExternalSecret → Bitwarden) |
| Open WebUI's environment and auth modes | The identity provider and its OIDC client |
| Internal service discovery between the four | The four PersistentVolumeClaims and their backups |
| meridian's CiliumNetworkPolicy (release-scoped) | **Postgres** |
| Which components exist at all | Node placement, Gatus probes, when Flux reconciles |

## Postgres stays ours

The chart defaults `postgres.enabled: true` and will render its own single-instance CNPG
`Cluster`. This deployment sets it **false**.

Not on principle — on data. The `litellm` database and role already exist on the shared cluster in
the `database` namespace, holding the proxy's virtual keys, budgets and spend history, including
the key Open WebUI authenticates with. That is exactly the arrangement the
[CNPG consolidation](2026-08-24-cnpg-consolidation.md) argued for: a database and a role on one
shared server, created idempotently by a `postgres-init` init container from a Bitwarden-held
credential, rather than a per-app cluster. Nothing about packaging the applications together
changes that argument, and switching would be a backup/restore cutover for no gain.

Concretely, with `postgres.enabled: false`:

- No `Cluster` is rendered by the chart. Verified against `helm template`.
- litellm keeps its `postgres-init` init container (the chart only omits it in bundled-Postgres
  mode) and takes `DATABASE_URL` from `litellm-secret`, unchanged.
- `cluster-apps-hearthai` keeps litellm's old `dependsOn: cluster-apps-cloudnative-pg-cluster` —
  the shared cluster must answer before init-db runs.

If the shared cluster ever needs to shed litellm, the move is: back up the litellm database,
`postgres.enabled: true`, restore into the new instance, then drop the role. Not a value flip.

## What actually changes in the cluster

Resource names follow the release, so **everything is replaced, not upgraded in place**:

| Was | Is |
| --- | --- |
| `Deployment/open-webui`, `Service/open-webui` | `hearthai-web` |
| `Deployment/litellm`, `Service/litellm:4000` | `hearthai-litellm:4000` |
| `Deployment/meridian`, `Service/meridian:3456` | `hearthai-meridian:3456` |
| `Deployment/hearthmem`, `Service/hearthmem` | `hearthai-hearthmem` |
| `ConfigMap/litellm-config` | `ConfigMap/hearthai-litellm` (same bytes) |
| `CiliumNetworkPolicy/meridian-litellm-only` | `hearthai-meridian`, release-scoped selectors |
| four `*-gatus-ep` ConfigMaps | one `hearthai-gatus-ep` |
| four Flux Kustomizations | `cluster-apps-hearthai` |
| `ReplicationSource/hearthmem` | recreated, **same name and restic repo** |

Unchanged, deliberately: both hostnames, all four claim names, all four Secret names and every key
in them, the model catalogue, the Authentik client and its callback URL, and the ingress class.
The VolSync identity is unchanged too — `APP` stays `hearthmem` in the new Kustomization, because
the restic repository path is derived from it and renaming would orphan every existing snapshot.

Two behaviour deltas worth knowing, both from the chart:

- **Open WebUI's code execution and interpreter are off**, and ordinary users cannot import or
  access workspace tools. hearthai disables them until its sandbox substrate exists; in-process
  tools are not a substitute for it.
- **Hardening the old manifests lacked**: `automountServiceAccountToken: false` on every pod, and
  a seccomp profile plus dropped capabilities on Open WebUI. The stock Open WebUI image still runs
  as root — that is upstream's, and the chart does not claim otherwise.

## Downtime

Yes, a few minutes, and that is fine here. The old Deployments are pruned when their
Kustomizations go, the new ones bind the same RWO claims, and the claims cannot be mounted twice —
so the ordering is enforced by Kubernetes rather than by care. Every component is single-writer
with `Recreate`; none of them tolerate an overlap, and none of them need to avoid one.

## The claims are the only thing that can go wrong

Everything else here is replaceable; the four PVCs are not. Open WebUI's SQLite database holds
every account and conversation, hearthmem's holds the git stores, and `nfs-csi` carries
`reclaimPolicy: Delete` — a PVC delete is a data delete, not a detach.

Moving a claim between Flux Kustomizations is exactly the situation where that happens. When
`cluster-apps-open-webui` is removed, its finalizer garbage-collects everything in its inventory,
including `open-webui-data`. The new `cluster-apps-hearthai` declares the same claim, but whether
it has applied it *first* is a race between two controllers, decided per object.

So it is not left to the race. **The claims carry
`kustomize.toolkit.fluxcd.io/prune: disabled`** (the label every namespace here already uses).
Flux reads that from the *live object* at prune time, not from Git, and Flux reconciles HEAD
rather than each commit — so ordering this inside one merge is not possible, and the label went
in ahead of this change as its own pull request
([#1254](https://github.com/jokajak/home-ops/pull/1254), merged 2026-09-10). Verified live before
this change was written:

```sh
kubectl get pvc -n ai -l kustomize.toolkit.fluxcd.io/prune=disabled
# hearthmem-data, litellm-token, meridian-auth, open-webui-data — all Bound
```

The label stays on afterwards: deleting household data should be a manual act.

## Cutover

The first of the two merges is done (#1254, the claim labels). This is the second, and the only
one that moves anything. Four Kustomizations disappear and `cluster-apps-hearthai` appears;
pruning removes the old Deployments, Services, ingresses and ConfigMaps, and skips the claims,
which now carry the label that makes Flux leave them alone. Then:

1. **Watch the claims release.** New pods stay `Pending` until the old pod holding the same RWO
   claim is gone. Give it a minute before assuming a problem.
2. **Verify, in this order:** litellm `/health/liveliness` through `llm.<domain>`; a streaming chat
   at `chat.<domain>` after an Authentik login (that exercises Open WebUI's virtual key against
   the *new* Service name, which is the one thing the chart rewired); a `claude-*` model, which
   exercises meridian and its new network policy; and conversation history from before the
   cutover, which proves the claim was adopted rather than recreated.
3. **Then n8n**, whose litellm credential is per-credential state in its own UI: repoint it at
   `hearthai-litellm:4000`. Its virtual key is unaffected — same litellm, same database.

Rollback is `git revert` of this change and reconcile: the claims, Secrets and database are
untouched by it, so the old manifests come back to the state they left. Revert only this one — the
claim labels from #1254 should stay whatever else happens.

## The chart's pins are already stale

The chart imported this cluster's litellm and meridian at the versions they were on that day. In
the four days between writing this and merging it, Renovate moved both here:

| | chart pins | this cluster runs |
| --- | --- | --- |
| `ghcr.io/berriai/litellm-database` | v1.99.1 | **v1.100.1** (#1268) |
| `ghcr.io/rynfar/meridian` | 1.68.0 | **1.71.1** (#1269) |

Adopting the chart unchanged would therefore be a **downgrade of a running system**, and not a
harmless one: `litellm-database` applies its own Prisma migrations at startup, so moving it
backwards against an already-migrated database is a risk with nothing to gain.

The cause is worth naming, because it is not drift — it is an absence. **hearthai had no Renovate
at all.** These pins were only ever kept current by *this* repo's Renovate, and packaging them into
the chart moved them out of its reach: a chart consumed by commit SHA is opaque to Renovate, which
cannot see a `values.yaml` in another repository. Left alone, the images would have frozen at
whatever versions the import captured, permanently, and "temporarily override them until the chart
catches up" would have described something that never happens.

So two things:

1. **hearthai gets Renovate** (`.github/renovate.json5` there, pushed alongside this) — helm-values
   for the `repository`/`tag` pairs, a small custom manager for the single `repo:tag` strings, and
   no automerge for Open WebUI or LiteLLM since both migrate a database on startup. ⚠️ It does
   nothing until the Renovate GitHub App is installed on that repository.
2. **The HelmRelease overrides both images back to what is running.** That crosses the line this
   change otherwise draws — hearthai owns images, home-ops owns site inputs — and it is the
   honest trade: the alternative is a downgrade on merge day, or a cross-repo dependency where
   nothing ships here until something merges there. Renovate keeps bumping them here meanwhile, in
   the `image.repository`/`tag` shape it already tracks throughout this repo.

The overrides come out when hearthai's own Renovate has carried the chart past them — delete them
then rather than racing them upward. The cost described below arrived early; it is not a surprise,
and this is what closing it looks like.

## Pinning, and the thing to fix later

hearthai has published no tag, so the chart is a **path in a GitRepository pinned to a commit**
(`kubernetes/flux/repositories/git/hearthai.yaml`). A branch ref would deploy whatever landed on
`main` unreviewed, which is worse than a stale pin.

The cost is real: bumping any of the four images is now a hearthai change plus a SHA bump here,
and **Renovate tracks none of it** — nothing tracks a bare commit. When hearthai cuts its first
tag, its release workflow publishes `oci://ghcr.io/jokajak/charts/hearthai`; that file should then
become an `OCIRepository` with a version range, which restores automated bumps and matches where
the upstream template is going anyway
([realignment plan](2026-08-04-upstream-template-realignment.md)).

Until then, treat the pin as the release: review the hearthai diff, bump the SHA, reconcile.

## Owner steps

Nothing new to create — every Secret, Bitwarden item and Authentik object this release needs
already exists and is unchanged. The two interactive logins (litellm → ChatGPT, meridian →
Claude) live on `litellm-token` and `meridian-auth`, which are adopted as-is, so neither has to be
done again. If `meridian-auth` were ever lost, redo the login in
[the Hermes plan's "meridian: logging it in"](2026-08-24-hermes-household-agents.md).
