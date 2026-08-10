{{- if hasKey .Node.Data "installerAnnotation" }}
machine:
  nodeAnnotations:
    installerImage: factory.talos.dev/metal-installer/{{ .SchematicID }}:{{ .TalosVersion }}
{{- end }}
