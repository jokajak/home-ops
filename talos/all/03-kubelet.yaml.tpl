# Configure kubelet; mount openebs-hostpath
machine:
  kubelet:
    extraArgs:
      image-gc-low-threshold: 50
      image-gc-high-threshold: 55
      rotate-server-certificates: true
    # Present on every running node but absent from talconfig.yaml — it was
    # applied out of band. Declared here so `topf apply` preserves it instead of
    # silently turning user namespaces off. See docs/ISSUES.md #10.
    extraConfig:
      featureGates:
        UserNamespacesSupport: true
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
