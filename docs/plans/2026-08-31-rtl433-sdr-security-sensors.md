# RTL-SDR → MQTT → Home Assistant: 319.5 MHz security sensors

> Status: **STAGED** — on a branch with an open PR, not yet merged or deployed · 2026-08-31 ·
> Owner: Josh · Author: Claude
>
> This is the **decision record**: why each choice was made and what was rejected. It is not
> where progress is tracked — rollout status lives in the status table in
> [`docs/rtl433-sdr-receive-path.md`](../rtl433-sdr-receive-path.md), which also carries the
> narrative walkthrough of how the pieces fit together. Update that table, not this header.
>
> One-shot change, not a multi-phase migration. The **Owner action items** section is the
> part that cannot be done from this repo; everything else reconciles on its own.

## Goal

An RTL-SDR Blog V3 is plugged into one cluster node with a dipole attached. Receive the
house's wireless security sensors with it and surface them as Home Assistant entities —
declaratively, with no click-ops beyond the one step Home Assistant genuinely has no YAML
for.

The sensors are **Interlogix / GE / UTC** (also branded NX, Qolsys IQ, ELK-319DWM, Alula
RE101), which transmit on **319.5 MHz** and are decoded by rtl_433's `interlogix` decoder as
model `Interlogix-Security`.

## Shape of the thing

Four moving parts, three of them new:

```
RTL-SDR v3 (USB 0bda:2838, one node)
     │
     │  generic-device-plugin (existing DaemonSet, kube-system)
     │  advertises squat.ai/rtl-sdr — only on the node holding the dongle
     ▼
rtl-433            (new, home-automation)   decodes 319.5 MHz → JSON
     │  MQTT, user `iot`
     ▼
emqx               (new, home-automation)   broker, cluster-internal
     │  MQTT
     ▼
home-assistant     (existing, default)      entities from packages/rtl433.yaml
```

MQTT topics published by rtl-433:

| Topic | Payload |
| --- | --- |
| `rtl_433/availability` | retained LWT, `online` / `offline` |
| `rtl_433/events` | one JSON object per decode (discovery + debugging) |
| `rtl_433/devices/<model>/<subtype>/<id>/<field>` | one retained topic per field |

So a door contact with id `1a2b3c` lands on
`rtl_433/devices/Interlogix-Security/contact/1a2b3c/switch1`, payload `OPEN` or `CLOSED`.

## Decisions, and why

### Device access: the device plugin, not hostPath + NFD

`zwave-js-ui` reaches its USB stick with a `hostPath` `CharDevice` mount plus a
`NodeFeatureRule` label plus `privileged: true` — three coupled pieces, and a device path
containing a U+00A0 that needed a seven-line comment to survive.

That pattern does not port to an SDR. A Z-Wave stick is a serial device with a stable
`/dev/serial/by-id/…` name; an RTL-SDR is a raw libusb device whose only node is
`/dev/bus/usb/<bus>/<dev>`, and the kernel renumbers that on every replug and reboot.

`generic-device-plugin` is already deployed and already does this. Adding a `usb` device
group makes it advertise `squat.ai/rtl-sdr` **on the node that physically has the dongle,
and nowhere else**, so a single line in the pod's `resources.limits` both pins scheduling to
that node and injects the current device node. No `NodeFeatureRule`, no `nodeSelector`, no
`privileged`, and nothing to update when the bus renumbers.

### `--domain squat.ai` is now pinned on the device plugin

Pre-existing latent breakage found on the way past, fixed while in there. The DaemonSet runs
`squat/generic-device-plugin` **untagged** (`:latest`), and upstream changed the default
resource domain from `squat.ai` to `devic.es`. `vpn/gateway` requests `squat.ai/tun`, so it
works today only because the nodes have an old image cached — the next pull would make the
VPN gateway unschedulable, for reasons that would look nothing like an image update.

Passing `--domain squat.ai` explicitly makes the resource names deterministic regardless of
which image a node has. It preserves current behaviour exactly; it does not fix the untagged
image, which is worth pinning separately.

### Broker: EMQX, reusing credentials that already existed

`terraform/bitwarden/main.tf` has provisioned an **"emqx credentials"** Bitwarden item —
admin login, a generated `user_password` field, and a `https://emqx.${SECRET_DOMAIN}` URI —
since before any broker existed. Nothing consumed it. This deployment consumes it, so **no
new Bitwarden item and no terraform change is needed**.

