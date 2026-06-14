variable "authentik_credentials_id" {
  type        = string
  description = "ID containing the authentik credentials"
}

variable "github_oauth_credentials_id" {
  type        = string
  description = "ID containing the github oauth credentials"
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
