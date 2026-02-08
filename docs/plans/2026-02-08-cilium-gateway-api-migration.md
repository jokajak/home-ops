# Migration Plan: nginx Ingress to Cilium Gateway API

## Overview

Incrementally migrate from dual nginx ingress controllers (internal/external) to Cilium Gateway API with HTTPRoutes. Both systems run in parallel during transition, with new Gateway IPs allocated alongside existing nginx IPs.

## Current State

- **Ingress controllers**: nginx-internal (192.168.116.82), nginx-external (192.168.116.83)
- **CNI**: Cilium 1.19.0 with L2 announcements, Maglev LB, DSR mode
- **LB IP pool**: `${LB_CIDR_V4}` via CiliumLoadBalancerIPPool
- **Cert-manager**: Let's Encrypt via Hurricane Electric DNS-01 webhook, wildcard cert in `networking/${SECRET_DOMAIN/./-}-production-tls`
- **External-DNS**: Pi-hole provider, sources: `["crd", "ingress"]`, policy: `upsert-only`
- **Chart**: bjw-s app-template v3.6.0 (supports `route` for Gateway API)

## Target State

- Cilium Gateway API with two Gateways: `gateway-external` and `gateway-internal`
- Each app uses `route` in HelmRelease instead of `ingress`
- External-DNS watches Gateway API sources alongside ingress
- Cert-manager issues wildcard cert referenced by Gateways
- nginx removed entirely
- Gatus optionally upgraded to use `gatus-sidecar` with HTTPRoute auto-discovery

## Phase 0: Prerequisites

### 0.1 Install Gateway API CRDs

Cilium requires Gateway API CRDs installed before enabling `gatewayAPI.enabled`. Install the standard channel CRDs:

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_gatewayclasses.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_gateways.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_httproutes.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/v1.2.1/config/crd/standard/gateway.networking.k8s.io_referencegrants.yaml
```

Or use the experimental bundle if you want TLSRoute/TCPRoute/GRPCRoute:
```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.1/experimental-install.yaml
```

Consider managing these CRDs via a Flux Kustomization for GitOps.

### 0.2 Allocate new Gateway IPs

Choose two new IPs from the LB pool for the Cilium Gateways (do NOT reuse 192.168.116.82/83):

| Gateway | Suggested IP | Purpose |
|---------|-------------|---------|
| gateway-internal | TBD (e.g., 192.168.116.90) | Internal services |
| gateway-external | TBD (e.g., 192.168.116.91) | External services |

These will coexist with nginx IPs during transition.

## Phase 1: Enable Cilium Gateway API

### 1.1 Update Cilium Helm values

Add to `kubernetes/apps/network/cilium/app/helmrelease.yaml`:

```yaml
values:
  gatewayAPI:
    enabled: true
  # gatewayClass auto-created by Cilium when gatewayAPI.enabled=true
```

Cilium automatically creates a `GatewayClass` named `cilium` when this is enabled.

### 1.2 Create Gateway resources

Create `kubernetes/apps/networking/cilium-gateway/app/gateway.yaml` (or similar path):

```yaml
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-external
  namespace: networking
  annotations:
    external-dns.alpha.kubernetes.io/target: external-gw.${SECRET_DOMAIN}
spec:
  gatewayClassName: cilium
  infrastructure:
    annotations:
      io.cilium/lb-ipam-ips: "${GATEWAY_EXTERNAL_IP}"
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        certificateRefs:
          - kind: Secret
            name: ${SECRET_DOMAIN/./-}-production-tls
            namespace: networking
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: gateway-internal
  namespace: networking
  annotations:
    external-dns.alpha.kubernetes.io/target: internal-gw.${SECRET_DOMAIN}
spec:
  gatewayClassName: cilium
  infrastructure:
    annotations:
      io.cilium/lb-ipam-ips: "${GATEWAY_INTERNAL_IP}"
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        certificateRefs:
          - kind: Secret
            name: ${SECRET_DOMAIN/./-}-production-tls
            namespace: networking
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: https-redirect
  namespace: networking
spec:
  parentRefs:
    - name: gateway-external
      sectionName: http
    - name: gateway-internal
      sectionName: http
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
```

### 1.3 Create ReferenceGrant for cross-namespace TLS

The wildcard cert lives in `networking` namespace. Apps in other namespaces need a ReferenceGrant:

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-tls-from-gateways
  namespace: networking
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: Gateway
      namespace: networking
  to:
    - group: ""
      kind: Secret
```

### 1.4 Update external-dns sources

Add `gateway-httproute` and `gateway-grpcroute` to external-dns sources:

```yaml
# In external-dns helmrelease.yaml
sources: ["crd", "ingress", "gateway-httproute"]
```

### 1.5 Verify

- `kubectl get gatewayclass` shows `cilium` class
- `kubectl get gateway -n networking` shows both gateways with assigned IPs
- Gateway LoadBalancer services get IPs from Cilium LBIPAM

## Phase 2: Migrate one test app (echo-server)

Start with echo-server since it's a non-critical test app.

### 2.1 Convert echo-server HelmRelease

Change from `ingress` to `route` in the HelmRelease values:

