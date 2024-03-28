## -----------------------------------------------------------------------------
## Authentik Applications
## These are the applications that can use authentik for sso
## -----------------------------------------------------------------------------

## ----------------------------------------
## Grafana - Graphing UI
## ----------------------------------------
module "grafana_oidc_creds" {
  source          = "./oidc_creds"
  application     = "grafana"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "grafana_oauth" {
  name = "grafana-provider"

  client_id     = module.grafana_oidc_creds.client_id
  client_secret = module.grafana_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings  = data.authentik_scope_mapping.oauth2.ids

  access_token_validity = "hours=8"

  redirect_uris = ["https://grafana.${var.domain}/login/generic_oauth"]

}

resource "authentik_application" "grafana_application" {
  name               = "Grafana"
  slug               = authentik_provider_oauth2.grafana_oauth.name
  protocol_provider  = authentik_provider_oauth2.grafana_oauth.id
  group              = authentik_group.monitoring.name
  open_in_new_tab    = true
  meta_icon          = "https://raw.githubusercontent.com/walkxcode/dashboard-icons/main/png/grafana.png"
  meta_launch_url    = "https://grafana.${var.domain}/login/generic_oauth"
  policy_engine_mode = "any"
}

## ----------------------------------------
## Weave - GitOps UI
## ----------------------------------------
module "weave_oidc_creds" {
  source          = "./oidc_creds"
  application     = "weave"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "weave_oauth" {
  name          = "gitops-provider"
  client_id     = module.weave_oidc_creds.client_id
  client_secret = module.weave_oidc_creds.client_secret

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  property_mappings  = data.authentik_scope_mapping.oauth2.ids

  access_token_validity = "hours=8"

  redirect_uris = ["https://gitops.${var.domain}/oauth2/callback"]
}

resource "authentik_application" "weave_application" {
  name               = "weave"
  slug               = authentik_provider_oauth2.weave_oauth.name
  protocol_provider  = authentik_provider_oauth2.weave_oauth.id
  group              = authentik_group.infrastructure.name
  open_in_new_tab    = true
  meta_icon          = "https://docs.gitops.weave.works/img/weave-logo.png"
  meta_launch_url    = "https://gitops.${var.domain}/login/generic_oauth"
  policy_engine_mode = "any"
}
