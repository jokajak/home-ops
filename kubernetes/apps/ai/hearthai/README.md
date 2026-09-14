# hearthai

The household AI stack, deployed as **one Helm release** from
[`jokajak/hearthai`](https://github.com/jokajak/hearthai) (`deploy/charts/hearthai`).

Until 2026-09-10 this was four app directories here — `open-webui`, `litellm`, `meridian` and
`hearthmem` — each with its own HelmRelease, image pin and hand-wired references to the others.
They are one product: Open WebUI only works against a LiteLLM that speaks the model names it
shows, LiteLLM's Claude routes only work against a meridian it can reach, and upgrading one
without the others is how they broke. hearthai now owns that compatibility surface, and this
repo supplies what only a cluster can. See
[`docs/plans/2026-09-10-hearthai-single-release.md`](../../../../docs/plans/2026-09-10-hearthai-single-release.md).

## Who owns what

| hearthai (the chart) | home-ops (here) |
| --- | --- |
| Images and their versions | Public URLs (`chat.`, `llm.`) and the ingress class |
| Probes, resources, security contexts | Every Secret, via `ExternalSecret` → Bitwarden |
| The LiteLLM model catalogue | The four `PersistentVolumeClaim`s and their backup policy |
| Open WebUI's environment and auth mode | The identity provider and its client |
| Internal wiring between the four | **Postgres** |
| The meridian `CiliumNetworkPolicy` | Node placement (`amd64`) and Gatus probes |

Everything home-ops supplies is in [`app/helmrelease.yaml`](./app/helmrelease.yaml)'s `values:`,
[`app/externalsecret.yaml`](./app/externalsecret.yaml) and [`app/pvc.yaml`](./app/pvc.yaml).

## Postgres is ours

`postgres.enabled: false`. The chart can render its own single-instance CNPG `Cluster`, and
deliberately isn't asked to: the `litellm` database and role already exist on the **shared**
cluster in the `database` namespace, holding the proxy's virtual keys, budgets and spend
history. LiteLLM takes `DATABASE_URL` from `litellm-secret` and keeps its `postgres-init` init
container, exactly as before — the same pattern Authentik uses, and the one the
[CNPG consolidation](../../../../docs/plans/2026-08-24-cnpg-consolidation.md) settled on.
Moving to the chart's bundled instance later would be a backup/restore cutover, not a value flip.

## What the release contains

- **Open WebUI** at `chat.${SECRET_DOMAIN}` — the household assistant. Authentik is the only way
  in; the application's policy bindings (`terraform/authentik/application_openwebui.tf`) decide
  who may sign in.
- **LiteLLM** at `llm.${SECRET_DOMAIN}`, and at `hearthai-litellm:4000` in-cluster — the
  inference router. One subscription, one virtual key per consumer.
- **meridian** — the Claude-subscription bridge LiteLLM's `anthropic/` routes point at.
  ClusterIP only, and its network policy admits only this release's LiteLLM pods.
- **hearthmem** — the shared-memory store, as a subchart. No ingress: a store's token is a bearer
  capability that cannot be revoked, so it never leaves the cluster network. **It still has no
  consumers** — its clients were the Hermes agents' `shared-memory` skill, removed 2026-09-04, and
  the Open WebUI adapter that would replace them is not built yet. Being in the release is not
  that integration; it is where the integration will land.

## ⚠️ Two logins this repo cannot do for you

Both are interactive, both happen once or twice in a component's life, and both survive restarts
on their own claim — so they are written down rather than automated:

- **LiteLLM → ChatGPT**: a device-code login, cached in `CHATGPT_TOKEN_DIR` on `litellm-token`.
- **meridian → Claude**: Claude Code credentials on `meridian-auth`. Until it has them, the
  `claude-*` models 401 and fail their 300-second health check — noisy, not harmful. See
  "meridian: logging it in" in
  [`docs/plans/2026-08-24-hermes-household-agents.md`](../../../../docs/plans/2026-08-24-hermes-household-agents.md).

A third by the same rule: Open WebUI's LiteLLM virtual key is minted in the LiteLLM admin UI and
pasted into the Bitwarden `open-webui litellm` item over its `replace-me` sentinel
(`terraform/bitwarden/README.md`).

## What is load-bearing

- **Single replica, `Recreate`, `ReadWriteOnce` — everywhere.** Open WebUI is SQLite on one
  volume, LiteLLM writes one OAuth token file, meridian owns one credentials directory, and each
  hearthmem store is a git repository guarded by one in-process writer lock. The chart pins all
  four; nothing here should try to scale them.
- **`amd64` for Open WebUI and LiteLLM.** This cluster has two RPi4s. LiteLLM's registry manifest
  *advertises* arm64 for its pinned tag and then fails with `exec format error`; Open WebUI runs a
  CPU embedding model on first boot. Both selectors are load-bearing, not leftovers.
- **`hearthmem-data` is the only backed-up claim.** VolSync keeps its restic identity as
  `hearthmem` (see the `APP` note in [`ks.yaml`](./ks.yaml)); renaming it would orphan every
  existing snapshot.

## Upgrading

While the chart is under active development it **floats on `main`** in
[`kubernetes/flux/repositories/git/hearthai.yaml`](../../../flux/repositories/git/hearthai.yaml)
— no `commit:` pin. Every push to hearthai's `main` becomes a new source revision, and
`reconcileStrategy: Revision` in `app/helmrelease.yaml` turns each one into an upgrade (chart
version `0.1.0+<sha>`). Bumping an image or adding a model is therefore just a hearthai change:
push it, the cluster follows. The trade-off is that whatever lands on `main` deploys unreviewed —
fine for a single-household lab whose chart owner is the one pushing. Pin it back to a `commit:`
(or an `OCIRepository` + version range once hearthai publishes
`oci://ghcr.io/jokajak/charts/hearthai`, which is also what lets Renovate track it) once the
chart stabilises.

**Two images are overridden in `app/helmrelease.yaml`, and are meant to come back out.** The
chart pins litellm v1.99.1 and meridian 1.68.0 — the versions this cluster ran when hearthai
imported them — while Renovate here has since moved the cluster to v1.100.1 and 1.71.1. Adopting
the chart's pins as-is would be a downgrade, and litellm-database applies Prisma migrations at
startup, so backwards is not free. The overrides hold the running versions, in the
`image.repository`/`tag` shape Renovate already tracks throughout this repo.

They stop being needed once hearthai's own Renovate catches its chart up — it had none until
this change, which is why the pins drifted; see `.github/renovate.json5` there. When the chart's
pins pass these, delete the overrides rather than racing them upward.

## Bootstrapping a memory store

The service has no built-in stores. A store is created by whatever client holds the token —
historically `hearthmem create family "shared household memory"`, which prints a token another
client joins with via `hearthmem add family <token>`. In-cluster clients reach it at
`hearthai-hearthmem`. Access control is a bearer token per store and nothing more: unrevocable,
with self-asserted attribution. Reasonable among people who already trust each other; not
authentication.
