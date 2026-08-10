# Image factory schematic for the x86 nodes, branching on role.
#
# Both variants were verified to compute locally to the schematic IDs already
# in use on the fleet, matching what talhelper produced from talconfig.yaml:
#   control-plane -> 0bf2de4e77b3fbc706d8d073dde8418c20842dde7b8ed2f49d35983d388b2449
#   worker        -> 1841b08a4f5414495c0014324f8366e7b112718c1b86ce154326c9d142ee50e3
#
# The Raspberry Pi node uses schematic-rpi.yaml instead.
customization:
  # disable predictable names so that multus is easier
  extraKernelArgs:
    - net.ifnames=0
  systemExtensions:
    officialExtensions:
      - siderolabs/crun
      {{- if eq (printf "%s" .Node.Role) "control-plane" }}
      - siderolabs/intel-ucode
      {{- end }}
      - siderolabs/kata-containers
      - siderolabs/spin
      - siderolabs/wasmedge
