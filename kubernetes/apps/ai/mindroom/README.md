# Mindroom trial

Upstream [Kubernetes instructions](https://docs.mindroom.chat/deployment/kubernetes/),
using the standalone `cluster/k8s/{tuwunel,runtime,client}` charts. The chart commit
is pinned in `kubernetes/flux/repositories/git/mindroom.yaml`; each HelmRelease also
pins its image by digest. No SaaS platform, Supabase, or second model gateway.

| Component | Address | State |
| --- | --- | --- |
| Mindroom Chat | `https://mindroom.${SECRET_DOMAIN}` | Browser; Matrix owns history |
| Tuwunel | `https://matrix.${SECRET_DOMAIN}` | `mindroom-matrix-data`, 20Gi local RWO |
| Mindroom runtime + workers | `mindroom:8765` in `ai`; no ingress | `mindroom-workspace`, 20Gi NFS RWX |
| Runtime journal + Matrix client state | Runtime only | `mindroom-state`, 5Gi local RWO |
| Existing LiteLLM | `http://hearthai-litellm.ai.svc.cluster.local:4000/v1` | Unchanged |

The Matrix identity domain is `${SECRET_DOMAIN}`, for example
`@josh:example.com`, while the service lives at `matrix.example.com`. **Choose
this before the first start: changing the server name requires rebuilding the
homeserver.** Client discovery is served at the apex's `/.well-known/matrix/client`.
The existing internal ingress certificate covers the apex and wildcard. The apex
must resolve to that ingress for clients using identity-domain discovery; the
bundled client is explicitly configured with the homeserver URL as well.

## Before enabling the runtime

The Tuwunel and client releases reconcile normally. The **runtime HelmRelease is
initially suspended**, preventing an automatically registered bot from taking the
first-user server-admin role. This is a one-time bootstrap gate, not an unfinished
runtime deployment.

1. Review `tuwunel.serverName`, the two ingress hostnames, and the owner localpart.
   `MINDROOM_OWNER_LOCALPART` defaults to `josh`; set it in `cluster-settings` or
   `cluster-secrets` if using another account. `SECRET_DOMAIN` is deliberately
   required, with no fallback that could accidentally create permanent identities
   on `internal`.
2. Apply `terraform/bitwarden` with the normal owner-managed OpenTofu workflow.
   This creates the following items; no values are committed here.

   | Bitwarden item | Field | Purpose |
   | --- | --- | --- |
   | `mindroom credentials` | `registration_token` | Token-gated human and agent registration |
   | `mindroom credentials` | `api_key` | Runtime dashboard/API login |
   | `mindroom credentials` | `sandbox_proxy_token` | Runtime-to-worker authentication |
   | `mindroom litellm` | `litellm_api_key` | Dedicated LiteLLM virtual key; replace `replace-me` |

3. Mint the Mindroom virtual key in the existing LiteLLM UI, allowing
   `gpt-5.6-sol`, and put it in the field above. Verify the model works through
   LiteLLM before debugging Mindroom. OpenTofu ignores later edits to that field.
   Do not reuse the LiteLLM master key or an upstream provider key.
4. Merge/reconcile this PR. Wait for both ExternalSecrets and Tuwunel to be ready.
   Check `https://matrix.<domain>/_matrix/client/versions` and
   `https://<domain>/.well-known/matrix/client` from a household device. The latter
   must advertise `https://matrix.<domain>` and permit cross-origin discovery.
5. Register the owner account **before starting Mindroom**, using a Matrix client
   that supports registration-token signup and the `registration_token` field.
   Match `MINDROOM_OWNER_LOCALPART` exactly. If the bundled client's registration
   UI does not offer a token field, use another Matrix client's registration flow
   against the same homeserver. Confirm the human owner is invited into Tuwunel's
   admin room. Keep this token private; possession permits creating accounts.
6. Set `spec.suspend: false` in `app/runtime.yaml` in Git and reconcile that change.
   Mindroom provisions its own Matrix accounts and the encrypted Household room,
   then invites the owner. Do not bypass the bootstrap by letting a bot register
   first. On a restore of an existing database, retain the original identities;
   there is no new first-user step.
7. Log into Mindroom Chat as the owner. Ask Hearth a question, then exercise a
   harmless Python or file tool. Verify a worker can use its workspace and later scales to zero. Workers
   can now schedule on another node; no runtime-node colocation is configured.
   Add the next human account
   and invite it to Household; verify access before expanding the trial.

## Behavior and limits

- The Household room is invite-only, unlisted, and encrypted. Joined room members
  can converse with Hearth. It does not accept invitations into other rooms, so
  the shared persona does not carry its context to another audience by accident.
- Only the configured owner is a Mindroom administrator. Matrix room membership
  grants conversation access, not platform administration or provider credentials.
- Git owns `app/config.yaml`. ConfigMap changes restart the runtime via Reloader;
  the dashboard cannot persist edits to that read-only mount. Add personas,
  rooms, models, and tools in Git.
- Shell, Python, and file tools use upstream Kubernetes workers with `user_agent`
  workspace scope, no worker service-account token, and no grantable shared
  credentials. This **intentionally bypasses the proposed ai-jobs integration**
  for the trial. It is not the ephemeral-per-tool HearthAI design.
- Workers reuse persistent state, have upstream default egress, and can install
  or execute code. The runtime has upstream namespace-scoped worker-management
  RBAC in `ai`. This is a trusted household trial, not a hostile multi-tenant
  boundary. Do not provide host mounts or cluster-admin credentials.
- Start with conversation history and workspaces, without automatic long-term
  memory extraction or Agno learning. This avoids making an unreviewed shared
  memory policy or requiring a separate embedding service. `hearthmem` is not
  connected in this PR. The instruction to ask before an external action is a
  behavioral instruction, not an enforced approval gate.
- Federation and guest registration are disabled. The Matrix ingress exposes
  only client/media and discovery paths. Existing Open WebUI, HearthAI, n8n,
  and SearXNG are unchanged.

For operator access:

```sh
kubectl -n ai port-forward service/mindroom 8765:8765
```

Open `http://localhost:8765` and use the `api_key` from Bitwarden. The dashboard is
not exposed through the household ingress. Matrix chat works independently of it.

## Backup and restore

The runtime and dedicated workers share `mindroom-workspace` on `nfs-csi` with
ReadWriteMany. Workers mount only their selected subdirectories and can run across
nodes. The primary stays single-replica; RWX is for worker access, not multiple
concurrent primary runtimes.

Two kinds of state remain local:

- `mindroom-matrix-data`: Tuwunel's RocksDB and media.
- `mindroom-state`: the runtime's `tracking/` directory, including its SQLite WAL
  event journal, plus encryption keys and sync continuity. The upstream
  `stateStorage` chart mounts the claim at `/app/agent_data/tracking` and overlays
  its `encryption_keys` and `sync_continuity` subdirectories at the normal paths.
  Workers do not mount this claim.

Mindroom explicitly disables Agno's default WAL mode for its session databases,
which remain on the NFS workspace with rollback journaling. This still depends on
correct NFS locking; verify concurrent worker operations and runtime restarts on
the actual NAS. The primary remains tied to its local state PV's node even though
workers can move freely.

**There is no scheduled backup in this trial.** Copy all three claims consistently
while the runtime, workers, and homeserver are stopped. NFS storage survives loss of
a compute node, but is not itself a backup. Node loss without a copy of the local
state can still lose journal/crypto or homeserver data.

This update assumes a fresh installation of the unmerged PR. It uses a new
`mindroom-workspace` claim instead of changing the immutable storage class of
`mindroom-data`. If the earlier manifests were already deployed, stop here and
perform an offline migration: copy the old data tree onto the NFS workspace, copy
`tracking/` contents into the root of `mindroom-state`, and copy `encryption_keys/`
and `sync_continuity/` into their matching subdirectories on that state claim.
Retain the old claim until restored encrypted conversations and worker files have
been verified. Never start the new runtime with empty crypto/journal state against
an existing homeserver expecting it to recover the old identity automatically.

Offline procedure (owner maintenance, not part of normal reconciliation):

1. Pause reconciliation of the three Mindroom HelmReleases during maintenance.
   Record which ones were suspended already, especially during first bootstrap.
2. Stop the `mindroom` Deployment first so it cannot create more workers. Stop
   all worker Deployments selected by `home-ops/component=mindroom-worker`, then
   stop `mindroom-tuwunel`. Wait for all their pods to terminate before copying.
3. Mount each claim read-only in a temporary maintenance pod in `ai` and copy its
   **entire directory**, including hidden files, onto the NAS. Process the claims
   separately: the local PVs can be on different nodes. Let the scheduler follow
   each bound PVC's node affinity; never force a maintenance pod onto another node.
   Preserve ownership and permissions. Record the Git commit and image digests with
   the copies. Treat them as sensitive: they include conversations and credentials.
4. Restart Tuwunel, then the runtime. Workers are recreated by Mindroom as needed.
   Restore the recorded reconciliation state and verify an existing encrypted
   conversation and a tool call still work.

Restore with the releases/workers stopped. Provision replacement claims if the
original node is lost, restore all three whole directories with their original
ownership,
and use the same server name, Bitwarden credentials, and image versions first.
Start Tuwunel before Mindroom. Never replace the runtime's crypto/session directory
with an empty one while expecting access to old encrypted conversations. The claims
have Flux prune protection; retain them when disabling this trial.

## Updates and validation

Update the GitRepository commit and all relevant image digests together. Read
upstream storage-migration notes first; restoring the pre-upgrade copy is the
rollback path if an image changed a database format. Image pins do not imply that
arbitrary database downgrades are safe.

Local validation mirrors CI:

```sh
flate test all -p kubernetes/flux/config
yamllint kubernetes/apps/ai/mindroom kubernetes/flux/repositories/git/mindroom.yaml
```

Additionally render and lint each upstream chart using its HelmRelease values,
including the suspended runtime. Check the nested Mindroom config against the
pinned upstream config schema. Rendering is not a live cluster or model test.
