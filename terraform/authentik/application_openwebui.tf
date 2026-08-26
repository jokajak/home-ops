## -----------------------------------------------------------------------------
## Authentik Application - Open WebUI
##
## A chat front end onto Josh's Hermes agent, at https://josh-chat.<domain>.
##
## An application existed here before and was removed in ded3a2f as stale — it
## had been created for an Open WebUI that was never deployed, and pointed at a
## callback on chat.<domain>, which hearthai now owns. This is a fresh one for a
## deployment that actually exists, on its own hostname.
##
## ⚠️ THE POLICY BINDING IS THE ENTIRE ACCESS BOUNDARY. Open WebUI is configured
## with no local password login at all, so whoever Authentik will issue a token
## to can read everything Josh's agent remembers. The binding is therefore to
## "Hermes Josh" — the same single-member group that guards his dashboard — and
## NOT to the household "users" group, which is what the old application used
## back when Open WebUI was a shared chatbot in front of a stateless model.
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
      url               = "https://josh-chat.${var.domain}/oauth/oidc/callback"
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
  meta_launch_url    = "https://josh-chat.${var.domain}"
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "openwebui_hermes_josh" {
  target = authentik_application.openwebui.uuid
  group  = authentik_group.hermes_josh.id
  order  = 0
}
