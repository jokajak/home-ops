# Mindroom household AI trial

## Decision

Deploy the upstream standalone Tuwunel, runtime, and client Helm charts from
https://docs.mindroom.chat/deployment/kubernetes/. Pin the chart source commit and
all three images. Keep HearthAI, Open WebUI, and the existing LiteLLM deployment;
Mindroom gets its own LiteLLM virtual key. This is an evaluation of Mindroom as the
household AI foundation, not a migration of existing conversations or memory.

Use the existing `internal` NGINX ingress, which is what this repository currently
runs for AI applications. Matrix is at `matrix.${SECRET_DOMAIN}`, the client at
`mindroom.${SECRET_DOMAIN}`. The runtime dashboard stays cluster-internal and is
available by port-forward with API-key authentication. No public federation or
open registration. Use `${SECRET_DOMAIN}` as the permanent Matrix server name;
serve client discovery at that domain's well-known path.

The owner explicitly accepted Mindroom's execution model for this trial. Enable
upstream Kubernetes workers for shell, Python, and file tools, without an ai-jobs
adapter. Workers get no Kubernetes API token or shared provider credentials.
They reuse their workspaces and are not fresh pods per tool invocation.

## Storage and recovery

Dedicated workers and the runtime share `mindroom-workspace`, an NFS-backed
ReadWriteMany claim. Workers are not pinned to the runtime node. This follows the
upstream dedicated-worker storage model and the owner's request to start with RWX.

Tuwunel's RocksDB stays on `mindroom-matrix-data` (local RWO). The runtime mounts
`mindroom-state` (local RWO) over `tracking/`, which contains its SQLite WAL event
journal. The chart also overlays encryption keys and sync continuity from that
state claim. Agent session databases use upstream's rollback-journal configuration
on the NFS workspace; keep one primary runtime and verify NFS locking in use.
Workers may run on other nodes; the primary still depends on its state PV's node.

Claims are prune-protected. There are no scheduled backups yet: take a consistent
offline copy of all three claims before treating the trial as durable household
infrastructure. See the app README for recovery and the fresh-install assumption.

## Bootstrap and owner steps

1. Apply `terraform/bitwarden` to create the declared secret items.
2. Mint a Mindroom-only LiteLLM virtual key and populate its Bitwarden field.
3. Review the permanent Matrix server name and the `${MINDROOM_OWNER_LOCALPART:=josh}`
   account name before merging. All domains use the existing Flux substitution.
4. Reconcile the merged manifests. Tuwunel and the client start; the runtime
   HelmRelease is initially suspended. Register the owner as the first human
   account, verify it is the homeserver admin, and verify client discovery/TLS.
5. Set `spec.suspend: false` on the runtime HelmRelease in Git and reconcile.
   Mindroom can now create its agent accounts without becoming the first admin.
6. Log into the client, test the Household room and its tools, then invite the
   next household member. Test denial outside the room before expanding access.

Detailed bootstrap, secret fields, validation, and recovery are in
`kubernetes/apps/ai/mindroom/README.md`.
