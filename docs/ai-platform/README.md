# Household AI Platform

> **Status:** 🟡 Brainstorm in progress (started 2026-06-21). Nothing here is decided.
> These are living documents, not a dated implementation plan.

## What this is

A tailored AI platform for Josh and the household — designed from scratch, but borrowing
the one idea from [PAI](https://ourpai.ai/) that's worth keeping: the **TELOS approach**.

The bet: most "AI platforms" are built around a model or a UI. This one is built around
**us** — who we are, what we're trying to do, and the continuous reconciliation of where we
are today vs. where we want to be. The model and the UI are swappable; the context engine is
the durable core.

```
        TELOS (who we are + what we're for)
                     │
          reconciles current ⇄ ideal
                     │
   ┌─────────────────┼─────────────────┐
 surfaces         capabilities        memory
 (chat/voice/     (what it does       (what it
  ambient)         for us)             remembers)
```

## The document set

| Doc | Purpose |
|-----|---------|
| [`00-telos.md`](./00-telos.md) | The household TELOS — identity, mission, goals, problems, ideal states. The context engine's source material. |
| [`01-platform-vision.md`](./01-platform-vision.md) | What the platform *is* and *does* — users, center of gravity, capabilities, surfaces. |
| [`02-keep-drop-from-pai.md`](./02-keep-drop-from-pai.md) | What we borrow from PAI vs. what we deliberately leave behind. |
| [`03-decisions.md`](./03-decisions.md) | Running log of decisions made + open questions still on the table. |

## How we'll work

Brainstorm-first. We fill these in conversationally; I bring structure and provocations,
Josh brings the actual content (TELOS is personal — I can't invent it). When a fork gets
decided, it moves from `03-decisions.md`'s open list into a decision entry.
