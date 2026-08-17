# Disable search domain everywhere; force nameservers
machine:
  network:
    disableSearchDomain: true
    nameservers:
      {{- range .Data.nameservers }}
      - {{ . }}
      {{- end }}
  certSANs:
    - 127.0.0.1 # KubePrism
