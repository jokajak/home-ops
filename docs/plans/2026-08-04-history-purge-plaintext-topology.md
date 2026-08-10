# Purging plaintext network topology from git history

> Status: **PLANNED — not executed** · 2026-08-04 · Owner: Josh · Author: Claude
>
> The audit below is complete and was run against the full 1592-commit history. The procedure is
> written to be executable later without re-deriving anything. **No history has been rewritten,
> no refs force-pushed, no tags deleted.**
>
> Companion to [`ISSUES.md`](../ISSUES.md) #6, which covers consolidating the two Talos trees in
> the *working tree*. This doc covers the separate question of what is already in *history*.

## Context

The de-templating pass ([`cc157a3`](../plans/2026-08-04-upstream-template-realignment.md)) found
`talos/talconfig.yaml` tracked in plaintext, carrying exactly the network detail `CLAUDE.md` says
stays out of the repo. Deleting a file removes it from `HEAD`, not from history — hence this.

Two facts shape everything below.

**The repository has been public since 2024-02-11.** ~2.5 years of world-readable history, 0
forks. A purge is damage limitation, not erasure. Anything here should be treated as disclosed.

**The same addresses are still live at `HEAD`.** Purging history while `main` continues to publish
them accomplishes nothing. Ordering matters, and it is step 1 of the procedure — not an
afterthought.

## Audit

Method, so this is reproducible: every blob under 2 MB was enumerated with
`git cat-file --batch-all-objects --batch-check` and grepped for three patterns — the real node
address prefix, `BEGIN … PRIVATE KEY`, and the internal domain. **1592 commits, 15178 objects,
3099 blobs scanned. 10 blobs matched, across 8 paths.**

> Run this from a **full** clone. See the shallow-clone warning in step 0.

### Confirmed sensitive, history-only — remove by path

| Path | Revisions | Contents |
| --- | --- | --- |
| `talos/talconfig.yaml` | 2, both plaintext | 7 nodes — addresses, API VIP, default gateway, MAC addresses, VLAN IDs, install-disk serials, internal API hostname |
| `kubernetes/talos/talconfig.yaml.norpi` | 1, plaintext | Same class of data, Talos v1.8.1 era |
| `kubernetes/talos/talosconfig.20240317.1258` | 1, plaintext | `os:admin` client certificate (`ca`/`crt`/`key`), **expired 2025-03-17**, plus 3 node addresses |

None of these three exist in any form worth keeping. `talos/talconfig.yaml` is superseded by the
consolidation work in ISSUES #6; the other two are stale artifacts.

### Sensitive in one old revision, clean today — replace content, do NOT delete the path

| Path | Revision | Contents |
| --- | --- | --- |
| `kubernetes/apps/kube-system/coredns/app/helm-values.yaml` | 2024-03-25 | Internal domain |

This file is live and must survive the rewrite. It is the reason the procedure needs
`--replace-text` and not just `--path`/`--invert-paths`.

### Verified safe — never committed in the clear

| Path | Revisions | Result |
| --- | --- | --- |
| `kubernetes/talos/talconfig.yaml` | 3 | All `ENC[AES256_GCM` |
| `kubernetes/talos/talsecret.sops.yaml` | 1 | Encrypted |

SOPS did its job. These need no action and must **not** be purged — `talsecret.sops.yaml` is the
irreplaceable Talos secrets bundle.

### False positive — recorded so nobody re-panics

`config.sample.yaml` matches `BEGIN OPENSSH PRIVATE KEY` in several revisions including the
initial 2024-02-11 commit. It is the upstream template's **commented-out placeholder**:

```text
      # key: |
      #   -----BEGIN OPENSSH PRIVATE KEY-----
      #   ...
      #   -----END OPENSSH PRIVATE KEY-----
```

No key material, in any revision. The file was deleted in `cc157a3` as template machinery.

### Live at `HEAD` — the ordering problem

