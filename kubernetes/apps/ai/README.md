# ai

The household AI stack: one inference router and the surfaces in front of it.

Design notes and the longer-range thinking live in [`docs/ai-platform`](../../../docs/ai-platform/README.md).

| App | Description | Manifest |
| --- | --- | --- |
| [hearthai](https://github.com/jokajak/hearthai) | The stack itself, as **one Helm release**: Open WebUI at `chat.${SECRET_DOMAIN}`, the litellm inference router behind it at `llm.${SECRET_DOMAIN}`, meridian's Claude-subscription bridge, and the hearthmem shared-memory store. hearthai owns the images, probes and the wiring between them; this repo supplies the URLs, Secrets, claims and the Postgres database. Collapsed from four separate app directories on 2026-09-10 — see [its README](./hearthai/README.md). | [ks.yaml](./hearthai/ks.yaml) |
| [n8n](https://n8n.io/) | Workflow automation at `n8n.${SECRET_DOMAIN}`. A trial started 2026-09-06; it sits here rather than in `productivity` because litellm is the point of it. | [ks.yaml](./n8n/ks.yaml) |
| [searxng](https://github.com/searxng/searxng) | Self-hosted metasearch, cluster-internal (no ingress). The search provider for hearthai's web-fetch tool: no account, no per-query cost, and the household's queries never reach a commercial provider. Results are untrusted input and are scrubbed by the consumer. | [ks.yaml](./searxng/ks.yaml) |

Anything in this namespace that wants a model talks to litellm at `hearthai-litellm:4000` with
its own virtual key, never to a provider directly.
