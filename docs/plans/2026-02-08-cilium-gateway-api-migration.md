# Migration Plan: ingress-nginx → Cilium Gateway API

> **Revised 2026-11-19.** The February draft was stale: it predated the namespace reorganisation,
> listed half the current hostnames, installed CRDs with `kubectl apply`, and gave no account of how
> DNS moves. Most importantly it had no cutover mechanics, so "both run in parallel" did not say what
> stops working, or when. This revision replaces it. The Cilium-vs-Envoy-Gateway question in
> [`2026-08-04-upstream-template-realignment.md` §5](./2026-08-04-upstream-template-realignment.md)
> is settled here in favour of **Cilium**: it is already the CNI and already ships Envoy, so this
> adds no control plane.

## Why now

ingress-nginx is retired upstream. Its bundled nginx (1.27.1) is affected by NGINX2Root
(CVE-2026-123007 and others, disclosed 2026-11-18), and no fixed controller release will ship.
**Interim mitigation until Phase 6:** set `use-http2: "false"` in `controller.config` of both nginx
HelmReleases. That closes the lead CVE's HTTP/2 path. It is a separate, small change and does not
wait on this plan.

## Goal: downtime measured in seconds, not minutes

The constraint that shapes everything below is that **Home Assistant and its satellites (esphome,
zwave-js-ui, matter-hub) should be unreachable for no more than a few coordinated minutes, and
ideally only seconds.** The design gets there with one property:

> **A hostname is never served by nothing.** For each host, the Gateway starts serving it *before*
> DNS points at the Gateway, and nginx keeps serving it *until after* DNS has moved. The cutover
> is a DNS answer changing between two working backends, not a teardown and rebuild.

That works because of how this cluster's DNS already behaves, which was verified against source
for this revision:

- **k8s-gateway prefers an HTTPRoute over an Ingress.** It looks up resource types in a fixed order
  (HTTPRoute, TLSRoute, GRPCRoute, …, Ingress, Service) and returns the *first* type that matches.
  So once an HTTPRoute for `home.${SECRET_DOMAIN}` exists, k8s-gateway answers with the Gateway's
  address, even while the old Ingress still exists. Deleting the HTTPRoute flips the answer back.
  **Creating a route is the flip, and removing it is the rollback.**
- **external-dns (Pi-hole) does *not* prefer either.** Given two sources for one name, it picks
  one by owner label, or else by the lowest target string, and with `registry: noop` there are
  no owner labels. So in the same change as the route, the Ingress is hidden from external-dns
  with `external-dns.alpha.kubernetes.io/ingress-hostname-source: annotation-only` (its
  hostnames stop being published, and nginx still serves it). That makes the Pi-hole answer as
  deterministic as k8s-gateway's. The annotation key was read from external-dns's constants but not
  from its annotations package, so confirm the exact spelling against the deployed 1.23 chart's
  app version during Batch 1.

So each app migrates in **two merges**:

1. **Flip.** Add the `route`, and add the `annotation-only` annotation to the still-present
   `ingress`. DNS moves to the Gateway, nginx still serves anyone whose resolver cached the old
   answer, and nothing is down.
2. **Retire.** Delete the `ingress` block. The only clients affected are those still holding a
   long-lived connection to nginx, such as a Home Assistant frontend websocket. They drop and
   reconnect within seconds, now through the Gateway.

Retire merges can ride along with the next batch's flip merge. They are independent.

## Current state (2026-11-19)

