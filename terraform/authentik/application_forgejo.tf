## -----------------------------------------------------------------------------
## Authentik Application - Forgejo
## These are resources for the Forgejo git forge to use authentik for SSO
## -----------------------------------------------------------------------------

## -----------------------------------------
## Forgejo - Authentication (authn) resources
## -----------------------------------------
module "forgejo_oidc_creds" {
  source          = "./oidc_creds"
  application     = "forgejo"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "forgejo_oauth" {
  name = "forgejo-provider"

  client_id     = module.forgejo_oidc_creds.client_id
  client_secret = module.forgejo_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  # Forgejo's OAuth2 callback. The "authentik" path segment is the name of the
  # auth source, which the Helm chart registers from gitea.oauth[0].name.
  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://git.${var.domain}/user/oauth2/authentik/callback"
    }
  ]
}

resource "authentik_application" "forgejo_application" {
  name               = "Forgejo"
  slug               = authentik_provider_oauth2.forgejo_oauth.name
  protocol_provider  = authentik_provider_oauth2.forgejo_oauth.id
  group              = authentik_group.home.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/forgejo.png"
  meta_launch_url    = "https://git.${var.domain}"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Forgejo - Authorization (authz) resources
## ----------------------------------------
# All users can access Forgejo. Forgejo has no group-driven admin role, so the
# site administrator stays the local account bootstrapped from the admin secret
# (terraform/bitwarden -> "forgejo credentials").
resource "authentik_policy_binding" "forgejo_users" {
  target = authentik_application.forgejo_application.uuid
  group  = authentik_group.users.id
  order  = 0
}
