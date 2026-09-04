# Home Assistant: a pollen & mold panel, shipped as code

> Status: **STAGED** — on a branch, not yet merged or deployed · 2026-09-01 ·
> Owner: Josh · Author: Claude
>
> Small change, two shape decisions worth writing down: this is the first Lovelace
> dashboard in this repo, and the first thing in it that scrapes a web page.

## Goal

A panel in the Home Assistant sidebar showing **mold** and **pollen** counts, defined in Git
rather than clicked together in the UI editor.

## Where the numbers come from

**Atlanta Allergy & Asthma's counting station**, read straight off
[their public pollen page](https://www.atlantaallergy.com/pollen_counts). It is the only
station in metro Atlanta certified by the National Allergy Bureau: these are microscope counts
of grains per cubic metre of air over the previous 24 hours, taken a few miles away — not a
model interpolating a grid cell. Free, no key, no account.

That is a better answer than any of the API options, all of which were considered first:

| Source | Mold | Pollen | Cost | Verdict |
| --- | --- | --- | --- | --- |
| **Atlanta Allergy** | ✅ activity band | ✅ real counts + species | free | Local, measured, and names the plants |
| AccuWeather (core) | ✅ modelled count | ✅ modelled counts | **paid key** | Rejected — pays for a worse number |
| IQVIA / Pollen.com (core) | ❌ | index only | free | No mold, no counts |
| Ambient Weather (core) | ❌ | ❌ | owned | Nothing to offer here — see below |
| Open-Meteo air quality | ❌ | Europe only | free | Useless from Atlanta |

An earlier revision of this plan built the panel on AccuWeather, because it is the only *core
integration* that reports an outdoor mold count. Reading the station directly is better on
every axis that matters — measured rather than modelled, local rather than gridded, free
rather than subscription — and the only thing given up is a 4-day forecast, which for deciding
whether to open the windows this morning is not the question being asked.

**The Ambient Weather station contributes nothing to this.** Its integration exposes
temperature, humidity, wind, rain, solar/UV, lightning, and — only with the AQIN add-on module
— PM2.5, PM10 and CO₂. There is no pollen or mold field anywhere in it, and there could not
be: a consumer weather station measures the atmosphere, while pollen and mold counts come from
microscope slide counts. It can measure PM2.5 locally with that module, which
would beat any forecast, but particulate is a different question from pollen and mold and is
deliberately not on this panel.

## Decisions, and why

### The built-in Scrape integration, not a CronJob publishing to MQTT

The obvious shape for "fetch a page twice a day and turn it into entities" is a small
container on a schedule pushing MQTT discovery messages, and the parts are all already here —
Mosquitto in `home-automation`, the MQTT integration configured.

It is still the wrong call. Home Assistant's **Scrape** integration is exactly this program,
already written, already running in a process that is up anyway: one `resource`, a list of
CSS selectors, a `scan_interval`. Choosing the CronJob instead would add an image to build and
keep patched, a workload to schedule, a broker dependency on the path between the data and the
dashboard, and a second place for the parsing to live — in exchange for nothing this needs.
`Fewer moving parts beats more nines`, and this is the cheapest possible version of that.

The CronJob shape earns its keep the day this needs something Scrape cannot express — several
pages stitched together, a login, history backfill. It does not today.

### Scraping this particular page is fine, and the once-a-day rate is the reason

Two things separate this from casual scraping. `robots.txt` is `User-agent: *` with an empty
`Disallow:`, which permits everything. And the count is **published once per weekday**, so
there is no benefit to polling faster than the data changes: `scan_interval` is **4 hours**,
six requests a day, fewer than a browser tab left open on the page. Do not lower it.

### Per-category counts are recovered from the gauge needle

The page prints one number — the combined total — and shows trees, grass and weeds only as
four-band gauges. But each gauge positions its needle by exact linear interpolation inside the
active band, and every band is 25% of the bar, so for a needle at `p%` in band `s = p // 25`:

```
count = lo[s] + (p - 25s) / 25 × (lo[s+1] - lo[s])
```

This recovers the exact per-category count the station measured. It was verified against four
days spanning three different bands, and in every derivable case the three categories sum to
the published total:

| Date | Trees | Grass | Weeds | Sum | Published total |
| --- | --- | --- | --- | --- | --- |
| 2026-09-01 | 5 | 1 | 7 | 13 | 13 ✅ |
| 2026-03-20 | 243 | 0 | 2 | 245 | 245 ✅ |
| 2026-05-20 | 26 | 5 | 2 | 33 | 33 ✅ |
| 2026-06-10 | 5 | 0 | 0 | 5 | 5 ✅ |

That sum is also the standing self-check: **if the three counts ever stop adding up to
`sensor.atlanta_pollen_total`, the site has changed its gauge** and those three sensors are
the ones to delete. Everything else on the panel is read from printed text and is unaffected.

The top band is open-ended (`E=1500+`) and the needle saturates at 99%, so no count can be
derived there. The `availability` template takes those sensors unavailable rather than
inventing a number — deliberately not patched around by subtracting from the total, because on
an extreme tree day the total *is* the tree count to within a rounding error (2026-04-01:
total 3640, of which weeds contributed 2), so the fallback would add an entity and a failure
mode to restate a number already on screen.

### Weekends need no handling

On days the station does not publish, the page says "There is no pollen data for `<date>`" and
the entire widget is absent. Every selector misses, Scrape logs a warning and marks each
sensor unavailable, and the cards grey out together. That is the correct behaviour and it
arrives for free — worth knowing so it is not mistaken for a break.

The reading-date sensor exists for the adjacent failure: a count that loads fine but is
yesterday's. It is the only way to tell from the dashboard.

### The dashboard is a YAML dashboard, registered from a package

Home Assistant's default dashboard is *storage mode* — the UI editor writes it into
`/config/.storage`, which here is a PVC. Anything built that way is invisible to Git and lost
on a restore, which is exactly the click-ops this repo is meant not to have.

A YAML-mode dashboard is registered under a top-level `lovelace:` key. The obvious home for
that is `configuration.yaml` — but that file lives on the PVC and is not in this repo, so
putting it there trades one manual step for another. `lovelace` is a plain dict-schema
integration with no platform list, so `merge_packages_config` merges it into the top-level
config like any other dict, which means the registration can live in a package ConfigMap
alongside `recorder.yaml` and `rtl433.yaml` and the whole panel reconciles from Git.

Two constraints this creates:

- **Nothing else in the repo may define a top-level `lovelace:` key.** Two packages declaring
  it would collide on merge. Future dashboards go in the `dashboards:` dict in this same file.
- **The dashboard slug must contain a hyphen.** Lovelace's `_validate_url_slug` rejects
  single-word url paths for everything except the built-in `lovelace` dashboard, so the panel
  is `air-quality`, not `pollen`.

### Two ConfigMaps, not one

`home-assistant-pollen` is the data (Scrape sensors); `home-assistant-air-quality` is the
presentation (Lovelace registration + cards). They change for different reasons — the first
when the site's markup moves, the second when the panel is rearranged — and the sensors are
useful to automations with no dashboard involved at all.

## Changed files

| File | Change |
| --- | --- |
| `kubernetes/apps/default/home-assistant/app/configmap-pollen.yaml` | new — 12 Scrape sensors |
| `kubernetes/apps/default/home-assistant/app/configmap-air-quality.yaml` | new — Lovelace registration + dashboard |
| `kubernetes/apps/default/home-assistant/app/helm-release.yaml` | mount all three keys |
| `kubernetes/apps/default/home-assistant/app/kustomization.yaml` | wire both ConfigMaps in |

## Entities created

| Entity | What it is |
| --- | --- |
| `sensor.atlanta_pollen_total` | Published total, `p/m³` |
| `sensor.atlanta_mold_activity` | Low / Moderate / High / Extremely High |
| `sensor.atlanta_pollen_reading_date` | Which day the page's count is for |
| `sensor.atlanta_{tree,grass,weed}_pollen` | Per-category count, `p/m³` |
| `sensor.atlanta_{tree,grass,weed}_pollen_level` | Per-category band |
| `sensor.atlanta_{tree,grass,weed}_pollen_contributors` | e.g. "Ragweed, Nettle, Pigweed" |

## Owner action items

**None.** No API key, no account, no integration to add in the UI, nothing in Bitwarden or
terraform. This is the first thing in this repo's Home Assistant setup with no manual step at
all — the Scrape platform is YAML-configurable, so unlike the MQTT and AccuWeather routes there
is no config flow to click through. Push the branch, let Flux reconcile, and the `Air Quality`
panel appears in the sidebar.

## Known gaps

- **No forecast.** The station reports what it counted yesterday; there is no "tomorrow will
  be worse". Accepted deliberately: the owner's call is that this page carries everything
  wanted, so no second source is wired in behind it.
- **No mold number**, because the station does not publish one — mold is an activity band on
  this page and nothing more. AccuWeather is still the only source of a numeric mold count,
  and it is modelled rather than measured.
- **Markup dependency.** A site redesign breaks the sensors. The cross-check above is the
  early warning; the failure mode is unavailable entities, not silently wrong ones, except in
  the derived counts where the sum is the guard.
