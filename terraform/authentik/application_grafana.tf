## -----------------------------------------------------------------------------
## Authentik Application - Grafana
## These are resources for grafana to use authentik for SSO
## -----------------------------------------------------------------------------

## ----------------------------------------
## Grafana - Authentication (authn) resources
## ----------------------------------------
module "grafana_oidc_creds" {
  source          = "./oidc_creds"
  application     = "grafana"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "grafana_oauth" {
  name = "grafana-provider"

  client_id     = module.grafana_oidc_creds.client_id
  client_secret = module.grafana_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://grafana.${var.domain}/login/generic_oauth"
    }
  ]

}

resource "authentik_application" "grafana_application" {
  name               = "Grafana"
  slug               = authentik_provider_oauth2.grafana_oauth.name
  protocol_provider  = authentik_provider_oauth2.grafana_oauth.id
  group              = authentik_group.monitoring.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/grafana.png"
  meta_launch_url    = "https://grafana.${var.domain}/login/generic_oauth"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Grafana - Authorization (authz) resources
## ----------------------------------------
resource "authentik_policy_binding" "grafana_infra" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.infrastructure.id
  order  = 0
}

resource "authentik_group" "grafana_admin" {
  name = "Grafana Admins"
  # is_superuser refers to authentik authorizations
  is_superuser = false
}

resource "authentik_group" "grafana_editors" {
  name = "Grafana Editors"
  # is_superuser refers to authentik authorizations
  is_superuser = false
  parent       = resource.authentik_group.grafana_admin.id
}

resource "authentik_group" "grafana_viewers" {
  name = "Grafana Viewers"
  # is_superuser refers to authentik authorizations
  is_superuser = false
  parent       = resource.authentik_group.grafana_admin.id
}

resource "authentik_group" "monitoring" {
  name         = "Monitoring"
  is_superuser = false
  parent       = resource.authentik_group.grafana_viewers.id
}

resource "authentik_policy_binding" "grafana_admins" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.grafana_admin.id
  order  = 0
}

resource "authentik_policy_binding" "grafana_editors" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.grafana_editors.id
  order  = 10
}

resource "authentik_policy_binding" "grafana_viewers" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.grafana_viewers.id
  order  = 20
}
