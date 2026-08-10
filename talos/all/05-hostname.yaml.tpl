# talhelper set the hostname from nodes[].hostname; topf does not do this
# implicitly, so it is declared here. Without it Talos auto-generates
# talos-XXX-XXX names and every Kubernetes node would be renamed.
apiVersion: v1alpha1
kind: HostnameConfig
auto: 'off'
hostname: {{ .Node.Host }}
