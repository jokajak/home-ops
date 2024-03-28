## -----------------------------------------------------------------------------
## Authentik hierarchy configurations
## -----------------------------------------------------------------------------
resource "authentik_group" "users" {
  name         = "users"
  is_superuser = false
}

resource "authentik_group" "home" {
  name         = "Home"
  is_superuser = false
}

resource "authentik_group" "infrastructure" {
  name         = "Infrastructure"
  is_superuser = false
}

resource "authentik_policy_binding" "gitops_infra" {
  target = authentik_application.weave_application.uuid
  group  = authentik_group.infrastructure.id
  order  = 0
}

resource "authentik_policy_binding" "grafana_infra" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.infrastructure.id
  order  = 0
}

resource "authentik_group" "media" {
  name         = "Media"
  is_superuser = false
  parent       = resource.authentik_group.users.id
}

resource "authentik_group" "grafana_admin" {
  name         = "Grafana Admins"
  is_superuser = false
}

resource "authentik_group" "grafana_editors" {
  name         = "Grafana Editors"
  is_superuser = false
}

resource "authentik_group" "grafana_viewers" {
  name         = "Grafana Viewers"
  is_superuser = false
}

resource "authentik_policy_binding" "grafana_admins" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.grafana_admin.id
  order  = 0
}

resource "authentik_policy_binding" "grafana_editors" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.grafana_editors.id
  order  = 10
}

resource "authentik_policy_binding" "grafana_viewers" {
  target = authentik_application.grafana_application.uuid
  group  = authentik_group.grafana_viewers.id
  order  = 20
}

resource "authentik_group" "monitoring" {
  name         = "Monitoring"
  is_superuser = false
  parent       = resource.authentik_group.grafana_admin.id
}
