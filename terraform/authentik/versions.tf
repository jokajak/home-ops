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
    # Pin to the Authentik SERVER line (Helm chart 2024.12.0 in
    # kubernetes/apps/security/authentik). A newer provider (renovate bumped this to
    # 2026.5.0) speaks a newer API schema than the 2024.12 server and fails reads with
    # "no value given for required property autocomplete". Keep this in lockstep with the
    # server; do not let renovate bump it ahead of the chart.
    authentik = {
      source  = "goauthentik/authentik"
      version = "2024.12.0"
    }
  }
}
