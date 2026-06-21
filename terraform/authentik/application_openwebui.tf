## -----------------------------------------------------------------------------
## Authentik Application - Open WebUI
## These are resources for open-webui to use authentik for SSO
## -----------------------------------------------------------------------------

## ----------------------------------------
## Open WebUI - Authentication (authn) resources
## ----------------------------------------
module "openwebui_oidc_creds" {
  source          = "./oidc_creds"
  application     = "open-webui"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "openwebui_oauth" {
  name = "open-webui-provider"

  client_id     = module.openwebui_oidc_creds.client_id
  client_secret = module.openwebui_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://chat.${var.domain}/oauth/oidc/callback"
    }
  ]

}

resource "authentik_application" "openwebui_application" {
  name               = "Open WebUI"
  slug               = authentik_provider_oauth2.openwebui_oauth.name
  protocol_provider  = authentik_provider_oauth2.openwebui_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/open-webui/open-webui/refs/heads/main/static/favicon.png"
  meta_launch_url    = "https://chat.${var.domain}"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Open WebUI - Authorization (authz) resources
## ----------------------------------------
resource "authentik_policy_binding" "openwebui_users" {
  target = authentik_application.openwebui_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
