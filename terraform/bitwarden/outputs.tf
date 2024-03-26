# for s3
output "minio_secret_id" {
  value = bitwarden_item_login.minio.id
}

# for authentik
output "authentik_credential_id" {
  value = bitwarden_item_login.authentik.id
}
