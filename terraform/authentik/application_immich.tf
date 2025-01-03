## -----------------------------------------------------------------------------
## Authentik Application - Immich
## These are resources for immich to use authentik for SSO
## -----------------------------------------------------------------------------

## ----------------------------------------
## Immich - Authentication (authn) resources
## ----------------------------------------
module "immich_oidc_creds" {
  source          = "./oidc_creds"
  application     = "immich"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "immich_oauth" {
  name = "immich-provider"

  client_id     = module.immich_oidc_creds.client_id
  client_secret = module.immich_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # From https://immich.app/docs/administration/oauth/
  allowed_redirect_uris = [
    # for logging in with OAuth from the Web Client
    {
      matching_mode = "strict",
      url           = "https://immich.${var.domain}/auth/login"
    },
    # for manually linking OAuth in the Web Client
    {
      matching_mode = "strict",
      url           = "https://immich.${var.domain}/user-settings"
    },
    # for logging in with OAuth from the mobile app
    {
      matching_mode = "strict",
      url           = "app.immich://oauth-callback"
    }
  ]

}

resource "authentik_application" "immich_application" {
  name               = "Immich"
  slug               = authentik_provider_oauth2.immich_oauth.name
  protocol_provider  = authentik_provider_oauth2.immich_oauth.id
  group              = authentik_group.monitoring.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/grafana.png"
  meta_launch_url    = "https://grafana.${var.domain}/login/generic_oauth"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Immich - Authorization (authz) resources
## ----------------------------------------
# All users can use immich
resource "authentik_policy_binding" "immich_users" {
  target = authentik_application.immich_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
