## -----------------------------------------------------------------------------
## Authentik Applications - Hermes household agents
##
## One OIDC application per agent, because each agent holds one person's private
## memory. The Hermes dashboard verifies any ID token issued for its client_id
## and does not itself filter by user, so **the application's policy binding is
## the entire access boundary**: whoever Authentik will issue a token to can read
## everything that agent remembers.
##
## Hence a group per agent, each with exactly one member. Membership is assigned
## in the (encrypted) users.sops.yaml by group name.
##
## These are PUBLIC clients: the dashboard's self-hosted OIDC plugin uses
## authorization-code + PKCE (S256) and never sends a client secret. The
## oidc_creds module still mints one and stores it in Bitwarden alongside the
## client id so the item matches every other application here; nothing consumes
## it, and nothing should start to.
## -----------------------------------------------------------------------------

## ------------------------------------------
## Groups — one member each, the access boundary
## ------------------------------------------
resource "authentik_group" "hermes_josh" {
  name         = "Hermes Josh"
  is_superuser = false
}

resource "authentik_group" "hermes_partner" {
  name         = "Hermes Partner"
  is_superuser = false
}

## ------------------------------------------
## Josh's agent — behind https://chat.<domain>
## ------------------------------------------
module "hermes_josh_oidc_creds" {
  source          = "./oidc_creds"
  application     = "hermes-josh"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "hermes_josh" {
  name = "hermes-josh-provider"

  client_id     = module.hermes_josh_oidc_creds.client_id
  client_secret = module.hermes_josh_oidc_creds.client_secret
  # PKCE, no secret on the wire. The dashboard plugin is a browser SPA flow.
  client_type = "public"

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # <dashboard public URL>/auth/callback. Both agents now advertise the SAME
  # public URL — the shared hearthai door — so both register the same redirect.
  # That is fine: they are separate OIDC clients, and the router sends the
  # callback back to whichever agent the caller's group maps to.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://chat.${var.domain}/auth/callback"
    }
  ]
}

resource "authentik_application" "hermes_josh" {
  name = "Hermes (Josh)"
  # The slug IS the issuer path: https://auth.<domain>/application/o/<slug>/.
  # HERMES_DASHBOARD_OIDC_ISSUER in the HelmRelease hardcodes "hermes-josh",
  # and the plugin pins the iss claim to it — so do not rename this.
  slug               = "hermes-josh"
  protocol_provider  = authentik_provider_oauth2.hermes_josh.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_launch_url    = "https://chat.${var.domain}"
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "hermes_josh" {
  target = authentik_application.hermes_josh.uuid
  group  = authentik_group.hermes_josh.id
  order  = 0
}

## ------------------------------------------
## Partner's agent — also behind https://chat.<domain>
## ------------------------------------------
module "hermes_partner_oidc_creds" {
  source          = "./oidc_creds"
  application     = "hermes-partner"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "hermes_partner" {
  name = "hermes-partner-provider"

  client_id     = module.hermes_partner_oidc_creds.client_id
  client_secret = module.hermes_partner_oidc_creds.client_secret
  client_type   = "public"

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://chat.${var.domain}/auth/callback"
    }
  ]
}

resource "authentik_application" "hermes_partner" {
  name               = "Hermes (Partner)"
  slug               = "hermes-partner"
  protocol_provider  = authentik_provider_oauth2.hermes_partner.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_launch_url    = "https://chat.${var.domain}"
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "hermes_partner" {
  target = authentik_application.hermes_partner.uuid
  group  = authentik_group.hermes_partner.id
  order  = 0
}
