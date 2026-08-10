apiVersion: v1alpha1
kind: VLANConfig
name: ethSel0.{{ .Data.vlanId }}
vlanID: {{ .Data.vlanId }}
parent: ethSel0
mtu: {{ .Data.mtu }}
addresses:
  - address: {{ .Node.Data.vlanAddress }}
