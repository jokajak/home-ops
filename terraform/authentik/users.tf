## -----------------------------------------------------------------------------
## Human users (declarative, from a SOPS-encrypted YAML file committed to git)
## Kept separate from the bootstrap `akadmin` account. None are superusers.
## Each logs in via the GitHub source: email_link matches the user's email to the
## GitHub identity (so each user's `email` must equal their GitHub primary email).
##
## Definitions live in `users.sops.yaml` (encrypted, safe to commit) as a LIST of users
## with `username` as a field, so the repo's SOPS rule encrypts every value — usernames
## included — and nothing about the users is readable in git.
##
## Bootstrap from users.sops.yaml.example, then:
##   task sops:encrypt file=terraform/authentik/users.sops.yaml
## Edit later with: sops terraform/authentik/users.sops.yaml
## -----------------------------------------------------------------------------

data "sops_file" "users" {
  source_file = "users.sops.yaml"
}

## Map of group NAME -> id so the users file can reference groups by name instead of
## computed UUIDs. Add a row here when a new group should be assignable.
locals {
  group_ids_by_name = {
    "users"           = authentik_group.users.id
    "home"            = authentik_group.home.id
    "infrastructure"  = authentik_group.infrastructure.id
    "media"           = authentik_group.media.id
    "admins"          = authentik_group.admins.id
    "people"          = authentik_group.people.id
    "Monitoring"      = authentik_group.monitoring.id
    "Grafana Admins"  = authentik_group.grafana_admin.id
    "Grafana Editors" = authentik_group.grafana_editors.id
    "Grafana Viewers" = authentik_group.grafana_viewers.id
  }

  # .raw is the decrypted file (may also carry a `sops` metadata key); `users` is a list.
  # Re-key it by username for for_each.
  users = { for u in yamldecode(data.sops_file.users.raw)["users"] : u.username => u }
}

resource "authentik_user" "this" {
  for_each = local.users

  username = each.value.username
  name     = each.value.name
  email    = each.value.email
  type     = "internal"

  # groups defaults to ["users"] if omitted for a user
  groups = [for g in try(each.value.groups, ["users"]) : local.group_ids_by_name[g]]
}
