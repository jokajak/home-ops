#!/usr/bin/env bash
# Validate that every Flux Kustomization `spec.path` points at a directory that exists.
#
# Why: renaming/moving a directory (e.g. `network` -> `network-system`) without updating
# the `spec.path` in the corresponding ks.yaml leaves Flux Kustomizations pointing at a
# deleted path, which fails on-cluster with "kustomization path not found". This catches
# that in pre-commit / CI, before it ever reaches the cluster.
#
# Portable: works with both BSD (macOS) and GNU (Linux) userland; no yq/kustomize needed.
# Usage: scripts/validate-ks-paths.sh [scope-dir ...]   (default scope: kubernetes)
set -euo pipefail

# Resolve repo root so the script works from anywhere and relative spec.path values resolve.
if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fi
cd "$root"

# Scope: directories to scan (default: kubernetes). Lets pre-commit/CI narrow if desired.
if [ "$#" -gt 0 ]; then
  scopes="$*"
else
  scopes="kubernetes"
fi

fail=0
checked=0
files=0

# Discover files that declare a Flux Kustomization (reference the kustomize toolkit API
# group). This catches ks.yaml plus the root apps.yaml / cluster.yaml, and ignores inner
# `kustomization.yaml` files (those use the kustomize.config.k8s.io API group).
# shellcheck disable=SC2086
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Must actually contain a Flux Kustomization document, not merely a schema-comment URL.
  grep -qE '^kind:[[:space:]]*Kustomization[[:space:]]*$' "$f" || continue
  files=$((files + 1))

  # Extract filesystem-style spec.path values: strip the `path:` key, optional quotes, and
  # a leading `./`, then keep only values under `kubernetes/` (this excludes JSON-pointer
  # patch paths like `/spec/template/...` that can also appear under a `path:` key).
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    checked=$((checked + 1))
    if [ ! -d "$p" ]; then
      printf 'MISS  %-52s  <- %s\n' "$p" "$f"
      fail=$((fail + 1))
    fi
  done < <(
    grep -E '^[[:space:]]*path:[[:space:]]*' "$f" \
      | sed -E 's/^[[:space:]]*path:[[:space:]]*//; s/^"//; s/"$//; s#^\./##' \
      | grep -E '^kubernetes/' || true
  )
done < <(grep -rlE 'kustomize\.toolkit\.fluxcd\.io' $scopes --include='*.yaml' 2>/dev/null || true)

if [ "$fail" -gt 0 ]; then
  echo ""
  echo "✖ $fail Flux Kustomization path(s) do not resolve to a directory (checked $checked across $files files)."
  echo "  A renamed/moved directory likely left a stale spec.path. Update the path or restore the directory."
  exit 1
fi

echo "✔ All $checked Flux Kustomization spec.path references resolve ($files files, scope: $scopes)."