Mosquitto would have been lighter, but it would have meant a new terraform resource and a
new item for the owner to apply, while leaving the emqx item dangling.

One shared MQTT account, `iot`, for both rtl-433 and Home Assistant: the broker is only
reachable inside the cluster, and the Bitwarden item carries exactly one non-admin secret.
Splitting the two clients apart means adding fields in terraform first — worth doing the
moment anything outside the cluster connects, unnecessary while nothing does.

### EMQX's data directory is deliberately an `emptyDir`

EMQX seeds MQTT users from a bootstrap CSV, and it reads that CSV **only when the
authenticator is created** — i.e. once per data directory, ever. On a persistent volume the
first password would be frozen in mnesia forever, and rotating it in Bitwarden would silently
lock both clients out.

With a throwaway data dir the authenticator is recreated on every pod start, so the CSV is
re-read every start and Bitwarden stays the source of truth. Nothing of value is lost:
sessions re-establish on reconnect and rtl-433 republishes retained device state on the next
transmission. This is the whole reason the deployment is stateless — it is a correctness
requirement, not a shortcut.

### Pinned to EMQX 5.10.4, not 6.x

6.2.3 is current. Everything here leans on env-var override of the `authentication` array and
the built-in-database bootstrap file, both long-settled on 5.x, and there is no cluster in
the authoring environment to test a major bump against. Moving to 6.x is a one-line change
once it can be verified against the live broker.

### One frequency, not band hopping

rtl_433 can hop across bands with repeated `-f`, but it hears nothing on the bands it is not
currently parked on. For temperature sensors that is a missed sample; for a door contact it
is a **silently dropped open event**. Locked to `-f 319.5M`.

All decoders stay enabled. The alternative, `-R <n>`, pins a protocol *number* that shifts
between rtl_433 releases, and spurious decodes are harmless here because the Home Assistant
entities subscribe to exact per-device topics.

### Hand-written HA entities, not `rtl_433_mqtt_hass.py`

The usual answer is rtl_433's autodiscovery bridge. It was checked and **it has no mapping
for Interlogix fields** — no `switch1`…`switch5`, no `subtype`. Pointed at these sensors it
would autodiscover the battery and nothing else: no door, no motion, no tamper. The one thing
actually wanted would be missing.

Hand-written MQTT entities in a Home Assistant package cost a three-line block per sensor and
give correct device classes, tamper and battery as separate entities grouped under one HA
device, and `expire_after`. Shipped as `configmap-rtl433.yaml`, mounted at
`/config/packages/rtl433.yaml` alongside the existing `recorder.yaml`.

`expire_after: 10800` matters more than it looks for security sensors. These transmit a
supervisory heartbeat roughly hourly; three hours of silence means a flat battery, a dead
sensor, or someone jamming it, and the entity goes `unavailable` rather than sitting on a
stale `CLOSED` forever.

The example block ships **commented out** — sensor ids are not knowable until the receiver
has actually heard the sensors, and live placeholder entities would just be three permanently
unavailable things to clean out of the entity registry later.

## Changed files

| File | Change |
| --- | --- |
| `kubernetes/apps/system/generic-device-plugin/app/daemonset.yaml` | `rtl-sdr` USB device group; `--domain squat.ai` pinned |
| `kubernetes/apps/home-automation/emqx/**` | new — HelmRelease, two ExternalSecrets, ks, gatus |
| `kubernetes/apps/home-automation/rtl-433/**` | new — HelmRelease, ExternalSecret, ks |
| `kubernetes/apps/home-automation/kustomization.yaml` | wire both apps in |
| `kubernetes/apps/home-automation/README.md` | app table + receive-path diagram |
| `kubernetes/apps/default/home-assistant/app/configmap-rtl433.yaml` | new — MQTT entity package |
| `kubernetes/apps/default/home-assistant/app/helm-release.yaml` | mount the package at `/config/packages/rtl433.yaml` |
| `kubernetes/apps/default/home-assistant/app/kustomization.yaml` | add the ConfigMap |

## Owner action items

Nothing in Bitwarden or terraform. Four things, in order:

1. **Re-point the antenna.** A shallow V is the NOAA-satellite configuration. These sensors
   are terrestrial and vertically polarised, so the dipole wants both elements **collinear
   and vertical** — one straight up, one straight down. At 319.5 MHz, λ = 93.9 cm, so each
   element is a quarter wave ≈ **23 cm** (a touch under, ~22 cm, with the whip's velocity
   factor). Higher and away from metal beats longer.

