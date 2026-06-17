# Host-binding judgment knowledge base

Judging whether a skill can be shared across Claude Code / Codex. Core principle: **signal ≠ verdict** — scanning finds signals, the review draws the conclusion.

## 1. Three kinds of signal scan

### Signal 1: host-specific frontmatter fields

Read the YAML header of SKILL.md. Beyond `name`, `description`, `license`, most fields are Claude-Code-specific:

| Field | Meaning | Consequence on the Codex end |
|---|---|---|
| `disable-model-invocation: true` | user-trigger only | ignored → Codex may auto-trigger (**behavior degradation**, restorable via openai.yaml, see below) |
| `argument-hint` | input hint text | ignored → pure cosmetic loss |
| `allowed-tools` | restrict available tools | ignored → **permission constraint lost**; if the skill relies on it for safety, share with care |
| `context: fork` | run in an isolated context | ignored → behavior difference, needs evaluation |
| `mode` / `model` | mode/model selection | ignored → behavior difference |

### Signal 2: mechanism words in the body

grep the SKILL.md body (and references), case-insensitive:

```
subagent|sub-agent|Task tool|allowed-tools|context: ?fork|CLAUDE\.md|AGENTS\.md|\.claude/|\.codex/|hooks?|worktree|MCP|\$ARGUMENTS|slash|slash command|plugin
```

A hit ≠ a binding. **You must re-read the sentence's context**: talking about "the object to operate on" (e.g. teaching the user to edit an Obsidian plugin) is a false positive; commanding a host mechanism (e.g. "dispatch a subagent", "read CLAUDE.md") is a real binding. Note that `Global Mode` will falsely match `Glob`, and "plugin" in content is often the teaching subject.

### Signal 3: name-clash check

- Clash with a Codex builtin: `ls ~/.codex/skills/.system/` (includes skill-creator, plan, etc.). Clash → keep single-host.
- Clash with an existing same-name real dir on the other end: needs a diff & merge, can't overwrite directly.

## 2. Review: broken vs degraded

After a signal hit, ask three things in order:

1. **Author intent**: does the README/repo declare cross-host usability (e.g. "works with any model")?
2. **Does the body actually use the host-specific mechanism**: or does only the frontmatter carry the specific field while the body is generic?
3. **After the field is ignored, is it "broken" or "degraded"**:
   - broken (core function depends on that mechanism, e.g. the body orchestrates subagents) → keep single-host
   - degraded (only loses a trigger restriction/appearance) → shareable, propose adding host config

Conclusion is one of three: **share / share + add host config / keep single-host**, each with a reason, the user's call.

## 3. Same name on both ends: the superset rule

1. `diff -rq A B -x .DS_Store` to see the differences first
2. Only one side has extra files (common: Codex has the extra `agents/openai.yaml`, or extra `references/`, `assets/`) → take the larger one (the superset) as the body
3. **The SKILL.md body itself differs** → stop, show the diff to the user to decide (each side may have its own edits, needs manual merge into a superset)
4. The source always stores the superset: host-specific files travel with the body, and each end picks up what it needs

## 4. openai.yaml fill-in template

The Codex-end equivalent restoration of Claude-specific fields, written into `<skill>/agents/openai.yaml`:

```yaml
interface:
  display_name: "<display name>"
  short_description: "<one-line description>"
  default_prompt: "Use $<skill-name> …"

policy:
  allow_implicit_invocation: false   # equivalent of disable-model-invocation: true
```

Mapping: `disable-model-invocation: true` ↔ `policy.allow_implicit_invocation: false` (Codex no longer triggers implicitly; explicit `$skill-name` invocation still works).

## 5. Cost awareness of sharing

- Each skill's name+description sits in both ends' startup context (each about 60~130 tokens)
- **The Codex skill list has a capacity cap** (about 2% of context, or 8000 characters); over it, descriptions get compressed or some skills are silently omitted
- So: beyond "can it be shared" also ask "**will it be used on both ends**". Keeping a skill used on only one end as single-host is a reasonable choice, not laziness.

## 6. Fixed exclusion list

| Type | How to identify | Handling |
|---|---|---|
| Claude plugin skill | located under `~/.claude/plugins/cache/...`, path is versioned | don't symlink (an update breaks the link); the source is its GitHub repo. Report only. |
| Codex builtin | `~/.codex/skills/.system/` | never touch |
| Clashes with a builtin name | a custom skill with the same name as one in `.system` | keep single-host |

> For skills above that are bound to stay single-host, record the name in `~/.skill-source-ignore` (one per line, template: [single-host.example](single-host.example)). `scan.sh` folds them out of "adoption candidates" into a single `CANDIDATE_IGNORED` line, so reconcile is no longer spammed by fixed noise. The list lives in your home dir, does not travel with the repo, and won't leak private skill names into a public repo.
