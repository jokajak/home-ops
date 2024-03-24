# storage

This namespace is used for providing storage related services.

## minio

[minio](https://github.com/minio/minio) provides s3 like storage.

S3 storage is used by restic with volsync to provide backup and restore capability for volumes that are stored on local
disks instead of the NAS.

Some services are IO sensitive and therefore benefit from being stored on a local disk instead of on an NFS share.

* [minio.yaml](./minio/ks.yaml)
