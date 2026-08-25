## -----------------------------------------------------------------------------
## Authentik Application - hearthai (the household door)
##
## One hostname for the whole household. oauth2-proxy sits behind
## https://hearthai.<domain>, authenticates every request against this
## application, and hands ingress-nginx the caller's group list; a small nginx
## then routes to that person's agent.
##
## Unlike the per-agent dashboard clients, this is a CONFIDENTIAL client:
## oauth2-proxy runs server-side and holds the secret, so no PKCE-public
## client_type here.
##
## Access binding is deliberately broad — the `users` group, not one person.
## This application only decides who may reach the door. WHICH agent they land
## on is decided by the Hermes Josh / Hermes Partner group membership, which is
## still the real boundary and is still bound per-agent in application_hermes.tf.
## Someone in `users` but in neither household group authenticates fine and then
## gets a 403 from the router, which is the intended outcome.
## -----------------------------------------------------------------------------
module "hearthai_oidc_creds" {
  source          = "./oidc_creds"
  application     = "hearthai"
  organization_id = var.organization_id
  collection_id   = var.collection_id
}

resource "authentik_provider_oauth2" "hearthai" {
  name = "hearthai-provider"

  client_id     = module.hearthai_oidc_creds.client_id
  client_secret = module.hearthai_oidc_creds.client_secret
  client_type   = "confidential"

  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid

  # The default `profile` scope mapping carries the group list, which is what
  # the router keys off. Dropping profile here silently breaks routing.
  property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids

  access_token_validity = "hours=8"

  allowed_redirect_uris = [
    {
      matching_mode     = "strict",
      redirect_uri_type = "authorization",
      url               = "https://hearthai.${var.domain}/oauth2/callback"
    }
  ]
}

resource "authentik_application" "hearthai" {
  name               = "hearthai"
  slug               = "hearthai"
  protocol_provider  = authentik_provider_oauth2.hearthai.id
  group              = authentik_group.home.name
  meta_launch_url    = "https://hearthai.${var.domain}"
  meta_description   = "The household assistant. You get your own agent, with your own memory."
  policy_engine_mode = "any"
}

resource "authentik_policy_binding" "hearthai_users" {
  target = authentik_application.hearthai.uuid
  group  = authentik_group.users.id
  order  = 0
}
