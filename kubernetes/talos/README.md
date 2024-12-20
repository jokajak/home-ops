# Talos

This directory contains the files for talos.

## Factory customizations

### Raspberry Pi

```yaml
overlay:
    image: siderolabs/sbc-raspberrypi
    name: rpi_generic
customization:
    extraKernelArgs:
        - net.ifnames=0
    systemExtensions:
        officialExtensions:
            - siderolabs/crun
            - siderolabs/kata-containers
            - siderolabs/spin
            - siderolabs/wasmedge
```

### x86_64

```yaml
customization:
    extraKernelArgs:
        - net.ifnames=0
    systemExtensions:
        officialExtensions:
            - siderolabs/crun
            - siderolabs/intel-ucode
            - siderolabs/kata-containers
            - siderolabs/spin
            - siderolabs/wasmedge
```
