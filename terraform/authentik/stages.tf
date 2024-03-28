################################################################################
## Authentik stages
################################################################################

# Stage for identifying the user
resource "authentik_stage_identification" "authentication-identification" {
  name               = "authentication-identification"
  user_fields        = ["username", "email"]
  show_source_labels = true
  show_matched_user  = false
  password_stage     = authentik_stage_password.authentication-password.id
  sources            = [authentik_source_oauth.github.uuid, data.authentik_source.inbuilt.uuid]
  enrollment_flow    = authentik_flow.enrollment-invitation.uuid
}

resource "authentik_stage_password" "authentication-password" {
  name                          = "authentication-password"
  backends                      = ["authentik.core.auth.InbuiltBackend"]
  failed_attempts_before_cancel = 3
}

resource "authentik_stage_user_login" "authentication-login" {
  name = "authentication-login"
}

## Invalidation stages
resource "authentik_stage_user_logout" "invalidation-logout" {
  name = "invalidation-logout"
}

## User settings stages
resource "authentik_stage_prompt" "user-settings" {
  name = "user-settings"
  fields = [
    resource.authentik_stage_prompt_field.username.id,
    resource.authentik_stage_prompt_field.name.id,
    resource.authentik_stage_prompt_field.email.id,
    resource.authentik_stage_prompt_field.locale.id
  ]
}

resource "authentik_stage_user_write" "user-settings-write" {
  name                     = "user-settings-write"
  create_users_as_inactive = false
}

## Invitation stages
resource "authentik_stage_invitation" "enrollment-invitation" {
  name                             = "enrollment-invitation"
  continue_flow_without_invitation = false
}

resource "authentik_stage_prompt" "source-enrollment-prompt" {
  name = "source-enrollment-prompt"
  fields = [
    resource.authentik_stage_prompt_field.username.id,
    resource.authentik_stage_prompt_field.name.id,
    resource.authentik_stage_prompt_field.email.id,
    resource.authentik_stage_prompt_field.password.id,
    resource.authentik_stage_prompt_field.password-repeat.id
  ]
  validation_policies = [
    resource.authentik_policy_password.password-complexity.id
  ]
}

resource "authentik_stage_user_write" "enrollment-user-write" {
  name                     = "enrollment-user-write"
  create_users_as_inactive = false
  create_users_group       = authentik_group.users.id
}

resource "authentik_stage_user_login" "source-enrollment-login" {
  name             = "source-enrollment-login"
  session_duration = "seconds=0"
}
