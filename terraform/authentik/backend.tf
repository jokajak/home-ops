terraform {
  backend "kubernetes" {
    namespace     = "flux-system"
    secret_suffix = "authentik"
    config_path   = "~/.kube/config"
  }
}
