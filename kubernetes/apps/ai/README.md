# ai

The household AI stack: one inference router and the surfaces in front of it.

Design notes and the longer-range thinking live in [`docs/ai-platform`](../../../docs/ai-platform/README.md).

| App | Description | Manifest |
| --- | --- | --- |
| [litellm](https://github.com/BerriAI/litellm) | The household's inference router: one upstream subscription, one virtual key per consumer. Own role on the shared CNPG Postgres. Everything else here talks to it rather than to a provider directly. | [ks.yaml](./litellm/ks.yaml) |
| [meridian](https://github.com/rkjdev/meridian) | Claude-subscription bridge for litellm. Inert until someone completes the interactive login — see its HelmRelease. | [ks.yaml](./meridian/ks.yaml) |
| [n8n](https://n8n.io/) | Workflow automation at `n8n.${SECRET_DOMAIN}`. A trial started 2026-09-06; it sits here rather than in `productivity` because litellm is the point of it. | [ks.yaml](./n8n/ks.yaml) |
| [searxng](https://github.com/searxng/searxng) | Self-hosted metasearch, cluster-internal (no ingress). The search provider for hearthai's web-fetch tool: no account, no per-query cost, and the household's queries never reach a commercial provider. Results are untrusted input and are scrubbed by the consumer. | [ks.yaml](./searxng/ks.yaml) |
| [open-webui](https://github.com/open-webui/open-webui) | The household assistant at `chat.${SECRET_DOMAIN}`. Talks to litellm directly; the per-person Hermes agents it used to front were removed 2026-09-04. | [ks.yaml](./open-webui/ks.yaml) |
| hearthmem | The hearthai shared-memory store. **Currently has no consumers** — they were the Hermes agents' shared-memory skill — and is kept while its future as a store of record is decided. See [its README](./hearthmem/README.md). | [ks.yaml](./hearthmem/ks.yaml) |
