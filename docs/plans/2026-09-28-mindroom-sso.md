# Mindroom SSO

Use native Tuwunel OIDC with the existing Authentik instance and the upstream
chart already pinned by the deployment. Mindroom Chat discovers the Matrix SSO
provider. Keep the operator dashboard API-key login and agent password login.

OpenTofu owns the confidential provider, strict callback, application, and the
same two household policy bindings as Open WebUI. The shared oidc_creds module
stores credentials in Bitwarden; ExternalSecrets supplies them to the chart.
Use preferred_username for Matrix IDs and reject random fallback IDs or implicit
matching to pre-existing password accounts.

Owner sequence: apply terraform/authentik, reconcile the Kubernetes changes,
verify the OIDC Secret and advertised SSO flow, then sign in as the owner first.
Confirm Matrix ID and homeserver admin status before enabling the suspended
runtime. Existing password accounts need explicit association before SSO login;
the app README documents this and the exact Bitwarden item and callback.

Validation: render the pinned chart with a synthetic client ID, parse its TOML,
check the callback and secret mount, lint YAML/HCL, and run targeted/full Flate.
Live login verification requires the owner's cluster and Authentik instance.
