# Home Assistant entity naming

Entity IDs are referenced by dashboard YAML (and later automations/scripts), so they follow
one predictable pattern. Display names are what the family sees and stay casual.

## Convention

```
<domain>.<area>_<thing>[_<qualifier>]
```

- **area** — the HA area slug, always first, so a room's entities sort together and the
  dashboard YAML for a room is guessable. Assign the entity to that HA area too.
- **thing** — what it is, generic noun, singular: `lamp`, `fan`, `fan_light`, `tv`, `roku`,
  `hvac`. Compound device names stay whole, in natural English order (`fan_light`,
  `ceiling_fan`, not `light_fan`), so a device's parts sort together
  (`fan.primary_bedroom_fan`, `light.primary_bedroom_fan_light`).
- **qualifier** — optional; distinguishes several of the same thing (`_emily`, `_left`,
  `_ceiling`). Owner names go here, never first.
- **groups** — plural of the thing, no qualifier: `light.<area>_lamps`.
- Lowercase, `_` separated, no brand or model names (`roku` is the device role, so it's fine;
  `tcl_55s4` is not).

**Exception — portable devices.** A device that moves between rooms is named after the
device, not an area, so its IDs don't go stale on every move:
`sensor.air_quality_meter_temperature`, `sensor.air_quality_meter_humidity`. Dashboard cards
that place it in a room say so in a comment; move those cards when the device moves.

The **display name** is independent: "Emily's lamp", "Bedroom TV". Edit it freely; nothing
references it.

## Area slugs

| Area | Slug |
|---|---|
| Primary bedroom | `primary_bedroom` |
| Office | `office` |
| Playroom | `playroom` |
| Upstairs (whole-floor devices) | `upstairs` |
| Downstairs (whole-floor devices) | `downstairs` |

Add rows as rooms are brought onto the dashboard.

## Renames

### Primary bedroom

| Current | New |
|---|---|
| `light.emily_lamp` | `light.primary_bedroom_lamp_emily` |
| `light.josh_lamp` | `light.primary_bedroom_lamp_josh` |
| `light.primary_bedroom_lamps` | unchanged (group) |
| `light.primary_fan_light` | `light.primary_bedroom_fan_light` |
| fan (renamed in HA) | `fan.primary_bedroom_fan` |
| `media_player.primary_bedroom_tv` | unchanged |
| `media_player.primary_bedroom_roku` | unchanged |
| `remote.primary_bedroom_roku` | unchanged (same device, different domain) |
| TV Wake-on-LAN button (renamed in HA) | `button.primary_bedroom_tv_wake` |

### Climate

The doubled names come from the integration joining the device name ("Upstairs") with the
entity name ("Upstairs"). Rename the thermostat's sibling entities (humidity, sensors) the
same way.

| Current | New |
|---|---|
| `climate.upstairs_upstairs` | `climate.upstairs_hvac` |
| `climate.downstairs_downstairs` | `climate.downstairs_hvac` |
| `climate.playroom_ac` | unchanged |
| `climate.fan_office` | `climate.office_fan` |
| `sensor.fan_office_temperature` | `sensor.office_fan_temperature` (and its other `fan_office_*` siblings) |

## Rename checklist

Renames are done in the HA UI (entity settings → Entity ID). They are a one-off owner step,
not reconciled from Git.

1. Rename before any dashboard YAML references the entity.
2. Recorder history migrates to the new ID automatically.
3. Automations and scripts are **not** rewritten — HA warns; fix references by hand.
4. Group helpers (e.g. `light.primary_bedroom_lamps`): confirm members still resolve.
5. home-assistant-matter-hub: if a bridge filters by entity ID rather than area/label, the
   exposed set changes — re-check the bridge's filter after renaming.
6. Set the HA area on the entity while you're there.
