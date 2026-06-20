# database

Database services consumed by applications throughout the cluster.

| App | Description | Manifest |
| --- | --- | --- |
| [cloudnative-pg](https://cloudnative-pg.io/) | PostgreSQL operator that provisions and manages in-cluster Postgres clusters. | [ks.yaml](./cloudnative-pg/ks.yaml) |
| [cnpg-barman-plugin](https://github.com/cloudnative-pg/plugin-barman-cloud) | Barman Cloud plugin for CloudNativePG — WAL archiving and backups to object storage (MinIO). | [ks.yaml](./cnpg-barman-plugin/ks.yaml) |
| [dragonfly](https://www.dragonflydb.io/) | Redis-compatible in-memory datastore (deployed via its operator) with better resource utilization than Redis. | [ks.yaml](./dragonfly/ks.yaml) |
