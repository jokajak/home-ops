# Security review — meridian

> 2026-08-25 · Reviewer: Claude · Subject: [`rynfar/meridian`](https://github.com/rynfar/meridian)
> at `main` HEAD `992f81c` (2026-08-21), `package.json` version **1.62.7**
>
> **Verdict: consistent with its claims. No malicious code found.** Three hardening changes were
> made to *our* deployment as a result — none of them because meridian misbehaves.

## What it claims to be

A local proxy that bridges the Claude Agent SDK to the standard Anthropic API format, so tools
expecting an API endpoint can be backed by a Claude subscription. It says it does this "within the
SDK's constraints, not around them" — no OAuth interception, no binary patching.

## What the code actually does

| Check | Finding |
|---|---|
| **Dependency surface** | Four runtime dependencies: `@anthropic-ai/claude-agent-sdk`, `@anthropic-ai/claude-code`, `jsonc-parser`, `libsql`. Two are official Anthropic packages. Unusually small for 72k lines of TypeScript |
| **Lifecycle hooks** | One `postinstall`, which runs `@anthropic-ai/claude-code`'s own `install.cjs` inside a try/catch. It invokes an official package's installer, not a fetch from an arbitrary URL |
| **Dynamic code execution** | **No `eval()`, no `new Function()`, no `vm` module** anywhere in `src/` |
| **Obfuscation** | None. No base64 blobs, no minified payloads. The four lines over 500 characters are template literals for log formatting and dashboard HTML |
| **Outbound network** | Every host referenced in `src/`: Anthropic domains, `localhost`/`127.0.0.1`, documentation links, and `registry.npmjs.org` |
| **Credential handling** | `~/.claude/.credentials.json` is read by `tokenRefresh.ts` and `oauthUsage.ts` only. The token is sent to `api.anthropic.com` and nowhere else. No path transmits it elsewhere, and no log statement prints a token value |
| **`child_process` usage** | Real but purposeful: `grepTool`, `mcpTools`, and shelling out to `claude auth status` / `claude auth login`. The `spawnSync("node", ["-e", …])` blocks are readline prompts — static scripts, no interpolation of untrusted input |
| **Plugin system** | Loads ES modules from local file paths. Nothing is installed unless `MERIDIAN_PLUGINS` is set, which we do not set |
| **Container entrypoint** | Minimal: symlinks `.claude.json` onto the volume, conditionally installs plugins, `exec "$@"` |

### The `telemetry/` directory is not telemetry

The name is alarming and the content is not. Every `fetch()` in it uses a **relative path**
(`/health`, `/profiles/list`, `/telemetry/summary`) — it is browser-side JavaScript for
meridian's own local dashboard, calling meridian's own server. Nothing leaves the host.

### The one piece of unsolicited egress

`src/proxy/updateCheck.ts` queries `registry.npmjs.org` for its own latest version, once a day,
with a 5-second timeout. Benign, and cleanly opt-out via `NO_UPDATE_CHECK` — which we now set.

## What this review does *not* establish

Stated plainly, because these are the gaps that matter:

1. **We reviewed source, not the image.** `package.json` says `1.62.7` and the GHCR tag we pin is
   `1.62.7`, which is good correspondence — but nothing here verifies the published image was
   built from this commit. No signature or build attestation was checked. **A malicious image
   published under a matching tag would not have been caught by this review.**
2. **The git tags and the release series have diverged** — git stops at `v1.29.2` while the
   registry and `package.json` are on `1.62.x`. So there is no `1.62.7` tag to read; we reviewed
   `main` as of 2026-08-21 and inferred correspondence from the version field.
3. **Transitive dependencies were not audited**, including `@anthropic-ai/claude-code` itself,
   which is large.
4. **This is a point-in-time review.** It says nothing about future versions; Renovate bumps will
   not re-run it.

## Findings against *our* deployment

None of these are defects in meridian. All three are consequences of taking software designed for
`127.0.0.1` and putting it on a cluster network.

| # | Finding | Fix |
|---|---|---|
| 1 | **The proxy was unauthenticated.** `MERIDIAN_API_KEY` gates it, but `auth.ts` is explicitly a no-op when unset — and we had not set it. Once logged in, anything able to reach port 3456 could spend the Claude subscription anonymously | `MERIDIAN_API_KEY` now generated in `terraform/bitwarden` and injected via ExternalSecret |
| 2 | **No network restriction.** Any pod in the cluster could open a connection to it | `CiliumNetworkPolicy` admitting only LiteLLM, which is the sole intended consumer |
| 3 | **Daily version check** to `registry.npmjs.org` | `NO_UPDATE_CHECK=1` |

### One thing to be aware of, not fixed

The image bakes `IS_SANDBOX=1`. That tells Claude Code it is running sandboxed, which relaxes
interactive permission prompting — reasonable in a container with no TTY to prompt on, but it
means the agent SDK runs with fewer guardrails than it would on a laptop. Relevant if meridian is
ever given credentials and pointed at anything that matters.

## Bottom line

The code does what it says. The philosophy in the README — work within the SDK rather than around
it — is borne out: it calls `query()`, holds no scraped tokens, and reaches nothing but Anthropic.
The residual risk is supply chain (point 1 above), not authorship.
