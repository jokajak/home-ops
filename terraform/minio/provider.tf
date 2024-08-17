terraform {
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.1.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.8.0"
    }
    minio = {
      source  = "aminueza/minio"
      version = "2.4.3"
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

provider "minio" {
  minio_server   = "s3.${var.domain}"
  minio_user     = data.bitwarden_item_login.minio_secret.username
  minio_password = data.bitwarden_item_login.minio_secret.password
  minio_ssl      = true
}

data "bitwarden_item_login" "minio_secret" {
  id = var.minio_secret_id
}