```yaml
# Before
ingress:
  app:
    className: external
    annotations:
      external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    hosts:
      - host: echo-server.${SECRET_DOMAIN}
        paths:
          - path: /
            service:
              identifier: app
              port: http
    tls:
      - hosts:
          - echo-server.${SECRET_DOMAIN}

# After
route:
  app:
    parentRefs:
      - name: gateway-external
        namespace: networking
        sectionName: https
    hostnames:
      - echo-server.${SECRET_DOMAIN}
```

### 2.2 Update DNS

External-DNS will automatically create DNS records pointing the hostname to the new gateway IP. With `upsert-only` policy, old records remain until manually cleaned. Update Pi-hole if needed.

### 2.3 Verify

- `kubectl get httproute -n networking` shows the route
- `curl https://echo-server.${SECRET_DOMAIN}` resolves to the new gateway IP and works
- TLS terminates correctly with the wildcard cert

## Phase 3: Migrate remaining external apps

After echo-server is confirmed working, migrate the other external ingress apps:

| App | Namespace | Hostname | Notes |
|-----|-----------|----------|-------|
| jellyfin | default | jellyfin.${SECRET_DOMAIN} | |
| headscale | network | hs.${SECRET_DOMAIN} | |
| gatus | observability | status.${SECRET_DOMAIN} | |

For each app:
1. Replace `ingress` block with `route` block in HelmRelease
2. Point `parentRefs` to `gateway-external`
3. Verify DNS and TLS

## Phase 4: Migrate internal apps

Migrate internal ingress apps to `gateway-internal`:

| App | Namespace | Hostname |
|-----|-----------|----------|
| calibre | default | calibre.${SECRET_DOMAIN} |
| esphome | default | esphome.${SECRET_DOMAIN} |
| home-assistant | default | home.${SECRET_DOMAIN} |
| home-assistant-matter-hub | default | matterhub.${SECRET_DOMAIN} |
| immich | default | photos.${SECRET_DOMAIN} |
| mealie | default | recipes.${SECRET_DOMAIN} |
| unifi | default | unifi.${SECRET_DOMAIN} |
| wallos | default | subs.${SECRET_DOMAIN} |
| zwave-js-ui | default | zwave.${SECRET_DOMAIN} |
| metube | downloads | metube.${SECRET_DOMAIN} |
| qbittorrent | downloads | qbittorrent.${SECRET_DOMAIN} |
| grafana | observability | grafana.${SECRET_DOMAIN} |
| minio | storage | minio.${SECRET_DOMAIN}, s3.${SECRET_DOMAIN} |

For each app:
1. Replace `ingress` block with `route` block in HelmRelease
2. Point `parentRefs` to `gateway-internal`
3. Verify DNS and connectivity

### HelmRelease conversion pattern (bjw-s app-template)

```yaml
# Before (Ingress)
ingress:
  app:
    className: internal
    hosts:
      - host: &host ${APP}.${SECRET_DOMAIN}
        paths:
          - path: /
            service:
              identifier: app
              port: http
    tls:
      - hosts: [*host]

# After (HTTPRoute)
route:
  app:
    parentRefs:
      - name: gateway-internal
        namespace: networking
        sectionName: https
    hostnames:
      - ${APP}.${SECRET_DOMAIN}
```

## Phase 5: Remove nginx

Once all apps are migrated and verified:

1. Delete `kubernetes/apps/networking/nginx/` directory
2. Remove nginx references from `kubernetes/apps/networking/kustomization.yaml`
3. Remove the ingress-nginx HelmRepository if no longer used
4. Clean up old DNS records in Pi-hole (external.${SECRET_DOMAIN} and internal.${SECRET_DOMAIN} pointing to old nginx IPs)
5. Release nginx IPs (192.168.116.82, 192.168.116.83) back to the pool

## Phase 6 (Optional): Upgrade Gatus to use gatus-sidecar

Replace the k8s-sidecar + ConfigMap template pattern with the `gatus-sidecar` from `ghcr.io/home-operations/gatus-sidecar`, which auto-discovers endpoints from HTTPRoutes and Services.

### Changes:
1. Replace k8s-sidecar init container with gatus-sidecar in HelmRelease
2. Add gatus endpoint annotation to each app's `route` block:
   ```yaml
   route:
     app:
       annotations:
         gatus.home-operations.com/endpoint: |-
           conditions: ["[STATUS] == 200"]
   ```
3. Remove all per-app gatus ConfigMaps and templates
4. Remove gatus RBAC for ConfigMap watching (replace with HTTPRoute/Service watching)

This phase is optional and can be done independently after the Gateway migration is complete.

## Rollback Strategy

Since nginx and Gateways coexist during transition:
- Revert any app to `ingress` block if the `route` conversion fails
- DNS records for both nginx and gateway IPs coexist (upsert-only policy)
- nginx can be kept running indefinitely as a fallback

## Variables to Define

| Variable | Description | Example |
|----------|-------------|---------|
| GATEWAY_INTERNAL_IP | New IP for internal gateway | 192.168.116.90 |
| GATEWAY_EXTERNAL_IP | New IP for external gateway | 192.168.116.91 |

Add these to `cluster-settings` ConfigMap or `cluster-secrets` Secret.

## References

- [Cilium Gateway API docs](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
- [Cilium Helm reference](https://docs.cilium.io/en/stable/helm-reference/)
- [External-DNS Gateway API sources](https://kubernetes-sigs.github.io/external-dns/latest/docs/sources/gateway-api/)
- [bjw-s app-template docs](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
- [Gateway API spec](https://gateway-api.sigs.k8s.io/)
