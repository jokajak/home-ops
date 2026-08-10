# ETCD configuration
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
    advertisedSubnets:
      - "{{ .Data.nodeCIDR }}"
