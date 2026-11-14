# Image factory schematic for the x86 nodes.
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode
      # gVisor (runsc) for the `gvisor` RuntimeClass; see
      # kubernetes/apps/system/runtime-classes.
      - siderolabs/gvisor
