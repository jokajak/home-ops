# storage

Storage-related services for the cluster.

| App | Description | Manifest |
| --- | --- | --- |
| [minio](https://min.io/) | S3-compatible object storage. | [ks.yaml](./minio/ks.yaml) |

MinIO backs restic/volsync backups for volumes kept on local disk (rather than the NAS)
and stores CNPG Postgres backups. Some services are IO-sensitive and benefit from local
disk instead of an NFS share, so object storage gives them a backup/restore path.
