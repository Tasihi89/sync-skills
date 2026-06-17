#!/bin/bash
# sync-skills reconcile scan (read-only): source-of-truth + each end's skills dir -> diff report
# Usage: scan.sh [source-path]
# Env overrides (for testing): CLAUDE_SKILLS_DIR / CODEX_SKILLS_DIR / SYNC_IGNORE
# Generic: does not assume both ends are installed (absent end -> SIDE_ABSENT); the ignore list folds permanent single-host candidate noise.
# Reports facts only; makes no changes and no judgments.

SOURCE="${1:-$HOME/.skill-source}"   # defaults to the pointer symlink; it points at the real source location
CC="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CX="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
IGNORE_FILE="${SYNC_IGNORE:-$HOME/.skill-source-ignore}"   # maintained locally by the user; does not travel with the repo

echo "SOURCE=$SOURCE"
echo "CLAUDE=$CC"
echo "CODEX=$CX"
[ -f "$IGNORE_FILE" ] && echo "IGNORE=$IGNORE_FILE"

if [ ! -d "$SOURCE" ]; then
  if [ -L "$SOURCE" ]; then
    echo "RESULT=POINTER_BROKEN  # pointer exists but target is gone: $(readlink "$SOURCE")"
  else
    echo "RESULT=NO_SOURCE  # pointer does not exist; needs init (ask the user where to put the source)"
  fi
  exit 0
fi

section() { echo; echo "## $1"; }

# List skill entries under a directory (skip hidden and .DS_Store)
entries() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  for e in "$dir"/*; do
    [ -e "$e" ] || [ -L "$e" ] || continue
    local n; n=$(basename "$e")
    [ "$n" = ".DS_Store" ] && continue
    echo "$n"
  done
}

# Whether a name is in the ignore list (permanent single-host; folded, not reported per-line). Exact per-line match; skips # comments and blank lines.
is_ignored() {
  local name="$1" line
  [ -f "$IGNORE_FILE" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"                       # strip inline comment
    line="${line#"${line%%[![:space:]]*}"}"  # strip leading whitespace
    line="${line%"${line##*[![:space:]]}"}"  # strip trailing whitespace
    [ -z "$line" ] && continue
    [ "$line" = "$name" ] && return 0
  done < "$IGNORE_FILE"
  return 1
}

section "1. Source inventory"
for n in $(entries "$SOURCE"); do
  files=$(find "$SOURCE/$n" -type f -not -name '.DS_Store' -not -name '.sync-origin' 2>/dev/null | wc -l | tr -d ' ')
  origin=$(head -1 "$SOURCE/$n/.sync-origin" 2>/dev/null | tr -d '[:space:]')
  [ -z "$origin" ] && origin="?"
  echo "SOURCE_SKILL $n files=$files origin=$origin"
done

# Report one end's status: healthy link / broken link / points elsewhere / real dir; absent end -> SIDE_ABSENT
report_side() {
  local label="$1" dir="$2"
  section "2. ${label} end status"
  if [ ! -d "$dir" ]; then
    echo "SIDE_ABSENT $label  # this end is not installed ($dir does not exist), skipping"
    return 0
  fi
  for n in $(entries "$dir"); do
    local p="$dir/$n"
    if [ -L "$p" ]; then
      local target; target=$(readlink "$p")
      if [ ! -e "$p" ]; then
        echo "BROKEN_LINK $label $n -> $target"
      elif [ "$target" = "$SOURCE/$n" ]; then
        echo "LINK_OK $label $n"
      else
        echo "LINK_ELSEWHERE $label $n -> $target"
      fi
    else
      echo "REAL_DIR $label $n"
    fi
  done
}
report_side claude "$CC"
report_side codex "$CX"

section "3. Adoption candidates (real dirs not yet in the source)"
candidates=0
ignored=0
for side in claude codex; do
  [ "$side" = claude ] && dir="$CC" || dir="$CX"
  [ -d "$dir" ] || continue
  for n in $(entries "$dir"); do
    p="$dir/$n"
    [ -L "$p" ] && continue
    [ ! -d "$p" ] && continue
    if is_ignored "$n"; then
      ignored=$((ignored+1))
      continue
    fi
    flags=""
    [ -e "$SOURCE/$n" ] && flags="$flags SOURCE_CONFLICT"   # source already has same name
    if [ "$side" = claude ]; then other="$CX/$n"; else other="$CC/$n"; fi
    [ -e "$other" ] && [ ! -L "$other" ] && flags="$flags DUP_BOTH_SIDES"  # same-name real dir on both ends
    [ -d "$CX/.system/$n" ] && flags="$flags COLLIDES_CODEX_BUILTIN"      # collides with a Codex builtin
    echo "CANDIDATE $side $n$flags"
    candidates=$((candidates+1))
  done
done
[ "$ignored" -gt 0 ] && echo "CANDIDATE_IGNORED count=$ignored  # in the ignore list ($IGNORE_FILE), folded"
[ "$candidates" -eq 0 ] && [ "$ignored" -eq 0 ] && echo "(none)"

section "4. Structural anomalies"
issues=0
# Source orphan: body is in the source but an end lacks its symlink (only checked for installed ends)
for n in $(entries "$SOURCE"); do
  for side in claude codex; do
    if [ "$side" = claude ]; then p="$CC/$n"; sdir="$CC"; else p="$CX/$n"; sdir="$CX"; fi
    [ -d "$sdir" ] || continue   # end not installed, not counted as a missing link
    if [ ! -e "$p" ] && [ ! -L "$p" ]; then
      echo "MISSING_LINK $side $n  # in source but missing on this end: link may need restoring, or you already removed this end -> if removing, use the remove flow (scenario 3); do not blindly re-link"
      issues=$((issues+1))
    fi
  done
done
# Broken / mispointed links (already flagged in section 2; tallied here)
for side in claude codex; do
  [ "$side" = claude ] && dir="$CC" || dir="$CX"
  [ -d "$dir" ] || continue
  for n in $(entries "$dir"); do
    p="$dir/$n"
    if [ -L "$p" ] && [ ! -e "$p" ]; then issues=$((issues+1)); fi
  done
done
# Frontmatter validity: Codex parses SKILL.md strictly as YAML; invalid frontmatter is silently rejected (symlink/name look fine but it never shows up)
for n in $(entries "$SOURCE"); do
  md="$SOURCE/$n/SKILL.md"
  [ -f "$md" ] || continue
  err=$(python3 - "$md" 2>/dev/null <<'PY'
import sys
try:
    import yaml
except Exception:
    sys.exit(0)                      # no pyyaml -> skip, avoid false positives
parts = open(sys.argv[1], encoding='utf-8').read().split('---')
if len(parts) < 3:
    sys.exit(0)                      # no frontmatter
try:
    yaml.safe_load(parts[1])
except Exception as e:
    print(str(e).splitlines()[0])
PY
)
  if [ -n "$err" ]; then
    echo "FRONTMATTER_INVALID $n  # Codex will reject: $err"
    issues=$((issues+1))
  fi
done
[ "$issues" -eq 0 ] && echo "(none)"

section "5. Plugins & builtins (count only, no action)"
sys_count=$(ls "$CX/.system" 2>/dev/null | grep -cv '^\.DS_Store$' | tr -d ' ')
plugin_count=$(find "$HOME/.claude/plugins/cache" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
echo "CODEX_BUILTIN count=$sys_count"
echo "CLAUDE_PLUGIN_SKILLS count=$plugin_count"

echo
echo "RESULT=DONE candidates=$candidates ignored=$ignored issues=$issues"
