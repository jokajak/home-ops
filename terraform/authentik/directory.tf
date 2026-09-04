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

## Single-member household groups. They were created per Hermes agent, where
## each was the entire access boundary on one person's private memory; the
## agents are gone (2026-09-04) and these now do one job: gate who may sign in
## to Open WebUI (application_openwebui.tf).
##
## ⚠️ The NAMES are load-bearing and cannot be changed from here alone.
## users.sops.yaml assigns membership by group name and users.tf resolves those
## names through group_ids_by_name, so renaming one here without editing the
## encrypted file in the same change makes `tofu apply` fail on a missing key.
## Renaming them to something Hermes-free is worth doing; it is an owner step,
## not a repo-only one.
resource "authentik_group" "hermes_josh" {
  name         = "Hermes Josh"
  is_superuser = false
}

resource "authentik_group" "hermes_partner" {
  name         = "Hermes Partner"
  is_superuser = false
}