| Piece | State |
| --- | --- |
| Ingress | `nginx-internal` (default class) and `nginx-external`, chart `ingress-nginx` 4.15.1, in `networking`. Their LB IPs are **not pinned**; LB-IPAM picks them. |
| Wildcard cert | `Certificate` `${SECRET_DOMAIN/./-}-production` lives in **`kubernetes/apps/networking/nginx/certificates/`**, inside the nginx Kustomization tree (`cluster-apps-nginx-certificates`). nginx serves it as `--default-ssl-certificate`. Per-app `secretName: wildcard-cert-tls` references point at nothing and are ignored. |
| CNI | Cilium 1.20.4 (`kubernetes/apps/network-system/cilium`): kube-proxy replacement, native routing, L2 announcements, Maglev, DSR. Gateway API is **not** enabled, and no Gateway API CRDs are installed. |
| Internal DNS | `k8s-gateway` 2.4.0 (app v0.4.0) answers `${SECRET_DOMAIN}` from Ingress status and from annotated LoadBalancer Services. `external-dns` 1.23.0 also writes Pi-hole local records from `sources: ["crd", "ingress"]`, `policy: upsert-only`, `registry: noop`. |
| App chart | bjw-s `app-template` **3.7.3** everywhere. It supports a `route:` key that renders an HTTPRoute. |
| Backups | **CNPG WAL archiving and all volsync restic repositories use `https://s3.${SECRET_DOMAIN}`, the MinIO Ingress.** The ingress tier is therefore on the durability path, not just the UI path. |
| Bootstrap | `talos/cilium/kustomization.yaml` references a `values.yaml` that does not exist in the repo. This is a pre-existing rebuild gap, and Phase 1 has to close it anyway. |

### Ingress inventory and how each translates

nginx annotations do not carry over. The table records what each one did and its Gateway API
equivalent. `hajimari.io/*` annotations are dropped, since no Hajimari is deployed, and so is
`nginx.org/websocket-services` on matter-hub, which belongs to a different controller and was
always a no-op. Envoy proxies websockets and streams request and response bodies without a size
cap by default, so **`proxy-body-size: 0`, `proxy-buffering: off` and
`proxy-request-buffering: off` need no replacement.**

| Host(s) | App (ns) | Class | Rendered by | Needs on the Gateway | Batch |
| --- | --- | --- | --- | --- | --- |
| `echo-server` | echo-server (networking) | ext | app-template | — (canary) | 0 |
| `inventory`, `garage`, `subs`, `tasks`, `wiki`, `recipes` | homebox, mygarage, wallos, vikunja, outline, mealie (productivity) | int | app-template | — | 1 |
| `calibre` | calibre (media) | int | app-template | — | 1 |
| `metube`, `qbittorrent` | (downloads) | int | app-template | — | 1 |
| `minecraft-rcon` | minecraft-rcon-web (games) | int | raw Ingress | — | 1 |
| `photos` | immich (default) | int | app-template | large uploads (default OK) | 2 |
| `paperless` | paperless (productivity) | int | app-template | large uploads (default OK) | 2 |
| `git` | forgejo (productivity) | int | forgejo chart 17.3.2 | large pushes (default OK) | 2 |
| `minio`, `s3` | minio (storage) | int | app-template | **backup path**, see Batch 2 | 2 |
| `home` | home-assistant (default) | int | app-template | websocket, proxy trust (see pre-flight) | 3 |
| `esphome`, `zwave` | esphome, zwave-js-ui (default) | int | app-template | websocket | 3 |
| `matterhub` | home-assistant-matter-hub (home-automation) | int | app-template | websocket, 3600s timeout | 3 |
| `grafana` | grafana (observability) | int | grafana chart 10.5.15 | — | 4 |
| `n8n` | n8n (ai) | int | app-template | long requests (3600s) | 4 |
| open-webui host, `llm` | hearthai (ai) | int | **hearthai git chart** | streaming (3600s) | 4 |
| `chat`, `mindroom`, `matrix` (3 paths), `mindroom-dashboard`, apex `/.well-known/matrix/client` | mindroom (ai) | int | raw Ingress ×4 | streaming (3600s), **CORS on the apex well-known** | 4 |
| `unifi` | unifi (default) | int | app-template | **HTTPS backend** (`backend-protocol: HTTPS`) | 5 |
| `status` | gatus (observability) | ext | app-template | — | 6 |
| `auth` | authentik (security) | ext | authentik chart 2026.8.5 | websocket (3600s) | 6 |
| `flux-webhook` (`/hook/`) | webhooks (flux-system) | ext | raw Ingress | — | 6 |
| `jellyfin` | jellyfin (default) | ext | app-template | **source-IP allowlist** (`whitelist-source-range`) | 6 |

How each special need translates:

- **Long timeouts (3600s).** nginx's `proxy-read-timeout` is an *idle* timeout between reads.
  Gateway API's `timeouts.request` is a *total* timeout, so copying 3600s across would cut a
  healthy websocket after an hour. Envoy's per-route default (15s) and how Cilium translates it
  are **not settled by Cilium's docs**, so Phase 2 measures it instead of guessing. If streams or
  websockets are cut, set `timeouts: {request: "0s"}` (disables it) on exactly the routes in the
  table marked 3600s or streaming.
