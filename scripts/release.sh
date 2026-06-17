#!/bin/bash
# sync-skills guarded release: restore a managed skill to a standalone real dir, re-attributed by origin
# Usage: release.sh <skill-name> [--confirm] [--both] [source-path]
#   Reads .sync-origin in the source to decide which end it returns to:
#     codex  -> back to codex only; the claude-end symlink is removed (no leftover copy)
#     claude -> back to claude only; the codex-end symlink is removed
#     both / no marker -> keep a standalone copy on each end
#   --both: ignore origin, force a copy on both ends (for "keep as-is" on restore; no loss of current availability)
#   Copy & verify first, delete the source last -- on any mid-way failure the body still exists.
# "Full exit": release each skill one by one (each back to its home), then reverse the move-house steps for the pointer.
# Env overrides (for testing): CLAUDE_SKILLS_DIR / CODEX_SKILLS_DIR
set -euo pipefail

NAME="${1:?Usage: release.sh <skill-name> [--confirm] [source-path]}"
shift
CONFIRM=0; BOTH=0
SOURCE="$HOME/.skill-source"
for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRM=1 ;;
    --both) BOTH=1 ;;
    *) SOURCE="$arg" ;;
  esac
done
CC="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CX="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
die() { echo "ABORT: $*" >&2; exit 1; }

[ -d "$SOURCE" ] || die "source does not exist: $SOURCE"
[ -d "$SOURCE/$NAME" ] || die "source has no such skill: $SOURCE/$NAME"
[ -f "$SOURCE/$NAME/SKILL.md" ] || die "source $NAME is missing SKILL.md, body unhealthy, refusing to release"

# Read origin (no marker / invalid value -> both)
origin="both"
[ -f "$SOURCE/$NAME/.sync-origin" ] && origin=$(head -1 "$SOURCE/$NAME/.sync-origin" | tr -d '[:space:]')
case "$origin" in claude|codex|both) ;; *) origin="both" ;; esac
[ "$BOTH" = 1 ] && origin="both"   # --both: ignore origin, keep as-is on both ends

# For each symlinked end decide keep (land a standalone copy) / drop (just remove the symlink; origin says not this end)
keep=(); drop=()
for side in claude codex; do
  if [ "$side" = claude ]; then dir="$CC"; else dir="$CX"; fi
  [ -d "$dir" ] || { echo "SKIP $side end not installed ($dir)"; continue; }
  p="$dir/$NAME"
  if [ -L "$p" ]; then
    if [ "$origin" = both ] || [ "$origin" = "$side" ]; then keep+=("$side|$dir"); else drop+=("$side|$dir"); fi
  elif [ -d "$p" ]; then
    echo "SKIP $side end is already a real dir (unmanaged or already released): $p"
  else
    echo "SKIP $side end has no $NAME"
  fi
done

[ "${#keep[@]}" -gt 0 ] || die "with origin=$origin there is no end to land the body on (nowhere to place it), aborting"

echo
echo "Releasing $NAME (origin=$origin):"
for s in "${keep[@]}"; do IFS='|' read -r l d <<<"$s"; echo "  · $l: $d/$NAME <- land as a standalone real dir (keep)"; done
for s in "${drop[@]:-}"; do [ -n "$s" ] || continue; IFS='|' read -r l d <<<"$s"; echo "  · $l: $d/$NAME <- remove symlink (origin says not this end)"; done
echo "  · source $SOURCE/$NAME <- deleted after distribution completes"

if [ "$CONFIRM" != 1 ]; then
  echo; echo "This is a preview (dry-run). When it looks right, add --confirm to actually run."; exit 0
fi

echo
# keep: land the copy and verify first (strip management metadata from the copy)
for s in "${keep[@]}"; do
  IFS='|' read -r l d <<<"$s"; p="$d/$NAME"
  rm "$p"
  cp -R "$SOURCE/$NAME" "$p"
  rm -f "$p/.sync-origin"
  [ -f "$p/SKILL.md" ] || die "release failed: $p missing SKILL.md (source still at $SOURCE/$NAME, run migrate.sh $NAME link to restore)"
  echo "RELEASED $l -> $p (standalone real dir)"
done
# drop: remove the symlink (origin says not this end)
for s in "${drop[@]:-}"; do
  [ -n "$s" ] || continue
  IFS='|' read -r l d <<<"$s"; rm "$d/$NAME"; echo "DROPPED $l symlink (origin $origin, not this end)"
done
# body safely distributed, delete the source copy
rm -rf "$SOURCE/$NAME"
echo "REMOVED source $SOURCE/$NAME"

echo
echo "Done. $NAME has been re-attributed by origin=$origin; the source no longer manages it."
echo "Reminder: a running session on the relevant end must restart to see the change."
