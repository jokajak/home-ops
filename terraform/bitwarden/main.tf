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

################################################################################
# n8n credentials
################################################################################
# Workflow automation in the `ai` namespace (kubernetes/apps/ai/n8n).
#
# Two secrets, both generated, both consumed by the same ExternalSecret.
#
# ⚠️ THE ENCRYPTION KEY CANNOT BE ROTATED. It encrypts every credential n8n
# stores in its database — the API tokens workflows use to reach anything else.
# Tainting `random_password.n8n_encryption_key` makes all of them permanently
# unreadable, exactly like litellm's salt key.
#
# The owner account is the instance's only login: n8n's SAML/OIDC support is an
# enterprise feature, so there is no Authentik application for it and no
# `terraform/authentik` resource. It is pre-provisioned from the environment
# rather than typed into a setup form — see the HelmRelease for the env vars —
# which is why the password is generated here like paperless's admin password
# and authentik's bootstrap password, rather than being invented by a human.
resource "random_password" "n8n_encryption_key" {
  length  = 64
  special = false
}

# Alphanumeric on purpose: this value is bcrypt-hashed below and also typed
# into a login form, and n8n's own validator wants at least one digit and one
# uppercase letter (8-64 chars). No special characters means nothing to escape
# on the way through either path.
resource "random_password" "n8n_owner_password" {
  length      = 32
  special     = false
  min_numeric = 1
  min_upper   = 1
}

resource "bitwarden_item_login" "n8n" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name = "n8n credentials"

  # The owner login. n8n keys the account on the email, so this is the one
  # field that must match N8N_INSTANCE_OWNER_EMAIL exactly — the ExternalSecret
  # reads it from here so there is only one place to change it.
  username = "siteadmin@${local.domain}"
  password = random_password.n8n_owner_password.result

  notes = "n8n owner login, plus the key that encrypts its stored workflow credentials. Rotating encryption_key makes every one of those credentials unreadable — do not."

  uri {
    value = "https://n8n.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "encryption_key"
    hidden = random_password.n8n_encryption_key.result
  }

  # n8n takes a pre-hashed password in N8N_INSTANCE_OWNER_PASSWORD_HASH; a
  # plaintext value there does not fail loudly, it just makes login impossible.
  # cost 10 matches n8n's own SALT_ROUNDS.
  field {
    name   = "owner_password_hash"
    hidden = bcrypt(random_password.n8n_owner_password.result, 10)
  }

  lifecycle {
    # bcrypt() salts randomly, so it returns a different hash on every single
    # evaluation even though the password has not changed. Without this the
    # item would show a diff on every plan and rewrite the hash on every apply
    # — churning the Secret, and with reloader, restarting the pod. Hashing
    # once at create time and never looking again is the whole point.
    #
    # ⚠️ This freezes every `field` on this item, encryption_key included.
    # That is deliberate for the key (it must never change), but it does mean
    # adding a new field here later requires tainting the item or setting it in
    # Bitwarden by hand. Same trade the `open-webui litellm` item makes.
    ignore_changes = [field]
  }
}

resource "random_password" "n8n_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "n8n_pgcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "n8n pgcreds"
  username = "n8n"
  password = random_password.n8n_pgpass.result

  notes = "n8n's role on the shared database/postgres cluster"

  field {
    name    = "terraform"
    boolean = true
  }
}

resource "random_password" "vikunja_pgpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "vikunja_pgcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "vikunja pgcreds"
  username = "vikunja"
  password = random_password.vikunja_pgpass.result

  notes = "Vikunja's role on the shared database/postgres cluster"

  field {
    name    = "terraform"
    boolean = true
  }
}

################################################################################
# vikunja credentials
################################################################################
# Signs Vikunja's session JWTs. Rotating it invalidates every logged-in session,
# so treat it as write-once. Vikunja has no local admin to bootstrap — accounts
# come from Authentik — so this item carries no login pair.
resource "random_password" "vikunja_service_secret" {
  length  = 64
  special = false
}

resource "bitwarden_item_login" "vikunja" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name = "vikunja credentials"

  uri {
    value = "https://tasks.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "service_secret"
    hidden = random_password.vikunja_service_secret.result
  }
}

################################################################################
# bookstack credentials
################################################################################
# Laravel APP_KEY. Encrypts session cookies and anything BookStack stores
# encrypted, so rotating it logs everyone out — write-once. No login pair: the
# first user in via Authentik becomes the admin, per application_bookstack.tf.
resource "random_password" "bookstack_app_key" {
  length  = 64
  special = false
}

resource "bitwarden_item_login" "bookstack" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name = "bookstack credentials"

  uri {
    value = "https://wiki.${local.domain}"
    match = "host"
  }

  field {
    name    = "terraform managed"
    boolean = true
  }

  field {
    name   = "app_key"
    hidden = random_password.bookstack_app_key.result
  }
}

################################################################################
# bookstack dbcreds
################################################################################
# BookStack runs its own MariaDB rather than a role on the shared postgres
# cluster, hence `dbcreds` and not `pgcreds`. root_password is a custom field
# read through the bitwarden-login store, the same way `authentik credentials`
# exposes secret_key.
#
# ⚠️ The mariadb image only reads MARIADB_* on an empty datadir, so rotating
# these after first boot does NOT change what MariaDB accepts — that needs a
# manual ALTER USER. See kubernetes/apps/productivity/bookstack/app/externalsecret.yaml.
resource "random_password" "bookstack_dbpass" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "random_password" "bookstack_db_root_password" {
  length           = 32
  special          = true
  override_special = "_=+-,~"
}

resource "bitwarden_item_login" "bookstack_dbcreds" {
  organization_id = var.terraform_organization
  collection_ids  = [var.collection_id]

  name     = "bookstack dbcreds"
  username = "bookstack"
  password = random_password.bookstack_dbpass.result

  notes = "BookStack's role on its own MariaDB instance in productivity"

  field {
    name    = "terraform"
    boolean = true
  }

  field {
    name   = "root_password"
    hidden = random_password.bookstack_db_root_password.result
  }
}
