## -----------------------------------------------------------------------------
## Authentik Application - Wallos
## These are resources for wallos to use authentik for SSO
## -----------------------------------------------------------------------------

## ----------------------------------------
## Wallos - Authentication (authn) resources
## ----------------------------------------
module "wallos_oidc_creds" {
  source          = "./oidc_creds"
  application     = "wallos"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "wallos_oauth" {
  name = "wallos-provider"

  client_id     = module.wallos_oidc_creds.client_id
  client_secret = module.wallos_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://subs.${var.domain}/api/oidc/callback"
    }
  ]

}

resource "authentik_application" "wallos_application" {
  name               = "Wallos"
  slug               = authentik_provider_oauth2.wallos_oauth.name
  protocol_provider  = authentik_provider_oauth2.wallos_oauth.id
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/wallos.png"
  meta_launch_url    = "https://subs.${var.domain}"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Wallos - Authorization (authz) resources
## ----------------------------------------
# All users can access Wallos
resource "authentik_policy_binding" "wallos_users" {
  target = authentik_application.wallos_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
