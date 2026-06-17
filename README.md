# sync-skills

A tool for managing skills across hosts (Claude Code / Codex): **one source-of-truth + symlinks + a pointer + reconcile**. Edit one place, both ends take effect at once — because there is no second copy.

## Core model

There is only one real body, living in the **source** directory; each end (Claude and Codex) holds only a **symlink** (a pointer).

```
   source (the body, the only copy, can move house)
        ▲
   pointer ~/.skill-source        ← moving house only changes this one link
        ▲
   ┌────┴────┐   each end's symlink "routes through the pointer", never directly at the source's absolute path
 Claude     Codex
  symlink     symlink
```

**There is no "sync" action, because there is no second copy.** Single-host (only Claude or only Codex installed) works as usual too.

## Install

```bash
# One-click download + install (source defaults to ~/skill-source)
git clone https://github.com/Tasihi89/sync-skills.git && bash sync-skills/install.sh

# Or a custom source location (ASCII, no spaces):
git clone https://github.com/Tasihi89/sync-skills.git && bash sync-skills/install.sh --source ~/my-skills
```

`install.sh` will: create the source + pointer → adopt sync-skills itself into management → build both ends' symlinks.
After installing, **restart Claude Code / Codex**, then tell Claude `/sync-skills` to bring your other existing skills under management too.

## Usage (7 scenarios)

| Scenario | How |
|---|---|
| **Inspect** (reconcile) | `bash scripts/scan.sh` — read-only; see consistency / adoption candidates / anomalies |
| **Add** (adopt) | `bash scripts/migrate.sh <name> <claude\|codex>` |
| **Delete** | `bash scripts/remove.sh <name> <all\|claude\|codex> --confirm` |
| **Release** (un-manage) | `bash scripts/release.sh <name> --confirm` |
| **Move house** | `mv old new && rm ~/.skill-source && ln -s new ~/.skill-source` |

> All write operations **default to dry-run** (print the plan only); add `--confirm` to actually run; deleting a real dir also needs `--force-real`. For the full flow (init/modify/judgment) see [SKILL.md](SKILL.md).

## Dependencies

- **Required**: bash, standard commands (`ln` / `mv` / `cp` / `find` / `readlink`)
- **Optional**: `python3` + `pyyaml` (validate frontmatter during reconcile; skipped automatically if absent); `sqlite3` (inspect the Codex rejection log)

## Layout

```
sync-skills/
├── SKILL.md                 instructions for the agent (core model + 7 scenarios)
├── install.sh               one-click install + bootstrap
├── scripts/                 scan / migrate / remove / release
├── references/              judgment.md (shareability judgment) + ignore-list template
└── agents/openai.yaml       Codex-end config
```

## Advanced

- **Folding single-host noise**: record the names of skills permanently used on only one end in `~/.skill-source-ignore` (template: [references/single-host.example](references/single-host.example)); reconcile folds them into a single line instead of spamming. This list lives in your home dir and does not travel with the repo.
- **Judging cross-host shareability**: see [references/judgment.md](references/judgment.md).
