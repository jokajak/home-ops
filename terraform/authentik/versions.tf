terraform {
  required_version = ">= 1.5"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.8.1"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.6.1"
    }
  }
}
