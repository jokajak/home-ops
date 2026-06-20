# cert-manager

Issues and renews the TLS certificates used across the cluster.

| App | Description | Manifest |
| --- | --- | --- |
| [cert-manager](https://cert-manager.io/) | Requests, issues, and renews X.509 certificates (e.g. via ACME / Let's Encrypt). | [ks.yaml](./cert-manager/ks.yaml) |
| [addons](https://github.com/jokajak/cert-manager-webhook-henet) | ACME DNS-01 solver webhook for Hurricane Electric (`dns.he.net`), enabling DNS-validated certificates. | [ks.yaml](./addons/ks.yaml) |
