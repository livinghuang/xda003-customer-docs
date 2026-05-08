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
# underconfirmissues, work_log, project_*, etc.) is considered internal
# and intentionally NOT synced. Edit FILES_TO_SYNC below to expand.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BELT_SRC="${BELT_SRC:-/Users/living/Projects/21_XDA003B}"
HOOK_SRC="${HOOK_SRC:-/Users/living/Projects/22_XDA003H}"

if [[ ! -d "$BELT_SRC" || ! -d "$HOOK_SRC" ]]; then
  echo "ERROR: source projects not found." >&2
  echo "  BELT_SRC=$BELT_SRC" >&2
  echo "  HOOK_SRC=$HOOK_SRC" >&2
  exit 1
fi

declare -a FILES_TO_SYNC=(
  "$BELT_SRC/docs/belt_operation.md::belt/operation.md"
  "$BELT_SRC/docs/belt_operation.pdf::belt/operation.pdf"
  "$BELT_SRC/docs/belt_hook_parameter_protocol.md::belt/parameter_protocol.md"
  "$BELT_SRC/docs/belt_hook_parameter_protocol.pdf::belt/parameter_protocol.pdf"
  "$BELT_SRC/firmware/release/README.md::belt/flashing.md"
  "$HOOK_SRC/docs/hook_operation.md::hook/operation.md"
  "$HOOK_SRC/docs/hook_operation.pdf::hook/operation.pdf"
  "$HOOK_SRC/firmware/release/README.md::hook/flashing.md"
)

changed=0
for entry in "${FILES_TO_SYNC[@]}"; do
  src="${entry%%::*}"
  dst="$REPO_ROOT/${entry##*::}"
  if [[ ! -f "$src" ]]; then
    echo "WARN: missing $src — skipped"
    continue
  fi
  mkdir -p "$(dirname "$dst")"
  if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
    cp "$src" "$dst"
    echo "  updated  ${entry##*::}"
    changed=$((changed + 1))
  else
    echo "  unchanged ${entry##*::}"
  fi
done

echo
if [[ $changed -gt 0 ]]; then
  echo "$changed file(s) updated. Review with: git -C \"$REPO_ROOT\" status"
else
  echo "Nothing changed."
fi
