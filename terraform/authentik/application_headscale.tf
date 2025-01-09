## -----------------------------------------------------------------------------
## Authentik Application - headscale
## These are resources for headscale to use authentik for SSO
## -----------------------------------------------------------------------------

## ----------------------------------------
## headscale - Authentication (authn) resources
## ----------------------------------------
module "headscale_oidc_creds" {
  source          = "./oidc_creds"
  application     = "headscale"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "headscale_oauth" {
  name = "headscale-provider"

  client_id     = module.headscale_oidc_creds.client_id
  client_secret = module.headscale_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode = "strict",
      url           = "https://hs.${var.domain}/"
    }
  ]

}

resource "authentik_application" "headscale_application" {
  name               = "headscale"
  slug               = authentik_provider_oauth2.headscale_oauth.name
  protocol_provider  = authentik_provider_oauth2.headscale_oauth.id
  group              = authentik_group.headscale_users.name
  open_in_new_tab    = true
  meta_launch_url    = "https://hs.${var.domain}/login/generic_oauth"
  policy_engine_mode = "any"
}

## ----------------------------------------
## headscale - Authorization (authz) resources
## ----------------------------------------
resource "authentik_policy_binding" "headscale_infra" {
  target = authentik_application.headscale_application.uuid
  group  = authentik_group.infrastructure.id
  order  = 0
}

resource "authentik_group" "headscale_admin" {
  name = "headscale Admins"
  # is_superuser refers to authentik authorizations
  is_superuser = false
}

resource "authentik_group" "headscale_users" {
  name = "headscale Viewers"
  # is_superuser refers to authentik authorizations
  is_superuser = false
  parent       = resource.authentik_group.headscale_admin.id
}

resource "authentik_policy_binding" "headscale_admins" {
  target = authentik_application.headscale_application.uuid
  group  = authentik_group.headscale_admin.id
  order  = 0
}

resource "authentik_policy_binding" "headscale_users" {
  target = authentik_application.headscale_application.uuid
  group  = authentik_group.headscale_users.id
  order  = 20
}
