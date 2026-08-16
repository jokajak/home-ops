# Decisions & Open Questions

> Append-only log. Open questions get answered → become decisions with a date + rationale.

## ✅ Decisions made

- **2026-06-21 — Borrow TELOS, not PAI's hooks.** The durable idea we're keeping from PAI is the
  TELOS context engine + reconciliation loop. PAI's hook/skill/settings plumbing is explicitly
  out of scope. _(Josh)_
- **2026-06-21 — Track this in `docs/ai-platform/` in home-ops.** Living doc set, not a dated
  `docs/plans/` design. The platform will run on this cluster, so it belongs here.

## ❓ Open questions (the forks that change everything)

1. **Who are the users?** Josh-only first, or household-from-day-one? Who's in the household,
   and do kids/guests get a (limited) surface?
2. **Center of gravity** — Household OS / Personal augmentation / Automation brain / Household
   memory? Where does it start being great?
3. **Sovereignty** — local-only models, cloud frontier, or hybrid (route by sensitivity)?
4. **Primary surface** — web chat (AG-UI), voice/ambient, proactive, mobile, CLI? Rank them.
5. **Autonomy** — how proactive by default? Where's the line between suggest and act?
6. **Substrate** — Claude Code harness, a custom AG-UI agent, OpenCode, or a mix?

> Next step: knock out 1–4 (they constrain everything downstream); 5–6 follow from them.
