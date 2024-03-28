resource "random_password" "client_id" {
  length  = 16
  special = false
}

resource "random_password" "client_secret" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "this_oidc_client" {
  organization_id = var.organization_id
  collection_ids  = [var.collection_id]

  name     = "authentik-client-${var.application}"
  username = random_password.client_id.result
  password = random_password.client_secret.result

  field {
    name    = "terraform"
    boolean = true
  }

  field {
    name = "repository"
    text = "jokajak/home-lab/terraform/authentik"
  }
}
