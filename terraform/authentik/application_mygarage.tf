## -----------------------------------------------------------------------------
## Authentik Application - MyGarage
## These are resources for MyGarage to use authentik for SSO
## -----------------------------------------------------------------------------

## ------------------------------------------
## MyGarage - Authentication (authn) resources
## ------------------------------------------
module "mygarage_oidc_creds" {
  source          = "./oidc_creds"
  application     = "mygarage"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "mygarage_oauth" {
  name = "mygarage-provider"

  client_id     = module.mygarage_oidc_creds.client_id
  client_secret = module.mygarage_oidc_creds.client_secret

  # MyGarage verifies the id_token against the provider's JWKS with joserfc and
  # accepts only EdDSA and RS256 — an HS256 token is signed with the client
  # secret and has no JWKS entry at all, so the callback fails. Same
  # requirement as Vikunja and BookStack; see the data source in main.tf.
  signing_key = data.authentik_certificate_key_pair.default_signing.id

  # grant_types has no useful default (Authentik's OAuth2Provider model
  # defaults it to an empty list), so an /authorize request with response_type
  # code fails check_grant() with "invalid_request". Same fix as
  # application_paperless.tf.
  grant_types = ["authorization_code", "refresh_token"]

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # MyGarage's callback path is fixed at /api/auth/oidc/callback. It
  # auto-generates the same value into Settings -> System -> OIDC, so leave the
  # "Redirect URI" box there empty rather than risking a trailing-slash
  # mismatch against this strict entry.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://garage.${var.domain}/api/auth/oidc/callback"
    }
  ]
}

# dashboard-icons has no MyGarage entry (its `garage.png` is the unrelated
# Deuxfleurs object store), so meta_icon below is the app's own PWA icon.
resource "authentik_application" "mygarage_application" {
  name               = "MyGarage"
  slug               = authentik_provider_oauth2.mygarage_oauth.name
  protocol_provider  = authentik_provider_oauth2.mygarage_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/homelabforge/mygarage/main/frontend/public/icon-192.png"
  meta_launch_url    = "https://garage.${var.domain}"
  policy_engine_mode = "any"
}

## -----------------------------------------
## MyGarage - Authorization (authz) resources
## -----------------------------------------
# All users get MyGarage. Admin is not group-driven here: the app has an
# oidc_admin_group setting, but it is left empty and the first account to sign
# in becomes the admin, the same way BookStack and Vikunja are handled.
resource "authentik_policy_binding" "mygarage_users" {
  target = authentik_application.mygarage_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
