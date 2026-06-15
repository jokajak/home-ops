terraform {
  required_version = ">= 1.5"
  required_providers {
    sops = {
      source  = "carlpett/sops"
      version = "1.4.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = "0.17.6"
    }
    # Keep in lockstep with the Authentik SERVER line (Helm chart in
    # kubernetes/apps/security/authentik, currently 2026.5.3). A provider that is newer than
    # the server fails reads with "no value given for required property autocomplete"; an
    # older one rejects newer API shapes (e.g. authentik_group `parents`). Do not let
    # renovate bump this ahead of the chart.
    authentik = {
      source  = "goauthentik/authentik"
      version = "2026.5.0"
    }
  }
}
