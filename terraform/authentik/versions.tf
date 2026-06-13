terraform {
  required_version = ">= 1.5"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.17.3"
    }
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.5.0"
    }
  }
}
