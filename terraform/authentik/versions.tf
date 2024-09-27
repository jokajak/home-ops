terraform {
  required_version = ">= 1.5"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.10.0"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.8.4"
    }
  }
}
