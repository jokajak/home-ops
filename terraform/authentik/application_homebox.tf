## -----------------------------------------------------------------------------
## Authentik Application - Homebox
## These are resources for Homebox to use authentik for SSO
## -----------------------------------------------------------------------------

## ------------------------------------------
## Homebox - Authentication (authn) resources
## ------------------------------------------
module "homebox_oidc_creds" {
  source          = "./oidc_creds"
  application     = "homebox"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "homebox_oauth" {
  name = "homebox-provider"

  client_id     = module.homebox_oidc_creds.client_id
  client_secret = module.homebox_oidc_creds.client_secret

  # Homebox verifies the id_token with go-oidc's IDTokenVerifier, which rejects
  # HS256 — the same failure Vikunja hit. See the data source in main.tf.
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

  # Homebox's callback path is fixed at /api/v1/users/login/oidc/callback, built
  # from HBOX_OPTIONS_HOSTNAME.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://inventory.${var.domain}/api/v1/users/login/oidc/callback"
    }
  ]
}

resource "authentik_application" "homebox_application" {
  name               = "Homebox"
  slug               = authentik_provider_oauth2.homebox_oauth.name
  protocol_provider  = authentik_provider_oauth2.homebox_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/homebox.png"
  meta_launch_url    = "https://inventory.${var.domain}"
  policy_engine_mode = "any"
}

## -----------------------------------------
## Homebox - Authorization (authz) resources
## -----------------------------------------
# All users get Homebox. Note that each user's first OIDC sign-in creates a
# fresh, empty "Home" group for them; the spouse is then invited into the
# owner's group from Homebox's own UI (owner step in the plan doc).
resource "authentik_policy_binding" "homebox_users" {
  target = authentik_application.homebox_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
