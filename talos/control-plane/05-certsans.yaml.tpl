cluster:
  apiServer:
    certSANs:
      - {{ .Data.vip }}
      # KubePrism
      - 127.0.0.1
      - {{ .Data.apiDNS }}
