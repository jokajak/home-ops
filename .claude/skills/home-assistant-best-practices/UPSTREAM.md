# Vendored skill: home-assistant-best-practices

Copied from [homeassistant-ai/skills](https://github.com/homeassistant-ai/skills)
(MIT, see `LICENSE`) so that sessions load it from this repository instead of fetching a
plugin marketplace at start-up. Updates arrive only as a reviewed commit here.

| | |
|---|---|
| Upstream path | `skills/home-assistant-best-practices/` |
| Upstream commit | `166defa51c606b3c77d45a9b29a459d1f993f357` (2026-10-29) |
| Plugin version | 0.56.0 (skill metadata version 56) |

Everything except `LICENSE` and this file is **byte-identical to upstream**. Do not edit the
vendored files; repo-specific overrides live in `CLAUDE.md` ("Home Assistant skill" section),
so an update stays a plain copy and its diff shows only upstream's changes.

Only the skill itself is vendored. Upstream's evals, scripts, CI workflows and plugin
manifests are not needed to use it.

## Updating

```sh
git clone --depth 1 https://github.com/homeassistant-ai/skills /tmp/ha-skills
rsync -a --delete --exclude LICENSE --exclude UPSTREAM.md \
  /tmp/ha-skills/skills/home-assistant-best-practices/ \
  .claude/skills/home-assistant-best-practices/
cp /tmp/ha-skills/LICENSE .claude/skills/home-assistant-best-practices/LICENSE
git -C /tmp/ha-skills log -1 --format='%H %cs'   # record in the table above
```

Review the diff before committing: this text steers the agent in every session.
