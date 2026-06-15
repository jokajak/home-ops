## -----------------------------------------------------------------------------
## Authentik groups
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

resource "authentik_group" "media" {
  name         = "Media"
  is_superuser = false
  parent       = resource.authentik_group.users.id
}

## "people" maps to Grafana's Viewer role (see grafana role_attribute_path:
## contains(groups[*], 'people') && 'Viewer'). Members also need an access binding to
## each app they should reach (e.g. authentik_policy_binding.people_grafana).
resource "authentik_group" "people" {
  name         = "people"
  is_superuser = false
}
