# Single VPN Gateway Architecture

**Date:** 2026-03-01
**Reference:** `~/git/k8s-home-ops/infra-mk3/cluster/gitops/networking/vpn/README.md` (simple alternative)

---

## Context

The current downloads architecture uses a per-pod gluetun VPN sidecar injected into the qbittorrent pod. This requires `CAP_NET_ADMIN`, the `squat.ai/tun` TUN device, dnsdist for DNS, and duplicated VPN credentials per app. The goal is a **single shared gluetun gateway pod** that all downloads apps route through via a Multus bridge network. Client pods need no VPN capabilities.

There is also an unused `networking/vpn-gateway` deployment using the old `pod-gateway` chart that will be removed.

---

## New Traffic Flow

```
qbittorrent pod (192.168.24.128)
  └─ vpn-gw-veth0 (Multus bridge NAD)
       └─ vpn-gw-bridge0 (Linux bridge — local, all pods co-located on same node)
            └─ vpn-gateway pod (192.168.24.254, vpn namespace)
                 └─ tun0 (WireGuard tunnel) → Internet
```

Cluster-internal traffic (10.42.0.0/16 pods, 10.43.0.0/16 services) continues via the primary Cilium CNI on eth0.

> **Note:** The original design included a VXLAN overlay (`vpn-gw-vxlan0`, multicast group 224.0.0.88) to span the bridge across all nodes. This was removed after deployment because VXLAN multicast combined with high-bandwidth torrent traffic flooded the physical LAN, making the network unusable. The fix is to pin all VPN pods to the same node via `podAffinity`, making the bridge purely local — the VXLAN is never needed.

---

## IP Addressing

| Role | IP / Range |
|------|-----------|
| VPN subnet | 192.168.24.0/24 |
| Gateway pod (fixed) | 192.168.24.254 |
| qbittorrent (fixed, for DNAT) | 192.168.24.128 |
| General client pods | 192.168.24.1–192.168.24.127 |

---

## Implementation Steps

### Step 1: Deploy node-network-operator

Installs bridge + VXLAN interfaces on all nodes via Kubernetes CRDs.

**New files:**

```
kubernetes/apps/network/node-network-operator/
  crds/
    kustomization.yaml         # installs CRDs from GitHub release
  app/
    helmrepository.yaml        # https://solidDoWant.github.io/helm-charts
    helmrelease.yaml           # chart: node-network-operator v0.0.8
    kustomization.yaml
  config/
    links.yaml                 # Link CRDs (see below)
    kustomization.yaml
  ks.yaml                      # three Kustomizations: crds, app, config
```

**`config/links.yaml`** — one Link resource (bridge only):

| Link | Interface | Type | Config |
|------|-----------|------|--------|
| `vpn-gateway-bridge` | `vpn-gw-bridge0` | bridge | mtu 1420 |

The VXLAN links (`vpn-gateway-vxlan-dev`, `vpn-gateway-vxlan`) described in the reference design were removed. See pod affinity note in Traffic Flow above.

The operator webhook requires TLS — create a self-signed `Certificate` via cert-manager in the `network` namespace.

**Modified files:**
- `kubernetes/apps/network/kustomization.yaml` — add `node-network-operator/ks.yaml`

**Flux Kustomization dependency chain:**
```
node-network-operator-crds (no deps)
  ↓
node-network-operator (depends on: crds)
  ↓
node-network-operator-config (depends on: app)
```

---

### Step 2: Add VPN Network Attachment Definitions

**New file:** `kubernetes/apps/network/multus/config/networkattachment-vpn.yaml`

Three NADs in the `network` namespace (matching existing IoT VLAN pattern):

**`gateway-network-vpn-gateway-pod`** — gateway pod:
```json
{
  "cniVersion": "0.3.0",
  "type": "bridge",
  "bridge": "vpn-gw-bridge0",
  "ipam": {
    "type": "whereabouts",
    "range": "192.168.24.0/24",
    "range_start": "192.168.24.254",
    "range_end": "192.168.24.254"
  },
  "mtu": 1420
}
```

