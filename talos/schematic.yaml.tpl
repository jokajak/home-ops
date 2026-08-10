# Image factory schematic for the x86 nodes.
#
# Trimmed 2026-08-10 to what this cluster can actually use. Previously this
# declared crun, kata-containers, spin and wasmedge; none were installed on any
# node (the whole fleet runs the empty schematic 376567988…) and none were
# reachable either — the cluster has no RuntimeClasses and no pod sets
# `runtimeClassName`. See docs/ISSUES.md #11.
#
# intel-ucode was previously gated to control-plane nodes only, which left the
# Intel workers foyer-hp-800g3 and basement-lenovo-m910q without microcode
# updates. Every x86 node here reports GenuineIntel, so it now applies to all of
# them and the role branch is gone.
#
# The Raspberry Pi nodes use schematic-rpi.yaml instead.
customization:
  # disable predictable names so that multus is easier
  extraKernelArgs:
    - net.ifnames=0
  systemExtensions:
    officialExtensions:
      - siderolabs/intel-ucode
