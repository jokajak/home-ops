# security

Authentication, authorization, and secrets management for cluster services.

| App | Description | Manifest |
| --- | --- | --- |
| [authentik](https://goauthentik.io/) | Identity provider / SSO. Federates external accounts (Google, GitHub) for authentication and uses Authentik or app-local groups for authorization. | [ks.yaml](./authentik/ks.yaml) |
| [openbao](https://openbao.org/) | Open-source secrets manager (Vault fork, MPL-2.0). Runs single-node with integrated raft storage. Used to mint short-lived Kubernetes service-account tokens via its Kubernetes secrets engine — no long-lived credential stored anywhere. | [ks.yaml](./openbao/ks.yaml) |

Authentik's objects (providers, applications, flows) are managed as IaC with OpenTofu —
see [`terraform/authentik`](../../../terraform/authentik/README.md).

## OpenBao post-install steps

### Prerequisites (run `tofu apply` in `terraform/bitwarden` first)

The `openbao credentials` Bitwarden item must exist before the pod starts.
Running `tofu apply` in `terraform/bitwarden` creates it and populates the
`unseal_key` field. ESO syncs the key into the `openbao-unseal` Kubernetes
Secret, which OpenBao reads on startup to auto-unseal.

### One-time initialisation

Static auto-unseal means OpenBao starts sealed but unseals itself using the key
from Bitwarden. You only need to run `init` once — no `bao operator unseal` ever.

```sh
# Wait for the pod to be Running, then initialise.
# With static auto-unseal, init produces recovery keys (not unseal keys).
# Save the recovery keys and root token in Bitwarden immediately.
kubectl exec -n security openbao-0 -- bao operator init \
  -recovery-shares=5 \
  -recovery-threshold=3

# Verify it sealed and re-opened itself automatically
kubectl exec -n security openbao-0 -- bao status
```

### Configure the Kubernetes secrets engine

```sh
kubectl exec -n security openbao-0 -- bao login <root-token>

kubectl exec -n security openbao-0 -- bao secrets enable kubernetes

kubectl exec -n security openbao-0 -- bao write kubernetes/roles/claude \
  service_account_name=claude \
  service_account_namespace=security \
  token_ttl=24h \
  token_max_ttl=48h

# Mint a credential (run this at the start of each Claude session)
bao write kubernetes/creds/claude
```

### Key management

| Item | Location |
|---|---|
| Unseal key (AES-256) | Bitwarden `openbao credentials / unseal_key` — managed by `terraform/bitwarden` |
| Recovery keys (5 shares) | Bitwarden — store manually after `bao operator init` |
| Root token | Bitwarden — store manually after `bao operator init`; revoke after setup |

The `claude` ServiceAccount and `npe.llm-readonly` ClusterRole/ClusterRoleBinding are
reconciled by Flux from [`openbao/app/rbac.yaml`](./openbao/app/rbac.yaml).
