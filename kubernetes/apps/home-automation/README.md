# home-automation

Smart-home / IoT applications. (Home Assistant itself and the Z-Wave/ESPHome bridges still
live in [`default`](../default/README.md) for now — see the
[namespace reorg plan](../../../docs/plans/2026-06-20-namespace-reorganization.md).)

| App | Description | Manifest |
| --- | --- | --- |
| [mosquitto](https://mosquitto.org/) | MQTT broker. Cluster-internal transport between `rtl-433` and Home Assistant. No web UI and no ingress; credentials seeded at pod start from the "mqtt credentials" Bitwarden item. | [ks.yaml](./mosquitto/ks.yaml) |
| [home-assistant-matter-hub](https://github.com/t0bst4r/home-assistant-matter-hub) | Bridges Home Assistant entities to the Matter smart-home protocol. Data backed up via VolSync. | [ks.yaml](./home-assistant-matter-hub/ks.yaml) |
| [rtl-433](https://github.com/merbanan/rtl_433) | Receives 319.5 MHz Interlogix security sensors on an RTL-SDR dongle and publishes decodes to MQTT. | [ks.yaml](./rtl-433/ks.yaml) |

## The SDR receive path

```
RTL-SDR v3 (USB, on one node)
  └─ generic-device-plugin advertises devic.es/rtl-sdr on that node only
       └─ rtl-433 pod  ── MQTT ──▶  mosquitto  ── MQTT ──▶  Home Assistant (default ns)
                                                        entities from
                                                        packages/rtl433.yaml
```

How this is wired end to end, the rollout status table, and the manual steps that are not yet
code: [`docs/rtl433-sdr-receive-path.md`](../../../docs/rtl433-sdr-receive-path.md).
The decision record for why it is built this way:
[`docs/plans/2026-08-31-rtl433-sdr-security-sensors.md`](../../../docs/plans/2026-08-31-rtl433-sdr-security-sensors.md).
