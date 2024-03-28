output "client_id" {
  value       = random_password.client_id.result
  description = "The client id for the oidc client."
}

output "client_secret" {
  value       = random_password.client_secret.result
  sensitive   = true
  description = "The client secret for the oidc client"
}
