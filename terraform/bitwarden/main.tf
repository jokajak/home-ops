locals {
  domain = data.sops_file.this.data["DOMAIN"]
}

################################################################################
# minio credentials
################################################################################
resource "random_password" "minio_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "minio" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "minio credentials"
  username = "Recoil7901"
  password = random_password.minio_password.result
  uri {
    value = "https://minio.${local.domain}"
    match = "host"
  }

  field {
    name = "terraform"
    text = "true"
  }

}

################################################################################
# cloudnative postgres credentials
################################################################################
resource "random_password" "cloudnative_pg_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "cloudnative_pg" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "cloudnative_pg credentials"
  username = "postgres"
  password = random_password.cloudnative_pg_password.result

  field {
    name = "terraform"
    text = "true"
  }
}

################################################################################
# authentik credentials
################################################################################
resource "random_password" "authentik_bootstrap_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "authentik_bootstrap_token" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "authentik_secret_key" {
  length           = 50
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "authentik_pguser" {
  length           = 12
  special          = false
  override_special = "_=+-,~"
}

resource "random_password" "authentik_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "authentik" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "authentik credentials"
  username = "akadmin"
  password = random_password.authentik_bootstrap_password.result

  uri {
    value = "https://auth.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "bootstrap_token"
    hidden = random_password.authentik_bootstrap_token.result
  }

  field {
    name   = "secret_key"
    hidden = random_password.authentik_secret_key.result
  }
}

resource "bitwarden_item_login" "authentik_pgcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "authentik pgcreds"
  username = random_password.authentik_pguser.result
  password = random_password.authentik_pgpass.result

  notes = "Used for connecting authentik to the postgres database"

  field {
    name    = "terraform"
    boolean = true
  }
}

resource "random_password" "authentik_redis_secret" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "authentik_redis" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "authentik redis"
  password = random_password.authentik_redis_secret.result

  field {
    name = "terraform"
    text = "true"
  }
}

################################################################################
# grafana credentials
################################################################################
resource "random_password" "grafana_username" {
  length  = 16
  special = false
}

resource "random_password" "grafana_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "grafana" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "grafana credentials"
  username = random_password.grafana_username.result
  password = random_password.grafana_password.result

  field {
    name = "terraform"
    text = "true"
  }

  uri {
    value = "https://grafana.${local.domain}"
    match = "host"
  }

}
################################################################################
# mqtt credentials
################################################################################
# The single MQTT account on the mosquitto broker in home-automation, used by
# both rtl-433 (publisher) and Home Assistant (subscriber).
#
# Replaces the former "emqx credentials" item, which carried a dashboard admin
# login plus a `user_password` custom field. Mosquitto has no web UI, so there
# is no admin account to hold -- one plain login item is the whole credential.
#
# The character set excludes ":" on purpose: this password is written as
# "user:password" into mosquitto's password file before being hashed, and a
# colon in the value would split the field.
resource "random_password" "mqtt_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "mqtt" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "mqtt credentials"
  username = "iot"
  password = random_password.mqtt_password.result

  field {
    name = "terraform"
    text = "true"
  }

}

################################################################################
# immich credentials
################################################################################
resource "random_password" "immich_admin_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "immich_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "immich_pg_superuser_pass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "immich" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "immich credentials"
  username = "immich_admin"
  password = random_password.immich_admin_password.result

  uri {
    value = "https://photos.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name = "pg_username"
    text = "immich"
  }

  field {
    name   = "pg_password"
    hidden = random_password.immich_pgpass.result
  }

  field {
    name   = "pg_superuser_pass"
    hidden = random_password.immich_pg_superuser_pass.result
  }
}

################################################################################
# paperless-ngx credentials
################################################################################
# Bootstraps the local paperless superuser (the fallback login when Authentik is
# unavailable) and Django's SECRET_KEY. Postgres credentials live in the separate
# `paperless pgcreds` item below — paperless moved onto the shared cluster, so the
# role is ours to generate rather than something a dedicated CNPG cluster mints.
resource "random_password" "paperless_admin_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "paperless_secret_key" {
  length  = 64
  special = false
}

resource "bitwarden_item_login" "paperless" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "paperless credentials"
  username = "admin"
  password = random_password.paperless_admin_password.result

  uri {
    value = "https://paperless.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "secret_key"
    hidden = random_password.paperless_secret_key.result
  }
}

################################################################################
# volsync restic repository password
################################################################################
# Encryption password for the VolSync/restic backup repositories in MinIO. The
# S3 credentials themselves come from the `minio-tf-backups` item (terraform/minio);
# this is only the restic repo password. Losing it makes the backups unrecoverable.
resource "random_password" "volsync_restic_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "volsync_restic" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "volsync restic"
  password = random_password.volsync_restic_password.result

  field {
    name = "terraform"
    text = "true"
  }
}

################################################################################
# forgejo credentials
################################################################################
# Bootstraps the local Forgejo site administrator — the break-glass login when
# Authentik is unavailable. Postgres credentials live in the separate
# `forgejo pgcreds` item below — forgejo moved onto the shared cluster, so the
# role is ours to generate rather than something a dedicated CNPG cluster mints.
# The OIDC client credentials are NOT here: terraform/authentik's oidc_creds
# module creates them as `authentik-client-forgejo`.
resource "random_password" "forgejo_admin_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "forgejo" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "forgejo credentials"
  username = "forgejo_admin"
  password = random_password.forgejo_admin_password.result

  uri {
    value = "https://git.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }
}

