# external-secrets

Bridges the cluster to the external secret manager so manifests reference only secret
*names*, never values.

| App | Description | Manifest |
| --- | --- | --- |
| [external-secrets](https://external-secrets.io/) | External Secrets Operator — syncs secrets from Bitwarden into Kubernetes `Secret`s via the `bitwarden-login` / `bitwarden-fields` `ClusterSecretStore`s. | [ks.yaml](./external-secrets/ks.yaml) |
