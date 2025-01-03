data "sops_file" "this" {
  source_file = "secrets.sops.yaml"
}

data "authentik_flow" "default-authorization-flow" {
  slug = "default-provider-authorization-implicit-consent"
}

data "bitwarden_item_login" "oidc_creds" {
  id = var.github_oauth_credentials_id
}

################################################################################
# Flow management
#
# The intention is to allow login with social logins like github and google
################################################################################
# Create identification stage with sources and showing a password field

## --------------------------------------------------------------------------------
## Set username automatically for google logins
## Per https://goauthentik.io/integrations/sources/google/#username-mapping
## --------------------------------------------------------------------------------
resource "authentik_policy_expression" "google_username" {
  name       = "Set Username"
  expression = <<-EOT
    email = request.context["prompt_data"]["email"]
    # Set username to email without domain
    # request.context["prompt_data"]["username"] = email.split("@")[0]
    return False
  EOT
}

## ------------------------------------------------------------
## Create a oauth provider for google
## Support logging in with a google account
## ------------------------------------------------------------
resource "authentik_source_oauth" "github" {
  name = "github"
  slug = "github"

  authentication_flow = data.authentik_flow.default-authorization-flow.id
  enrollment_flow     = authentik_flow.enrollment-invitation.uuid

  provider_type   = "github"
  consumer_key    = data.bitwarden_item_login.oidc_creds.username
  consumer_secret = data.bitwarden_item_login.oidc_creds.password

  oidc_jwks_url = "https://token.actions.githubusercontent.com/.well-known/jwks"
}

data "authentik_property_mapping_provider_scope" "oauth2" {
  managed_list = [
    "goauthentik.io/providers/oauth2/scope-openid",
    "goauthentik.io/providers/oauth2/scope-email",
    "goauthentik.io/providers/oauth2/scope-profile"
  ]
}
