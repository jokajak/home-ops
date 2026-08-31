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
mosquitto          (new, home-automation)   broker, cluster-internal
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

### Broker: Mosquitto

Started as EMQX for one reason, and that reason did not survive scrutiny.
`terraform/bitwarden/main.tf` had provisioned an **"emqx credentials"** item — admin login,
a generated `user_password` field, an `emqx.${SECRET_DOMAIN}` URI — since before any broker
existed, and nothing consumed it. EMQX therefore needed no new secret plumbing.

That is a weak reason to run an Erlang cluster broker for two clients and a few hundred
messages an hour. EMQX's memory *request* alone reserved 256Mi of a node whether used or not
(limit 768Mi); Mosquitto is a single C binary idling under 10 MB, requesting 16Mi. The only
real loss is the web dashboard, which `kubectl logs` and `mosquitto_sub -t '#' -v` replace for
every use it would have had. EMQX also went BSL at 5.9.

The Bitwarden item is renamed **"mqtt credentials"** and simplified: EMQX needed a dashboard
admin login *plus* a `user_password` custom field, whereas Mosquitto has no web UI, so it is
now a plain login item (username `iot`, one password). Both ExternalSecrets read it through
`bitwarden-login`; nothing needs `bitwarden-fields` any more. **This costs one `tofu apply`,
which only the owner can run** — the manifests fail closed until it exists.

### The password file is built by an initContainer

Mosquitto's one piece of real plumbing, and the thing not to "simplify" away later.

Mosquitto 2.x refuses plaintext entries in `password_file` (argon2id by default) *and* refuses
to load a file that is group- or world-readable. Secret volumes mount 0644, so the credential
can be neither rendered as plaintext nor mounted pre-hashed. The `init-passwd` initContainer
therefore writes `iot:<password>` into an `emptyDir`, hashes it in place with
`mosquitto_passwd -U`, and chowns it to `mosquitto` at 0600.

Because it runs on every pod start, the file is re-derived from Bitwarden each time and
rotation actually takes effect. That is the same property EMQX's throwaway data directory was
protecting — EMQX reads its bootstrap CSV only once per data directory, so a PVC there would
have frozen the first password forever — but reached directly, with no way to break it later by
adding a PVC.

The chown is by *name*, not uid: the image sets no `USER`, so Mosquitto starts as root and
drops privileges itself, and its entrypoint chowns only `/mosquitto/data`. The container keeps
`CHOWN`/`SETUID`/`SETGID` out of an otherwise-`drop: ALL` set for exactly that reason.

`persistence false`: retained messages last only as long as the pod, which is fine because
rtl-433 republishes on the next transmission and the entities carry `expire_after` anyway.

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
| `kubernetes/apps/home-automation/mosquitto/**` | new — HelmRelease (+ init-passwd), ConfigMap, ExternalSecret, ks |
| `kubernetes/apps/home-automation/rtl-433/**` | new — HelmRelease, ExternalSecret, ks |
| `terraform/bitwarden/main.tf` | "emqx credentials" → "mqtt credentials", simplified to a plain login |
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
   - Broker: `mosquitto.home-automation.svc.cluster.local`, port `1883`
   - Username: `iot`
   - Password: the password on the **mqtt credentials** Bitwarden item

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
- rtl-433's logs should open with `Publishing MQTT data to mosquitto…` and
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
  secret, so the missing one falls back. Moot here now that the broker has no ingress at all,
  rather than copy the pattern. Worth cleaning up across the repo separately; nothing is broken
  today, it is just load-bearing coincidence.
- **`squat/generic-device-plugin` is still untagged.** `--domain` is pinned now, so a surprise
  pull no longer renames resources, but the image itself should be pinned to a digest.
- **rtl-433 is a single point of failure by construction.** One dongle, one node, `Recreate`
  strategy — if that node is down, the sensors are not heard. Inherent to the hardware; worth
  knowing before these entities back any automation that matters.

## Possible follow-ups

- **Decide what `LB_EMQX_CIDR_V4` was for.** `kubernetes/flux/vars/cluster-settings.sops.yaml`
  carries a substitution variable reserving a load-balancer address for an MQTT broker,
  alongside the unused "emqx credentials" item. Nothing consumes it, and the Mosquitto Service
  here is deliberately **ClusterIP only** — rtl-433 and Home Assistant are both in-cluster, so
  nothing needs a LAN address. If the original intent was to let off-cluster IoT devices publish
  to the broker, that is a real change and should land as a set: an L2 `LoadBalancer` Service on
  that address, per-client accounts, a Mosquitto ACL file, and TLS on the listener — not a
  ClusterIP quietly promoted. If it was speculative, drop the variable.
- Pin the `generic-device-plugin` image.
- Split `iot` into per-client accounts plus a Mosquitto ACL file, once terraform grows the
  fields for it.
- If non-security 433.92 MHz devices ever show up (weather stations, TPMS), they want a
  *second* dongle and a second rtl-433 instance rather than hopping — see the frequency
  decision above.
