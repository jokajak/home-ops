# database

Shared database *infrastructure* — operators and a shared instance — consumed by
applications throughout the cluster.

> **Shared infra vs. per-app databases.** This namespace holds the CloudNativePG operator,
> the Barman Cloud backup plugin, dragonfly, and a shared `postgres` cluster. A given app's
> *own* Postgres lives **with that app**, not here — e.g. `immich-database` and
> `home-assistant` each carry a CNPG `Cluster` in [`default`](../default/README.md). That is
> intentional: it keeps each app's data and blast-radius local and avoids coupling unrelated
> databases. New per-app databases should follow the same pattern (co-locate with the app),
> not be centralized here.

| App | Description | Manifest |
| --- | --- | --- |
| [cloudnative-pg](https://cloudnative-pg.io/) | PostgreSQL operator that provisions and manages in-cluster Postgres clusters. | [ks.yaml](./cloudnative-pg/ks.yaml) |
| [cnpg-barman-plugin](https://github.com/cloudnative-pg/plugin-barman-cloud) | Barman Cloud plugin for CloudNativePG — WAL archiving and backups to object storage (MinIO). | [ks.yaml](./cnpg-barman-plugin/ks.yaml) |
| [dragonfly](https://www.dragonflydb.io/) | Redis-compatible in-memory datastore (deployed via its operator) with better resource utilization than Redis. | [ks.yaml](./dragonfly/ks.yaml) |
