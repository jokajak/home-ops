# Decisions & Open Questions

> Append-only log. Open questions get answered → become decisions with a date + rationale.

## ✅ Decisions made

- **2026-06-21 — Borrow TELOS, not PAI's hooks.** The durable idea we're keeping from PAI is the
  TELOS context engine + reconciliation loop. PAI's hook/skill/settings plumbing is explicitly
  out of scope. _(Josh)_
- **2026-06-21 — Track this in `docs/ai-platform/` in home-ops.** Living doc set, not a dated
  `docs/plans/` design. The platform will run on this cluster, so it belongs here.
- **2026-08-24 — Household from day one, one agent per person.** Two Hermes agents (Josh,
  partner), each its own container, volume and identity — not one agent with two profiles.
  Answers open question 1 for the adults; kids and guests are still open. The isolation is
  structural rather than policy-based, which is what makes hearthai's "a private store is
  private" claim mean anything. _(Josh)_
- **2026-08-24 — Substrate is Hermes; the household layer is a skill, not an agent.**
  Answers open question 6. Per-person agents plus
  [hearthai](https://github.com/jokajak/hearthai)'s `shared-memory` skill between them, rather
  than building an orchestrator. _(Josh)_
- **2026-08-24 — Hybrid sovereignty, routed through self-hosted LiteLLM.** Answers open
  question 3 as far as it can be answered: no GPU in this cluster means no local inference
  today, so Anthropic is upstream — but behind a router we run, so the household holds one
  credential, each person gets a virtual key with its own budget, and adding a local model
  later is a config edit rather than a migration. _(Josh)_
- **2026-08-24 — Primary surface is the web dashboard, gated by Authentik.** Answers open
  question 4 by elimination: no messaging platform is available to this household. Voice,
  ambient and mobile remain unbuilt. _(Josh)_

- **2026-09-04 — Substrate is Open WebUI; Hermes is out.** Reverses the 2026-08-24 substrate
  decision after two weeks. Open WebUI has the autonomy the agents were kept for — scheduled
  automations run by a background worker, sub-agents, OpenAPI/MCP tool servers, and memory
  scoped per signed-in user — so one shared application replaces two agent processes, and
  identity stops being "which model did you pick". _(Josh)_
- **2026-09-04 — Structural separation is not worth its cost.** Per-person process, volume and
  home-directory isolation was what made "a private store is private" structural rather than
  policy. The household does not want it at that price, which is what made the decision above
  possible. hearthai's first non-negotiable no longer holds here; say so rather than pretending
  otherwise. _(Josh)_
- **2026-09-04 — hearthai becomes the extension repo, not the runtime.** Plugins, tools and the
  memory-extraction loop are built there and reach Open WebUI over HTTP, so home-ops holds
  wiring rather than logic. _(Josh)_

> Implementation: [`docs/plans/2026-08-24-hermes-household-agents.md`](../plans/2026-08-24-hermes-household-agents.md)
> (superseded — describes what was removed on 2026-09-04).

## ❓ Open questions (the forks that change everything)

1. ~~**Who are the users?**~~ Partly answered 2026-08-24: two adults, one agent each. Still
   open: **kids and guests** — private-means-private and guardianship pull against each other,
   and nothing reconciles them yet.
2. **Center of gravity** — Household OS / Personal augmentation / Automation brain / Household
   memory? Where does it start being great? Still open, and now answerable from use rather than
   from argument.
3. ~~**Sovereignty**~~ — answered 2026-08-24 (hybrid, via LiteLLM). Revisit when there is
   hardware that could serve a tool-calling model locally.
4. ~~**Primary surface**~~ — answered 2026-08-24 (web dashboard). "Reachable where you already
   are" is still unmet; that was hearthai's second goal.
5. **Autonomy** — how proactive by default? Where's the line between suggest and act? Still
   unanswered, and now urgent rather than theoretical: Open WebUI's scheduled automations run
   unattended **with full tool approval**, so the question is no longer "could we" but "what
   licenses this run to act".
6. ~~**Substrate**~~ — answered 2026-08-24 (Hermes), **reversed 2026-09-04** (Open WebUI).

> Next step: live with it. 2 and 5 are the ones real use should answer, and the TELOS engine
> (`00-telos.md`) is still a skeleton that nothing reads.