**`gateway-network-client-pods`** — general client pods (future apps):
```json
{
  "cniVersion": "0.3.0",
  "type": "bridge",
  "bridge": "vpn-gw-bridge0",
  "ipam": {
    "type": "whereabouts",
    "range": "192.168.24.0/24",
    "range_start": "192.168.24.1",
    "range_end": "192.168.24.127",
    "routes": [
      {"dst": "0.0.0.0/5"},   {"dst": "8.0.0.0/7"},
      {"dst": "11.0.0.0/8"},  {"dst": "12.0.0.0/6"},
      {"dst": "16.0.0.0/4"},  {"dst": "32.0.0.0/3"},
      {"dst": "64.0.0.0/2"},  {"dst": "128.0.0.0/1"}
    ],
    "gateway": "192.168.24.254"
  },
  "mtu": 1420
}
```

**`gateway-network-client-pod-qbittorrent`** — qbittorrent with fixed IP for DNAT:
```json
{
  "cniVersion": "0.3.0",
  "type": "bridge",
  "bridge": "vpn-gw-bridge0",
  "ipam": {
    "type": "whereabouts",
    "range": "192.168.24.0/24",
    "range_start": "192.168.24.128",
    "range_end": "192.168.24.128",
    "routes": [ /* same as client-pods */ ],
    "gateway": "192.168.24.254"
  },
  "mtu": 1420
}
```

**Modified files:**
- `kubernetes/apps/network/multus/config/kustomization.yaml` — add `networkattachment-vpn.yaml`
- `kubernetes/apps/network/multus/ks.yaml` — add `node-network-operator` to `multus-config` dependsOn

---

### Step 3: Deploy VPN gateway (`vpn` namespace)

**New files:**

```
kubernetes/apps/vpn/gateway/
  app/
    helmrelease.yaml
    externalsecret.yaml
    kustomization.yaml
  ks.yaml
```

**`externalsecret.yaml`** — pulls from Bitwarden `vpn-gateway-secrets`:
- `WIREGUARD_PRIVATE_KEY`
- `WIREGUARD_ADDRESSES`
- `WIREGUARD_PRESHARED_KEY`
- `VPN_FORWARDED_PORT`

Target secret: `vpn-gateway-credentials`

**`helmrelease.yaml`** — app-template chart (bjw-s v3.5.1):

Pod annotation:
```yaml
k8s.v1.cni.cncf.io/networks: network/gateway-network-vpn-gateway-pod@vpn-gw-veth0
```

initContainers:

| Container | Purpose |
|-----------|---------|
| `setup-masquerade` | `iptables -t nat -A POSTROUTING -o tun0 ... -j MASQUERADE` |
| `setup-dnat` | DNAT `tun0:$VPN_FORWARDED_PORT` → `192.168.24.128:$VPN_FORWARDED_PORT` (TCP+UDP) |

Both initContainers use `ghcr.io/qdm12/gluetun:v3.41.0` image and need `NET_ADMIN` capability.

Main container `gluetun`:
```yaml
image: ghcr.io/qdm12/gluetun:v3.41.0
env:
  VPN_SERVICE_PROVIDER: ${VPN_SERVICE_PROVIDER:=openvpn}
  VPN_TYPE: wireguard
  VPN_INTERFACE: tun0
  WIREGUARD_MTU: "1420"
  DOT: "off"
  HTTPPROXY: "on"
  SHADOWSOCKS: "on"
  SERVER_COUNTRIES: ${VPN_SERVER_COUNTRIES:=US}
  FIREWALL_ENABLED_DISABLING_IT_SHOOTS_YOU_IN_YOUR_FOOT: "off"
  HEALTH_VPN_DURATION_INITIAL: 30s
lifecycle:
  postStart: [ip rule del table 51820 || true]  # gluetun IPv6 bug workaround
securityContext:
  capabilities:
    add: [NET_ADMIN, DAC_OVERRIDE, MKNOD, CHOWN]
resources:
  limits:
    squat.ai/tun: "1"
probes:
  readiness/liveness: exec [/gluetun-entrypoint, healthcheck]
```

Services:
- `control` — ClusterIP, port 8000 (for gluetun-qb-port-sync)
- `proxy` — ClusterIP, port 8888 (HTTP proxy)

**`ks.yaml`** Flux Kustomization:
```yaml
targetNamespace: vpn
dependsOn:
  - name: multus-config
  - name: node-network-operator-config
  - name: generic-device-plugin
  - name: cluster-apps-external-secrets-bitwarden
```

