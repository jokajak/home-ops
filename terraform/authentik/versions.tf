terraform {
  required_version = ">= 1.5"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.0.0"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.7.2"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.2.0"
    }
  }
}
