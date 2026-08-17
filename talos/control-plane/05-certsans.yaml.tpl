machine:
  certSANs:
    - {{ .Data.vip }}
    - {{ .Data.apiDNS }}
