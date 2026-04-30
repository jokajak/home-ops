terraform {
  required_version = ">= 1.5"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.9.0"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.17.6"
    }
  }
}
