# bitwarden terraform

This terraform code is responsible for managing the bitwarden items used by the cluster.

The approach is that terraform generates entries in bitwarden that can be referenced by the external-secrets controller
to be pulled into kubernetes.

Some resources need to be referenced across terraform modules, therefore they are exported to kubernetes secrets using
the outputs capability of terraform. From there, they can be made an input to other terraform modules that need to
retrieve data from bitwarden.

## What is *not* managed here

Some Bitwarden items are created by hand and only *read* by external-secrets. They are the ones
whose value another party issues, so there is nothing for `random_password` to generate — a
Terraform stub could own the item's name and field names, but the secret itself would still have
to be pasted in, and a placeholder that syncs successfully is worse than an item that is missing:
the pod starts and fails with a 401 at runtime instead of staying unready and obviously
unconfigured.

Create these in Bitwarden (same organization + collection as the generated ones), then the
`ExternalSecret` that names them picks them up on its next refresh.

| Item | Fields the ExternalSecret reads | Consumed by | Issued by |
|---|---|---|---|
| `github runner app credentials` | login + fields | `actions-runner-system/actions-runner-controller` | a GitHub App |
| `home assistant` | fields | `default/home-assistant` | Home Assistant |
| `maxmind api` | `username`, `password` | `observability/vector` | maxmind.com |
| `opn-plugins signing key` | fields | `actions-runner-system/runner-scale-set` | generated offline |
| `vpn-gateway-secrets` | fields | `vpn/gateway` | the VPN provider |

Two more — `authentik-github-creds` and `authentik-google-creds` — are also hand-made, but read by
`terraform/authentik` through a `data "bitwarden_item_login"` lookup rather than by
external-secrets.

## Terraform owns the item, you own the value

A third category, for credentials that only a human can produce but that something else *blocks
on*. `hermes josh` and `hermes partner` hold LiteLLM virtual keys, which cannot exist until
LiteLLM is running, because LiteLLM mints them.

That ordering used to be a deadlock. **external-secrets has no per-key "optional"**: if a single
`data[]` entry cannot resolve, the target Secret is never created at all, so an agent waiting on
an unmintable key could not even start.

So terraform creates these two items with an **empty** `litellm_api_key`, and
`lifecycle { ignore_changes = [field] }` means it never looks at the value again. Everything
reconciles from the first apply; the agents run and return auth errors until real keys arrive;
pasting a key in is permanent.

⚠️ **Edit that field, never delete it.** An empty value resolves fine. A *missing* property fails
the whole ExternalSecret and takes the agent down with it.

Order of operations: `tofu apply` → deploy LiteLLM → log in at `llm.<domain>` → mint a virtual key
per agent (a monthly budget on each is the point of having two) → paste each into its item. The
agents are up and reconciled the whole way through.
