#!/bin/bash
# sync-skills guarded remove: delete a skill by scope (one end only / fully)
# Usage:
#   remove.sh <skill-name> <all|claude|codex> [--confirm] [--force-real] [source-path]
#     all     delete both ends' symlinks + the source copy (full delete; this skill no longer exists)
#     claude  detach only the claude-end copy (source and the other end stay = disable single-host)
#     codex   detach only the codex-end copy
#   Default dry-run: without --confirm it only prints what would be deleted, touches nothing (writes need approval).
#   --force-real: required explicitly when a target is a real dir (not a symlink; content would be lost), else abort.
# Ask scope first: when the user hasn't said "one end only or full delete", ask before choosing scope; don't presume.
# Env overrides (for testing): CLAUDE_SKILLS_DIR / CODEX_SKILLS_DIR
set -euo pipefail

NAME="${1:?Usage: remove.sh <skill-name> <all|claude|codex> [--confirm] [--force-real] [source-path]}"
SCOPE="${2:?missing scope: all|claude|codex}"
shift 2

CONFIRM=0; FORCE_REAL=0
SOURCE="$HOME/.skill-source"
for arg in "$@"; do
  case "$arg" in
    --confirm)    CONFIRM=1 ;;
    --force-real) FORCE_REAL=1 ;;
    *)            SOURCE="$arg" ;;
  esac
done
CC="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CX="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"

die() { echo "ABORT: $*" >&2; exit 1; }

case "$SCOPE" in all|claude|codex) ;; *) die "scope must be all|claude|codex" ;; esac
[ -d "$SOURCE" ] || die "source does not exist: $SOURCE"

# Determine an end entry's kind: link / realdir / absent
kind_of() {
  local p="$1"
  if [ -L "$p" ]; then echo link
  elif [ -d "$p" ]; then echo realdir
  else echo absent
  fi
}

# Collect plan: each targets item is "kind|path|description"
targets=()
add_side() {   # $1=label $2=dir
  local label="$1" dir="$2" p k
  [ -d "$dir" ] || { echo "SKIP $label end not installed ($dir), skipping"; return; }
  p="$dir/$NAME"
  k=$(kind_of "$p")
  case "$k" in
    link)    targets+=("link|$p|$label end symlink (safe to delete, body is in the source)") ;;
    realdir) targets+=("realdir|$p|$label end real dir (WARNING content will be lost, needs --force-real)") ;;
    absent)  echo "SKIP $label end has no $NAME ($p does not exist)" ;;
  esac
}

case "$SCOPE" in
  claude) add_side claude "$CC" ;;
  codex)  add_side codex  "$CX" ;;
  all)
    add_side claude "$CC"
    add_side codex  "$CX"
    if [ -e "$SOURCE/$NAME" ]; then
      files=$(find "$SOURCE/$NAME" -type f 2>/dev/null | wc -l | tr -d ' ')
      targets+=("source|$SOURCE/$NAME|source body ($files files, WARNING permanent delete)")
    else
      echo "SKIP source has no $NAME ($SOURCE/$NAME does not exist)"
    fi
    ;;
esac

[ "${#targets[@]}" -gt 0 ] || die "no targets to delete (skill not present in the given scope)"

echo
echo "Will delete the following (scope: $SCOPE):"
has_real=0
for t in "${targets[@]}"; do
  IFS='|' read -r k p desc <<<"$t"
  echo "  - [$k] $p  # $desc"
  [ "$k" = realdir ] && has_real=1
done

# dry-run gate
if [ "$CONFIRM" != 1 ]; then
  echo
  [ "$has_real" = 1 ] && echo "Note: includes a real-dir target; you'll also need --force-real to run (else it aborts); to keep the content use release.sh instead."
  echo "This is a preview (dry-run). When it looks right, add --confirm to actually run."
  exit 0
fi

# Pre-exec guard: real dir
if [ "$has_real" = 1 ] && [ "$FORCE_REAL" != 1 ]; then
  die "real-dir target present (deleting loses the content). To delete anyway add --force-real; to keep the content use release.sh"
fi

# Execute
echo
for t in "${targets[@]}"; do
  IFS='|' read -r k p desc <<<"$t"
  case "$k" in
    link)           rm "$p";     echo "REMOVED link   $p" ;;
    realdir|source) rm -rf "$p"; echo "REMOVED $k $p" ;;
  esac
done

echo
echo "Done. Reminder: a running session on the other end must restart to see the change; suggest running scan.sh to re-check."
