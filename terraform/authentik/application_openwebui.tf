## -----------------------------------------------------------------------------
## Authentik Application - Open WebUI
##
## The household's chat front end onto both Hermes agents, at
## https://chat.<domain> (kubernetes/apps/ai/open-webui). Both agents are
## wired in as separate model connections; which model a signed-in user can
## see is a manual grant in Open WebUI's own admin UI, not an Authentik
## concern.
##
## The policy binding below is who may sign in AT ALL — bound to the "Home"
## group, same as the rest of the household's applications.
##
## Unlike the agents' dashboards this is a CONFIDENTIAL client: Open WebUI runs
## the code exchange server-side, so the secret is used rather than ignored.
## -----------------------------------------------------------------------------

module "openwebui_oidc_creds" {
  source          = "./oidc_creds"
  application     = "open-webui"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "openwebui" {
  name = "open-webui-provider"

  client_id     = module.openwebui_oidc_creds.client_id
  client_secret = module.openwebui_oidc_creds.client_secret
  client_type   = "confidential"

  # Explicit for the same reason as the Hermes providers: Authentik's model
  # defaults grant_types to an empty list, and an /authorize with response_type
  # code then fails as "Invalid grant_type for provider".
  grant_types = ["authorization_code", "refresh_token"]

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

resource "authentik_application" "openwebui" {
  name = "Open WebUI"
  # The slug IS the issuer path: https://auth.<domain>/application/o/<slug>/.
  # OPENID_PROVIDER_URL in the HelmRelease hardcodes "open-webui", so renaming
  # this breaks discovery.
  slug               = "open-webui"
  protocol_provider  = authentik_provider_oauth2.openwebui.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/open-webui/open-webui/refs/heads/main/static/favicon.png"
  meta_launch_url    = "https://chat.${var.domain}"
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "openwebui_hermes_josh" {
  target = authentik_application.openwebui.uuid
  group  = authentik_group.home.id
  order  = 0
}
