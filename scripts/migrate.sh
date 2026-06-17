#!/bin/bash
# sync-skills guarded migrate: move body into the source + per-end symlinks + inode verify + record origin
# Usage:
#   migrate.sh <skill-name> <claude|codex> [--origin claude|codex|both] [source-path]
#   migrate.sh <skill-name> link [--origin claude|codex|both] [source-path]
# origin: which end the skill originally belongs to; decides which end it returns to on release.
#   claude|codex modes default to writing the source end; for a body merged from both use --origin both;
#   link mode leaves an existing origin untouched by default (override with --origin).
# Env overrides (for testing): CLAUDE_SKILLS_DIR / CODEX_SKILLS_DIR
set -euo pipefail

NAME="${1:?Usage: migrate.sh <skill-name> <claude|codex|link> [--origin …] [source-path]}"
MODE="${2:?missing second argument: claude|codex|link}"
shift 2
ORIGIN_OPT=""
SOURCE="$HOME/.skill-source"
while [ $# -gt 0 ]; do
  case "$1" in
    --origin) ORIGIN_OPT="${2:?--origin needs a value: claude|codex|both}"; shift 2 ;;
    *) SOURCE="$1"; shift ;;
  esac
done
CC="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
CX="${CODEX_SKILLS_DIR:-$HOME/.codex/skills}"

die() { echo "ABORT: $*" >&2; exit 1; }
if [ -n "$ORIGIN_OPT" ]; then
  case "$ORIGIN_OPT" in claude|codex|both) ;; *) die "--origin must be claude|codex|both" ;; esac
fi

[ -d "$SOURCE" ] || die "source does not exist: $SOURCE"
CC_OK=0; CX_OK=0
[ -d "$CC" ] && CC_OK=1
[ -d "$CX" ] && CX_OK=1
[ "$CC_OK" = 1 ] || [ "$CX_OK" = 1 ] || die "neither end's skills dir exists: $CC / $CX"

if [ "$MODE" = "claude" ] || [ "$MODE" = "codex" ]; then
  [ "$MODE" = "claude" ] && ORIGIN="$CC/$NAME" || ORIGIN="$CX/$NAME"
  [ "$MODE" = "claude" ] && OTHER="$CX/$NAME"  || OTHER="$CC/$NAME"
  [ -d "$ORIGIN" ] || die "source dir missing or not a directory: $ORIGIN"
  [ -L "$ORIGIN" ] && die "source is already a symlink, no migration needed: $ORIGIN"
  [ -e "$SOURCE/$NAME" ] && die "source already has same name, resolve manually first: $SOURCE/$NAME"
  if [ -e "$OTHER" ] && [ ! -L "$OTHER" ]; then
    die "other end has a same-name real dir (diff & merge to a superset first): $OTHER"
  fi
  mv "$ORIGIN" "$SOURCE/$NAME"
  echo "MOVED $ORIGIN -> $SOURCE/$NAME"
elif [ "$MODE" = "link" ]; then
  [ -d "$SOURCE/$NAME" ] || die "source has no such skill: $SOURCE/$NAME"
else
  die "second argument must be claude|codex|link"
fi

[ -d "$SOURCE/$NAME/SKILL.md" ] && die "SKILL.md inside source $NAME is a directory, structural anomaly"
[ -f "$SOURCE/$NAME/SKILL.md" ] || die "source $NAME is missing SKILL.md, refusing to link"

# Record origin: decides which end release returns it to
origin_file="$SOURCE/$NAME/.sync-origin"
if [ -n "$ORIGIN_OPT" ]; then
  echo "$ORIGIN_OPT" > "$origin_file"; echo "ORIGIN $NAME = $ORIGIN_OPT (explicit)"
elif [ "$MODE" = "claude" ] || [ "$MODE" = "codex" ]; then
  echo "$MODE" > "$origin_file"; echo "ORIGIN $NAME = $MODE (source end)"
elif [ ! -f "$origin_file" ]; then
  echo "NOTE $NAME has no origin marked (link without --origin; release treats it as both ends)"
fi

# Only link ends that exist; skip absent ends (single-host env)
linked=()
for side in claude codex; do
  if [ "$side" = claude ]; then dir="$CC"; ok="$CC_OK"; else dir="$CX"; ok="$CX_OK"; fi
  if [ "$ok" != 1 ]; then echo "SKIP $side end not installed ($dir does not exist), not linking"; continue; fi
  p="$dir/$NAME"
  if [ -L "$p" ]; then rm "$p"; fi
  if [ -e "$p" ]; then die "real file still at target, refusing to overwrite: $p"; fi
  ln -s "$SOURCE/$NAME" "$p"
  linked+=("$p")
done

# inode verify: with multiple ends check all-equal; single end just confirm created
if [ "${#linked[@]}" -ge 2 ]; then
  base=$(ls -idL "${linked[0]}" | awk '{print $1}')
  for p in "${linked[@]:1}"; do
    cur=$(ls -idL "$p" | awk '{print $1}')
    [ "$cur" = "$base" ] || die "inode mismatch: ${linked[0]}=$base $p=$cur"
  done
  echo "OK $NAME inode=$base same dir on all ends (${#linked[@]} ends)"
elif [ "${#linked[@]}" = 1 ]; then
  base=$(ls -idL "${linked[0]}" | awk '{print $1}')
  echo "OK $NAME inode=$base linked (single end: ${linked[0]})"
else
  die "no end available to link"
fi
