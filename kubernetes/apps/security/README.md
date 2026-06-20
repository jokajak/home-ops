# security

Authentication and authorization for cluster services.

| App | Description | Manifest |
| --- | --- | --- |
| [authentik](https://goauthentik.io/) | Identity provider / SSO. Federates external accounts (Google, GitHub) for authentication and uses Authentik or app-local groups for authorization. | [ks.yaml](./authentik/ks.yaml) |

Authentik's objects (providers, applications, flows) are managed as IaC with OpenTofu —
see [`terraform/authentik`](../../../terraform/authentik/README.md).
