# Listening to the house: an SDR receive path for 319.5 MHz security sensors

> **Living document.** It describes how the RTL-SDR → MQTT → Home Assistant path is wired,
> and it is where rollout progress is tracked. Update the status table as each stage is
> deployed and confirmed — that table, not the commit log, is the source of truth for what
> is actually running.
>
> Companion decision record: [`docs/plans/2026-08-31-rtl433-sdr-security-sensors.md`](plans/2026-08-31-rtl433-sdr-security-sensors.md)
> (why each choice was made, and the alternatives that were rejected).

## Status at a glance

**Last updated: 2026-08-31** · Merged to `main`, and the Bitwarden item is applied. Everything
from stage 4 on needs eyes on the cluster to confirm — 🟡 means the manifest is on `main`, not
that it is running. Tick rows off as they are actually observed.

Legend: ⬜ not started · 🟡 on `main`, not confirmed in-cluster · 🔵 deployed, not verified ·
✅ confirmed

| # | Stage | Where it lives | State | Confirmed by |
|---|-------|----------------|-------|--------------|
| 1 | PR merged to `main` | — | ✅ | #1224, merged 2026-08-31 |
| 2 | `generic-device-plugin` advertises `devic.es/rtl-sdr` | `kubernetes/apps/system/generic-device-plugin` | 🟡 | `kubectl get node <node> -o jsonpath='{.status.allocatable}'` shows the resource |
| 3 | `tofu apply` the **"mqtt credentials"** Bitwarden item | `terraform/bitwarden` | ✅ | applied by owner 2026-08-31 |
| 4 | **Mosquitto deployed** | `kubernetes/apps/home-automation/mosquitto` | 🟡 | pod `Running`; `init-passwd` logged `password file built for user iot` — **with a non-empty username** |
| 5 | `rtl-433` scheduled onto the dongle's node | `kubernetes/apps/home-automation/rtl-433` | 🟡 | pod `Running`, not `Pending`, on the expected node |
| 6 | rtl-433 connected to the broker | same | 🟡 | log line `Publishing MQTT data to mosquitto…` |
| 7 | Sensors actually decoding | — | ⬜ | tripping a sensor produces a JSON line in the pod log |
| 8 | Antenna re-oriented + cut for 319.5 MHz | physical | ⬜ | `rssi`/`snr` in decodes look healthy |
| 9 | HA MQTT integration added (manual, UI) | Home Assistant | ⬜ | MQTT shows as a configured integration |
| 10 | `sensor.rtl_433_last_event` populating | `configmap-rtl433.yaml` | 🟡 | entity state changes when a sensor is tripped |
| 11 | Sensor ids collected | — | ⬜ | one id noted per physical sensor |
| 12 | Real `binary_sensor` entities uncommented + deployed | `configmap-rtl433.yaml` | ⬜ | door entity flips `on`/`off` on open/close |
| 13 | Battery + tamper entities behaving | same | ⬜ | both report, grouped under one HA device |

**Known blockers / watch items**

- Stage 4 is the current front line. With the Bitwarden item applied, the ExternalSecret should
  sync and `init-passwd` should run. **Check the username in its log line is not empty** — an
  empty one would mean a `${VAR}` was eaten by Flux substitution somewhere, which is what
  `8eb64f8` fixed for the two known cases.
- Stage 5 is gated on stage 4: `cluster-apps-rtl-433` `dependsOn` mosquitto, whose Kustomization
  has `wait: true`, so rtl-433 is not applied at all until the broker is healthy.
- Stage 5 may then fail on the DVB kernel driver. See *When it doesn't work*.

---

## The problem

There is a houseful of wireless security sensors — door contacts, motion, the usual — talking
to a panel over the air. They are already transmitting; the panel is just one listener among
however many care to tune in. Nothing needs to be installed on the sensors, nothing needs to
be paired, and no cloud service needs to be involved. It is a pure receive problem.

An RTL-SDR Blog V3 is plugged into one of the cluster nodes. The task is to turn what that
dongle hears into Home Assistant entities, declaratively, from this repo.

## Prior art

