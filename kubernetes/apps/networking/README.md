# networking

Application-facing networking: ingress controllers and DNS. (The CNI and low-level pod
networking live in [`network`](../network/README.md).)

| App | Description | Manifest |
| --- | --- | --- |
| [echo-server](https://github.com/mendhak/docker-http-https-echo) | Simple HTTP echo service for testing ingress and routing. | [ks.yaml](./echo-server/ks.yaml) |
| [external-dns](https://github.com/kubernetes-sigs/external-dns) | Syncs ingress/service hostnames to the upstream DNS provider (Pi-hole). | [ks.yaml](./external-dns/ks.yaml) |
| [k8s-gateway](https://github.com/ori-edge/k8s_gateway) | DNS server that answers for in-cluster ingress hostnames. | [ks.yaml](./k8s-gateway/ks.yaml) |
| [nginx](https://github.com/kubernetes/ingress-nginx) | ingress-nginx controllers (`internal` and `external`) that terminate HTTP ingress. | [ks.yaml](./nginx/ks.yaml) |
