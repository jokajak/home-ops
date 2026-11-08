## -----------------------------------------------------------------------------
## Authentik Application - Outline
## These are resources for Outline to use authentik for SSO
## -----------------------------------------------------------------------------

## ------------------------------------------
## Outline - Authentication (authn) resources
## ------------------------------------------
module "outline_oidc_creds" {
  source          = "./oidc_creds"
  application     = "outline"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "outline_oauth" {
  name = "outline-provider"

  client_id     = module.outline_oidc_creds.client_id
  client_secret = module.outline_oidc_creds.client_secret

  # No signing_key: Outline decodes the id_token for missing claims but never
  # verifies it against JWKS (plugins/oidc/server/auth/oidcRouter.ts), so the
  # HS256 default works — and main.tf asks that the RS256 key only be wired into
  # clients that need it.

  # grant_types has no useful default (Authentik's OAuth2Provider model
  # defaults it to an empty list), so an /authorize request with response_type
  # code fails check_grant() with "invalid_request". Same fix as
  # application_paperless.tf.
  grant_types = ["authorization_code", "refresh_token"]

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # Outline's callback is ${URL}/auth/<provider id>.callback, and the OIDC
  # plugin's id is `oidc`.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://wiki.${var.domain}/auth/oidc.callback"
    }
  ]
}

resource "authentik_application" "outline_application" {
  name               = "Outline"
  slug               = authentik_provider_oauth2.outline_oauth.name
  protocol_provider  = authentik_provider_oauth2.outline_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/outline.png"
  meta_launch_url    = "https://wiki.${var.domain}"
  policy_engine_mode = "any"
}

## -----------------------------------------
## Outline - Authorization (authz) resources
## -----------------------------------------
# All users get Outline. The first account to sign in creates the workspace and
# becomes its admin; everyone after joins it as a member.
resource "authentik_policy_binding" "outline_users" {
  target = authentik_application.outline_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
