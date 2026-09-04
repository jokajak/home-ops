# hearthmem

[`jokajak/hearthai`](https://github.com/jokajak/hearthai) `v0.1.0` published
`ghcr.io/jokajak/hearthmem:0.1.0` and its Helm chart, so this is wired into
`kubernetes/apps/ai/kustomization.yaml` and deployed like any other app here.

## ⚠️ Currently has no consumers

Its only clients were the two Hermes agents' `shared-memory` skill, and those were removed on
2026-09-04. Nothing reads or writes this service today. It is left deployed — the data is small,
the volume is backed up, and markdown-in-git is inspectable in a way a vector table is not — while
it is decided whether it becomes the store of record behind Open WebUI or is retired. Retiring it
means dropping `./hearthmem/ks.yaml` from `kubernetes/apps/ai/kustomization.yaml`, which prunes
the PVC.

## Bootstrapping the household store

The service itself has no built-in stores. A store is created by whatever client holds the
token — historically `hearthmem create family "shared household memory"` from an agent, which
printed a token the other person's agent joined with via `hearthmem add family <token>`.

Renovate tracks `ghcr.io/jokajak/hearthmem` tags for future bumps the same as any other image
in this repo.

## What is load-bearing here

Two constraints are correctness requirements, not conventions — both inherited from upstream:

- **Exactly one replica, `Recreate` strategy.** Each store is a git repository guarded by a
  single in-process writer lock. A second pod on the same volume corrupts it, and a rolling
  update briefly runs two.
- **`ReadWriteOnce`.** Same reason.

Access control is a bearer token per store, and that is all it is: unrevocable, with
self-asserted attribution. Reasonable among people who already trust each other; not
authentication. It stays inside the cluster — no ingress — so the token never crosses a network
this household does not control.