**Modified files:**
- `kubernetes/apps/vpn/kustomization.yaml` — add `./gateway/ks.yaml`

---

### Step 3.5: Pin VPN pods to the same node (pod affinity)

Without VXLAN, all VPN pods **must** run on the same physical node — the bridge is local and cannot span nodes. This is enforced with `requiredDuringSchedulingIgnoredDuringExecution` podAffinity on vpn-dns and qbittorrent, both targeting `app.kubernetes.io/name: vpn-gateway`.

**vpn-dns** (`kubernetes/apps/vpn/dns/app/helmrelease.yaml`) — same namespace as vpn-gateway, no `namespaces:` field needed:
```yaml
controllers.vpn-dns.pod.affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: vpn-gateway
        topologyKey: kubernetes.io/hostname
```

**qbittorrent** (`kubernetes/apps/downloads/qbittorrent/app/helmrelease.yaml`) — cross-namespace, must include `namespaces: ["vpn"]` otherwise the scheduler searches in `downloads` and finds nothing:
```yaml
controllers.qbittorrent.pod.affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      - labelSelector:
          matchLabels:
            app.kubernetes.io/name: vpn-gateway
        namespaces: ["vpn"]
        topologyKey: kubernetes.io/hostname
```

> **Gotcha:** `podAffinity.labelSelector` defaults to the pod's own namespace when `namespaces:` is omitted. Cross-namespace affinity requires explicitly listing the target namespace.

---

### Step 4: Refactor qbittorrent

**`helmrelease.yaml`** changes:

| Remove | Add/Update |
|--------|-----------|
| `dnsdist` initContainer | Pod annotation for Multus NAD |
| `gluetun` initContainer | Update `port-forward` env (see below) |
| `squat.ai/tun` resource | — |
| `FIREWALL_INPUT_PORTS`, `DNS_ADDRESS` gluetun env vars | — |
| `dnsdist` persistence volume | — |
| `empty-config` persistence volume | — |

Pod annotation to add:
```yaml
k8s.v1.cni.cncf.io/networks: network/gateway-network-client-pod-qbittorrent@vpn-gw-veth0
```

`port-forward` container env update:
```yaml
GLUETUN_CONTROL_SERVER_HOST: vpn-gateway.vpn.svc.cluster.local
GLUETUN_CONTROL_SERVER_PORT: 8000
```

**`kustomization.yaml`** changes:
- Remove `configMapGenerator` for `qbittorrent-dnsdist`
- Remove `./config/dnsdist.conf` reference

**`externalsecret.yaml`** changes:
- Remove: `WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES`, `WIREGUARD_PRESHARED_KEY`, `FIREWALL_VPN_INPUT_PORTS`, `SHADOWSOCKS_PASSWORD`
- If no remaining secrets, remove the ExternalSecret entirely

**`ks.yaml`** changes:
- Add `dependsOn: [name: vpn-gateway]`
- Remove `generic-device-plugin` from dependsOn

**Delete:** `kubernetes/apps/downloads/qbittorrent/app/config/dnsdist.conf`

---

### Step 5: Remove old pod-gateway

**Delete:** `kubernetes/apps/networking/vpn-gateway/` (entire directory)

**Modified files:**
- `kubernetes/apps/networking/kustomization.yaml` — remove `vpn-gateway` entry

---

## Files Summary

