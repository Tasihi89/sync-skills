---
name: sync-skills
description: "Install, adopt, remove, release, and centrally manage skills across Claude Code and Codex: a single source-of-truth (skill-source) + symlinks + a pointer + status reconcile. Whenever the user installs/downloads/creates/deletes/uninstalls/releases ANY skill, or wants to batch-unify existing skills, this skill must take over the whole flow (do it well first, then reconcile). Triggers: 'install skill', 'download skill', 'delete skill', 'uninstall/remove skill', 'release/unshare', 'sync/unify skills', 'skill drift', 'broken link', 'skills differ across ends', 'init skill management', or /sync-skills."
---

# sync-skills: cross-host skill management

## Core model

There is only one real body, living in the **source** directory; each end's skills dir (Claude and Codex) holds only a **symlink** (a pointer).

```
   source (the body, the only copy, can move house)
        ▲
   pointer ~/.skill-source        ← moving house only changes this one link
        ▲
   ┌────┴────┐   each end's symlink "routes through the pointer", never directly at the source's absolute path
 Claude     Codex
  symlink     symlink
```

Edit the source = both ends take effect at once. **There is no "sync" action, because there is no second copy.**
`SKILL.md` is a cross-agent open standard: the body is universal, while host-specific config (`agents/openai.yaml`, Claude-only frontmatter fields) is picked up by each end as needed, without interfering with the other.
**Single-host works too**: if only Claude or only Codex is installed, this skill and its scripts work as usual; the absent end is skipped automatically.

---

## Common mechanisms (shared by all 7 scenarios; not repeated within each)

