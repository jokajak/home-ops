# Upstream cluster-template realignment

> Status: **ROADMAP** — cleanup landed, no convention changes made · 2026-08-04 · Owner: Josh ·
> Author: Claude
>
> This repo was created from [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template)
> and diverged in substance long ago. The formal de-templating never happened: upstream's
> `task repo:clean` was never run, so `bootstrap/` and `ansible/` were deleted by hand and every
> *reference* to the generation engine was left pointing at directories that no longer exist.
> That cleanup is done (see [What already landed](#what-already-landed)). What remains is the
> harder question — upstream has been **rewritten from the ground up** since the fork, and this
> doc maps that delta into phases you can pick up one at a time.

## Why this isn't a "merge upstream"

There is no shared shape left to merge. Upstream today is a different program:

| | This repo | Upstream `main` (2026-08) |
| --- | --- | --- |
| Task runner | `task` + `.taskfiles/` | `just` + per-directory `mod.just` |
| Dev env | `direnv` + `.venv` + `pip` | `mise` (pins the entire toolchain) + `uv` |
| Template input | *(removed)* `config.yaml` / makejinja | `cluster.toml`, pydantic-validated |
| Flux install | hand-rolled `flux-manifests` `OCIRepository` + `Kustomization` | `flux-operator` + `FluxInstance` CR |
| Root entrypoint | `kubernetes/flux/config/` + `kubernetes/flux/apps.yaml` | `kubernetes/flux/cluster/ks.yaml` |
| Chart sources | 13 `HelmRepository`, 52 HelmReleases using `chart.spec` | per-app `OCIRepository` + `chartRef` |
| Secret substitution | `postBuild.substituteFrom` wired per-Kustomization | `components/sops` Kustomize Component + controller-level `--sops-age-secret` |
| Ingress | ingress-nginx | Envoy Gateway (Gateway API) |
| CI validation | `kubeconform` + `flux-local` + `flux-ks-paths` | `flate` (single tool) |
| Talos | `talhelper` + `talconfig.yaml` | `topf` + `topf.yaml` + per-node patch files |
| Bootstrap | `flux install` + `kubectl apply` | `helmfile` chain (cilium → coredns → spegel → cert-manager → flux-operator → flux-instance) |

Regenerating from the current template would mean porting 56 apps onto a new scaffold and
reconfiguring a live Talos cluster under a different tool. That's a rebuild. The phases below are
the incremental alternative — each independently shippable, each with an honest verdict.

## What already landed

The de-templating pass (2026-08-04), which changed **zero** Kubernetes objects:

- Deleted `makejinja.toml`, `config.sample.yaml`, `requirements.txt`, `.github/tests/`,
  `.github/workflows/release.yaml` (upstream's monthly template-release cron), and
  `.taskfiles/Ansible/`.
- Deleted `.taskfiles/Repository/` — `clean` was the de-templating task itself, and
  `reset`/`force-reset` chained into `.reset` tasks that `rm -rf`'d `kubernetes/`, `talos/` and
  `.sops.yaml`. Those `.reset` tasks are gone too.
- Repaired `task flux:bootstrap` (applied a `kubernetes/bootstrap` dir that doesn't exist; read
  `cluster-settings.yaml` when the file is `cluster-settings.sops.yaml`) and dropped
  `flux:github-deploy-key` (the repo clones over public HTTPS).
- Widened `task sops:encrypt` to cover `terraform/`, not just `kubernetes/`.
- Stripped `(\.j2)?` patterns, the `ansible/` file patterns, the `ansible-galaxy` and
  `pip_requirements` managers, and the ansible package rules/labels from `.github/renovate.json5`.
- Retargeted the devcontainer at `ghcr.io/jokajak/home-ops/devcontainer` (which this repo's own
  workflow already publishes) instead of upstream's image.
- Rewrote `README.md`, which was still upstream's k3s/Ansible/Cloudflare template docs.

## Phases

### 1. CI → `flate`

Replace `kubeconform.yaml` + `flux-diff.yaml` + `flux-ks-paths.yaml` with
[`home-operations/flate`](https://github.com/home-operations/flate), which upstream now runs as a
single `flate test all -p ./kubernetes/flux/cluster` step. It covers schema validation and
Kustomization/HelmRelease rendering in one pass.

- **Blast radius:** CI only. No cluster contact, fully reversible.
- **Snag:** `flate` wants a single root path to walk. This repo's root is
  `kubernetes/flux/config` + `kubernetes/flux/apps.yaml`, not upstream's
  `kubernetes/flux/cluster`. Either point `flate` at the existing layout or sequence this after
  phase 2. `scripts/validate-ks-paths.sh` and `scripts/detect-hidden-unicode.sh` are local
  additions with no upstream equivalent — keep them regardless.
- **Verdict: recommended.** Best value-to-risk ratio here; do it first.

### 2. Flux control plane → flux-operator

Adopt `flux-operator` + a `FluxInstance` CR, move the root entrypoint to
`kubernetes/flux/cluster/ks.yaml`, and hoist the per-Kustomization boilerplate into one root
patch. Upstream's root `ks.yaml` sets `decryption.provider: sops` and
`deletionPolicy: WaitForTermination` for *every* child Kustomization, plus a nested patch giving
every HelmRelease sane `install`/`upgrade`/`rollback` remediation. This repo repeats
`substituteFrom` blocks in `kubernetes/flux/apps.yaml` to achieve part of the same thing.

Bundled with it: the `components/sops` Kustomize Component (each namespace
`kustomization.yaml` lists `components: [../../components/sops]`) and controller-level SOPS via
`--sops-age-secret=sops-age`, which removes the per-Kustomization `secretRef`.

- **Blast radius:** high. Touches how Flux itself is installed and how every Kustomization
  decrypts and substitutes. Needs a maintenance window and a tested rollback.
- **Payoff:** also high — most of the per-app YAML this repo carries becomes unnecessary.
- **Verdict: recommended, but plan it separately** with its own design doc.

### 3. Chart sources → `OCIRepository`

Convert 52 HelmReleases from `chart.spec.sourceRef` → `HelmRepository` to `chartRef` →
per-app `OCIRepository`. Upstream ships one `ocirepository.yaml` per app alongside the
HelmRelease and has no shared `HelmRepository` list at all; `kubernetes/flux/repositories/helm/`
would eventually disappear.

- **Blast radius:** wide but shallow — mechanical, one app at a time, each verifiable with a
  `flux-local` diff before pushing.
- **Snag:** not every chart this repo uses is published as an OCI artifact. Audit first; the ones
  that aren't stay on `HelmRepository`, which is fine — the two coexist.
- **Verdict: worthwhile, do it incrementally per namespace.** No reason to big-bang it.

### 4. Toolchain → mise + just

Replace `task`/`.taskfiles/` with a root `justfile` + `mod.just` modules, and
`direnv`/`.venv`/`pip` with `mise` (which pins every CLI version in `.mise/config.toml`, so the
devcontainer and a laptop agree).

- **Blast radius:** none on the cluster. Pure developer ergonomics.
- **Payoff:** the pinned toolchain is genuinely nice; the `task`→`just` half is a lateral move.
- **Verdict: optional.** Consider taking `mise` alone and leaving `task` in place — that captures
  most of the benefit for a fraction of the churn.

### 5. Ingress → Gateway API

Upstream moved from ingress-nginx to **Envoy Gateway**, with `envoy-internal` / `envoy-external`
gateways and per-app `HTTPRoute`s. This repo is still entirely ingress-nginx (0 Gateway API
resources today).

- **Prior art conflict:** [`2026-02-08-cilium-gateway-api-migration.md`](./2026-02-08-cilium-gateway-api-migration.md)
  already chose **Cilium** Gateway API for this cluster. Cilium is already the CNI here, so that
  choice needs no extra control plane; Envoy Gateway is upstream's answer, not necessarily this
  cluster's.
- **Verdict: decide first, then migrate.** Following upstream here is not automatically right.
  Resolve Cilium vs Envoy against that existing doc before any work starts. Whichever wins, the
  migration itself is a per-app `Ingress` → `HTTPRoute` conversion and belongs in its own plan.

### 6. Talos → `topf`

Upstream replaced `talhelper` + `talconfig.yaml` with
[`topf`](https://postfinance.github.io/topf/) + `topf.yaml` + numbered per-node machine-config
patch files (`talos/all/*.yaml`, `talos/control-plane/*.yaml`), and drives bootstrap through
`topf apply --auto-bootstrap`.

- **Verdict: defer.** `talhelper` works, tuppr already owns Talos/Kubernetes version upgrades
  in-cluster, and the Talos tree here needs consolidation before any tool swap makes sense — see
  [`ISSUES.md`](../ISSUES.md) #6, and
  [`2026-08-04-history-purge-plaintext-topology.md`](./2026-08-04-history-purge-plaintext-topology.md)
  for the separate (planned, unexecuted) question of what the plaintext Talos config left behind
  in git history.

### 7. Namespace names

Upstream uses a single `network` namespace. This repo has `networking` (ingress, external-dns,
k8s-gateway) and `network-system` (cilium, multus, whereabouts) after the deliberate
[2026-06-20 reorganization](./2026-06-20-namespace-reorganization.md).

- **Verdict: skip.** The current split is intentional and better documented than upstream's. This
  would be churn for cosmetic parity, and namespace moves mean PVC migrations.

## Suggested order

1. Phase 1 (CI) — cheap, immediate feedback on everything after it.
2. Phase 5's *decision* (Cilium vs Envoy) — unblocks planning, costs nothing to settle.
3. Phase 2 (flux-operator) — its own design doc, its own maintenance window.
4. Phase 3 (OCIRepository) — trickles in per namespace afterwards.
5. Phase 4 (mise) if wanted; phases 6 and 7 probably never.

## Verification

Every phase above shares the same gate, because none of them should change cluster *intent*:

- `task k8s:kubeconform` clean.
- `flux-local` diff shows only the changes the phase intends — for phases 1, 4 and 7 that means
  **no diff at all**.
- `yamllint .` and `pre-commit run --all-files` clean.
- For phases 2 and 3, a real reconcile on the cluster with `flux get ks -A` / `flux get hr -A` all
  `Ready=True` before the next phase starts.