################################################################################
# Roles on the SHARED database/postgres cluster
################################################################################
# Every app that moved off its own CNPG cluster needs a role the cluster does not
# mint for it. Same shape as `authentik pgcreds`, which has always worked this
# way. postgres-init reads these and reconciles CREATE/ALTER ROLE on every app
# start, so rotating a password here and re-applying actually takes effect.
#
# The usernames are fixed and readable rather than generated: several apps now
# share one server, and `\du` on it should say who is who.
#
# See docs/plans/2026-08-24-cnpg-consolidation.md.

resource "random_password" "forgejo_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "forgejo_pgcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "forgejo pgcreds"
  username = "forgejo"
  password = random_password.forgejo_pgpass.result

  notes = "Forgejo's role on the shared database/postgres cluster"

  field {
    name    = "terraform"
    boolean = true
  }
}

resource "random_password" "paperless_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "paperless_pgcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "paperless pgcreds"
  username = "paperless"
  password = random_password.paperless_pgpass.result

  notes = "Paperless's role on the shared database/postgres cluster"

  field {
    name    = "terraform"
    boolean = true
  }
}

resource "random_password" "litellm_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "litellm_pgcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "litellm pgcreds"
  username = "litellm"
  password = random_password.litellm_pgpass.result

  notes = "LiteLLM's role on the shared database/postgres cluster"

  field {
    name    = "terraform"
    boolean = true
  }
}

################################################################################
# litellm credentials
################################################################################
# The proxy's own secrets. All four are generated — none is issued by anyone
# else — so none of them belongs in a human's hands.
#
# ⚠️ salt_key ENCRYPTS PROVIDER CREDENTIALS STORED IN LITELLM'S DATABASE AND
# CANNOT BE ROTATED. Tainting `random_password.litellm_salt_key` makes every
# credential LiteLLM has stored permanently unreadable. If it ever has to
# change, the recovery is to re-enter the upstream credentials afterwards.
resource "random_password" "litellm_master_key" {
  length  = 32
  special = false
}

resource "random_password" "litellm_salt_key" {
  length  = 32
  special = false
}

resource "random_password" "litellm_ui_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "litellm" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name = "litellm credentials"

  uri {
    value = "https://llm.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  # LiteLLM expects the master key to carry an `sk-` prefix.
  field {
    name   = "master_key"
    hidden = "sk-${random_password.litellm_master_key.result}"
  }

  field {
    name   = "salt_key"
    hidden = random_password.litellm_salt_key.result
  }

  field {
    name = "ui_username"
    text = "admin"
  }

  field {
    name   = "ui_password"
    hidden = random_password.litellm_ui_password.result
  }
}


################################################################################
# meridian credentials
################################################################################
# Gates meridian's proxy. Its API-key check is opt-in — unset means no gate at
# all — and behind that proxy sits a Claude subscription, so an unauthenticated
# listener on a cluster network is somebody else's quota to spend.
#
# Safe to rotate: it authenticates callers to meridian, and nothing durable is
# encrypted with it.
resource "random_password" "meridian_api_key" {
  length  = 48
  special = false
}

resource "bitwarden_item_login" "meridian" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name  = "meridian credentials"
  notes = "API key callers must present to meridian. Not the Claude credential — that is a login stored on the meridian-auth volume."

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "api_key"
    hidden = random_password.meridian_api_key.result
  }
}

################################################################################
# Open WebUI's LiteLLM virtual key
################################################################################
# The one credential in the platform with a genuine chicken-and-egg: LiteLLM
# mints it, so it cannot exist until LiteLLM is running — but Open WebUI's
# ExternalSecret references it, and ESO has NO per-key "optional". One
# unresolvable data[] entry and the whole target Secret is never created, so
# Open WebUI would sit waiting for a key that cannot be minted yet.
#
# So terraform owns the ITEM and the human owns the VALUE. The item is created
# with a `replace-me` sentinel, which lets ESO resolve and the workload
# reconcile; Open WebUI comes up and fails at conversation time with an auth
# error instead of failing to exist. `ignore_changes` is what makes it
# eventually consistent: paste the real key into Bitwarden and no later apply
# will revert it.
#
# ⚠️ EDIT the litellm_api_key field, never DELETE it. A missing property fails
# the whole ExternalSecret and takes Open WebUI down with it — which is also
# why the sentinel is a real string rather than "".
#
# Mint it at https://llm.<domain> once LiteLLM is up. A virtual key rather than
# the master key so the household's spend on chat is attributable and capped on
# its own budget.
#
# Replaced the per-agent `hermes josh` / `hermes partner` keys and the two
# `hermes * gateway` API-server tokens, all removed with the agents on
# 2026-09-04. Delete those four items from Bitwarden by hand; terraform will
# not, because it no longer knows they exist.

resource "bitwarden_item_login" "open_webui_litellm" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name  = "open-webui litellm"
  notes = "Open WebUI's LiteLLM virtual key. Minted in the LiteLLM admin UI, then pasted over the replace-me sentinel in litellm_api_key."

  field {
    name = "litellm_api_key"
    # NOT empty. An empty hidden field is dropped rather than stored, which
    # would leave the item with no litellm_api_key property at all — and a
    # MISSING property fails the whole ExternalSecret, the exact blocking
    # failure this resource exists to avoid.
    hidden = "replace-me"
  }

  lifecycle {
    # Terraform creates this once and then never looks at the value again, so a
    # pasted key survives every subsequent apply.
    ignore_changes = [field]
  }
}

resource "random_password" "open_webui_secret_key" {
  length           = 48
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "open_webui" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name  = "open-webui credentials"
  notes = "Signs Open WebUI session cookies. Rotating it logs everyone out and destroys nothing."

  uri {
    value = "https://chat.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "webui_secret_key"
    hidden = random_password.open_webui_secret_key.result
  }
}
