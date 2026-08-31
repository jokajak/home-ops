# CLAUDE.md

Guidance for Claude (and other AI agents) working in this repository.

## What this repo is

A GitOps home-ops repo that declaratively manages a single Kubernetes cluster. It was originally
derived from [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template) but is now
**fully detached** — the makejinja/`config.yaml` generation machinery has been removed, and
`kubernetes/` is hand-maintained. Upstream has since been rewritten (mise + just, `cluster.toml`,
flux-operator, `OCIRepository` chart refs, Envoy Gateway, `flate`); see
[`docs/plans/2026-08-04-upstream-template-realignment.md`](docs/plans/2026-08-04-upstream-template-realignment.md)
for the phased map of that delta. Don't reintroduce template scaffolding.

**Guiding principle — everything as code.** The whole system is meant to be reproducible from
this Git repository: no click-ops, no manual `kubectl apply`, no console-configured infra. State
lives in version control and is reconciled by machines, via two complementary engines:

- **GitOps (Flux)** for everything *inside* the cluster — a push to the tracked branch is the only
  thing that changes cluster state.
- **OpenTofu** (the `tofu` CLI, the open-source Terraform fork) for everything *outside* the
  cluster — Authentik objects, Bitwarden items, MinIO buckets. The `terraform/` directory holds
  this IaC; `.tf`/`.hcl` is OpenTofu code regardless of the directory name. Prefer `tofu` over
  `terraform` in new tooling/docs.

When something can't yet be expressed as code, treat that as a gap to close, and call it out
rather than papering over it with a manual step.

The pieces:

- **OS / cluster**: Talos Linux, bootstrapped via the `talos` taskfiles.
- **GitOps engine**: Flux — everything under `kubernetes/` is reconciled from Git. A push to
  the tracked branch is what changes the cluster; `kubectl apply` is not part of the workflow.
- **App pattern**: most apps use the bjw-s `app-template` Helm chart, laid out as
  `kubernetes/apps/<namespace>/<app>/{ks.yaml, app/{helmrelease.yaml, kustomization.yaml, ...}}`.
- **Out-of-cluster config**: OpenTofu code in `terraform/` manages things that live outside Kubernetes
  (Authentik objects, Bitwarden items, MinIO buckets) with SOPS-encrypted state inputs.
- **Storage**: a Synology NAS (RAID 1) is the durable data tier, exposed to the cluster over
  NFS (e.g. Immich data lives on `nfs://<nas>/volume1/immich`). openebs-hostpath is used for
  ephemeral/local PVCs; CNPG Postgres backups go to MinIO (S3).

## This is a home lab — uptime is not the goal

This cluster serves one household. There is no SLA, no on-call rotation, no paying users, and
nobody is paged when something is down. **Availability is cheap to lose here; complexity is
expensive to live with.** Design for the simplest thing that works, not for the most resilient.

- **Downtime is fine.** Single-replica apps, `Recreate` update strategies, RWO volumes, brief
  outages while Flux reconciles, and whole-cluster reboots for Talos upgrades are all acceptable.
  Don't design zero-downtime migrations, and don't treat "this app will be unavailable for a few
  minutes" as a blocker worth engineering around.
- **Don't add HA machinery unasked.** Multiple replicas, PodDisruptionBudgets, anti-affinity,
  topology spread constraints, leader election, and multi-instance datastores are not defaults
  to reach for. Add them when the app genuinely requires it, when they're the chart's own default,
  or when the owner asks — otherwise leave them out and keep the manifest small.
- **Durability still matters.** An outage is an annoyance; losing data is not recoverable. Effort
  belongs in the backup/restore path — NAS-backed NFS for durable data, CNPG backups to MinIO,
  volsync — rather than in keeping things serving through a failure. A change that means deleting
  a workload and restoring from backup is a perfectly good option if it's the simpler one.
- **Prefer the boring, legible option.** Fewer moving parts beats more nines. When a simpler
  design costs some availability, take it and note the trade-off in a sentence rather than
  building around it.

## ⚠️ Secrets: I do not have them, and that is by design

**I (Claude) cannot read or decrypt the real secret values in this repo, and I should never
try to.** The owner injects all sensitive material securely, outside of anything I can see.
Concretely:

- **SOPS / age**: files matching `*.sops.yaml` (and the patterns in `.sops.yaml`) are
  encrypted with an **age key that is not present in this environment**. I cannot decrypt them,
  and I should not attempt to (`sops -d`, `task sops:*`, importing keys, etc. will fail and are
  not expected to succeed). The age **public** key in `.sops.yaml` is fine to see; the private
  key is held only by the owner / the cluster.
