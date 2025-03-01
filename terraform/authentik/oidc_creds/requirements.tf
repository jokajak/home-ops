terraform {
  required_version = ">= 1.5"
  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.13.0"
    }
  }
}
