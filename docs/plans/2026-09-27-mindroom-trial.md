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

Tuwunel's RocksDB and Mindroom's SQLite/session/crypto state use separate
`openebs-hostpath` PVCs. Runtime workers colocate with the runtime automatically
so its RWO local volume remains usable. A failed node requires recovery rather
than automatic failover; that is acceptable for this household trial.

Do not claim that live VolSync Direct copies of these databases are consistent
backups. The app README supplies an offline backup/restore procedure. Automated,
application-consistent backups remain a prerequisite before treating this trial
as the only copy of important household information. Claims are protected from
Flux pruning; that protection does not protect against node loss.

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
