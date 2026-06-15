variable "authentik_credentials_id" {
  type        = string
  description = "ID containing the authentik credentials"
}

variable "organization_id" {
  type        = string
  description = "Bitwarden organization in which to store items"
}

variable "collection_id" {
  type        = string
  description = "Collection to store resources in"
}

variable "domain" {
  type        = string
  description = "The domain for the server"
}

variable "users" {
  type = map(object({
    name   = string
    email  = string
    groups = optional(list(string), ["users"])
  }))
  default     = {}
  description = <<-EOT
    Human users to create in Authentik, keyed by username (separate from the bootstrap
    akadmin). `email` MUST match the user's GitHub primary email so the GitHub source links
    to this account via email_link. `groups` is a list of group NAMES (see the
    group_ids_by_name map in users.tf); defaults to ["users"]. None of these are superusers.
    Set this in tfvars so identities stay out of git.
  EOT
}
