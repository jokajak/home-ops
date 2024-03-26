terraform {
  backend "kubernetes" {
    namespace     = "flux-system"
    secret_suffix = "minio"
    config_path   = "~/.kube/config"
  }
}