> **Script invocation convention**: every script in this skill is run with `bash <skill-root>/scripts/xxx.sh`, with no dependence on the executable bit (`<skill-root>` = this skill's base directory).

### Reconcile scan (read-only, do anytime)
`scripts/scan.sh` (reads the `~/.skill-source` pointer by default) prints five sections: source inventory / each end's status / adoption candidates / structural anomalies / plugins & builtins. **It reports facts only — no judgment, no file changes.** Key signals:

| Signal | Meaning |
|---|---|
| `LINK_OK` / `BROKEN_LINK` / `LINK_ELSEWHERE` | symlink healthy / broken / points to the wrong place |
| `CANDIDATE` | a real dir on some end, not yet in the source (possibly side-loaded, awaiting adoption) |
| `MISSING_LINK` | in the source but missing on some end (**ambiguous**: link to restore, or you already removed that end) |
| `SIDE_ABSENT` | that end is not installed (single-host env) |
| `CANDIDATE_IGNORED` | matched the ignore list; a folded permanent single-host candidate |
| `FRONTMATTER_INVALID` | the SKILL.md YAML is invalid; Codex will silently reject it |

### Guarded writes (shared by migrate / remove / release)
- **Default dry-run**: a write script without `--confirm` only prints the plan and touches nothing; add `--confirm` after you confirm.
- **Real-dir protection**: deleting something that is not a symlink (a body / side-loaded content, gone once deleted) requires an explicit `--force-real`.
- **Land before deleting the body**: release first copies the body out to each end and verifies health, then deletes the source last.
- **inode verification**: after migrate builds the links, it verifies each end points at the same directory.
- Only operates on **ends that exist**; an absent end is skipped automatically.
- **Origin marker**: on adoption, the source end is recorded in `.sync-origin` inside the source; release uses it to **re-attribute** (something from `codex` goes back only to codex, with no leftover copy on the other end).

### The three iron rules
1. Read-only scans anytime; **every write must be the user's call** (item by item, or explicit batch approval).
2. **Frontmatter must be valid YAML**: any value containing a "colon + space" (like `description`) **must be wrapped in double quotes**, or Codex silently rejects it (symlink and name look fine, it just never enters the list and `$name` won't summon it).
3. Moving house only changes the one `~/.skill-source` pointer; **never let an end's symlink point directly at the source's absolute path**.

---

## The 7 scenarios

### 1. Init (first-time enablement / the big cleanup right after install)
**A one-time big cleanup: fully inventory, classify, and batch-adopt the existing skills scattered across the ends. Two entry points both count as init:**
- `NO_SOURCE`: no source yet → first create the source + pointer (step 1).
- **Just ran `install.sh`**: the source is built, but it only contains sync-skills itself; other skills are still scattered across the ends (scan shows a pile of `CANDIDATE`). This is equally an "unreconciled first state".

**On the first invocation, run `scan` first; if it's the first state (a near-empty source + many `CANDIDATE`), proactively open the conversation — don't just dump a candidate list:**
> "I see you have these skills not yet brought in: A, B, C…. Want me to help judge which suit both ends and adopt them one by one?"

Steps:
1. **Locate/create the source** (only when `NO_SOURCE`): ask where to put the source (a short ASCII name, no spaces), echo back to confirm, then `mkdir -p <location> && ln -s <location> ~/.skill-source`; if an old default location (`~/Desktop/skill-source`, `~/skill-source`) already has a source, upgrade it to the pointer scheme. **If installed via install.sh this is already done — skip this step.**
2. **Full inventory**: `scan.sh` to see which `CANDIDATE`s exist on both ends.
3. **Batch classification**: judge each by "can it be shared" → share / share + add host config / keep single-host; record the single-host ones in `~/.skill-source-ignore` (template: `references/single-host.example`).
4. **Batch adoption**: for those judged shareable, `migrate.sh <name> <claude|codex>` adopts + builds each end's symlink.
5. Wrap up: `scan.sh` re-checks, report a results table.

### 2. Add (a new skill day-to-day, once the system is set up)
Signal: a new `CANDIDATE` appears on some end.
1. Install/create it normally on the originating end (Claude: `~/.claude/skills/<name>`; Codex: `~/.codex/skills/<name>`).
2. **Immediately verify the frontmatter is valid** (`description` double-quoted), or Codex rejects it.
3. **Reconcile-adopt**: judge by "can it be shared"; if shareable and no name clash → `migrate.sh <name> <originating-end>` (auto-records **origin** in `.sync-origin` by source end, deciding which end it returns to later; for a body merged from both ends use `--origin both`).
4. **The share confirmation cannot be skipped**: unless the user said "single-host only", you must explicitly ask "Adopt into the source and share on both ends?" — do not just report "adoption candidate" and stop.
5. User only wants it single-host → keep the real dir, record it in the ignore list.

### 3. Delete (take a skill offline — two kinds; ask scope first)
**There are two kinds of delete; by default ask the scope first, and never presume for the user:**
- **Delete one end only**: `remove.sh <name> <claude|codex> --confirm` — the source and the other end stay (= disable single-host).
- **Full delete**: `remove.sh <name> all --confirm` — both ends' symlinks + the source are all deleted; this skill ceases to exist.

Key points:
- User says "delete X" with no scope → **ask first**: "Just one end, or both ends + source, a full delete?"
- Deleting a symlink is safe (the body is in the source); deleting a **real dir** (a side-loaded body, content is lost) makes the script require `--force-real`.
- Default dry-run to see the plan; add `--confirm` after confirming.

### 4. Modify (change content)
One body. **Editing the source takes effect on both ends, with no process needed.** The only "modify" that needs an action is: wanting a skill to behave differently on the two ends → add host-specific config `agents/openai.yaml` (e.g. disable implicit triggering on the Codex end).

### 5. Inspect (reconcile, three intents)
Run `scan.sh` and branch by signal:
- **Check consistency**: `BROKEN_LINK`/`LINK_ELSEWHERE` → broken/mispointed, `migrate.sh <name> link` to restore/re-point.
- **Check new findings**: `CANDIDATE` → a real dir side-loaded (other channels / a terminal / dragged a folder in); ask whether to adopt (go to scenario 2); record permanent single-host ones in the ignore list.
- **Check losses**: `MISSING_LINK` → in source but missing on some end. **Ambiguous**: maybe a link to restore (re-link), maybe you already removed that end (that's the other half of a delete; go to scenario 3). **Ask which it is first; don't blindly re-link.**

Presentation: list each item as a table (signal + suggestion + reason) and wait for the user's call; if there are no differences, report "system is consistent".

### 6. Move house (relocate the source)
Signal `POINTER_BROKEN` (or the user proactively wants to move).
`mv <old-location> <new-location>`, then `rm ~/.skill-source && ln -s <new-location> ~/.skill-source`.
Every end's symlink routes through the pointer, so **not one breaks** — no need to change them one by one.

### 7. Release (un-manage, re-attribute by origin)
Restore a skill from "managed by the source" back to a "standalone real dir", with no loss of content:
`release.sh <name> --confirm` (copies out and verifies first, deletes the source last).
**Origin `.sync-origin` decides which end it returns to:**
- `codex` → back to Codex only; the Claude-end symlink is removed (no leftover copy)
- `claude` → back to Claude only; the Codex-end symlink is removed
- `both` / no marker → keep a standalone copy on each end
- add `--both`: ignore origin, force a copy on both ends (use when you want to keep the current state, not re-attribute)

- Use cases: a skill needs to split across the two ends (unshare); or fully exiting this whole scheme.
- **Full exit / restore**: ask the user which kind of restore first (**default recommendation: "keep as-is"**):
  - **Keep as-is** (default): each skill keeps one copy on each end, no loss of current availability → `release.sh <name> --both` one by one.
  - **Each back home** (by origin): restore to how it was before sharing, codex ones go back to codex → `release.sh <name>` one by one.
  Then handle the pointer by reversing the move-house steps. No one-click batch (too dangerous).
- **Different from delete**: delete means the content is gone; release means the content stays, it's just no longer centrally managed.

---

## Can it be shared (adoption judgment)

An adoption candidate must be judged for cross-host shareability; see [references/judgment.md](references/judgment.md). In one line:
**Signal ≠ verdict** — a scan finds signals (host-specific frontmatter fields / mechanism words in the body / name clashes); the review distinguishes whether it is "broken" (core function depends on a host mechanism → keep single-host) or "degraded" (only loses a trigger restriction/appearance → shareable, propose adding `agents/openai.yaml`).
Conclusion is one of three: **share / share + add host config / keep single-host** (each with a reason, the user's call).
Cost awareness: each shared skill's name+description sits in both ends' startup context, and the Codex list also has a capacity cap — beyond "can it be shared" also ask "will it be used on both ends"; keeping a skill used on only one end as single-host is a reasonable choice.

---

## Boundaries (report only, don't handle)
- **Plugin-type skills** (e.g. Claude marketplace plugins): the source lives in their GitHub repo, the path is versioned, can't be symlink-merged. Report and explain.
- **Builtin skills** (Codex `~/.codex/skills/.system/`): owned by the vendor, never touch.
- **Clashing with a builtin/the other end**: keep single-host, explain why.

The ones bound to be single-host above can be recorded once in `~/.skill-source-ignore` so reconcile stops repeating the prompt.

## Safety iron rules
1. `diff` before merging; if there are differences, stop and hand it to the user.
2. Before any `rm`, confirm the copy you mean to keep is healthy.
3. Read-only scans anytime; **writes must be the user's call**.
4. Destructive ops (delete/release) default to dry-run, `--confirm` only after confirming; deleting a real dir needs `--force-real`.
5. Moving house changes only the one pointer; never bypass the pointer to make a symlink point directly at the source's absolute path.
6. **Frontmatter must be valid YAML**: any value containing a "colon + space" must be double-quoted. Self-check: `scan.sh` reports `FRONTMATTER_INVALID`; or check the Codex log (needs sqlite3):
   ```bash
   sqlite3 ~/.codex/logs_2.sqlite "SELECT feedback_log_body FROM logs WHERE feedback_log_body LIKE '%failed to load skill%' ORDER BY id DESC LIMIT 10;"
   ```
