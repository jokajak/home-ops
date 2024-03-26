variable "minio_secret_id" {
  type        = string
  description = "ID containing the minio credentials"
}

variable "buckets" {
  type        = list(string)
  default     = ["backups", "logs", "databases"]
  description = "Buckets to create in s3"
}

variable "terraform_organization" {
  type        = string
  description = "My Cloud Organization"
}

variable "collection_id" {
  type        = string
  description = "Collection to store resources in"
}

variable "domain" {
  type        = string
  description = "The domain for the server"
}
