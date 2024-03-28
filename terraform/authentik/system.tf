resource "authentik_brand" "home" {
  domain           = var.domain
  default          = false
  branding_title   = "Home"
  branding_logo    = "/static/dist/assets/icons/icon_left_brand.svg"
  branding_favicon = "/static/dist/assets/icons/icon.png"

  flow_authentication = authentik_flow.authentication.uuid
  flow_invalidation   = authentik_flow.invalidation.uuid
  flow_user_settings  = authentik_flow.user-settings.uuid
}

resource "authentik_service_connection_kubernetes" "local" {
  name  = "local"
  local = true
}
