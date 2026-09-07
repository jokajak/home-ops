# observability

Metrics, logs, dashboards, and health monitoring for the cluster and home network.

| App | Description | Manifest |
| --- | --- | --- |
| [gatus](https://github.com/TwiN/gatus) | Uptime/health status dashboard for services. | [ks.yaml](./gatus/ks.yaml) |
| [goflow2](https://github.com/netsampler/goflow2) | NetFlow/sFlow/IPFIX collector for network-flow telemetry. | [ks.yaml](./goflow2/ks.yaml) |
| [grafana](https://grafana.com/) | Dashboards for metrics and logs. | [ks.yaml](./grafana/ks.yaml) |
| [unpoller](https://github.com/unpoller/unpoller) | Exports UniFi controller metrics. | [ks.yaml](./unpoller/ks.yaml) |
| [vector](https://vector.dev/) | Log/metric collection pipeline (agent + aggregator) that feeds Loki — used instead of promtail. | [ks.yaml](./vector/ks.yaml) |
| [victoriametrics](https://victoriametrics.com/) | Metrics storage and the VictoriaMetrics k8s stack (used in place of Prometheus). | [ks.yaml](./victoriametrics/ks.yaml) |

`smartctl-exporter` still has manifests in this directory but is **not listed in
`kustomization.yaml`**, so Flux does not reconcile it and no S.M.A.R.T. metrics are being
collected. Either wire it back in or delete the directory.
