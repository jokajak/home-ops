## -----------------------------------------------------------------------------
## Human users (declarative, from the `users` input variable)
## Kept separate from the bootstrap `akadmin` account. None are superusers.
## Each logs in via the GitHub source: email_link matches the user's email to the
## GitHub identity (so each user's `email` must equal their GitHub primary email).
## -----------------------------------------------------------------------------

## Map of group NAME -> id so the `users` variable can reference groups by name
## instead of computed UUIDs. Add a row here when a new group should be assignable.
locals {
  group_ids_by_name = {
    "users"           = authentik_group.users.id
    "home"            = authentik_group.home.id
    "infrastructure"  = authentik_group.infrastructure.id
    "media"           = authentik_group.media.id
    "Monitoring"      = authentik_group.monitoring.id
    "Grafana Admins"  = authentik_group.grafana_admin.id
    "Grafana Editors" = authentik_group.grafana_editors.id
    "Grafana Viewers" = authentik_group.grafana_viewers.id
  }
}

resource "authentik_user" "this" {
  for_each = var.users

  username = each.key
  name     = each.value.name
  email    = each.value.email
  type     = "internal"

  groups = [for g in each.value.groups : local.group_ids_by_name[g]]
}
