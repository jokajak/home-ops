# Disable search domain everywhere; force nameservers
machine:
  network:
    disableSearchDomain: true
    nameservers:
      {{- range .Data.nameservers }}
      - {{ . }}
      {{- end }}
  certSANs:
    - {{ .Data.vip }}
    # KubePrism
    - 127.0.0.1
    - {{ .Data.vip }}
    - {{ .Data.apiDNS }}
