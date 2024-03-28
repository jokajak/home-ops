# database
This directory contains the applications that provide database services throughout the cluster.

## cloudnative-pg

[cloudnative-pg](https://cloudnative-pg.io/) provides a postgres service within the cluster usable by applications.

* [cnpg.yaml](./cloudnative-pg/ks.yaml)

## dragonfly

[dragonfly](https://www.dragonflydb.io/) is an alternative to redis and provides better resource utilization.

* [dragonfly.yaml](./dragonfly/ks.yaml)