| Action | Path |
|--------|------|
| CREATE | `kubernetes/apps/network/node-network-operator/crds/kustomization.yaml` |
| CREATE | `kubernetes/apps/network/node-network-operator/app/helmrepository.yaml` |
| CREATE | `kubernetes/apps/network/node-network-operator/app/helmrelease.yaml` |
| CREATE | `kubernetes/apps/network/node-network-operator/app/kustomization.yaml` |
| CREATE | `kubernetes/apps/network/node-network-operator/config/links.yaml` |
| CREATE | `kubernetes/apps/network/node-network-operator/config/kustomization.yaml` |
| CREATE | `kubernetes/apps/network/node-network-operator/ks.yaml` |
| MODIFY | `kubernetes/apps/network/kustomization.yaml` |
| CREATE | `kubernetes/apps/network/multus/config/networkattachment-vpn.yaml` |
| MODIFY | `kubernetes/apps/network/multus/config/kustomization.yaml` |
| MODIFY | `kubernetes/apps/network/multus/ks.yaml` |
| CREATE | `kubernetes/apps/vpn/gateway/app/helmrelease.yaml` |
| CREATE | `kubernetes/apps/vpn/gateway/app/externalsecret.yaml` |
| CREATE | `kubernetes/apps/vpn/gateway/app/kustomization.yaml` |
| CREATE | `kubernetes/apps/vpn/gateway/ks.yaml` |
| MODIFY | `kubernetes/apps/vpn/kustomization.yaml` |
| MODIFY | `kubernetes/apps/vpn/dns/app/helmrelease.yaml` — add podAffinity (vpn namespace, no namespaces: field needed) |
| MODIFY | `kubernetes/apps/downloads/qbittorrent/app/helmrelease.yaml` — add podAffinity with `namespaces: ["vpn"]` |
| MODIFY | `kubernetes/apps/downloads/qbittorrent/app/kustomization.yaml` |
| MODIFY | `kubernetes/apps/downloads/qbittorrent/app/externalsecret.yaml` |
| MODIFY | `kubernetes/apps/downloads/qbittorrent/ks.yaml` |
| DELETE | `kubernetes/apps/downloads/qbittorrent/app/config/dnsdist.conf` |
| DELETE | `kubernetes/apps/networking/vpn-gateway/` |
| MODIFY | `kubernetes/apps/networking/kustomization.yaml` |

---

## Key Design Decisions

- **DNS:** Remove dnsdist from qbittorrent; pod uses cluster CoreDNS. Public DNS goes via primary CNI (acceptable DNS leak for home lab). A VPN-attached CoreDNS pod can be added later if DNS privacy is required.
- **Port forwarding:** Gateway DNAT's VPN-forwarded port to qbittorrent's fixed bridge IP (192.168.24.128). The `gluetun-qb-port-sync` sidecar reads the port from gluetun's control server via a ClusterIP Service.
- **No VXLAN:** The original design used VXLAN (multicast group 224.0.0.88) to span the bridge across nodes. This was removed because VXLAN multicast + high-bandwidth torrent traffic flooded the physical LAN. All VPN pods are pinned to the same node via `podAffinity` instead — the bridge is local and VXLAN is unnecessary.
- **Pod affinity is required, not preferred:** Using `preferredDuringScheduling` would allow pods to land on different nodes, silently breaking connectivity. `required` causes a pod to stay Pending rather than schedule incorrectly.
- **Primary interface:** Cluster nodes use `eth0` (not `bond0` like reference) per `net.ifnames=0` Talos setting.
- **Old vpn-gateway:** The `networking/vpn-gateway` pod-gateway deployment is removed — it was replaced by qbittorrent's own gluetun sidecar and is now being superseded by this architecture.
- **Namespace for NADs:** `network` namespace, matching the existing `iot-vlan` NAD pattern.

---

## Verification

```bash
# 1. node-network-operator running
kubectl get pods -n network -l app.kubernetes.io/name=node-network-operator

# 2. Only bridge Link exists (no VXLAN)
kubectl get links
# expect: vpn-gateway-bridge only

# 3. All VPN pods on the same node
kubectl get pods -n vpn -o wide
kubectl get pods -n downloads -l app.kubernetes.io/name=qbittorrent -o wide
# vpn-gateway, vpn-dns, qbittorrent must all show the same NODE

# 5. NADs created
kubectl get networkattachmentdefinitions -n network

# 6. Gateway pod healthy
kubectl get pods -n vpn
kubectl exec -n vpn deploy/vpn-gateway -c gluetun -- /gluetun-entrypoint healthcheck

# 7. qbittorrent running without gluetun initContainers
kubectl get pods -n downloads

# 8. qbittorrent has bridge interface with correct IP
kubectl exec -n downloads <qbittorrent-pod> -- ip addr show vpn-gw-veth0
# expect: 192.168.24.128/24

# 9. Internet traffic routes via VPN bridge
kubectl exec -n downloads <qbittorrent-pod> -- ip route
# expect: public ranges via vpn-gw-veth0 → 192.168.24.254

# 10. Verify VPN IP (not your real IP)
kubectl exec -n downloads <qbittorrent-pod> -- curl -s https://ifconfig.me

# 11. qbittorrent web UI: Settings → Connection → listening port = VPN forwarded port
```