2. **Add the MQTT integration in Home Assistant.** Settings → Devices & Services → Add
   Integration → MQTT:
   - Broker: `emqx.home-automation.svc.cluster.local`, port `1883`
   - Username: `iot`
   - Password: the `user_password` field on the **emqx credentials** Bitwarden item

   This is the one manual step, and it is a genuine gap against the everything-as-code rule
   — see **Known gaps** below.

3. **Find the sensor ids.** Once rtl-433 is running, trip each sensor and read the decode
   from either:
   - `kubectl -n home-automation logs deploy/rtl-433 -f` (JSON, one line per decode), or
   - the `sensor.rtl_433_last_event` entity's attributes in Developer Tools → States, or
   - `kubectl -n home-automation port-forward svc/rtl-433 8433:8433` for rtl_433's live UI.

4. **Fill in the entities.** Uncomment the `binary_sensor:` block in
   `kubernetes/apps/default/home-assistant/app/configmap-rtl433.yaml`, duplicate it per
   sensor, and substitute the real ids. The switch-to-function mapping is documented inline
   there (`switch1` primary trigger, `switch3` tamper).

## Verification

- `kubectl -n home-automation get pods` — `rtl-433` should land on the node with the dongle.
  If it is `Pending` with *Insufficient squat.ai/rtl-sdr*, the device plugin is not seeing
  the dongle: check `kubectl get node <node> -o jsonpath='{.status.allocatable}'`.
- rtl-433's logs should open with `Publishing MQTT data to emqx…` and
  `Publishing device info to MQTT topic "rtl_433/devices…"`.
- `-M level` puts `rssi`/`snr` on every decode — use it to judge antenna placement.

## Known gaps and risks

- **The MQTT broker connection is not code.** Home Assistant removed YAML broker config in
  2022.6; the connection is a config entry in `.storage/`. MQTT *entities* are still YAML,
  which is what this change uses. Closing the gap properly would mean templating a config
  entry into `.storage` at boot, which is unsupported and brittle. Left as a documented
  one-time manual step.
- **The DVB kernel driver may claim the dongle.** On most distros `dvb_usb_rtl28xxu`
  auto-binds to an RTL2832U and has to be blacklisted; librtlsdr normally detaches it, but if
  rtl-433 logs `usb_claim_interface error -6`, that is this. The Talos remedy is a kernel arg
  in `talos/all/00-install.yaml` (`machine.install.extraKernelArgs: [modprobe.blacklist=dvb_usb_rtl28xxu]`),
  which costs a node reboot — not applied pre-emptively, since Talos's trimmed kernel may not
  ship the module at all.
- **MQTT is plaintext on the pod network.** No TLS on 1883, and the broker has no ACLs — any
  authenticated client can publish to any topic. Acceptable for a cluster-internal broker with
  two clients; revisit if anything off-cluster connects, at which point per-client accounts
  and an authz ruleset should land together.
- **`wildcard-cert-tls` is a dangling reference repo-wide.** Ten ingresses name it as their
  TLS `secretName`, but no `Certificate` anywhere issues a secret by that name — the only real
  one is `networking/${SECRET_DOMAIN/./-}-production-tls`. Those ingresses serve valid TLS only
  because both nginx controllers run with `default-ssl-certificate` pointing at the real
  secret, so the missing one falls back. The emqx ingress here deliberately omits `secretName`
  rather than copy the pattern. Worth cleaning up across the repo separately; nothing is broken
  today, it is just load-bearing coincidence.
- **`squat/generic-device-plugin` is still untagged.** `--domain` is pinned now, so a surprise
  pull no longer renames resources, but the image itself should be pinned to a digest.
- **rtl-433 is a single point of failure by construction.** One dongle, one node, `Recreate`
  strategy — if that node is down, the sensors are not heard. Inherent to the hardware; worth
  knowing before these entities back any automation that matters.

## Possible follow-ups

- Pin the `generic-device-plugin` image.
- Split `iot` into per-client accounts plus an EMQX authz ruleset, once terraform grows the
  fields for it.
- If non-security 433.92 MHz devices ever show up (weather stations, TPMS), they want a
  *second* dongle and a second rtl-433 instance rather than hopping — see the frequency
  decision above.
