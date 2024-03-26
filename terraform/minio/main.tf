data "sops_file" "this" {
  source_file = "secrets.sops.yaml"
}

module "minio" {
  for_each   = toset(var.buckets)
  source     = "./minio"
  bucketname = each.value
}

resource "bitwarden_item_login" "this" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  for_each = module.minio
  name     = "minio-tf-${each.value.service}"
  username = each.value.access_key
  password = each.value.secret_key

  field {
    name = "terraform"
    text = "true"
  }

  field {
    name = "repository"
    text = "jokajak/home-lab/terraform/minio"
  }
}
