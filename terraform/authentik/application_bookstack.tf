## -----------------------------------------------------------------------------
## Authentik Application - BookStack
## These are resources for BookStack to use authentik for SSO
## -----------------------------------------------------------------------------

## -------------------------------------------
## BookStack - Authentication (authn) resources
## -------------------------------------------
module "bookstack_oidc_creds" {
  source          = "./oidc_creds"
  application     = "bookstack"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "bookstack_oauth" {
  name = "bookstack-provider"

  client_id     = module.bookstack_oidc_creds.client_id
  client_secret = module.bookstack_oidc_creds.client_secret

  # BookStack fetches JWKS and errors on the HS256 default, which publishes no
  # keys. Same requirement as Open WebUI; see the data source in main.tf.
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

  # BookStack's OIDC callback path is fixed at /oidc/callback.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://wiki.${var.domain}/oidc/callback"
    }
  ]
}

resource "authentik_application" "bookstack_application" {
  name               = "BookStack"
  slug               = authentik_provider_oauth2.bookstack_oauth.name
  protocol_provider  = authentik_provider_oauth2.bookstack_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/bookstack.png"
  meta_launch_url    = "https://wiki.${var.domain}"
  policy_engine_mode = "any"
}

## ------------------------------------------
## BookStack - Authorization (authz) resources
## ------------------------------------------
# All users can reach the wiki. BookStack roles are not group-driven here
# (OIDC_USER_TO_GROUPS is off): the first person in becomes the admin and
# assigns roles in Settings -> Roles by hand, the same way Paperless is run.
resource "authentik_policy_binding" "bookstack_users" {
  target = authentik_application.bookstack_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