| Path | Occurrences | Note |
| --- | --- | --- |
| `kubernetes/apps/observability/gatus/app/nodes-configmap.yaml` | 7 | **Live manifest.** Gatus monitors kubelet on `:10250` per node |
| `docs/plans/2026-02-08-cilium-gateway-api-migration.md` | 7 | Design doc |
| `docs/plans/2026-02-08-distributed-gatus-design.md` | 7 | Design doc |

These are the same addresses the purge targets. Left alone, they remain on the default branch of a
public repo and the rewrite is theatre.

> **Cleared 2026-08-10.** All three are fixed, plus a fourth the table missed —
> `talos/talconfig.yaml`, which held the same addresses in the clear and has been replaced by the
> SOPS-encrypted `talos/topf.yaml`. `git grep` for the node prefix and the VLAN prefix now returns
> nothing at `HEAD`. See [the topf migration](./2026-08-10-talos-consolidation-and-topf.md).
> The ordering problem is resolved; the purge itself remains **planned and unexecuted**.

## Procedure

### 0. Start from a full mirror

```sh
git clone --mirror https://github.com/jokajak/home-ops.git home-ops-purge.git
cd home-ops-purge.git
git rev-list --count --all      # sanity: expect ~1592+, not ~50
```

> **Warning.** The clone this audit ran in arrived **shallow** — 50 commits, grafted at
> `47115aa` — and had to be `git fetch --unshallow`'d to reach 1592. A `filter-repo` run against a
> shallow clone rewrites only the grafted commits and silently truncates everything older.
> Always check the commit count before filtering.

### 1. Fix `HEAD` first — **done 2026-08-10**

Nothing else in this procedure was worth doing until this landed on `main`. What shipped:

- **`kubernetes/apps/observability/gatus/app/nodes-configmap.yaml`** — the 7 addresses are now
  `${SECRET_NODE_*}` substitutions. They resolve from a new `cluster-secrets-user` Secret rather
  than `cluster-secrets`: `kubernetes/flux/apps.yaml` already wired `cluster-secrets-user` into
  every Kustomization as an *optional* `substituteFrom`, so it was the sanctioned slot and needed
  no access to the existing encrypted secrets. The variable was created and populated in the same
  change, so there is no window where the Kustomization cannot reconcile.
- **The two design docs** — redacted. They refer to nodes by name and to addresses by variable.
- **`talos/talconfig.yaml`** — not in the original table, but it carried the same addresses in the
  clear. Replaced by the SOPS-encrypted `talos/topf.yaml`.

Verified: `git grep` for the node prefix and the VLAN prefix returns nothing at `HEAD`.

### 2. Back up off-origin

```sh
git bundle create ../home-ops-pre-purge.bundle --all
```

Keep the bundle somewhere that is **not** `origin`. Pushing a backup ref to origin would keep
alive precisely the objects being purged. After the force-push in step 7 this bundle and your
local clones are the only copies of the old history — treat it accordingly.

### 3. Install the tool

```sh
pip install git-filter-repo
```

Not preinstalled in the CI/devcontainer images; confirmed pip-installable.

### 4. Rewrite

Create `replacements.txt` with the literal values to scrub (real values intentionally not
reproduced in this repo — take them from `talos/talconfig.yaml` before it is removed):

```text
regex:\b<node-address-prefix>\.\d{1,3}\b==><REDACTED-IP>
regex:\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b==><REDACTED-MAC>
<internal-api-hostname>==><REDACTED-HOST>
```

Then:

```sh
git filter-repo \
  --invert-paths \
    --path talos/talconfig.yaml \
    --path kubernetes/talos/talconfig.yaml.norpi \
    --path kubernetes/talos/talosconfig.20240317.1258 \
  --replace-text ../replacements.txt
```

**Why both mechanisms.** `--invert-paths` removes files that should cease to exist. `--replace-text`
scrubs leaks *inside* files that must survive — the 2024-03-25 coredns values — and acts as a
backstop for anything the path enumeration missed. Neither alone is sufficient.

