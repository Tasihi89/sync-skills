#!/bin/bash
# sync-skills one-click install (first run on a fresh machine)
# Does three things: (1) create the source + pointer  (2) bootstrap: adopt sync-skills into the source and link both ends
#           (3) print next steps (reconcile your other existing skills in)
# Usage:
#   ./install.sh                      # source defaults to ~/skill-source
#   ./install.sh --source ~/my-skills # custom source location (ASCII, no spaces)
# Env overrides (for testing): CLAUDE_SKILLS_DIR / CODEX_SKILLS_DIR
set -euo pipefail

# Locate the cloned skill root (the directory this script lives in)
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SOURCE_REAL="$HOME/skill-source"
while [ $# -gt 0 ]; do
  case "$1" in
    --source) SOURCE_REAL="${2:?--source needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (use --help for usage)" >&2; exit 1 ;;
  esac
done

POINTER="$HOME/.skill-source"
CC="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CX="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"
die() { echo "ABORT: $*" >&2; exit 1; }

echo "== sync-skills install =="
echo "skill source:  $SELF_DIR"
echo "source (body): $SOURCE_REAL"
echo "pointer:       $POINTER -> $SOURCE_REAL"
echo

# 1. Detect ends (don't assume both are installed; if neither, create at least the Claude end)
have_cc=0; have_cx=0
[ -d "$CC" ] && have_cc=1
[ -d "$CX" ] && have_cx=1
if [ "$have_cc" = 0 ] && [ "$have_cx" = 0 ]; then
  echo "neither end's skills dir exists, creating $CC"
  mkdir -p "$CC"; have_cc=1
fi
echo "ends: Claude=$([ "$have_cc" = 1 ] && echo yes || echo no)  Codex=$([ "$have_cx" = 1 ] && echo yes || echo no)"

# 2. Create the source + pointer (reuse if present, don't overwrite)
mkdir -p "$SOURCE_REAL"
if [ -L "$POINTER" ]; then
  cur="$(readlink "$POINTER")"
  if [ "$cur" != "$SOURCE_REAL" ]; then
    echo "Note: pointer already exists and points at $cur, reusing it (ignoring this run's $SOURCE_REAL)"
    SOURCE_REAL="$cur"
  fi
elif [ -e "$POINTER" ]; then
  die "$POINTER already exists and is not a symlink, please resolve manually and retry"
else
  ln -s "$SOURCE_REAL" "$POINTER"
  echo "created pointer $POINTER -> $SOURCE_REAL"
fi

# 3. Bootstrap: put sync-skills itself into the source (skip if already there)
if [ -e "$SOURCE_REAL/sync-skills" ]; then
  echo "source already has sync-skills, skipping copy"
else
  cp -R "$SELF_DIR" "$SOURCE_REAL/sync-skills"
  rm -rf "$SOURCE_REAL/sync-skills/.git"   # don't carry git history into the source
  echo "copied sync-skills into the source"
fi

# Ensure scripts are executable (a non-git download/copy may drop +x; self-heal, don't rely on a manual chmod)
chmod +x "$SOURCE_REAL/sync-skills/install.sh" "$SOURCE_REAL/sync-skills/scripts/"*.sh 2>/dev/null || true

# 4. Link both ends (reuse our own migrate link; pass the pointer so links route through it; sync-skills lives on both ends -> both)
bash "$SOURCE_REAL/sync-skills/scripts/migrate.sh" sync-skills link --origin both "$POINTER"

echo
echo "== install complete =="

# Inventory: list other not-yet-adopted skills to guide the next step (install also guides)
pending=$(bash "$SOURCE_REAL/sync-skills/scripts/scan.sh" 2>/dev/null | awk '/^CANDIDATE /{print "  · "$3"  ("$2")"}')
if [ -n "$pending" ]; then
  n=$(printf '%s\n' "$pending" | wc -l | tr -d ' ')
  echo
  echo "Inventory: you still have $n skill(s) scattered across ends, not yet centrally managed:"
  printf '%s\n' "$pending"
  echo
  echo "Next steps --"
  echo "  1) Restart Claude Code / Codex (so they pick up sync-skills)"
  echo "  2) Tell Claude /sync-skills; it will help judge which ones suit both ends and adopt them one by one"
else
  echo
  echo "Next: restart Claude Code / Codex. From now on, when installing a new skill, just tell Claude /sync-skills."
fi
