## -----------------------------------------------------------------------------
## Authentik Source - Google
## Lets the existing Authentik account be logged into with a Google identity.
## Adds a "Login with Google" button to the main login (identification) screen.
##
## Owner prerequisites:
##   - Google Cloud OAuth client (Web application) created under the jokajak
##     consumer Gmail account, with authorized redirect URI:
##       https://auth.${var.domain}/source/oauth/callback/google/
##   - OAuth consent screen user type = External (any Google account, incl. the
##     domain-managed login identity, can sign in).
##   - Bitwarden login item named "authentik-google-creds" (username = client_id,
##     password = client_secret), mirroring "authentik-github-creds".
##
## The default-source-authentication flow and the inbuilt source data sources are
## already declared in main.tf; this file reuses them.
## -----------------------------------------------------------------------------

## Google OAuth client creds, looked up by Bitwarden item name (scoped to the
## configured org + collection), matching the authentik-<provider>-creds convention.
data "bitwarden_item_login" "google_oidc_creds" {
  search                 = "authentik-google-creds"
  filter_organization_id = var.organization_id
  filter_collection_id   = var.collection_id
}

resource "authentik_source_oauth" "google" {
  name = "google"
  slug = "google" # drives the callback URL: /source/oauth/callback/google/

  authentication_flow = data.authentik_flow.default-source-authentication.id
  enrollment_flow     = authentik_flow.enrollment-invitation.uuid

  provider_type   = "google"
  consumer_key    = data.bitwarden_item_login.google_oidc_creds.username
  consumer_secret = data.bitwarden_item_login.google_oidc_creds.password

  # Link a Google login to the existing Authentik user with the same email
  # instead of provisioning a brand-new user.
  user_matching_mode = "email_link"

  # For provider_type=google Authentik derives the OIDC endpoint URLs server-side
  # (authorize/token/jwks/userinfo). They aren't set in config, so the provider
  # plans to null them on every run; ignore them to avoid a perpetual no-op diff.
  lifecycle {
    ignore_changes = [
      access_token_url,
      authorization_url,
      oidc_jwks_url,
      profile_url,
    ]
  }
}
