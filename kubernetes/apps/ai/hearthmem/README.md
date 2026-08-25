# hearthmem

[`jokajak/hearthai`](https://github.com/jokajak/hearthai) `v0.1.0` published
`ghcr.io/jokajak/hearthmem:0.1.0` and its Helm chart, so this is wired into
`kubernetes/apps/ai/kustomization.yaml` and deployed like any other app here.

## Bootstrapping the household store

The service itself has no built-in stores. Once the pod is up, create the shared one from
either agent: `hearthmem create family "shared household memory"` — then give the token it
prints to the other person so their agent can `hearthmem add family <token>`.

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
