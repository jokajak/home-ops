# Matrix SSO; same household access groups as Open WebUI.
module "mindroom_oidc_creds" {
  source          = "./oidc_creds"
  application     = "mindroom"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "mindroom" {
  name = "mindroom-provider"

  client_id     = module.mindroom_oidc_creds.client_id
  client_secret = module.mindroom_oidc_creds.client_secret
  client_type   = "confidential"

  signing_key = data.authentik_certificate_key_pair.default_signing.id

  # grant_types has no useful default — Authentik's model defaults it to an
  # empty list, and an /authorize with response_type code then fails as
  # "Invalid grant_type for provider".
  grant_types = ["authorization_code", "refresh_token"]

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://matrix.${var.domain}/_matrix/client/unstable/login/sso/callback/${module.mindroom_oidc_creds.client_id}"
    }
  ]
}

resource "authentik_application" "mindroom" {
  name               = "Mindroom"
  slug               = "mindroom"
  protocol_provider  = authentik_provider_oauth2.mindroom.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_launch_url    = "https://chat.${var.domain}"
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "mindroom_hermes_josh" {
  target = authentik_application.mindroom.uuid
  group  = authentik_group.hermes_josh.id
  order  = 0
}

resource "authentik_policy_binding" "mindroom_hermes_partner" {
  target = authentik_application.mindroom.uuid
  group  = authentik_group.hermes_partner.id
  order  = 10
}
