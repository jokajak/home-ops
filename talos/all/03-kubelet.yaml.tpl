# Configure kubelet; mount openebs-hostpath
machine:
  kubelet:
    extraArgs:
      image-gc-low-threshold: 50
      image-gc-high-threshold: 55
      rotate-server-certificates: true
    nodeIP:
      validSubnets:
        - "{{ .Data.nodeCIDR }}"
        - "{{ .Data.vlanCIDR }}"
    extraMounts:
      - destination: /var/openebs/local
        type: bind
        source: /var/openebs/local
        options:
          - bind
          - rshared
          - rw
