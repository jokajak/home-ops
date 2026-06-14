## -----------------------------------------------------------------------------
## Authentik Source - Google
## Lets the existing Authentik account be logged into with a Google identity.
## Adds a "Login with Google" button to the main login (identification) screen.
##
## Owner prerequisites (see docs/plans/2026-06-14-authentik-google-sso.md):
##   - Google Cloud OAuth client (Web application) with authorized redirect URI:
##       https://auth.${var.domain}/source/oauth/callback/google/
##   - Bitwarden login item (username = client_id, password = client_secret),
##     referenced by var.google_oauth_credentials_id.
## -----------------------------------------------------------------------------

data "bitwarden_item_login" "google_oidc_creds" {
  id = var.google_oauth_credentials_id
}

## Standard built-in source flows shipped with Authentik. Using these (rather than
## the provider-authorization flow) is the documented setup for a social source.
data "authentik_flow" "default-source-authentication" {
  slug = "default-source-authentication"
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
}

## Built-in "authentik" source — kept on the identification stage so username/password
## login stays available alongside the Google button.
data "authentik_source" "inbuilt" {
  managed = "goauthentik.io/sources/inbuilt"
}
