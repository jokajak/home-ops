## -----------------------------------------------------------------------------
## Authentik Application - Vikunja
## These are resources for Vikunja to use authentik for SSO
## -----------------------------------------------------------------------------

## -----------------------------------------
## Vikunja - Authentication (authn) resources
## -----------------------------------------
module "vikunja_oidc_creds" {
  source          = "./oidc_creds"
  application     = "vikunja"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "vikunja_oauth" {
  name = "vikunja-provider"

  client_id     = module.vikunja_oidc_creds.client_id
  client_secret = module.vikunja_oidc_creds.client_secret

  # grant_types has no useful default (Authentik's OAuth2Provider model
  # defaults it to an empty list), so an /authorize request with response_type
  # code fails check_grant() with "invalid_request". Same fix as
  # application_paperless.tf.
  grant_types = ["authorization_code", "refresh_token"]

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # Vikunja builds its callback from the provider's `name` in config.yml, which
  # is `authentik` — see the vikunja-config ExternalSecret.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://tasks.${var.domain}/auth/openid/authentik"
    }
  ]
}

resource "authentik_application" "vikunja_application" {
  name               = "Vikunja"
  slug               = authentik_provider_oauth2.vikunja_oauth.name
  protocol_provider  = authentik_provider_oauth2.vikunja_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/vikunja.png"
  meta_launch_url    = "https://tasks.${var.domain}"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Vikunja - Authorization (authz) resources
## ----------------------------------------
# All users get Vikunja. It has no group-driven admin role; project sharing is
# per-project inside the app, and the first account to sign in is just a user
# like any other.
resource "authentik_policy_binding" "vikunja_users" {
  target = authentik_application.vikunja_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
