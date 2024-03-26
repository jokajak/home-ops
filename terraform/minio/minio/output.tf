output "access_key" {
  value       = minio_iam_service_account.this.access_key
  description = "The access key for the service account."
}

output "secret_key" {
  value       = minio_iam_service_account.this.secret_key
  sensitive   = true
  description = "The secret key for the service account."
}

output "service" {
  value       = var.bucketname
  description = "The name of the service."
}
