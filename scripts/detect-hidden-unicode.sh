#!/usr/bin/env bash
# Detect hidden Unicode characters -- ones that are invisible or that alter rendering.
#
# Why: a zero-width space or a non-breaking space inside a manifest changes what Flux
# reconciles onto the cluster while looking identical in review, and bidi overrides
# (Trojan Source, CVE-2021-42574) or Unicode tag characters (U+E0000-U+E007F) can hide
# text a reviewer never sees. Commits here are often authored by copy-paste from chat or
# the web, which is the usual way such characters get in. This catches them in CI, before
# they ever reach the cluster.
#
# Scope: only invisible / rendering-altering characters. Ordinary non-ASCII text is
# legitimate and is NOT flagged -- this repo deliberately contains em dashes, arrows, box
# drawing and emoji. Homoglyph and mixed-script confusables (Cyrillic "a" vs Latin "a")
# are out of scope; catching those needs a confusables table.
#
# Requires: GNU grep with PCRE (`grep -P`). This is the CI check and runs on ubuntu-latest,
# so unlike scripts/validate-ks-paths.sh it is not written for BSD/busybox userland.
# Usage: scripts/detect-hidden-unicode.sh [pathspec ...]   (default scope: whole repo)
set -euo pipefail

# PCRE only reads \x{...} as a codepoint, rather than a raw byte, in a UTF-8 locale.
export LC_ALL=C.UTF-8

# Resolve repo root so the script works from anywhere and pathspecs stay repo-relative.
if root="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
else
    root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
fi
cd "$root"

if ! printf 'x' | grep -qP 'x' 2>/dev/null; then
    echo "✖ This script needs GNU grep built with PCRE support (grep -P)." >&2
    exit 2
fi

# Deliberate exemptions, as git pathspecs. Keep this list short, and always say why.
# Empty by design: a character that genuinely has to exist can usually be written as an
# escape instead -- see the \u00A0 escape in the zwave-js-ui device path, which keeps the file
# bytes visible in review while still parsing to the character the node needs.
exclusions=()

# Detected character groups, as "label|PCRE class". Each entry is a single class (or a
# two-class sequence) so the combined pattern below can join them with a plain `|`.
groups=(
    'zero-width or joiner|[\x{200B}-\x{200D}\x{2060}-\x{2064}\x{FEFF}\x{180E}]'
    'bidi control|[\x{200E}\x{200F}\x{202A}-\x{202E}\x{2066}-\x{2069}\x{061C}]'
    'invisible or filler|[\x{00AD}\x{034F}\x{115F}\x{1160}\x{17B4}\x{17B5}\x{3164}\x{FFA0}\x{2800}]'
    'deprecated format|[\x{206A}-\x{206F}\x{FFF9}-\x{FFFB}]'
    'unusual whitespace|[\x{00A0}\x{1680}\x{2000}-\x{200A}\x{202F}\x{205F}\x{3000}]'
    'line or paragraph separator|[\x{2028}\x{2029}]'
    'tag character (ASCII smuggling)|[\x{E0000}-\x{E007F}]'
    # A variation selector after an emoji base is normal presentation (the warning sign in
    # README.md is one); after a plain ASCII character it is how text gets smuggled.
    'variation selector after ASCII|[\x00-\x7F][\x{FE00}-\x{FE0F}]'
)

combined=""
for group in "${groups[@]}"; do
    combined="${combined:+${combined}|}${group#*|}"
done

# Scope: pathspecs to scan (default: whole repo). Lets CI or a caller narrow the search.
if [ "$#" -gt 0 ]; then
    scopes=("$@")
else
    scopes=(".")
fi

# Fast pass: one search over all tracked, non-binary files (`-I`). Most runs stop here.
mapfile -t hits < <(
    git grep -I -l -P -e "$combined" -- "${scopes[@]}" "${exclusions[@]}" || true
)

scanned="$(git ls-files -- "${scopes[@]}" "${exclusions[@]}" | wc -l | tr -d '[:space:]')"

if [ "${#hits[@]}" -eq 0 ]; then
    echo "✔ No hidden Unicode characters found ($scanned tracked files, scope: ${scopes[*]})."
    exit 0
fi

# Detail pass: only over files that matched, to name the exact codepoint on each line.
findings=0
for file in "${hits[@]}"; do
    for group in "${groups[@]}"; do
        label="${group%%|*}"
        pattern="${group#*|}"

        while IFS= read -r entry; do
            [ -n "$entry" ] || continue
            lineno="${entry%%:*}"
            content="${entry#*:}"

            while IFS= read -r match; do
                # The variation-selector group matches two characters; the hidden one is last.
                char="${match: -1}"
                printf -v codepoint '%d' "'$char"
                printf -v token '<U+%04X>' "$codepoint"

                # Render the line with the offender made visible, then trim and clip it.
                rendered="${content//"$char"/$token}"
                rendered="${rendered#"${rendered%%[![:space:]]*}"}"
                [ "${#rendered}" -le 140 ] || rendered="${rendered:0:140}..."

                printf 'HIDDEN  %s:%s  U+%04X  (%s)\n' "$file" "$lineno" "$codepoint" "$label"
                printf '        %s\n' "$rendered"
                findings=$((findings + 1))
            done < <(printf '%s\n' "$content" | grep -oP -e "$pattern" || true)
        done < <(grep -nP -e "$pattern" -- "$file" || true)
    done
done

echo ""
echo "✖ $findings hidden Unicode character(s) found across ${#hits[@]} file(s) (scanned $scanned)."
echo "  They are invisible in review but are part of the file content. Remove them; if one"
echo "  is genuinely required, add a documented exemption to the exclusions list in this script."
exit 1
