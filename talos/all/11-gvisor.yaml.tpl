{{- /*
gVisor (runsc, from the siderolabs/gvisor extension in schematic.yaml.tpl) needs
unprivileged user namespaces. This relaxes a KSPP hardening default, so it is
set only on nodes whose data carries `gvisor: true` in topf.yaml: the x86 nodes,
which are also the only ones whose schematic includes the extension and the only
ones the `gvisor` RuntimeClass schedules onto. Owner decision, 2026-11-14.
*/}}
{{- if hasKey .Node.Data "gvisor" }}
machine:
  sysctls:
    user.max_user_namespaces: "11255"
{{- end }}