- **CORS on the apex `/.well-known/matrix/client`.** Use a `ResponseHeaderModifier` filter that
  adds `Access-Control-Allow-Origin: *`. That is all the nginx annotations amounted to for an
  unauthenticated GET. It is standard channel and needs no experimental CRDs.
- **HTTPS backend (unifi).** This needs a `BackendTLSPolicy`, which Cilium 1.20 supports. Gateway
  API has **no "skip verification" option**, and unifi serves a self-signed cert. That is a real
  decision, made in Batch 5.
- **Allowlist (jellyfin).** Gateway API has no per-route source-IP filter. Cilium can filter
  *which clients reach Gateway Envoy* with a `CiliumClusterwideNetworkPolicy` on the
  `reserved:ingress` identity, but that identity is shared by **every** Gateway and route, so it
  cannot express "only jellyfin is restricted". That is also a decision, made in Batch 6.
- **Lost globals.** nginx added an HSTS header (`hsts-max-age`) and Brotli compression to every
  host. Neither is replicated by default. HSTS can be restored per route with a
  `ResponseHeaderModifier` if wanted. Brotli is not worth reproducing.

## Target state

- Gateway API CRDs (standard channel, v1.6.x, the version Cilium 1.20 is tested against)
  reconciled by Flux from a pinned `GitRepository`. Nothing goes in with `kubectl apply`.
- Cilium with `gatewayAPI.enabled: true`. It creates the `cilium` GatewayClass.
- Two Gateways in `networking`: `internal` and `external`. Each gets a **pinned** LB address
  (`spec.addresses`, fed by `${GATEWAY_INTERNAL_IP}` / `${GATEWAY_EXTERNAL_IP}`), an HTTP
  listener that only redirects to HTTPS, and an HTTPS listener terminating the wildcard cert.
- Every host is an HTTPRoute. app-template apps use `route:`, the forgejo, grafana and authentik
  charts use their own route support where the chart version has it, and everything else is a
  raw `httproute.yaml` in the app's directory.
- k8s-gateway and external-dns resolve HTTPRoutes.
- The wildcard Certificate lives beside the Gateways, not under `nginx/`.
- nginx, its HelmRepository, its Grafana dashboard and its ServiceMonitor are all gone.

## Owner pre-flight (answer before Phase 1)

These are facts about the live network and the HA config that the repo does not hold. Each one
changes a step below.

1. **How does WAN traffic reach `nginx-external`?** For example, a router port-forward to its LB
   IP. Since that IP is not pinned, check whether the forward targets an address LB-IPAM could
   reassign. The external cutover (Batch 6) is a change *on the router*, so it needs to be known.
2. **What does Pi-hole hold for `${SECRET_DOMAIN}`?** Export its local DNS records and note whether
   it conditionally forwards `${SECRET_DOMAIN}` to k8s-gateway (`${DNS_CIDR_V4}`). With
   `upsert-only`, stale records are never removed. A stale local record would override every flip
   for its name, so delete stale ones now.
3. **Home Assistant `http:` block** (`configuration.yaml` on the PVC, not in this repo). Record
   `use_x_forwarded_for` and `trusted_proxies`. HA returns **400 to every request** if a proxy it
   does not trust sends `X-Forwarded-For`. Gateway Envoy sends XFF, as nginx does, and its
   connections to backends originate from per-node addresses in the pod CIDR, much like nginx's
   pod IPs. So if pod-CIDR sources are trusted today it should just work. Batch 3's rehearsal
   confirms it before the flip.
4. **`JELLYFIN_ALLOWLIST`**: is it only private ranges (LAN/VPN) or does it include public CIDRs?
   That decides Batch 6's jellyfin option.
5. **Pick two free addresses** in `${LB_CIDR_V4}` (outside the k8s-gateway, unifi, forgejo and
   minecraft pins) and add `GATEWAY_INTERNAL_IP` and `GATEWAY_EXTERNAL_IP` to `cluster-secrets`.
   Do not reuse nginx's addresses. Both stacks run side by side until Phase 6.

## Phase 1: CRDs (one merge)

