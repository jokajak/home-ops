# hearthai: local inference, lanes and what this repo wires

> Status: **PROPOSED, for review** · 2026-11-13 · Owner: Josh · Author: Claude
>
> Companion to hearthai's
> [`docs/superpowers/plans/2026-11-13-local-first-increments.md`](https://github.com/jokajak/hearthai/blob/main/docs/superpowers/plans/2026-11-13-local-first-increments.md),
> which holds the design, the increments (I1–I15) and the open decisions. This document is only
> what home-ops supplies, in what order, and what the owner does by hand. Nothing here is applied.

## The finding

The owner's laptop runs a model the cluster can reach on the home network. hearthai will expose it
through LiteLLM as a *lane*: a model name (`local-qwen`) with one backend and no fallback. Private
personas bind to that lane and are unavailable, not rerouted, when the laptop is off. hearthai owns
all of that. home-ops owns three things: where the laptop is, the Secrets, and later a namespace
for sandboxed tool pods.

Uptime is not a goal for the lane. The laptop being asleep is its normal state.

## The split

| hearthai owns | home-ops owns |
| --- | --- |
| The lane, the gate in front of the laptop, the router hook, the Open WebUI deny table | The laptop's address, as `${SECRET_LOCAL_LLM_HOST}` |
| The fixed "unavailable" behaviour and its tests | A status-page probe for the gate |
| Runbooks for the coding CLIs | The `llm.` ingress annotations those CLIs need |
| `ai-jobs`, its profiles and pod specs | The sandbox namespace, quota, default-deny policy, and every Secret |

## Cutover order

The hearthai `GitRepository` floats on `main`, so a chart merge deploys within the source interval.
That makes order a cross-repository concern. The rule hearthai follows is that a new capability
ships default-off; the rule here is that the switch is flipped only after the owner has seen the
default-off chart reconcile. Per the cutover rules in `CLAUDE.md`, each numbered step below is its
own merge with a check in between, and the pause belongs to the owner.

### Local lane (hearthai I1, I2)

1. **hearthai I1 merges.** Check: `hearthai` HelmRelease is Ready on the new revision; no gate
   objects exist; the model list is unchanged. Nothing here depends on this repo.
2. **Owner populates `SECRET_LOCAL_LLM_HOST`** in `kubernetes/flux/vars/cluster-secrets.sops.yaml`
   (name or address only, no scheme or port) and prepares the laptop (owner steps below). Its own
   commit.
3. **home-ops change A merges** (files below). Check: the gate pod is Running; with the laptop
   awake, `local-qwen` answers; with it asleep, the request fails in about 3 s with the fixed
   message and the status tile is down.

What breaks out of order: nothing destructive. If A lands before step 2, the value falls back to
`local-llm.invalid`, the gate reports unavailable, and the lane fails closed until the variable is
populated. If A lands before step 1, the chart ignores the unknown values and nothing changes. No
data is at risk in either case.

**Change A, files:**

- `kubernetes/apps/ai/hearthai/app/helmrelease.yaml`: add
  `localInference.enabled: true` and
  `localInference.upstreamUrl: "http://${SECRET_LOCAL_LLM_HOST:=local-llm.invalid}:11434"`, with a
  comment that the address is the only site input and that the lane must never gain a fallback.
- `kubernetes/apps/ai/hearthai/app/gatus.yaml`: one endpoint, `local-inference`, probing the gate
  Service's `/api/version` in-cluster, group `internal`, **no alert**. The probe never sees the
  laptop's address.
- `kubernetes/apps/ai/hearthai/README.md`: a "Local lane" section: what it is, that down is normal,
  and the owner steps.

### Catalogue in Git only (hearthai I4)

1. **Owner checks the LiteLLM admin UI** for models that exist only in the database, and reports
   them. If any is in use it goes into the chart catalogue first.
2. **hearthai I4 merges.** Check: every existing virtual key still authenticates (Open WebUI,
   Mindroom, n8n each send one message).

Out of order, a database-only model disappears from the gateway until it is added to the chart.
Keys, budgets and spend are not touched.

### Router term list (hearthai I5)

1. **`tofu apply` in `terraform/bitwarden`** creates the item below with a `replace-me` sentinel;
   the owner replaces it.
2. **home-ops change B merges:** a new `ExternalSecret` target `hearthai-router-secret` in
   `app/externalsecret.yaml`, and the chart value naming it.
3. **hearthai I5 merges** (router in shadow mode). The hook refuses if the list is missing, so
   landing I5 before step 2 makes `auto` refuse; no other model is affected.

### Sandbox namespace (hearthai I12)

1. **home-ops change C merges and is confirmed live:** namespace `ai-jobs`, a `ResourceQuota` on
   pods, CPU and memory, a default-deny `CiliumNetworkPolicy` for the namespace, and the
   namespace-scoped Role the control plane needs to create and delete pods there. No workload.
   Check: `kubectl get cnp,quota -n ai-jobs` shows them.
2. **Only then** the home-ops value that sets `aiJobs.enabled: true`.

This is the case the cutover rules exist for: the default-deny policy is read from the live
cluster, and a sandbox pod that starts before it exists has open egress. Do not merge the two
together.

### Smaller wiring, no ordering concern

- **Coding CLIs (hearthai I7):** `litellm.ingress.annotations` in the HelmRelease gain the same
  `proxy-read-timeout`, `proxy-send-timeout` and `proxy-buffering: "off"` values the Open WebUI
  ingress already has. Without them the ingress cuts a response whose first token takes over a
  minute, which a cold local model can.
- **Mindroom (hearthai I9):** update `kubernetes/apps/ai/mindroom/app/config.yaml` (the first-start
  seed) with the lane model entries so a rebuild matches the live dashboard config. The live change
  is an owner step in the dashboard.
- **Image overrides:** the `litellm` and `meridian` overrides in the HelmRelease are unrelated to
  this plan and stay until hearthai's pins pass them.
- **Pinning (hearthai O9):** once the local lane is live, change
  `kubernetes/flux/repositories/git/hearthai.yaml` from `branch: main` to a reviewed `commit:`.
  From the deny-table increment onward, chart merges change security settings.

## Owner steps

One-off steps, written down rather than automated, per the corollary in `CLAUDE.md`.

**Laptop, once:**

1. Pull the model and apply the Ollama settings in the hearthai plan ("Practical limits of the
   laptop"). Confirm `ollama ps` shows `100% GPU`.
2. Expose Ollama beyond localhost (app setting, or `launchctl setenv OLLAMA_HOST "0.0.0.0:11434"`
   plus a LaunchAgent so it survives a reboot).
3. Give the laptop a stable name or address on the home network.
4. Decide how the port is restricted. Ollama has no authentication; once exposed it answers on
   whatever network the laptop joins. That is a network decision and is not designed here.

**Substitution variables (`cluster-secrets`, SOPS):**

| Variable | Value | Needed by |
| --- | --- | --- |
| `SECRET_LOCAL_LLM_HOST` | The laptop's name or address. No scheme, no port. | Change A |

**Bitwarden items:**

| Item | Property | Created by | Needed by |
| --- | --- | --- | --- |
| `hearthai router` | `sensitive_terms` (one term per line) | `terraform/bitwarden`, sentinel pattern like `open-webui litellm`; owner fills it | Change B |
| `hearthmem stores` | one property per store, e.g. `household_token` | Owner, after creating the store with the CLI | hearthai I13 |

No Bitwarden item is needed for the local lane itself.

**LiteLLM admin UI (`llm.${SECRET_DOMAIN}`), virtual keys:**

| Key | Model allowlist | Stored where |
| --- | --- | --- |
| Open WebUI (existing) | all lanes; confirm `local-qwen` is visible | `open-webui litellm` (unchanged) |
| One per coding CLI or machine | `local-qwen` only | On the laptop, in each CLI's own configuration |
| Mindroom (existing) | add the lanes it should see | `mindroom litellm` (unchanged) |
| n8n, private workflows | `local-qwen` only | A second credential in n8n's UI |

**Open WebUI, once per persona (until hearthai I11):** Admin → Models → new preset on `local-qwen`,
memory and built-in tools off, a name that states the rule.

## Validation in this repo

```sh
task k8s:flate
yamllint kubernetes/apps/ai docs/plans
pre-commit run --all-files
```

`flate` renders the HelmRelease against the chart at the floating revision, so run it after the
matching hearthai increment has merged; before that it validates the manifest shape only. None of
this is a runtime check. The checks under each cutover step are the owner's, on the live cluster.

## Rollback

Each change reverts on its own. Reverting change A removes the gate and the lane; private personas
then fail with "model not found", which is still fail-closed. No claim, database or Secret is
created or removed by anything in this document except the `ai-jobs` namespace, which holds no
state.