This design owes a lot to
[*Integrating old GE Interlogix burglar alarm sensors into HomeAssistant with SDR*](https://pdx.su/blog/2024-10-20-integrating-old-ge-interlogix-burglar-alarm-sensors-into-homeassistant-with-sdr/)
(pdx.su, 2024) — same sensors, same band, same decoder, arrived at independently. Worth reading; it is
the shortest path from "I have these sensors" to "I have entities".

It corroborates three conclusions reached separately here, which is reassuring given none of
this could be tested against real hardware while it was written:

- **319.5 MHz, and a quarter-wave element ≈ 9.2 in** — 23.4 cm, against the 23.5 cm derived
  below from λ/4.
- **The Interlogix decoder is protocol 100**, matching the position of `DECL(interlogix)` in
  rtl_433's `rtl_433_devices.h`.
- **Entities are written by hand**, with per-sensor ids discovered by watching MQTT — the same
  place the autodiscovery bridge was abandoned here, for the same reason.

Where this deployment deliberately diverges:

| | The post | Here |
|---|---|---|
| Runtime | `rtl_433` as a CLI process on a host | a pod under Flux, with the SDR attached by a device plugin |
| Decoder selection | `-R 100` to enable only Interlogix | all decoders left on — `-R` pins a *positional* number that shifts as decoders are added upstream, and stray decodes are harmless when entities subscribe to exact topics |
| Entity type | `cover` | `binary_sensor` with `device_class: door`, plus separate tamper and battery entities |

One correction worth flagging, since it would otherwise send you shopping: the post says cheaper
RTL-SDRs cannot receive this band and recommends a Nooelec NESDR. That is not true of the
RTL-SDR Blog V3 already plugged in here — its R820T2 tuner covers 24–1766 MHz, so 319.5 MHz is
comfortably in range with no direct-sampling mode and no different hardware.

## A little RF, because the numbers matter

These sensors are **Interlogix / GE / UTC** (also sold as NX, Qolsys IQ, ELK-319DWM, Alula
RE101), and they transmit on **319.5 MHz** — not the 433.92 MHz that "433" in `rtl_433`
suggests, and not the 345 MHz that Honeywell and 2GIG use. Three vendors, three bands, and
the wrong guess means hearing nothing at all.

Two consequences fall straight out of that number:

**Antenna length.** λ = 300 / 319.5 MHz ≈ **93.9 cm**. A half-wave dipole is λ/2, so each of
the two elements is a quarter wave ≈ **23.5 cm** — call it 22 cm once the telescopic whip's
velocity factor is accounted for.

**Antenna orientation.** The RTL-SDR dipole kit is usually pictured in a shallow V, because
that is the configuration for NOAA weather satellites overhead. These sensors are terrestrial
and **vertically polarised**. The dipole wants both elements collinear and vertical — one
straight up, one straight down. A cross-polarised antenna throws away most of the signal for
free. Height and distance from metal matter more than getting the length exactly right.

**One frequency, not several.** `rtl_433` can hop between bands with repeated `-f` flags, and
it is tempting to cover 315/319.5/345/433.92 and catch everything. Don't. The radio can only
be parked on one frequency at a time, so hopping means being deaf to each band most of the
time. For a temperature sensor that transmits every 30 seconds, a missed sample is invisible.
For a door contact that transmits *once*, when the door opens, it is a dropped security event.
The receiver stays locked to 319.5 MHz.

## The pipeline

```
  ┌─────────────────┐
  │  RTL-SDR V3     │  USB 0bda:2838, on exactly one node
  └────────┬────────┘
           │  generic-device-plugin (DaemonSet, kube-system)
           │  advertises devic.es/rtl-sdr on that node only
           ▼
  ┌─────────────────┐
  │  rtl-433 pod    │  -f 319.5M, decodes RF → JSON
  └────────┬────────┘
           │  MQTT, user `iot`
           ▼
  ┌─────────────────┐
  │  mosquitto      │  broker, cluster-internal
  └────────┬────────┘
           │  MQTT
           ▼
  ┌─────────────────┐
  │  home-assistant │  entities from /config/packages/rtl433.yaml
  └─────────────────┘
```

Three of those four boxes are new. The interesting engineering is in the first and the third.

### 1. Getting a radio into a pod

This is the part that looks solved and isn't. There is already a USB device attached to this
cluster — the Z-Wave stick behind `zwave-js-ui` — so the obvious move is to copy that pattern:
a `NodeFeatureRule` labelling the node, a `nodeSelector` matching the label, a `hostPath`
mount of the device, and `privileged: true`.

It does not port. A Z-Wave stick is a **serial** device, and udev gives it a stable name under
`/dev/serial/by-id/…` that survives reboots. (Even that was not painless — the existing
`hostPath` contains a non-breaking space from the USB product descriptor and needed a
seven-line comment defending it from well-meaning whitespace normalisation.)

An RTL-SDR is not a serial device. It is a raw libusb device, and the only node it has is
`/dev/bus/usb/<bus>/<dev>` — where both numbers are assigned by the kernel at enumeration time
and change when the dongle is replugged or the machine reboots. There is no stable path to
hardcode. A `hostPath` mount would work until the first power cut.

The cluster already runs [`generic-device-plugin`](https://github.com/squat/generic-device-plugin),
today advertising `/dev/net/tun` for the VPN gateway. It also supports matching USB devices by
vendor and product ID, which is exactly the missing piece:

```yaml
- --device
- |
  name: rtl-sdr
  groups:
    - usb:
        - vendor: "0bda"
          product: "2838"
```

The plugin walks `/sys/bus/usb/devices`, finds the dongle, and advertises the extended resource
`devic.es/rtl-sdr` — **only from the node that physically has it**. Which means the entire
scheduling and device-access story collapses into one line in the pod spec:

```yaml
resources:
  limits:
    devic.es/rtl-sdr: 1
```

Requesting the resource pins the pod to the right node *and* makes the kubelet inject the
current `/dev/bus/usb/<bus>/<dev>` into the container, re-resolved every time. No node label,
no `nodeSelector`, no `privileged`, and nothing to fix when the bus renumbers.

The container still runs as uid 0, and that is not laziness. The injected USB node is
root-owned, and libusb needs write access to it to claim the device; no Linux capability grants
that, so a non-root uid simply fails to open the SDR. Everything else is dropped —
`allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true`, all capabilities dropped.
Root, and nothing more.

#### The device-plugin domain trap

Worth knowing, because it explains why the resource is called what it is — and because it was
one image pull from biting.

`generic-device-plugin` constructs resource names as `<domain>/<name>`, and upstream **changed
the default domain from `squat.ai` to `devic.es`**. The DaemonSet used to run the image
untagged (`:latest`) while `vpn/gateway` requested `squat.ai/tun` — a combination that worked
only because the nodes happened to have an older image cached. The next pull would have started
advertising `devic.es/tun`, the gateway's request would have matched nothing, and it would have
gone `Pending` with a failure looking nothing like "an image changed underneath us".

Surfaced while adding the SDR device, and **fixed separately on `main`**
(`a31b435`): the image is now pinned to `0.2.0`, `--domain devic.es` is explicit, and
`vpn/gateway` asks for `devic.es/tun`. This branch follows that, which is why the SDR resource
is `devic.es/rtl-sdr` rather than the `squat.ai/rtl-sdr` earlier revisions of this doc named.

### 2. Decoding

[`rtl_433`](https://github.com/merbanan/rtl_433) does the actual signal work: sample the air at
319.5 MHz, demodulate, and run the bitstream past ~250 protocol decoders. The Interlogix decoder
turns a 64-bit packet into JSON.

The container image's `ENTRYPOINT` is `rtl_433` itself, so the pod's `args` are literally its
flags:

| Flag | Why |
|------|-----|
| `-f 319.5M` | the one frequency, per above |
| `-M level` | adds `rssi`/`snr` to every decode — this is how you aim the antenna |
| `-M time:iso:local` | readable timestamps in the log |
| `-F json` | decoded events to stdout, so `kubectl logs` is the discovery tool |
| `-F http` | read-only live UI on `:8433` (not ingressed — it is unauthenticated) |
| `-F mqtt://…` | the actual output |

All decoders stay enabled. `rtl_433` can restrict to one with `-R <n>`, but `<n>` is a
positional protocol *number* that shifts as decoders are added upstream — pinning it means a
version bump can silently start decoding the wrong protocol. Spurious decodes cost nothing
here, because the Home Assistant entities subscribe to exact per-device topics and ignore
everything else.

Credentials never appear in the flags. `rtl_433` reads `MQTT_USERNAME` and `MQTT_PASSWORD` from
the environment natively, so they come from a Secret via `envFrom` and stay out of both this
repo and the process's `argv`.

### 3. Transport

MQTT is the lingua franca here: `rtl_433` speaks it natively and Home Assistant consumes it
natively. The broker is **Mosquitto**, deliberately the boring choice.

This was originally EMQX, for one reason: `terraform/bitwarden/main.tf` had been provisioning
an "emqx credentials" item since before any broker existed, and nothing consumed it, so EMQX
meant no new secret plumbing. That is a weak reason to run an Erlang cluster broker to move a
few hundred messages an hour between two clients. EMQX's memory *request* alone reserved 256Mi
of a node whether used or not; Mosquitto is a single C binary that idles under 10 MB and asks
for 16Mi. The only thing genuinely lost is a web dashboard, and `kubectl logs` plus
`mosquitto_sub -t '#' -v` cover everything it would have been used for.

The Bitwarden item was renamed to **"mqtt credentials"** to match — and simplified while there.
EMQX needed two secrets (a dashboard admin login plus a `user_password` custom field for MQTT
clients); Mosquitto has no web UI, so there is no admin account and the item is now a plain
login: username `iot`, one password. That also means both ExternalSecrets read it through the
`bitwarden-login` store rather than one of them needing `bitwarden-fields`.

#### The password file is built at pod start, not mounted

The one piece of real plumbing Mosquitto costs, and worth understanding before someone tries to
simplify it away.

**Mosquitto 2.x will not read plaintext passwords.** Entries in `password_file` must be hashed
(argon2id by default), so the file cannot simply be an ExternalSecret rendered into a volume.
It also refuses to load a password file that is group- or world-readable, and Secret volumes
mount 0644 — so even a pre-hashed file could not be mounted directly.

Hence the `init-passwd` initContainer. It writes `iot:<password>` from the Secret into an
`emptyDir`, hashes it in place with `mosquitto_passwd -U`, and chowns it to the `mosquitto`
user at 0600:

```sh
printf '%s:%s\n' "$${MQTT_USERNAME}" "$${MQTT_PASSWORD}" > /mosquitto/auth/passwd
mosquitto_passwd -U /mosquitto/auth/passwd
chown mosquitto:mosquitto /mosquitto/auth/passwd
chmod 0600 /mosquitto/auth/passwd
```

**The `$$` is required.** Flux runs postBuild variable substitution over this manifest before
applying it, so a bare `${MQTT_USERNAME}` is consumed there as a *cluster* variable and never
reaches the shell. `$${VAR}` is Flux's escape and renders as `${VAR}`, which the container's
environment then expands at runtime.

This is worth stating loudly because the failure mode is asymmetric. Undefined Flux variables
substitute to an **empty string** by default, so the bare form does not error — it silently
writes `:` as the credential, `mosquitto_passwd` hashes that quite happily, and every client is
then rejected with no indication why. Check it with `flux envsubst`:

```console
$ printf 'printf %%s:%%s "${MQTT_USERNAME}"\n' | flux envsubst
printf %s:%s ""                 # bare — credential silently gone

$ printf 'printf %%s:%%s "$${MQTT_USERNAME}"\n' | flux envsubst
printf %s:%s "${MQTT_USERNAME}" # escaped — survives to the shell
```

Three details that are load-bearing:

- **It runs every pod start**, so the file is re-derived from Bitwarden each time. Rotating the
  password there actually takes effect. This is the same guarantee EMQX's throwaway data
  directory was protecting, reached by a more direct route — and unlike EMQX, there is no way
  to break it by adding a PVC later.
- **The chown is by name, not uid.** The image sets no `USER`: Mosquitto starts as root and
  drops privileges to its own account itself. Its entrypoint chowns only `/mosquitto/data`, so
  nothing else fixes up `/mosquitto/auth`. (The image's `PUID`/`PGID` default to 1883, but
  referencing the name means this does not break if that ever changes.)
- **The container keeps `CHOWN`, `SETUID` and `SETGID`** out of an otherwise-`drop: ALL` set,
  which is exactly what the entrypoint's chown and the privilege drop need. Forcing a non-root
  `runAsUser` instead would skip the drop and leave the daemon unable to read its own state.

Also `persistence false`: retained messages live only as long as the pod. rtl-433 republishes
device state on the next transmission, and the entities carry `expire_after` regardless, so a
PVC here would pin the pod to a node in exchange for data that regenerates itself within the
hour.

One shared `iot` account serves both clients. The broker is reachable only inside the cluster
and has exactly two of them, so one account is proportionate. Splitting rtl-433 and Home
Assistant apart means a second terraform item first — worth doing the moment anything
off-cluster connects, unnecessary while nothing does.

### 4. Entities

The conventional answer is `rtl_433_mqtt_hass.py`, the autodiscovery bridge that watches the
event stream and publishes Home Assistant MQTT discovery topics. It was the plan, right up
until its source was actually read.

**It has no Interlogix mappings.** It knows `reed_open`, `contact_open`, `tamper`, `alarm` —
none of which Interlogix emits. The Interlogix decoder outputs `switch1`…`switch5` and
`subtype`, which the script does not recognise. Pointed at these sensors it would autodiscover
the *battery* and nothing else: no door, no motion, no tamper. The single thing this whole
exercise exists to produce would be missing.

So the entities are hand-written, as a Home Assistant **package** — a ConfigMap mounted at
`/config/packages/rtl433.yaml`, alongside the existing `recorder.yaml`. It costs a short YAML
block per sensor and buys correct device classes, tamper and battery as first-class entities,
and everything grouped under one HA device.

## Following a door open, end to end

The wiring, traced once through:

**1. The sensor transmits.** A reed switch opens; the sensor sends a 64-bit packet on
319.5 MHz containing a 20-bit serial, a device-type nibble, a low-battery bit, and five latch
bits (F1–F5).

**2. rtl-433 decodes it** and emits JSON:

```json
{"model":"Interlogix-Security","subtype":"contact","id":"1a2b3c",
 "battery_ok":1,"switch1":"OPEN","switch2":"CLOSED","switch3":"CLOSED",
 "switch4":"CLOSED","switch5":"CLOSED","raw_message":"...","rssi":-11.2}
```

**3. It publishes to MQTT**, in two shapes at once. The topic layout comes from the `devices=`
format string in the `-F mqtt://…` flag:

| Topic | Payload |
|-------|---------|
| `rtl_433/availability` | retained LWT: `online` / `offline` |
| `rtl_433/events` | the whole JSON object, one per decode |
| `rtl_433/devices/<model>/<subtype>/<id>/<field>` | one retained topic per field |

So this event lands on, among others:

```
rtl_433/devices/Interlogix-Security/contact/1a2b3c/switch1   → "OPEN"
rtl_433/devices/Interlogix-Security/contact/1a2b3c/switch3   → "CLOSED"
rtl_433/devices/Interlogix-Security/contact/1a2b3c/battery_ok → "1"
```

(Naming `devices=` and `events=` explicitly also *suppresses* the `states` topic, which would
otherwise republish every payload a third time.)

**4. Home Assistant is subscribed** to that exact topic and flips the entity:

```yaml
- name: "Front door"
  state_topic: "rtl_433/devices/Interlogix-Security/contact/1a2b3c/switch1"
  payload_on: "OPEN"
  payload_off: "CLOSED"
  device_class: door
```

Which latch is which, per the decoder (it implements US patent #5761206):

| Field | Meaning |
|-------|---------|
| `switch1` | primary trigger — the reed on a contact, the PIR on a motion sensor |
| `switch2` | external contact loop (a wired sensor on the terminals) |
| `switch3` | **cover/case tamper** |
| `switch4` | spare |
| `switch5` | supervisory |
| `battery_ok` | `1` = healthy, `0` = low (note: HA's `battery` device class is inverted — `on` means low) |

**5. `expire_after` earns its keep.** Each entity carries `expire_after: 10800`. These sensors
send a supervisory heartbeat roughly hourly, so three hours of silence means a flat battery, a
dead sensor, or someone jamming the band — and the entity goes `unavailable` rather than
sitting on a confident, stale `CLOSED` forever. For a security sensor, "I don't know" is a much
more useful state than a lie.

## Adding a sensor

1. Trip it, and read the id from any of:
   - `kubectl -n home-automation logs deploy/rtl-433 -f` — one JSON line per decode
   - the `sensor.rtl_433_last_event` entity's attributes in Developer Tools → States
   - `kubectl -n home-automation port-forward svc/rtl-433 8433:8433` for the live UI
2. Uncomment the example block in
   `kubernetes/apps/default/home-assistant/app/configmap-rtl433.yaml`, duplicate it, and
   substitute the real id and a name.
3. Pick the `device_class` (`door`, `window`, `motion`, `smoke`, `gas`).
4. Commit. Flux reconciles, the ConfigMap changes, and Reloader restarts Home Assistant.

The shipped example is **commented out** on purpose: sensor ids are not knowable until the
receiver has heard the sensors, and live placeholder entities would just be dead things to
purge from the entity registry later.

## When it doesn't work

| Symptom | Cause | Fix |
|---------|-------|-----|
| `rtl-433` pod `Pending`, *Insufficient devic.es/rtl-sdr* | plugin doesn't see the dongle | check `kubectl get node <node> -o jsonpath='{.status.allocatable}'`; confirm the USB id with `lsusb` — clones may be `0bda:2832` (already matched) or something else entirely |
| `usb_claim_interface error -6` | the DVB kernel driver grabbed the dongle first | blacklist it via a kernel arg in `talos/all/00-install.yaml`: `machine.install.extraKernelArgs: [modprobe.blacklist=dvb_usb_rtl28xxu]`. Costs a node reboot, so not applied pre-emptively — Talos's trimmed kernel may not ship the module at all |
| Pod runs, zero decodes | wrong band, or antenna | confirm the sensors really are Interlogix; check the antenna is **vertical**, not a V, and ~22 cm per element |
| Decodes appear but no HA entities | MQTT integration not added | stage 10 — it is a UI step, see below |
| Entities go `unavailable` after 3h | `expire_after` firing | either the sensor is genuinely silent (battery) or the supervisory interval is longer than assumed — stretch the value |
| Kustomization fails to render, *variable not defined* | a bare `${VAR}` meant for the shell was eaten by Flux postBuild substitution | escape it as `$${VAR}` — see *The `$$` is required* above |
| Broker pod stuck in `Init:` | `init-passwd` failed | `kubectl -n home-automation logs deploy/mosquitto -c init-passwd`. Usually the ExternalSecret has not synced yet, so `MQTT_USERNAME`/`MQTT_PASSWORD` are unset |
| Clients rejected with bad username/password | password file built from a stale Secret, or the `tofu apply` for "mqtt credentials" never ran | check the item exists in Bitwarden, then `kubectl -n home-automation rollout restart deploy/mosquitto` to rebuild the file |

## What isn't code yet

Being honest about the gap, per the everything-as-code principle:

**The MQTT broker connection in Home Assistant is a manual UI step.** Home Assistant removed
YAML broker configuration in 2022.6; the connection is now a config entry living in
`.storage/`. MQTT *entities* are still YAML — which is what this design uses — but the
connection itself is not expressible in this repo.

Settings → Devices & Services → Add Integration → MQTT:

- Broker: `mosquitto.home-automation.svc.cluster.local`
- Port: `1883`
- Username: `iot`
- Password: the password on the **mqtt credentials** Bitwarden item

Closing this properly would mean templating a config entry into `.storage` at boot, which is
unsupported and brittle. It stays a documented one-time step rather than a hidden one.

Two other things are honest limitations rather than gaps:

- **MQTT is plaintext on the pod network**, and the broker has no authorization rules — any
  authenticated client can publish anywhere. Fine for a cluster-internal broker with two
  clients; revisit alongside per-client accounts if anything off-cluster ever connects.
- **rtl-433 is a single point of failure by construction, and that is fine.** One dongle, one
  node, `Recreate` strategy — if that node is down, the house is not being heard. Per the
  home-lab posture in `CLAUDE.md`, that is an accepted trade rather than something to engineer
  around: a second radio on a second node would double the hardware to remove an outage nobody
  is paged for. The real caveat is not availability but expectation — **this is a sensor feed,
  not an alarm system**, so don't let it back anything life-safety.
