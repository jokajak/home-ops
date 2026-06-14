data "sops_file" "this" {
  source_file = "secrets.sops.yaml"
}

## Standard built-in flow Authentik uses to authenticate via an external source.
data "authentik_flow" "default-source-authentication" {
  slug = "default-source-authentication"
}

## Built-in "authentik" source — kept on the identification stage so username/password
## login stays available alongside the social-login button(s).
data "authentik_source" "inbuilt" {
  managed = "goauthentik.io/sources/inbuilt"
}

## GitHub OAuth client creds, looked up by Bitwarden item name (scoped to the configured
## org + collection), matching the authentik-<provider>-creds convention.
data "bitwarden_item_login" "github_oidc_creds" {
  search                 = "authentik-github-creds"
  filter_organization_id = var.organization_id
  filter_collection_id   = var.collection_id
}

################################################################################
## Social login sources
## Let the existing Authentik account be logged into with an external identity.
## Each source adds a button to the login (identification) screen; it is bound
## there via authentik_stage_identification.authentication-identification.sources.
################################################################################

## ------------------------------------------------------------
## GitHub — log in to Authentik with a GitHub account.
## Uses Authentik's built-in GitHub provider type, so the authorize/token/profile
## URLs are handled internally (no oidc_jwks_url — that GitHub-Actions OIDC URL was
## for CI tokens, not user login).
## ------------------------------------------------------------
resource "authentik_source_oauth" "github" {
  name = "github"
  slug = "github" # drives the callback URL: /source/oauth/callback/github/

  authentication_flow = data.authentik_flow.default-source-authentication.id
  enrollment_flow     = authentik_flow.enrollment-invitation.uuid

  provider_type   = "github"
  consumer_key    = data.bitwarden_item_login.github_oidc_creds.username
  consumer_secret = data.bitwarden_item_login.github_oidc_creds.password

  # Link a GitHub login to the existing Authentik user with the same email
  # instead of provisioning a brand-new user.
  user_matching_mode = "email_link"
}

data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile"
  ]
}
