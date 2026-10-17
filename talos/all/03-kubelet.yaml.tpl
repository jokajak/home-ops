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
      allowedUnsafeSysctls:
        # matter-server: accept Thread border-router route advertisements on its
        # multus interface (net1). See
        # kubernetes/apps/home-automation/matter-server/app/helmrelease.yaml.
        - net.ipv6.conf.net1.accept_ra_rt_info_max_plen
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
