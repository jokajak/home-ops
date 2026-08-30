## -----------------------------------------------------------------------------
## Authentik Application - Paperless-ngx
## These are resources for paperless-ngx to use authentik for SSO
## -----------------------------------------------------------------------------

## -------------------------------------------
## Paperless - Authentication (authn) resources
## -------------------------------------------
module "paperless_oidc_creds" {
  source          = "./oidc_creds"
  application     = "paperless"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "paperless_oauth" {
  name = "paperless-provider"

  client_id     = module.paperless_oidc_creds.client_id
  client_secret = module.paperless_oidc_creds.client_secret

  # grant_types has no useful default (Authentik's OAuth2Provider model
  # defaults it to an empty list), so an /authorize request with response_type
  # code fails check_grant() with "invalid_request" / "Invalid grant_type for
  # provider" unless this is set explicitly. Same fix as application_hermes.tf
  # and application_openwebui.tf.
  grant_types = ["authorization_code", "refresh_token"]

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # django-allauth's openid_connect provider callback. The "authentik" path
  # segment is the provider_id in PAPERLESS_SOCIALACCOUNT_PROVIDERS.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://paperless.${var.domain}/accounts/oidc/authentik/login/callback/"
    }
  ]
}

resource "authentik_application" "paperless_application" {
  name               = "Paperless"
  slug               = authentik_provider_oauth2.paperless_oauth.name
  protocol_provider  = authentik_provider_oauth2.paperless_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/paperless.png"
  meta_launch_url    = "https://paperless.${var.domain}"
  policy_engine_mode = "any"
}

## ------------------------------------------
## Paperless - Authorization (authz) resources
## ------------------------------------------
# All users can access Paperless. Paperless has no group-driven admin role, so
# the superuser stays the local account bootstrapped from PAPERLESS_ADMIN_USER
# (terraform/bitwarden -> "paperless credentials").
resource "authentik_policy_binding" "paperless_users" {
  target = authentik_application.paperless_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
