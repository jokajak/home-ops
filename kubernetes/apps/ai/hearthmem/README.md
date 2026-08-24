# hearthmem — staged, not deployed

These manifests are complete and reviewed but **deliberately not referenced** from
`kubernetes/apps/ai/kustomization.yaml`, because the image they name does not exist yet:
[`jokajak/hearthai`](https://github.com/jokajak/hearthai) ships `service/Dockerfile` but has no
CI that builds or publishes it, so `ghcr.io/jokajak/hearthmem` is empty.

## To bring it up

1. Publish an image — add a build workflow to `jokajak/hearthai` (preferred: the image then
   tracks its own source and Renovate can follow it here) or build and push one by hand.
2. Pin the real tag in `app/helmrelease.yaml`, replacing the placeholder.
3. Add `- ./hearthmem/ks.yaml` to `kubernetes/apps/ai/kustomization.yaml`.
4. Create the household store once it is running, from either agent:
   `hearthmem create family "shared household memory"` — then give the token it prints to the
   other person so their agent can `hearthmem add family <token>`.

## Until then

Both agents already carry the `shared-memory` skill and point `HEARTHMEM_URL` at this service.
Calls fail loudly rather than silently succeeding, which is the failure mode we want: nothing is
shared, and nobody is under the impression that it was.

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
