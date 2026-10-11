apiVersion: v1alpha1
kind: VLANConfig
# The matching Media NAD uses ethSel0.${MEDIA_VLAN_ID} as its host master.
# Apply this Talos link on every node Home Assistant may use before reconciling
# that NAD/pod; otherwise Multus cannot create the pod's secondary interface.
name: ethSel0.{{ .Data.mediaVlanId }}
vlanID: {{ .Data.mediaVlanId }}
parent: ethSel0
mtu: {{ .Data.mtu }}
# No node IP or route is needed: only the macvlan pod has a Media VLAN address.