- Add `kubernetes/apps/networking/gateway-api-crds/` with a Flux `GitRepository` pinned to a
  `kubernetes-sigs/gateway-api` tag (`v1.6.x`), ignoring everything except `config/crd/standard`,
  and a `Kustomization` (`cluster-apps-gateway-api-crds`, `prune: false`, `wait: true`) on that
  path. Renovate can track the tag.
- Wire it into `kubernetes/apps/networking/kustomization.yaml`.
- Add `dependsOn: cluster-apps-gateway-api-crds` to the cilium Flux Kustomization, so a
  from-scratch rebuild never enables Gateway API without the CRDs.

**Verify:** the `gatewayclasses`, `gateways`, `httproutes`, `grpcroutes`, `referencegrants`,
`backendtlspolicies` and `tlsroutes` CRDs exist and are `Established`. Cilium lists TLSRoute and
BackendTLSPolicy as *required*. With any of them missing, the operator logs "Required
GatewayAPI resources are not found" and turns Gateway support off.

**Why it is its own merge:** the Cilium operator and k8s-gateway both check for CRDs **once, at
startup**. If Phase 2 landed in the same merge and their pods started first, Gateway support would
be silently off until something restarted them.

## Phase 2: Gateways and canary (one merge, then soak)

### 2.1 Cilium

In `kubernetes/apps/network-system/cilium/app/helmrelease.yaml`:

```yaml
gatewayAPI:
  enabled: true
  # enableAlpn stays false (default): clients speak HTTP/1.1 to the Gateway. No HTTP/2 to
  # clients until there is a reason; it is the attack surface NGINX2Root lived in.
envoy:
  resources:            # was `limit:` (a typo, so silently unapplied). Envoy now
    requests:           # carries all HTTP traffic; size it for that, then tune
      cpu: 100m         # from the cilium-envoy dashboards.
      memory: 64Mi
    limits:
      memory: 256Mi
```

`operator.rollOutPods` and `rollOutCiliumPods` are already true, so the config change rolls the
operator and agents. Expect a brief network blip per node while agents restart, which is
acceptable. Mirror `gatewayAPI.enabled` in the Talos bootstrap values: create
`talos/cilium/values.yaml`, which closes the pre-existing gap. Also order the bootstrap so the
Gateway API CRDs apply before Cilium.

### 2.2 Gateways

Add `kubernetes/apps/networking/gateway/` with its own `ks.yaml`, depending on the CRDs, cilium
and the certificate Kustomization, containing:

- **The certificate move.** Do not delete `cluster-apps-nginx-certificates`. **Keep the Flux
  Kustomization name** and change only its `path` to `./kubernetes/apps/networking/gateway/certificates`
  (a `git mv` of the directory). Same Kustomization, same objects, so nothing is pruned or
  re-issued. Renaming the Kustomization *would* prune and recreate the Certificate. cert-manager
  would keep the Secret, but there is no reason to take the chance.
- **Two Gateways**, `internal` and `external`, in `networking`:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: internal
  namespace: networking
spec:
  gatewayClassName: cilium
  addresses:
    - type: IPAddress
      value: "${GATEWAY_INTERNAL_IP}"
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces: { from: Same }      # only the redirect route below
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces: { from: All }
      tls:
        certificateRefs:
          - name: ${SECRET_DOMAIN/./-}-production-tls   # same namespace: no ReferenceGrant needed
