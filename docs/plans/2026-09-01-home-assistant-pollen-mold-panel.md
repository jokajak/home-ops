# Home Assistant: a pollen & mold panel, shipped as code

> Status: **STAGED** — on a branch, not yet merged or deployed · 2026-09-01 ·
> Owner: Josh · Author: Claude
>
> Small change, one shape decision worth writing down: this is the first Lovelace
> dashboard in this repo, and how it gets registered sets the precedent for the next one.

## Goal

A panel in the Home Assistant sidebar showing outdoor **mold** and **pollen** counts,
defined in Git rather than clicked together in the UI editor.

## Where the numbers come from

Mold is the constraint. Pollen has several sources; an outdoor **mold spore count** has
essentially one that Home Assistant can reach without a custom component:

| Source | Mold | Pollen | Cost | Notes |
| --- | --- | --- | --- | --- |
| **AccuWeather** (core) | ✅ count, p/m³ | ✅ tree / grass / ragweed, p/m³ | **paid API key** | Each sensor also carries a `level` attribute — Low…Extreme |
| IQVIA / Pollen.com (core) | ❌ | index only, no counts | free, ZIP code, no key | Names the driving allergens, which AccuWeather does not |
| Ambient Weather (core) | ❌ | ❌ | already owned | See below |
| Open-Meteo air quality | ❌ | ✅ but Europe-only | free | Not useful from `America/New_York` |

**The Ambient Weather station gets you nothing here.** Its integration exposes temperature,
humidity, wind, rain, solar/UV, lightning, and — only with the AQIN add-on module — PM2.5,
PM10 and CO₂. There is no pollen or mold field anywhere in it, and there could not be: a
consumer weather station measures the atmosphere, while pollen and mold counts come from
microscope slide counts at certified stations and the forecast models built on them. What the
station *can* contribute to the same panel is local PM2.5, which is better data than any
forecast because it is measured in the yard. That section ships commented out, since the base
stations without the AQIN module have no PM entities to point at.

So: **AccuWeather drives the panel**, and it costs an API subscription. AccuWeather retired
its free tier, and the HA integration's own docs now open with "a paid subscription is
required". IQVIA is wired up commented-out as a free cross-check for the pollen half.

## Decisions, and why

### The dashboard is a YAML dashboard, registered from a package

Home Assistant's default dashboard is *storage mode* — the UI editor writes it into
`/config/.storage`, which here is a PVC. Anything built that way is invisible to Git and lost
on a restore, which is exactly the click-ops this repo is meant not to have.

A **YAML-mode dashboard** is registered under a top-level `lovelace:` key and read from a file.
The obvious place for that key is `configuration.yaml` — but `configuration.yaml` lives on the
PVC and is not in this repo, so putting it there would trade one manual step for another.

`lovelace` is a plain dict-schema integration with no platform list, so
`merge_packages_config` merges it into the top-level config like any other dict. That means the
registration can live in a package ConfigMap alongside `recorder.yaml` and `rtl433.yaml`, and
the whole panel — registration *and* cards — reconciles from Git with no edit to
`configuration.yaml` at all.

One constraint this creates: **nothing else in the repo may define a top-level `lovelace:`
key.** Two packages both declaring it would collide on merge and Home Assistant would log a
duplicate-key error rather than picking a winner. Future dashboards go in the `dashboards:`
dict inside this same package.

A second, non-obvious one: the dashboard slug **must contain a hyphen**. Lovelace's
`_validate_url_slug` rejects single-word url paths for everything except the built-in
`lovelace` dashboard, so the panel is `air-quality`, not `allergy`.

### Both files come off one ConfigMap, mounted twice

`home-assistant-air-quality` carries two keys, `subPath`-mounted to two places:
`/config/packages/air-quality.yaml` (the registration) and
`/config/dashboards/air-quality.yaml` (the cards). They are one unit — the registration names
the file — so splitting them across two ConfigMaps would only add a way for them to drift.

Both must be on disk before Home Assistant starts: a YAML dashboard is read during setup, not
lazily on first view.

### The cards ship pointing at entities that do not exist yet

Same call as the rtl-433 package, for the same reason — but resolved the other way, and the
difference is worth naming. There, sensor ids were *unknowable* until the receiver had heard a
transmission, so live placeholders would have been permanent junk in the entity registry.
Here the ids are fully predictable (`sensor.home_mold_pollen_day_0` and friends, from a config
entry titled "Home"); the only thing missing is the integration. So the AccuWeather cards ship
**live**. Until the integration is added they render "Entity not found", which is a legible
TODO on a home-lab dashboard, and they light up on their own the moment it lands — no second
commit.

The two sections that *are* commented out — Ambient PM and IQVIA — are commented for the
rtl-433 reason: their entity ids embed a station name and a ZIP code, so they cannot be
written down correctly from here.

### `state_content: [state, level]`

The tile cards show the count and AccuWeather's own category together — "1247 p/m³ · High".
The bare number means little without knowing that ragweed is scored on a different scale than
tree pollen; the category is the half that gets read at a glance.

## Changed files

| File | Change |
| --- | --- |
| `kubernetes/apps/default/home-assistant/app/configmap-air-quality.yaml` | new — Lovelace registration + dashboard |
| `kubernetes/apps/default/home-assistant/app/helm-release.yaml` | mount both keys |
| `kubernetes/apps/default/home-assistant/app/kustomization.yaml` | wire the ConfigMap in |

## Owner action items

Three, in order. Nothing in Bitwarden or terraform.

1. **Buy an AccuWeather API key.** [developer.accuweather.com](https://developer.accuweather.com/)
   → register → subscribe → create an application, and take the key from **Subscriptions &
   Keys**. The free tier is gone; the cheapest paid plan covers one location comfortably. The
   integration polls current conditions every 10 min, daily forecast every 6 h, hourly every
   30 min.

2. **Add the integration.** Settings → Devices & Services → Add Integration → AccuWeather.
   It defaults to Home Assistant's own coordinates, which makes the config entry "Home" and
   the entity ids match what the dashboard already expects. If you name it after the town
   instead, adjust the `sensor.home_*` prefix in the ConfigMap to match.

3. **Enable the four sensors.** All of `Mold pollen`, `Tree pollen`, `Grass pollen` and
   `Ragweed pollen` ship `entity_registry_enabled_default: False`, so they exist but are
   switched off. On the AccuWeather device page, filter to disabled entities and enable
   `… day 0` through `… day 3` for each of the four. This is the step that is easy to miss —
   the cards stay "Entity not found" until it is done, looking identical to step 2 not being
   done.

Optionally: uncomment the Ambient PM section if the station has an AQIN module, and the IQVIA
section after adding that integration (ZIP code, no key). Both need their real entity ids
filled in from Developer Tools → States first.

## Known gaps

- **Adding the integration is click-ops.** AccuWeather is config-flow only — it has no YAML
  configuration at all — so there is no declarative way to express it. Same category as the
  MQTT integration in the rtl-433 plan.
- **Enabling a disabled-by-default entity is click-ops too**, and there is likewise no YAML
  for it. Both are Home Assistant gaps, not repo ones.