Note `filter-repo` drops the `origin` remote by design; re-add it before step 7.

### 5. Verify

Re-run the audit scan against the rewritten mirror and expect **zero** hits:

```sh
git cat-file --batch-all-objects --batch-check='%(objectname) %(objecttype) %(objectsize)' \
  | awk '$2=="blob" && $3<2000000 {print $1}' \
  | while read -r b; do
      git cat-file -p "$b" 2>/dev/null \
        | grep -qE '<node-address-prefix>\.|BEGIN [A-Z ]*PRIVATE KEY|<internal-domain>' \
        && echo "STILL PRESENT: $b"
    done
```

Also confirm the commit count did not collapse, and that
`kubernetes/talos/talsecret.sops.yaml` and the encrypted `kubernetes/talos/talconfig.yaml`
survived.

### 6. Delete the 30 template-release tags

`2024.3.0` … `2026.8.0` were generated by the upstream cluster-template's monthly release cron,
which was deleted in `cc157a3`. They carry no meaning for a personal home-ops repo, and each one
pins old objects reachable.

```sh
git tag | xargs -r git tag -d
git push origin --delete $(git ls-remote --tags origin | awk '{print $2}' | sed 's|refs/tags/||')
```

**This step is independent of the rewrite** and can be done on its own at any time.

### 7. Force-push

All refs, not just `main` — ~20 other branches exist on origin.

```sh
git remote add origin https://github.com/jokajak/home-ops.git
git push --force --all origin
```

Then every clone must `git fetch origin && git reset --hard origin/main`. A `git pull` against
rewritten history will produce a merge that reintroduces the purged blobs.

Flux syncs `main` over HTTPS; a force-push changes every commit SHA. Expect the `GitRepository` to
re-resolve on its next interval. Nothing else should notice.

### 8. GitHub-side residue

A force-push does **not** remove blobs from GitHub. Unreferenced objects remain fetchable by SHA,
and `refs/pull/*` keep old PR heads — and their trees — alive indefinitely.

Draft support request:

> Repository: `jokajak/home-ops`
>
> I have rewritten this repository's history with `git filter-repo` to remove files that contained
> private network configuration, and force-pushed all refs. Please garbage-collect unreferenced
> objects and stale `refs/pull/*` references so the removed content is no longer retrievable by
> commit SHA.

The only method that *guarantees* no residue is pushing the rewritten history to a brand-new
repository and deleting the old one — at the cost of all issues, pull requests, watchers, Actions
history, and the Flux `GitRepository` URL until it is re-pointed. Given the exposure below, that
trade is probably not worth it.

## What is deliberately not being done

**Nothing here is rotatable.** The `os:admin` certificate expired 2025-03-17 — there is no live
credential to revoke. Addresses, MAC addresses and VLAN IDs are not secrets in the cryptographic
sense; they cannot be rotated, only renumbered.

**Treat the topology as disclosed.** Public repository, 2.5 years, indexable by anyone. The purge
stops future casual discovery from the repo itself; it does not un-publish what has already been
served, cached, or scraped. If this genuinely matters, renumbering the LAN is the only real
remedy, and that is a decision about the network, not about git.

## Verification checklist

Before declaring the purge done:

- [x] `HEAD` fixed and pushed (step 1) — gatus configmap variabilized, design docs redacted, `talconfig.yaml` replaced by an encrypted `topf.yaml` (2026-08-10)
- [ ] Commit count on the mirror sane before filtering (not shallow)
- [ ] Off-origin bundle exists and has been checked
- [ ] Post-rewrite blob scan returns zero hits
- [ ] `talsecret.sops.yaml` (now `talos/secrets.yaml`) and the encrypted `kubernetes/talos/talconfig.yaml` blob survived the rewrite
- [ ] Tags deleted locally and on origin
- [ ] All branches force-pushed
- [ ] Every local clone reset to `origin/main` (not merged)
- [ ] Flux `GitRepository` reconciled against the new history
- [ ] GitHub Support request sent
