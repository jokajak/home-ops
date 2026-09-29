# Chat hostname reassignment

Move Open WebUI from chat.${SECRET_DOMAIN} to chatgpt.${SECRET_DOMAIN} and
Mindroom Chat from mindroom.${SECRET_DOMAIN} to chat.${SECRET_DOMAIN}.
The Matrix homeserver stays at matrix.${SECRET_DOMAIN}, the Matrix identity domain
stays unchanged, and the operator dashboard stays at mindroom-dashboard.${SECRET_DOMAIN}.
No runtime config or agent memory changes are involved.

Update the HearthAI URL input (which derives ingress and OIDC callback), the
Mindroom ingress, Authentik callback/launcher URLs, and Bitwarden login URLs.
Retain mindroom.${SECRET_DOMAIN} as a temporary alias for old Matrix client sessions.
Do not redirect away from it until users can access their encrypted history on
the new origin. Historical plan documents describe the old URLs at initial rollout.

## Owner cutover

1. Ensure chatgpt.${SECRET_DOMAIN} resolves to internal ingress; chat already does.
   The existing wildcard certificate covers both names.
2. Apply terraform/authentik from this branch, then merge/reconcile the Kubernetes
   changes. Open WebUI SSO may be briefly unavailable between the callback change
   and the rollout; downtime is acceptable. Flux updates two ingresses separately,
   so chat may briefly have competing routes while reconciliation completes.
3. Apply terraform/bitwarden to update saved login URLs (credentials are unchanged).
4. Open chatgpt.${SECRET_DOMAIN}, sign in through Authentik, and verify Open WebUI.
5. Open chat.${SECRET_DOMAIN}, sign in through Matrix SSO, and verify the new
   session using the old mindroom.${SECRET_DOMAIN} session or recovery key/backup.
   Confirm encrypted history is readable before retiring old sessions. Browser
   storage does not move between origins; server-side accounts and history remain.
6. Remove the legacy mindroom alias in a later PR after the household transitions.

If rolling back, revert the hostname change and reapply terraform/authentik so
Open WebUI's callback matches its restored URL. No storage rollback is required.
