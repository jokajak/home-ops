terraform {
  required_version = ">= 1.5"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.2.0"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.13.5"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2025.2.0"
    }
  }
}
