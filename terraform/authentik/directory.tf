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
  parents      = [resource.authentik_group.users.id]
}

## "readers" maps to Grafana's Viewer role (see grafana role_attribute_path:
## contains(groups[*], 'readers') && 'Viewer'). Members also need an access binding to
## each app they should reach (e.g. authentik_policy_binding.readers_grafana).
resource "authentik_group" "readers" {
  name         = "readers"
  is_superuser = false
}
