terraform {
  required_providers {
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.7.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.0"
    }
    random = {
      source = "hashicorp/random"
      version = "3.8.1"
    }
  }
}

provider "bitwarden" {
  master_password = data.sops_file.this.data["BW_PASSWORD"]
  client_id       = data.sops_file.this.data["BW_CLIENTID"]
  client_secret   = data.sops_file.this.data["BW_CLIENTSECRET"]
  email           = data.sops_file.this.data["BW_EMAIL"]
  server          = "https://vault.bitwarden.com"
}

terraform {
  backend "kubernetes" {
    namespace     = "flux-system"
    secret_suffix = "bitwarden"
    config_path   = "~/.kube/config"
  }
}