```

  `external` is identical except for its name and `${GATEWAY_EXTERNAL_IP}`. Use `spec.addresses`,
  not the `io.cilium/lb-ipam-ips` infrastructure annotation, which Cilium is deprecating. Leave the
  `:=` fallback **off** these two variables. A Gateway that silently claims a template default
  address on the LAN is worse than one that fails to render.
- **One `https-redirect` HTTPRoute** attached to both `http` listeners, with no `hostnames` (so
  neither DNS tool indexes it) and a `RequestRedirect` to `https`, status 301.

The old draft's `ReferenceGrant` is dropped. The Gateways and the cert Secret share a namespace,
and routes in other namespaces never reference the Secret.

### 2.3 DNS tools

- `external-dns`: `sources: ["crd", "ingress", "gateway-httproute"]`.
- `k8s-gateway`: bump a pod annotation in its HelmRelease (e.g. `gateway-api-crds: v1.6.x`) so it
  restarts **after** the CRDs exist and starts watching HTTPRoutes. Leave `watchedResources`
  unset.

### 2.4 Canary: echo-server

In the same merge, add a `route` to echo-server **on both Gateways under canary hostnames**
(`echo-gw-int.${SECRET_DOMAIN}`, `echo-gw-ext.${SECRET_DOMAIN}`). The wildcard cert covers them,
and the real `echo-server` host stays on nginx.

**Verify (owner, the Phase 2 soak):**

- Both Gateways are `Programmed`, and the `cilium-gateway-*` Services hold the pinned addresses.
- k8s-gateway logs show no "CRDs are not found" and no Forbidden error for HTTPRoutes. A
  Forbidden would mean the chart's RBAC lacks Gateway API rules, which needs fixing before
  anything else.
- `dig echo-gw-int.${SECRET_DOMAIN}` returns `${GATEWAY_INTERNAL_IP}` from Pi-hole and from
  k8s-gateway directly.
- `curl -v https://echo-gw-int.${SECRET_DOMAIN}` shows the wildcard cert, and `http://` returns 301.
- **Timeout behaviour, which settles the timeouts question above.** echo-server honours
  `x-set-response-delay-ms`. A 30s delay must succeed. Separately, keep a websocket open through
  the Gateway for more than 10 minutes (e.g. `websocat` to any websocket backend once Batch 1 is
  through). If either is cut, `timeouts.request: "0s"` goes on the long-lived routes in Batches 3,
  4 and 6. Record the outcome here.
- Echo-server's response shows the real client IP in `x-forwarded-for`, which confirms source-IP
  preservation through DSR and TPROXY.
- If connections to the Gateway time out without reaching Envoy, the TPROXY netfilter path is
  missing on Talos. Try `bpf.tproxy: true` in Cilium values.

Nothing user-facing has changed yet. **Rollback** is reverting the merge.

## Phase 3: migrate apps in batches

Each batch is the two-merge pattern from the top of this doc.

**Flip merge**, per app:

```yaml
# app-template 3.7.3: keep the ingress for now, hide it from external-dns
ingress:
  app:
    className: internal
    annotations:
      external-dns.alpha.kubernetes.io/ingress-hostname-source: annotation-only
    # …unchanged hosts/tls…
route:
  app:
    parentRefs:
      - name: internal
        namespace: networking
        sectionName: https
    hostnames: ["home.${SECRET_DOMAIN:=internal}"]
    rules:
      - backendRefs:
          - identifier: app
            port: 8123
        # timeouts: { request: "0s" }   # only if Phase 2 showed cuts
```

**Verify after each flip:** `dig` from a LAN client returns the Gateway IP from both resolvers, the
app works in a fresh browser session, and `kubectl -n networking logs deploy/nginx-internal` shows
that host's traffic tailing off.

**Rollback:** revert the flip merge. The HTTPRoute disappears, k8s-gateway falls back to the
Ingress, and external-dns republishes it.

**Retire merge:** delete the `ingress:` block, the raw `ingress.yaml`, or `ingress.enabled: true`.
Do it only after the flip has been verified. **Running it first, or squashing both into one
merge, turns a zero-downtime flip into an outage of up to the DNS cache lifetime.** That is why
they are separate merges with a check in between, not separate commits in one merge.

### Batch 1: low-stakes internal (rehearses the pattern)

homebox, mygarage, wallos, vikunja, outline, mealie, calibre, metube, qbittorrent, minecraft-rcon.
Use this batch to tune the pattern. Nothing here is time-sensitive.

### Batch 2: large bodies and the backup path

immich, paperless, forgejo, minio (`minio`, `s3`).

`s3.${SECRET_DOMAIN}` carries **CNPG WAL archiving and every volsync job**. The flip is still
zero-downtime, and both clients retry, but verify durability explicitly rather than by absence of
complaints:

- Every CNPG `Cluster` reports `ContinuousArchiving: True` after the flip, and a manual
  `Backup` completes.
- The next scheduled volsync `ReplicationSource` run succeeds, or trigger one manually.
- Do the minio retire merge only after both checks pass.

