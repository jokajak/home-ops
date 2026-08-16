# Platform Vision

> What the platform *is* and *does*, on top of the TELOS engine.
>
> **Status:** 🟡 Brainstorm — dimensions below are a menu to react to, not commitments.

## Center of gravity (pick one to start)

A platform that tries to do everything does nothing. What's the *first* thing it's great at?

- **A. Household OS** — shared brain for the home: calendars, reminders, "where's the X",
  meal planning, who-needs-to-do-what, status of the house (and this cluster).
- **B. Personal augmentation** — Josh's TELOS, goals, knowledge work, writing, decisions.
  Single-principal, deep. (This is closest to what PAI already is.)
- **C. Home automation brain** — the reasoning layer over IoT/sensors/cluster; the house
  acts on its own state.
- **D. Household memory** — the durable, queryable record of the family: documents, decisions,
  "what did we decide about…", manuals, warranties, kids' stuff.

> My read: start at **A or B**, treat the others as capabilities that accrete. Brainstorm needed.

## Users & access

- Multi-tenant from day one, or Josh-only first then expand?
- Per-member identity → different context, different permissions, age-appropriate gating.
- Guest mode?

## Interaction surfaces

How do people actually *touch* it? (Can be several; rank them.)

- **Web chat** — likely AG-UI-based (see `02-keep-drop`), not an OpenAI-shim. Runs in-cluster.
- **Voice** — ambient, room-based (PAI's Luma is voice-first via ElevenLabs). Household-friendly.
- **Proactive / ambient** — it speaks up unprompted (nudges, reminders, reconciliation).
- **Mobile** — on-the-go access.
- **Terminal / agent CLI** — power surface for Josh (the PAI/Claude Code style).

## Capabilities (what it actually does)

> The verbs. Seeded — add/cut freely.

- Remembers (household memory, compounding)
- Reconciles (TELOS loop — nudges toward goals)
- Schedules / reminds
- Answers (household knowledge: manuals, decisions, "where is…")
- Automates (acts on the home / cluster)
- Creates (writing, planning, research for the household)
- Watches (status of home systems, surfaces problems)

## Autonomy spectrum

Borrowed from PAI's DA model — what can it do *without asking*?

- **Observe only** (silent context) →
- **Suggest** (nudges, drafts) →
- **Act with approval** (human-in-the-loop — AG-UI handles this well) →
- **Act autonomously** (within guardrails)

> Different capabilities sit at different points. Reminders = autonomous; spending = approval.

## Models & sovereignty

- Local-only (Ollama/vLLM in-cluster), cloud frontier (Claude/GPT), or **hybrid** (route by
  sensitivity)? Given the "everything as code, self-hosted" ethos of this repo, hybrid with a
  local default and cloud escalation is the natural fit — but it's a real decision.

## Where it runs

- This cluster (Flux/Talos) — HelmReleases for each component, same GitOps discipline.
- TELOS + memory data tier: NAS/NFS like Immich? CNPG Postgres? Needs a home.
