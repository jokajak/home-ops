data "sops_file" "this" {
  source_file = "secrets.sops.yaml"
}