For forgejo: chart 17.x may template its own HTTPRoute. If it does, use it. If not, set
`ingress.enabled: false` in the retire merge and add a raw `httproute.yaml` in the flip merge.

### Batch 3: Home Assistant and satellites (the coordinated window)

home-assistant, esphome, zwave-js-ui, home-assistant-matter-hub.

1. **Rehearse (own merge, no user impact).** Add routes for all four under canary hostnames
   (`home-gw.${SECRET_DOMAIN}` etc.). In a browser on the canary host, confirm:
   - HA loads, logs in, and its log has **no** "untrusted proxy" or "reverse proxy" errors (the
     pre-flight item 3 check, done for real);
   - the HA dashboard stays live for more than 10 minutes, so the websocket survives;
   - the esphome and zwave-js-ui UIs connect, as does the matter-hub UI.

   Fix anything found here, for example widening `trusted_proxies` to the pod CIDR in HA's config
   (an owner step). Then drop the canary hostnames.
   matter-hub's ingress also carries `external-dns.alpha.kubernetes.io/hostname:
   internal.${SECRET_DOMAIN}`, which publishes `internal.${SECRET_DOMAIN}` from that Ingress.
   Under `annotation-only` it would keep doing so, so remove it in the flip merge.
2. **Flip (one merge, all four together).** Swap the hostnames to the real ones and add the
   `annotation-only` annotation. Nobody is cut off: existing sessions stay on nginx, and new ones
   go to the Gateway.
3. **Retire (one merge, at a time you choose).** Delete the four ingresses. Open HA frontends and
   companion apps drop their websocket and reconnect through the Gateway, which is **the only
   user-visible moment: seconds, at a time the owner picks**. HA automations, Z-Wave and Matter
   traffic never cross the ingress and are not affected at all.

Mosquitto, matter-server and the Z-Wave/Matter device paths are not HTTP ingress, so this
migration does not touch them.

### Batch 4: AI and observability (long-lived streams)

grafana, n8n, hearthai (open-webui and `llm`), mindroom (four ingresses).

- grafana: chart 10.x has a `route:` value. Use it if the pinned version renders it, and fall back
  to a raw HTTPRoute if not.
- hearthai: the chart is the owner's own git chart. Either add route support there, which is a
  hearthai change, or set its ingress values off in the retire merge and add raw HTTPRoutes here
  that point at the chart's Services. Take the Service names from `task k8s:flate`'s render.
- mindroom: there are four raw Ingresses. `mindroom-matrix` becomes one HTTPRoute with three
  `PathPrefix` matches. The apex `/.well-known/matrix/client` route carries the CORS
  `ResponseHeaderModifier`. The apex host is in the wildcard cert's `dnsNames`, so the HTTPS
  listener needs no extra hostname.
- Apply `timeouts.request: "0s"` here if Phase 2 found cuts.

### Batch 5: unifi (HTTPS backend), owner decision

Options, in order of preference:

1. **Give unifi a cert the Gateway can verify.** Use a cert-manager `Issuer` of type CA, local to
   `default`, issuing a cert for `unifi.default.svc`. Install it as unifi's keystore cert (an
   owner step in the unifi UI or keystore, done once), then add a `BackendTLSPolicy` with that CA
   in `caCertificateRefs` and `hostname: unifi.default.svc`.
2. **Pin unifi's existing self-signed cert as the CA** in a ConfigMap for `BackendTLSPolicy`. This
   is less work, but it breaks silently whenever unifi regenerates its cert.
3. **Skip the Gateway.** Browse unifi on its own LoadBalancer address
   (`${LB_UNIFI_CIDR_V4}`, already exposed) and accept its self-signed cert.

### Batch 6: external hosts and the WAN cutover

gatus, authentik, flux-webhook, jellyfin, and echo-server's real host.

The LAN side flips per host as above. WAN clients follow the router, not DNS, so:

1. **Flip merge**: routes on `external` for all five hosts, plus the `annotation-only`
   annotation. Also add the Gateway target annotation
   `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}` on the `external` Gateway,
   and the hostname annotation `external.${SECRET_DOMAIN}` to its Service via
   `spec.infrastructure.annotations`. During the overlap k8s-gateway returns both stacks'
   addresses for that name, and both serve every external host, so the overlap is harmless.
2. **Owner, on the router**: repoint the WAN port-forward from nginx-external's address to
   `${GATEWAY_EXTERNAL_IP}`. In-flight WAN connections drop once. A GitHub webhook missed in that
   moment just means Flux catches up on its interval.
3. **Retire merge**: delete the external ingresses and remove the `external.${SECRET_DOMAIN}`
   hostname annotation from nginx-external.

**jellyfin's allowlist**, owner decision from pre-flight item 4:

- If `JELLYFIN_ALLOWLIST` holds only private ranges, attach jellyfin to **`internal`** instead.
  Only LAN and VPN clients could ever use it, so this is the same effect with less machinery.
- If it includes public ranges, enforce the list in Jellyfin itself: Dashboard → Networking →
  remote IP filter, with the Gateway's pod-CIDR source addresses as known proxies so that it
  reads the real client IP from XFF. That is an owner step in Jellyfin's UI. A
  `reserved:ingress` network policy would restrict *every* external host, not just jellyfin.

## Phase 4: remove nginx

Only when `kubectl get ingress -A` is empty:

1. Delete `kubernetes/apps/networking/nginx/{external,internal}` and their Kustomizations from
   `nginx/ks.yaml`. The certificates Kustomization already moved in Phase 2.
2. Remove `kubernetes/flux/repositories/helm/ingress-nginx.yaml` and its kustomization entry.
3. Drop `"ingress"` from external-dns `sources`.
4. Remove the nginx dashboard from the grafana HelmRelease.
5. Update `kubernetes/apps/networking/README.md` and the "Routing" lines in other plan docs.
6. **Owner:** delete the Pi-hole records that external-dns left pointing at the old nginx
   addresses and at the canary hostnames. `upsert-only` never removes them.

NGINX2Root exposure ends here.

## Phase 5 (optional): gatus-sidecar

This is unchanged from the original draft and independent of the cutover. Swap the k8s-sidecar
ConfigMap pattern for `ghcr.io/home-operations/gatus-sidecar` with HTTPRoute discovery, once
every host is a route.

## Order constraints at a glance

| If this happens out of order | Effect |
| --- | --- |
| Cilium `gatewayAPI.enabled` before the CRDs are Established | The operator turns Gateway support off and stays that way until restarted. |
| k8s-gateway not restarted after the CRDs exist | HTTPRoutes are never resolved. Canary hosts don't resolve, and flips do nothing. |
| Flip and retire in one merge | The host is down for clients with cached DNS until their cache expires. |
| Deleting the `cluster-apps-nginx-certificates` Kustomization instead of moving its path | The Certificate is pruned and recreated, with a needless re-issue risk. |
| Removing minio's ingress before CNPG archiving is confirmed on the Gateway | WAL archiving stalls and backups silently stop. |
| Retiring nginx-external before the router forward moves | WAN access is down until the forward moves. |

## Variables

| Variable | Where | Purpose |
| --- | --- | --- |
| `GATEWAY_INTERNAL_IP` | `cluster-secrets` (SOPS) | Pinned address of the `internal` Gateway |
| `GATEWAY_EXTERNAL_IP` | `cluster-secrets` (SOPS) | Pinned address of the `external` Gateway, and the WAN port-forward target |

No new secrets or Bitwarden items are needed.

## References

- [Cilium Gateway API support (1.20)](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/): required CRDs, `spec.addresses` with LB-IPAM, source-IP behaviour
- [Cilium: Ingress/Gateway and network policy](https://docs.cilium.io/en/stable/network/servicemesh/ingress-and-network-policy/): the `reserved:ingress` identity
- [Cilium 1.20 release notes](https://github.com/cilium/cilium/releases/tag/v1.20.0): Gateway API v1.6.1, BackendTLSPolicy
- [k8s_gateway `gateway.go`](https://github.com/ori-edge/k8s_gateway/blob/master/gateway.go): resource order, first match wins
- [external-dns `plan/conflict.go`](https://github.com/kubernetes-sigs/external-dns/blob/master/plan/conflict.go): the PerResource resolver
- [external-dns Gateway API sources](https://kubernetes-sigs.github.io/external-dns/latest/docs/sources/gateway-api/)
- [Gateway API HTTPRoute timeouts](https://gateway-api.sigs.k8s.io/api-types/httproute/#timeouts-optional)
- [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/)
