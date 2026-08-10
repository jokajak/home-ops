# Distributed Gatus Configuration

## Problem

Gatus only monitors its own status endpoint. Per-app `gatus.yaml` ConfigMaps exist for a few apps but are not wired into their kustomizations. No node monitoring exists.

## Goal

Every ingress and every node appears in Gatus, with config distributed across each app's kustomization.

## Architecture

The k8s-sidecar in the Gatus pod watches for ConfigMaps labeled `gatus.io/enabled: "true"` across all namespaces. Each app deploys its own ConfigMap via Flux postBuild variable substitution (`${APP}`, `${GATUS_SUBDOMAIN}`, `${SECRET_DOMAIN}`, `${GATUS_STATUS}`). The parent `cluster-apps` Kustomization patches all children with `substituteFrom` for cluster-settings/secrets.

## Templates

### Guarded (existing): `kubernetes/templates/gatus/guarded/configmap.yaml`

Used by internal ingress apps. Two endpoints per app:
1. DNS exposure check — verifies the hostname does NOT resolve externally
2. HTTPS health check — verifies the app responds

### External (new): `kubernetes/templates/gatus/external/configmap.yaml`

Used by external ingress apps. One endpoint per app:
1. HTTPS health check via external DNS resolver (1.1.1.1:53)

## Changes Per App

### Internal ingresses — guarded template

Each app gets two changes:
- `app/kustomization.yaml`: add `../../../../templates/gatus/guarded/configmap.yaml` to resources
- `ks.yaml`: ensure `postBuild.substitute.APP` is set; add `GATUS_SUBDOMAIN` when subdomain differs from app name

| App | Namespace | Subdomain | GATUS_SUBDOMAIN needed |
|-----|-----------|-----------|----------------------|
| calibre | default | calibre | no |
| esphome | default | esphome | no |
| home-assistant | default | home | yes: `home` |
| home-assistant-matter-hub | default | matterhub | yes: `matterhub` |
| immich | default | photos | yes: `photos` |
| mealie | default | recipes | yes: `recipes` |
| wallos | default | subs | yes: `subs` |
| zwave-js-ui | default | zwave | yes: `zwave` |
| metube | downloads | metube | no |
| qbittorrent | downloads | qbittorrent | no |
| grafana | observability | grafana | no |

### External ingresses — external template

Same two-change pattern but referencing the external template.

| App | Namespace | Subdomain | GATUS_SUBDOMAIN needed |
|-----|-----------|-----------|----------------------|
| jellyfin | default | jellyfin | no |
| echo-server | networking | echo-server | no |
| headscale | network | hs | yes: `hs` |

### Custom gatus.yaml files

| App | Reason |
|-----|--------|
| unifi | Needs `client: insecure: true` for self-signed cert |
| minio | Two hostnames: minio + s3 |

Both: no pushover alerts.

### Skipped

| App | Reason |
|-----|--------|
| gatus/status | Already in main config |
| flux-webhook | flux-system managed separately |

## Node Monitoring

Separate ConfigMap `gatus-nodes-ep` in `kubernetes/apps/observability/gatus/app/nodes-configmap.yaml`. Uses TCP checks against kubelet port 10250 (ICMP not possible due to dropped capabilities). Group: `nodes`.

Addresses are not written here or in the manifest. Each endpoint substitutes a
`${SECRET_NODE_*}` variable from the `cluster-secrets-user` Secret
(`kubernetes/flux/vars/cluster-secrets-user.sops.yaml`); the authoritative copy
of the inventory is `talos/topf.yaml`.

| Node | Substitution variable |
|------|-----------------------|
| basement-dell-sff | `${SECRET_NODE_BASEMENT_DELL_SFF}` |
| basement-lenovo-m910q | `${SECRET_NODE_BASEMENT_LENOVO_M910Q}` |
| basement-rpi4-chocolate | `${SECRET_NODE_BASEMENT_RPI4_CHOCOLATE}` |
| basement-rpi4-peach | `${SECRET_NODE_BASEMENT_RPI4_PEACH}` |
| foyer-dell-3040 | `${SECRET_NODE_FOYER_DELL_3040}` |
| foyer-dell-mff | `${SECRET_NODE_FOYER_DELL_MFF}` |
| foyer-hp-800g3 | `${SECRET_NODE_FOYER_HP_800G3}` |

This file is NOT committed to git.

## Files to Delete

- `kubernetes/apps/observability/grafana/app/gatus.yaml` (replaced by guarded template)
- `kubernetes/apps/default/zwave-js-ui/app/gatus.yaml` (replaced by guarded template)
