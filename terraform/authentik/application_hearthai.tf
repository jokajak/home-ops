## -----------------------------------------------------------------------------
## Authentik Application - hearthai (the household door)
##
## One hostname for the whole household. An Authentik proxy outpost protects
## https://chat.<domain> in forward-auth mode and hands ingress-nginx the
## caller's group list; a small nginx then routes to that person's agent.
##
## Access binding is deliberately broad — the `users` group, not one person.
## This application only decides who may reach the door. WHICH agent they land
## on is decided by the Hermes Josh / Hermes Partner group membership, which is
## still the real boundary and is still bound per-agent in application_hermes.tf.
## Someone in `users` but in neither household group authenticates fine and then
## gets a 403 from the router, which is the intended outcome.
## -----------------------------------------------------------------------------
resource "authentik_provider_proxy" "hearthai" {
  name               = "hearthai-provider"
  authorization_flow = resource.authentik_flow.provider-authorization-implicit-consent.uuid
  invalidation_flow  = resource.authentik_flow.invalidation.uuid
  external_host      = "https://chat.${var.domain}"
  mode               = "forward_single"
}

resource "authentik_application" "hearthai" {
  name               = "hearthai"
  slug               = "hearthai"
  protocol_provider  = authentik_provider_proxy.hearthai.id
  group              = authentik_group.home.name
  meta_launch_url    = "https://chat.${var.domain}"
  meta_description   = "The household assistant. You get your own agent, with your own memory."
  policy_engine_mode = "any"
}

# Run the Authentik-native proxy in the security namespace. Authentik deploys
# and updates this outpost through the existing local Kubernetes connection.
resource "authentik_outpost" "hearthai" {
  name               = "hearthai"
  type               = "proxy"
  protocol_providers = [authentik_provider_proxy.hearthai.id]
  service_connection = authentik_service_connection_kubernetes.local.id

  # A proxy provider does not have a usable OAuth client until it belongs to
  # an application. Without this edge OpenTofu may create the outpost and the
  # application concurrently, leaving the first outpost configuration with an
  # empty client_id until it happens to reconcile again.
  depends_on = [authentik_application.hearthai]

  config = jsonencode({
    kubernetes_namespace   = "security"
    authentik_host         = "http://authentik-server.security.svc.cluster.local:80"
    authentik_host_browser = "https://auth.${var.domain}"
  })
}

resource "authentik_policy_binding" "hearthai_users" {
  target = authentik_application.hearthai.uuid
  group  = authentik_group.users.id
  order  = 0
}
