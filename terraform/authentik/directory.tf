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
