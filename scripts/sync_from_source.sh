#!/usr/bin/env bash
#
# Pull customer-facing documents from the (private) source projects into
# this public docs repo. Run from this repo's root after each Belt /
# Hook firmware release, then commit + push.
#
#   ./scripts/sync_from_source.sh
#
# Authoritative sources (private repos):
#   /Users/living/Projects/21_XDA003B/docs/
#   /Users/living/Projects/21_XDA003B/firmware/release/README.md
#   /Users/living/Projects/22_XDA003H/docs/
#   /Users/living/Projects/22_XDA003H/firmware/release/README.md
#
# Anything else under those private docs/ folders (decision_log, status,
# underconfirmissues, work_log, project_*, etc.) is intentionally NOT
# synced. Inside the synced markdown files, sections starting with
# `### 附錄` (engineering reconciliation tables that point to internal
# open_issues / decision_log) are stripped automatically. After
# stripping, the markdown is reconverted to PDF via the
# 09_markdown_to_pdf skill so the public PDF matches the public md.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BELT_SRC="${BELT_SRC:-/Users/living/Projects/21_XDA003B}"
HOOK_SRC="${HOOK_SRC:-/Users/living/Projects/22_XDA003H}"
MD2PDF="${MD2PDF:-/Users/living/Projects/09_markdown_to_pdf/scripts/convert.sh}"

if [[ ! -d "$BELT_SRC" || ! -d "$HOOK_SRC" ]]; then
  echo "ERROR: source projects not found." >&2
  echo "  BELT_SRC=$BELT_SRC" >&2
  echo "  HOOK_SRC=$HOOK_SRC" >&2
  exit 1
fi
if [[ ! -x "$MD2PDF" ]]; then
  echo "ERROR: markdown→pdf converter not found / not executable: $MD2PDF" >&2
  exit 1
fi

# Pairs of "<source-md>::<dst-md-relative>". For each pair, sync_md will
# (1) copy + strip "### 附錄" sections, and (2) regenerate <dst>.pdf
# from the filtered markdown.
declare -a MD_PAIRS=(
  "$BELT_SRC/docs/belt_operation.md::belt/operation.md"
  "$BELT_SRC/docs/belt_hook_parameter_protocol.md::belt/parameter_protocol.md"
  "$BELT_SRC/docs/parameter_protocol_v2_vs_v3.md::belt/parameter_protocol_v2_vs_v3.md"
  "$HOOK_SRC/docs/hook_operation.md::hook/operation.md"
)

# Plain-copy markdown files that don't need filtering / pdf rebuild.
declare -a RAW_PAIRS=(
  "$BELT_SRC/firmware/release/README.md::belt/flashing.md"
  "$HOOK_SRC/firmware/release/README.md::hook/flashing.md"
)

changed=0

# awk filter: stop output the moment a heading like "### 附錄" appears, so
# everything from that point to EOF is dropped. Also tolerates extra
# whitespace and the "***" hr that usually precedes the appendix.
strip_appendix() {
  awk '
    BEGIN { skip = 0; pending_hr = "" }
    /^[[:space:]]*### +附錄/ { skip = 1; next }
    skip == 1 { next }
    /^[[:space:]]*\*\*\*[[:space:]]*$/ { pending_hr = $0; next }
    {
      if (pending_hr != "") { print pending_hr; pending_hr = "" }
      print
    }
  ' "$1"
}

# Cross-repo links resolve in the source layout (sibling 21_XDA003B /
# 22_XDA003H folders) but break in this public repo. Rewrite the known
# inbound patterns to either:
#   * a path that works inside this repo (belt_operation → belt/...)
#   * plain text without a link, when the target is a private-only
#     resource that we deliberately do not expose (e.g., dev tools).
#
# `sed -i ''` is the BSD/macOS form; on GNU sed it's `sed -i`. The bare
# pattern keeps this script portable across both.
rewrite_links() {
  local file="$1"
  # Cross-repo doc → public-repo doc.
  sed -i '' \
    -e 's|\.\./\.\./21_XDA003B/docs/belt_operation\.md|../belt/operation.md|g' \
    -e 's|\.\./\.\./21_XDA003B/docs/belt_hook_parameter_protocol\.md|../belt/parameter_protocol.md|g' \
    -e 's|\.\./\.\./22_XDA003H/docs/hook_operation\.md|../hook/operation.md|g' \
    "$file"
  # Private-only tool links → unwrap to plain text (drop the `[...](...)`
  # wrapper, keep only the visible text).
  /opt/homebrew/bin/python3 - "$file" <<'PY'
import re, sys
p = sys.argv[1]
text = open(p, 'r', encoding='utf-8').read()
# Patterns whose targets are not part of the public repo. Match the
# whole `[text](url)` and replace with just `text`.
patterns = [
    r'\[([^\]]+)\]\(\.\./\.\./21_XDA003B/tools/[^)]*\)',
    r'\[([^\]]+)\]\(\.\./\.\./22_XDA003H/tools/[^)]*\)',
    r'\[([^\]]+)\]\(\.\./\.\./tools/[^)]*\)',
]
for pat in patterns:
    text = re.sub(pat, r'\1', text)
open(p, 'w', encoding='utf-8').write(text)
PY
}

for entry in "${MD_PAIRS[@]}"; do
  src="${entry%%::*}"
  dst_rel="${entry##*::}"
  dst="$REPO_ROOT/$dst_rel"
  if [[ ! -f "$src" ]]; then
    echo "WARN: missing $src — skipped"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp)"
  strip_appendix "$src" > "$tmp"
  rewrite_links "$tmp"
  if [[ ! -f "$dst" ]] || ! cmp -s "$tmp" "$dst"; then
    mv "$tmp" "$dst"
    echo "  updated  $dst_rel  (stripped appendix + rewrote links)"
    # Rebuild PDF alongside.
    pdf_dst="${dst%.md}.pdf"
    if "$MD2PDF" "$dst" "$pdf_dst" >/dev/null 2>&1; then
      echo "  updated  ${pdf_dst##$REPO_ROOT/}"
    else
      echo "  WARN: pdf rebuild failed for $dst_rel" >&2
    fi
    changed=$((changed + 1))
  else
    rm -f "$tmp"
    echo "  unchanged $dst_rel"
  fi
done

for entry in "${RAW_PAIRS[@]}"; do
  src="${entry%%::*}"
  dst_rel="${entry##*::}"
  dst="$REPO_ROOT/$dst_rel"
  if [[ ! -f "$src" ]]; then
    echo "WARN: missing $src — skipped"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  tmp="$(mktemp)"
  cp "$src" "$tmp"
  rewrite_links "$tmp"
  if [[ ! -f "$dst" ]] || ! cmp -s "$tmp" "$dst"; then
    mv "$tmp" "$dst"
    echo "  updated  $dst_rel"
    changed=$((changed + 1))
  else
    rm -f "$tmp"
    echo "  unchanged $dst_rel"
  fi
done

echo
if [[ $changed -gt 0 ]]; then
  echo "$changed file(s) updated. Review with: git -C \"$REPO_ROOT\" status"
else
  echo "Nothing changed."
fi
