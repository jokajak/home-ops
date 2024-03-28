variable "application" {
  type        = string
  description = "The name of the oidc client application"
}

variable "organization_id" {
  type        = string
  description = "Bitwarden organization in which to store items"
}

variable "collection_id" {
  type        = string
  description = "Collection to store resources in"
}
