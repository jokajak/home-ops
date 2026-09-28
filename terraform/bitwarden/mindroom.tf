# Mindroom trial: infrastructure secrets are generated here. The model key is
# minted by LiteLLM once and stored separately so OpenTofu never overwrites it.
resource "random_password" "mindroom" {
  for_each = toset(["registration_token", "api_key", "sandbox_proxy_token"])
  length   = 48
  special  = false
}

resource "bitwarden_item_login" "mindroom" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]
  name            = "mindroom credentials"
  notes           = "Matrix registration token, Mindroom dashboard API key, and worker proxy token. Register the human owner before enabling the runtime."

  uri {
    value = "https://mindroom.${local.domain}"
    match = "host"
  }

  dynamic "field" {
    for_each = random_password.mindroom
    content {
      name   = field.key
      hidden = field.value.result
    }
  }
}

resource "bitwarden_item_login" "mindroom_litellm" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]
  name            = "mindroom litellm"
  notes           = "Mint a Mindroom-only LiteLLM virtual key allowing gpt-5.6-sol, then replace the sentinel. This is not an upstream provider key or LiteLLM master key."

  field {
    name   = "litellm_api_key"
    hidden = "replace-me"
  }

  lifecycle {
    ignore_changes = [field]
  }
}
