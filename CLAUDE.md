# CLAUDE.md

Guidance for Claude (and other AI agents) working in this repository.

## What this repo is

A GitOps home-ops repo (fork of [onedr0p/cluster-template](https://github.com/onedr0p/cluster-template))
that declaratively manages a single Kubernetes cluster:

- **OS / cluster**: Talos Linux, bootstrapped via the `talos` taskfiles.
- **GitOps engine**: Flux — everything under `kubernetes/` is reconciled from Git. A push to
  the tracked branch is what changes the cluster; `kubectl apply` is not part of the workflow.
- **App pattern**: most apps use the bjw-s `app-template` Helm chart, laid out as
  `kubernetes/apps/<namespace>/<app>/{ks.yaml, app/{helmrelease.yaml, kustomization.yaml, ...}}`.
- **Out-of-cluster config**: `terraform/` manages things that live outside Kubernetes
  (Authentik objects, Bitwarden items, MinIO buckets) with SOPS-encrypted state inputs.
- **Storage**: a Synology NAS (RAID 1) is the durable data tier, exposed to the cluster over
  NFS (e.g. Immich data lives on `nfs://<nas>/volume1/immich`). openebs-hostpath is used for
  ephemeral/local PVCs; CNPG Postgres backups go to MinIO (S3).

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
  ExternalSecret/SOPS *references*, Terraform resources. When a new secret is needed I add the
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

> Note: parts of the existing repo (inherited from the cluster-template and the VPN/downloads
> stack) still contain literal `192.168.x.x` addresses — some as `${VAR:=default}` fallbacks,
> some hardcoded (e.g. the `192.168.24.0/24` VPN bridge subnet). New work must not add to this,
> and scrubbing the existing literals is a tracked cleanup task.

## Execution environment constraints

- This runs in an **ephemeral remote container with a fresh clone** — there is **no kubeconfig
  and no cluster access**. I cannot run `kubectl`, `flux`, or `talosctl` against the live
  cluster, and I should not assume I can observe runtime state. Changes take effect only after
  the owner reconciles Flux from the pushed branch.
- Validation I *can* do locally: schema/lint checks the way CI does them — `kubeconform`
  (see `.github/workflows/kubeconform.yaml`), `flux-local` diffs
  (`.github/workflows/flux-diff.yaml`), `yamllint`, and the `pre-commit` hooks. Prefer these
  over claiming runtime verification.
- Outbound network access depends on the environment's network policy; don't assume arbitrary
  egress.

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
