# bitwarden terraform

This terraform code is responsible for managing the bitwarden items used by the cluster.

The approach is that terraform generates entries in bitwarden that can be referenced by the external-secrets controller
to be pulled into kubernetes.

Some resources need to be referenced across terraform modules, therefore they are exported to kubernetes secrets using
the outputs capability of terraform. From there, they can be made an input to other terraform modules that need to
retrieve data from bitwarden.
