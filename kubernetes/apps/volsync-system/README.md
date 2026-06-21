# volsync-system

Volume backup/restore for app PVCs, via [VolSync](https://volsync.readthedocs.io/) with the
**restic** mover to MinIO (S3). Apps opt in by pulling the
[`components/volsync`](../../components/volsync) Flux component into their `ks.yaml`. See the
design doc under [`docs/plans`](../../../docs/plans/2026-06-21-volsync-backups.md).

| App | Description | Manifest |
| --- | --- | --- |
| [volsync](https://github.com/backube/volsync) | Operator that reconciles `ReplicationSource`/`ReplicationDestination` to back up and restore PVCs. | [ks.yaml](./volsync/ks.yaml) |
