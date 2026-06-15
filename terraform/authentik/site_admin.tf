## -----------------------------------------------------------------------------
## Site admin
## A dedicated admin account for the downstream applications. It is admin in the
## apps (via the "admins" group) but is NOT an Authentik superuser — akadmin stays
## the sole Authentik administrator. Random username + password, stored in Bitwarden
## as "authentik-site-admin".
## -----------------------------------------------------------------------------

resource "random_string" "site_admin_username" {
  length  = 16
  special = false
  upper   = false
}

resource "random_password" "site_admin_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "site_admin" {
  organization_id = var.organization_id
  collection_ids  = [var.collection_id]

  name     = "authentik-site-admin"
  username = random_string.site_admin_username.result
  password = random_password.site_admin_password.result

  uri {
    match = "host"
    value = "https://auth.${var.domain}"
  }

  field {
    name    = "terraform"
    boolean = true
  }
  field {
    name = "repository"
    text = "jokajak/home-ops/terraform/authentik"
  }
}

## Non-superuser admin group. Named "admins" so apps that key their admin role on the
## group NAME (e.g. Grafana's role_attribute_path) pick it up. is_superuser = false
## => no Authentik admin rights. Bound to each SSO application below for access.
resource "authentik_group" "admins" {
  name         = "admins"
  is_superuser = false
}

resource "authentik_user" "site_admin" {
  username = random_string.site_admin_username.result
  name     = "Site Admin"
  email    = "siteadmin@${var.domain}"
  type     = "internal"
  password = random_password.site_admin_password.result

  groups = [authentik_group.admins.id]
}

## Grant the admins group access to Grafana. The admin role *within* Grafana then comes
## from its role_attribute_path matching the "admins" group name. Add equivalent bindings
## for other apps as SSO is rolled out to them (see docs/authentik-sso-integration.md).
resource "authentik_policy_binding" "admins_grafana" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.admins.id
  order  = 30
}
