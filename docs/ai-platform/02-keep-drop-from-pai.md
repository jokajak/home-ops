# Keep / Drop from PAI

> Josh's framing: *"The part I want from PAI is the TELOS approach, not the specific
> implementation of hooks."* This doc makes that explicit so we don't accidentally re-import
> PAI's complexity.
>
> **Status:** 🟡 Draft — starting opinions, open to challenge.

## ✅ Keep (the durable ideas)

- **TELOS context engine** — identity → mission → goals → problems → ideal states, and the
  continuous reconciliation of current vs. ideal. This is the whole reason we're here.
- **Compounding memory** — memory that accrues across sessions and becomes more useful over
  time (PAI: WORK → LEARNING → KNOWLEDGE). Household-scaled.
- **Verifiable iteration** — PAI's Algorithm/ISC idea: state the ideal, build toward it, verify
  against explicit criteria. Worth keeping as a *principle*, not necessarily the machinery.
- **DA identity (optional)** — a named, voiced assistant the household relates to. Nice for a
  voice/ambient surface; not load-bearing.

## ❌ Drop / replace (the implementation we don't want)

- **The hook system** — PAI's lifecycle hooks, settings.json plumbing, force-loaded files.
  Replace with whatever our chosen platform gives us natively.
- **The specific skill/workflow file layout** — 45 skills / 171 workflows / 37 hooks is PAI's
  answer to PAI's problem, not ours.
- **Claude-Code-as-substrate assumption** — PAI is a Claude Code harness. We want to choose our
  substrate deliberately (could still be Claude Code, could be an AG-UI agent, could be both).
- **Single-principal assumption** — PAI is built around one person. We need household/multi-user
  from the design stage.

## 🤔 Open / undecided

- The Algorithm/ISC machinery: keep the *principle* of verifiable iteration, but how much of the
  formal apparatus survives at household scale? TBD.
- Voice: keep (household-friendly) or drop (complexity)? Depends on surfaces.
