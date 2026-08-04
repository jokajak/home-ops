# home-ops

GitOps configuration for a single Kubernetes cluster running on [Talos Linux](https://www.talos.dev/),
reconciled by [Flux](https://fluxcd.io/).

**Everything as code.** The whole system is meant to be reproducible from this repository — no
click-ops, no manual `kubectl apply`, no console-configured infrastructure. State lives in Git and
is reconciled by machines, via two complementary engines:

- **Flux** for everything *inside* the cluster. A push to `main` is the only thing that changes
  cluster state; everything under [`kubernetes/`](./kubernetes) is reconciled from Git.
- **OpenTofu** for everything *outside* it — Authentik objects, Bitwarden items, MinIO buckets —
  under [`terraform/`](./terraform), with SOPS-encrypted inputs.

## Layout

| Path | Contents |
| --- | --- |
| [`kubernetes/`](./kubernetes/README.md) | Everything Flux reconciles onto the cluster. |
| [`kubernetes/apps/`](./kubernetes/apps/README.md) | All applications, grouped by namespace, each with its own README. |
| `kubernetes/flux/` | The GitOps engine itself — sources, cluster settings/secrets, root `Kustomization`s. |
| `kubernetes/components/` | Reusable Kustomize components (currently volsync). |
| `kubernetes/templates/` | Shared manifest templates used across apps (Gatus configs). |
| `talos/`, `kubernetes/talos/` | Talos machine configuration (talhelper). See [known issues](./docs/ISSUES.md). |
| [`terraform/`](./terraform) | OpenTofu for out-of-cluster state (Authentik, Bitwarden, MinIO). |
| [`docs/plans/`](./docs/plans) | Dated design docs. Non-trivial changes get written up here first. |
| [`docs/ISSUES.md`](./docs/ISSUES.md) | Living list of known issues and follow-ups. |
| `.taskfiles/`, `Taskfile.yaml` | [go-task](https://taskfile.dev) recipes. Run `task -l` to list them. |

Applications follow the [bjw-s `app-template`](https://bjw-s-labs.github.io/helm-charts/) pattern:

```text
kubernetes/apps/<namespace>/<app>/
├── ks.yaml                     # Flux Kustomization pointing at app/
└── app/
    ├── helmrelease.yaml
    └── kustomization.yaml
```

## Workflow

Push to `main`. Flux notices and reconciles — there is no apply step. Cross-cutting values come
from Flux post-build substitution (`${SECRET_DOMAIN}`, `${SECRET_NFS_SERVER}`, `${LB_CIDR_V4}`, …),
sourced from `cluster-settings` and `cluster-secrets`.

Before pushing, run the same checks CI runs:

```sh
task k8s:kubeconform        # schema-validate every manifest
yamllint .
pre-commit run --all-files
```

To preview what a change would do to the cluster, run
[flux-local](https://github.com/allenporter/flux-local) the way
[`.github/workflows/flux-diff.yaml`](./.github/workflows/flux-diff.yaml) does.

Day-2 helpers: `task flux:reconcile`, `task flux:apply path=<ns>/<app>`, `task k8s:resources`,
`task talos:*`. Dependency updates arrive as [Renovate](https://www.mend.io/free-developer-tools/renovate/)
PRs; Talos and Kubernetes version upgrades are driven in-cluster by
[tuppr](./kubernetes/apps/system-upgrade/tuppr).

## Storage

A Synology NAS (RAID 1) is the durable tier, exposed over NFS. `openebs-hostpath` backs
ephemeral/local PVCs, CNPG Postgres backups go to MinIO (S3), and volsync handles PVC replication.

## Secrets

Nothing sensitive is committed in the clear.

- **SOPS + age** for in-repo secrets — files matching the patterns in [`.sops.yaml`](./.sops.yaml).
  Encrypt with `task sops:encrypt`; the private age key lives with the cluster owner.
- **[External Secrets](https://external-secrets.io) + Bitwarden** for runtime secrets. The
  `ExternalSecret` manifests here reference only Bitwarden **item names and property keys** — the
  values live in Bitwarden.
- **Network topology** — real IPs, CIDRs, VLANs, NFS/gateway addresses — is treated the same way,
  and referenced through `${SECRET_*}` substitution variables rather than hardcoded. See
  [`docs/iot-address-plan.md`](./docs/iot-address-plan.md) for the addressing convention.

## Relationship to upstream

This repo was originally created from
[onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) and is now **fully
detached**: the makejinja/`config.yaml` generation machinery has been removed and `kubernetes/` is
hand-maintained. Upstream has since been rewritten around mise + just, `cluster.toml`,
flux-operator, per-app `OCIRepository` chart refs, Envoy Gateway and `flate`.

[`docs/plans/2026-08-04-upstream-template-realignment.md`](./docs/plans/2026-08-04-upstream-template-realignment.md)
maps that delta into phases, with a recommendation on each — including the ones not worth doing.
