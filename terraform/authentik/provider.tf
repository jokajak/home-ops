provider "bitwarden" {
  master_password = data.sops_file.this.data["BW_PASSWORD"]
  client_id       = data.sops_file.this.data["BW_CLIENTID"]
  client_secret   = data.sops_file.this.data["BW_CLIENTSECRET"]
  email           = data.sops_file.this.data["BW_EMAIL"]
  server          = "https://vault.bitwarden.com"
}

data "bitwarden_item_login" "authentik_credentials" {
  id = var.authentik_credentials_id
}

locals {
  bootstrap_token = zipmap(
    data.bitwarden_item_login.authentik_credentials.field[*].name,
    data.bitwarden_item_login.authentik_credentials.field[*]
  )["bootstrap_token"].hidden
}

provider "authentik" {
  url   = "https://auth.${var.domain}"
  token = local.bootstrap_token
}
