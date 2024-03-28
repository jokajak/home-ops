# authentik terraform

This terraform code is responsible for managing the configuration of the authentik service. It creates oidc client ids
and secrets and stores them in bitwarden. It then uses those values for creating applications within authentik.

I created a module for managing the bitwarden items so that the code was reusable.

I created a module for managing the authentik oidc clients since it was reusable.

I created separate files per application because I have to specify application specific URLs and groups. This way I can
define any necessary authentik groups or additional resources beyond the oidc clients.