- **External Secrets + Bitwarden**: live secrets are pulled at runtime by
  [external-secrets](https://external-secrets.io) from Bitwarden via the
  `bitwarden-login` and `bitwarden-fields` `ClusterSecretStore`s. The `ExternalSecret`
  manifests in this repo only reference Bitwarden item **names and property keys** (e.g.
  `key: "immich credentials"`, `property: pg_password`) — the values themselves live in
  Bitwarden, which I have no access to.
- **What this means for my work**: I edit the *declarations* — HelmReleases, Kustomizations,
  ExternalSecret/SOPS *references*, OpenTofu resources. When a new secret is needed I add the
  `ExternalSecret`/SOPS reference and tell the owner exactly which **Bitwarden item + property**
  (or which SOPS key) they must create and populate. I do **not** invent, guess, paste, or
  commit real secret values, and I assume any value I can't see is being supplied by the owner.

If a task seems to require a secret value I can't see, that's expected — surface what's needed
and hand that step back to the owner rather than trying to work around the encryption.

## ⚠️ Network details stay out of the repo

The owner does **not** want real network topology committed to this repo. Treat IPs, CIDRs,
subnets, gateway/router addresses, NFS server addresses, MAC addresses, VLAN IDs, and similar as
sensitive — same posture as secrets.

- **Never hardcode** a real address in a manifest, doc, or commit. Reference a Flux substitution
  variable instead — `${SECRET_NFS_SERVER}`, `${LB_CIDR_V4}`, `${ROUTER_CIDR_V4}`,
  `${IOT_CIDR}`, etc. The real values live in `cluster-secrets` (SOPS), which the owner injects.
- In `docs/` and plan files, refer to hosts by name (`auth.${SECRET_DOMAIN}`) or by role
  ("the VPN gateway pod"), not by address. Use placeholders (`A.B.C.D`, `<nas-ip>`) if an example
  is unavoidable.
- When adding config that needs an address, add a new `${SECRET_*}`/`${*_CIDR_*}` substitution
  variable (wired through `cluster-secrets`) rather than a literal, and tell the owner which
  variable to populate.

> **What counts as sensitive here:** the owner's *real* network — LAN/router/NFS/gateway
> addresses, VLANs — which is already injected via `cluster-secrets` (the `${VAR:=192.168.1.x}`
> literals scattered through the repo are generic cluster-template fallbacks, not the real
> values).
>
> **Explicitly OK:** the `192.168.24.0/24` VPN subnet and its fixed pod IPs (in
> `kubernetes/apps/{network,vpn,downloads}` and the VPN plan doc) are an **internal overlay**,
> not real LAN topology — they may stay hardcoded. Don't waste effort variabilizing them.

## Execution environment constraints

- This runs in an **ephemeral remote container with a fresh clone** — there is **no kubeconfig
  and no cluster access**. I cannot run `kubectl`, `flux`, or `talosctl` against the live
  cluster, and I should not assume I can observe runtime state. Changes take effect only after
  the owner reconciles Flux from the pushed branch.
- Validation I *can* do locally: schema/lint checks the way CI does them — `flate`
  (see `.github/workflows/flate.yaml`), which covers schema validation and
  Kustomization/HelmRelease rendering in one pass, plus `yamllint` and the `pre-commit`
  hooks. Prefer these over claiming runtime verification.
- Outbound network access depends on the environment's network policy; don't assume arbitrary
  egress.

## Commands

Tasks are driven by [go-task](https://taskfile.dev); run `task -l` to list everything. The
includes are namespaced (`task k8s:…`, `task flux:…`, `task talos:…`, `task sops:…`). The
cluster-touching tasks (`flux:*`, `talos:*`, anything needing `KUBECONFIG`) **won't work in this
container** — no kubeconfig, no cluster. The ones below are the locally useful, read-only/validation
ones that mirror CI.

- **Validate manifests and rendering** — `task k8s:flate` (aliases: `kubeconform`, `validate`).
  Runs `flate test all -p kubernetes/flux/config`, exactly what CI runs in
  `.github/workflows/flate.yaml`. This replaced both the kubeconform and flux-local jobs: it
  schema-validates every manifest *and* renders Kustomizations/HelmReleases in one pass. Run it
  after editing any HelmRelease/Kustomization.
- **Lint** — `yamllint .` (config in `.yamllint.yaml`) and `pre-commit run --all-files`
  (`.pre-commit-config.yaml`: trailing whitespace, EOF, merge-conflict, JSON checks).
- **Encrypt a SOPS file** — `task sops:encrypt` re-encrypts any unencrypted `*.sops.*` file under
  `kubernetes/` and `terraform/`. Decryption requires the age key, which is not present here — see
  the secrets section.

## Conventions

- Keep the existing layout: per-app `ks.yaml` Flux Kustomization + an `app/` dir with the
  HelmRelease and a `kustomization.yaml`. Wire new apps into the parent namespace
  `kustomization.yaml`.
- Cross-cutting variables come from Flux substitution: `${SECRET_DOMAIN}`, `${SECRET_NFS_SERVER}`,
  `${LB_CIDR_V4}`, etc. Reference those rather than hardcoding domains/IPs.
- Secret plumbing is **always** via `ExternalSecret` (Bitwarden) or `*.sops.yaml`, never plaintext
  in a manifest. Match the style of the nearest existing `externalsecret.yaml`.
- Larger multi-step efforts are written up first as dated design docs in `docs/plans/`
  (see the VPN-gateway and Cilium Gateway API plans for the expected format). Follow that
  convention for non-trivial changes.
- Don't commit or push unless asked; when asked, develop on the designated feature branch.
