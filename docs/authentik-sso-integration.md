# Authentik SSO integration — per-application runbook

> Living reference for adding an application to Authentik SSO. Not a dated plan —
> update it as the pattern evolves and as apps are onboarded (see the status table).

## Model

- **Authentik** is the OIDC provider. Out-of-cluster config lives in `terraform/authentik/`
  (applied with `tofu`, state in the `flux-system` k8s backend). In-cluster apps are Flux/Helm.
- **`akadmin`** — the Authentik superuser. Used **only** to administer Authentik itself.
- **Site admin** (`site_admin.tf`) — a random-credential account (stored in Bitwarden as
  `authentik-site-admin`) that is admin **in the applications**, but **not** an Authentik
  superuser. Member of the `admins` group.
- **`admins` group** (`is_superuser = false`) — the "app admin" group. Apps key their admin
  role on this group's **name**; it must also be **policy-bound** to each app for access.
- **Human users** (`users.tf` + `users.sops.yaml`) — real people, non-superuser, defined in a
  **SOPS-encrypted** YAML file committed to git, read via `yamldecode(data.sops_file…​.raw)`.
  Encryption hides the values (emails, names); usernames are the map keys and stay readable
  (use a list with the username as an encrypted field if you need those hidden too). They log
  in via the GitHub source (`email_link` on their GitHub primary email). Edit with
  `sops terraform/authentik/users.sops.yaml`; bootstrap from `users.sops.yaml.example`.
- **`users` group** — baseline membership; granted access to most apps.

### Provider/server version lockstep (don't skip)

The `goauthentik/authentik` provider in `versions.tf` **must match the Authentik server line**
(Helm chart in `kubernetes/apps/security/authentik`, currently `2024.12.0`). A newer provider
fails reads with `no value given for required property autocomplete` and flips
`authentik_group.parent` ↔ `parents`. Do not let renovate bump the provider ahead of the chart.

## Two things every integration needs (don't conflate them)

1. **Access** — *who may use the app.* Controlled by `authentik_policy_binding`s on the
   `authentik_application`. No binding for a user's group → they can't launch/log in.
2. **Role inside the app** — *admin vs viewer etc.* Controlled by the **app's own** mapping of
   the OIDC `groups` claim (or a role claim) to its roles. Authentik just ships the group
   names in the token; the app decides what they mean.

⇒ For the site admin to be a working app-admin you need **both**: bind `admins` to the app
*and* configure the app to treat the `admins` group as its admin role.

## Per-app integration steps

### A. Authentik side — `terraform/authentik/application_<app>.tf`

Mirror `application_grafana.tf`:

1. **OIDC client creds** — `module "<app>_oidc_creds" { source = "./oidc_creds"; application = "<app>"; organization_id = var.organization_id; collection_id = var.collection_id }`.
   This generates a client_id/secret and stores them in Bitwarden item **`authentik-client-<app>`**
   (username = client_id, password = client_secret).
2. **OAuth2 provider** — `authentik_provider_oauth2.<app>_oauth`:
   - `client_id`/`client_secret` from the module.
   - `authorization_flow = authentik_flow.provider-authorization-implicit-consent.uuid`,
     `invalidation_flow = authentik_flow.invalidation.uuid`.
   - `property_mappings = data.authentik_property_mapping_provider_scope.oauth2.ids`
     (openid + email + profile; the `profile` mapping emits the `groups` claim).
   - `allowed_redirect_uris` — the app's exact OAuth callback URL(s).
3. **Application** — `authentik_application.<app>_application` (name, `slug`, `protocol_provider`,
   `meta_icon`, `meta_launch_url`, `policy_engine_mode = "any"`).
4. **Access bindings** — `authentik_policy_binding` for each group allowed to use the app
   (e.g. `users` for everyone, plus `admins` for the site admin).
5. **Admin role** — bind `admins` to the app (access) and wire the app to map the `admins`
   group to its admin role (step B). Add the app to `group_ids_by_name` in `users.tf` only if
   you want to assign people to an app-specific group by name.

### B. App side — `kubernetes/apps/<ns>/<app>/`

1. **Pull the client creds** via an `ExternalSecret` from Bitwarden item `authentik-client-<app>`
   (`username` → client_id, `password` → client_secret), exposed to the app as env/secret.
2. **Configure the OIDC client** in the HelmRelease values:
   - Issuer / endpoints under `https://auth.${SECRET_DOMAIN}/application/o/<slug>/`
     (`.../authorize/`, `.../token/`, `.../userinfo/`, end-session `.../end-session/`).
   - Scopes: `openid profile email groups`. PKCE where supported.
   - **Role/group mapping** if the app supports it (see table).
3. **Redirect URI** in the app must match `allowed_redirect_uris` from step A.2 exactly.

### C. Apply & verify

- `cd terraform/authentik && tofu plan` (no `BW_SESSION` set — provider uses the embedded
  client), review, `tofu apply`. Then push the app-side Flux changes and reconcile.
- Verify: login screen → app → correct access **and** role. Check `admins` members get admin,
  `users` members get the baseline role.

## Per-app admin-role mechanism

| App | Access | Admin-role source | Maps `admins` group? |
|-----|--------|-------------------|----------------------|
| **Grafana** | policy bindings (incl. `admins`) | Helm `grafana.ini` `auth.generic_oauth.role_attribute_path` on the `groups` claim | **Yes** — `contains(groups[*], 'admins') && 'Admin'`. ⚠️ also references `people` for Viewer, which is not a defined group. |
| **Immich** | policy binding (`users`) | **Internal to Immich** — admin is the first user / set in Immich; Immich does **not** map admin from OIDC group claims | No (cannot, today) |

> When onboarding a new app, add a row here: how it grants access, how it decides admin, and
> whether the `admins` group reaches its admin role. If an app can't map admin from a claim
> (like Immich), note that admin must be set in-app.

## New-app checklist (copy per app)

```
- [ ] application_<app>.tf: oidc_creds module, provider, application, access bindings
- [ ] bind `admins` to the app (if it should have a site-admin)
- [ ] ExternalSecret pulling authentik-client-<app> (client_id/secret)
- [ ] HelmRelease OIDC config: endpoints, scopes, redirect URI matches allowed_redirect_uris
- [ ] app-side group→role mapping for `admins` (or note admin is set in-app)
- [ ] tofu apply + Flux reconcile
- [ ] verify: access for `users`, admin for `admins`, login via GitHub
- [ ] add a row to the admin-role-mechanism table above
```

## Status

| App | Authn (login) | Authz/admin | Notes |
|-----|---------------|-------------|-------|
| Grafana | ✅ wired (`application_grafana.tf` + Helm `generic_oauth`) | ⏳ `admins` group now bound + role_attribute_path matches `admins` | First target; verify after `site_admin.tf` apply |
| Immich | ✅ wired (authn) | ❌ admin not via Authentik (internal) | Access via `users` group only |
