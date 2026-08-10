apiVersion: v1alpha1
kind: LinkConfig
name: ethSel0
mtu: {{ .Data.mtu }}
addresses:
  - address: {{ .Node.IP }}/{{ .Data.prefix }}
routes:
  - gateway: {{ .Data.gateway }}
