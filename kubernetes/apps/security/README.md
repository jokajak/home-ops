# security

Authentication, authorization, and secrets management for cluster services.

| App | Description | Manifest |
| --- | --- | --- |
| [authentik](https://goauthentik.io/) | Identity provider / SSO. Federates external accounts (Google, GitHub) for authentication and uses Authentik or app-local groups for authorization. | [ks.yaml](./authentik/ks.yaml) |
| [openbao](https://openbao.org/) | Open-source secrets manager (Vault fork, MPL-2.0). Runs single-node with integrated raft storage. Used to mint short-lived Kubernetes service-account tokens via its Kubernetes secrets engine — no long-lived credential stored anywhere. | [ks.yaml](./openbao/ks.yaml) |

Authentik's objects (providers, applications, flows) are managed as IaC with OpenTofu —
see [`terraform/authentik`](../../../terraform/authentik/README.md).

## OpenBao post-install steps

OpenBao requires a one-time manual init and unseal after the pod first starts:

```sh
# Initialise — save the unseal keys and root token somewhere safe (e.g. Bitwarden)
kubectl exec -n security openbao-0 -- bao operator init

# Unseal (repeat with three different keys from the output above)
kubectl exec -n security openbao-0 -- bao operator unseal <key>

# Configure the Kubernetes secrets engine so OpenBao can mint short-lived tokens
# for the claude-readonly ServiceAccount
kubectl exec -n security openbao-0 -- bao login <root-token>
kubectl exec -n security openbao-0 -- bao secrets enable kubernetes
kubectl exec -n security openbao-0 -- bao write auth/token/roles/claude-readonly \
  allowed_policies=default \
  period=24h
kubectl exec -n security openbao-0 -- bao write kubernetes/roles/claude \
  service_account_name=claude \
  service_account_namespace=security \
  token_ttl=24h \
  token_max_ttl=48h

# Mint a credential (run this at the start of each Claude session)
bao write kubernetes/creds/claude
```

The `claude` ServiceAccount and `claude-readonly` ClusterRole/ClusterRoleBinding are
reconciled by Flux from [`openbao/app/rbac.yaml`](./openbao/app/rbac.yaml).
