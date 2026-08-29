# deej-stack

My personal agent skills and automations, for Claude Code and Cursor. I kept typing the same planning and review prompts into every project; this is where they live now, as a plugin, so one `/plan` does what used to take a paragraph.

Modelled on [cursor's pstack](https://github.com/cursor/plugins/tree/main/pstack) by Poteto: a manifest, a `skills/` directory of `SKILL.md` workflows, and `references/` files that get handed to sub-agents verbatim.

## Install

The repo is its own marketplace, so both harnesses install straight from GitHub. A local checkout also loads in both if you want to edit the skills.

**Claude Code**

```bash
claude plugin marketplace add danjonesio/deej-stack
claude plugin install deej-stack@deej-stack
```

Then `/reload-plugins` in an open session, or start a new one. Skills are namespaced: `/deej-stack:plan`. The same two steps are available in-session via `/plugin` (Marketplaces tab, then Discover).

Updating: `claude plugin update deej-stack@deej-stack`, or turn it on once with `/plugin` → **Marketplaces** → `deej-stack` → **Enable auto-update** (off by default for non-Anthropic marketplaces). Either way the install is a snapshot keyed by `version` in `.claude-plugin/plugin.json`, so a push without a version bump does not reach installed copies.

To work from a checkout instead, `claude --plugin-dir /path/to/deej-stack` loads it for that session with nothing cached.

**Cursor**

Open **Customize** from the sidebar, then **Add Marketplace → Import from GitHub**, paste `https://github.com/danjonesio/deej-stack`, and press **Add** on the `deej-stack` card. Skills run unprefixed: `/plan`.

To work from a checkout instead:

```bash
ln -s /path/to/deej-stack ~/.cursor/plugins/local/deej-stack
```

then **Developer: Reload Window**. A marketplace install of the same name takes precedence over the local copy, so keep one or the other.

## Skills

| skill | use it when |
|---|---|
| [`/plan`](./skills/plan/SKILL.md) | you're about to build a feature, an app, or a change that's more than a one-file edit, and you want the plan stress-tested before any code exists. |

### `/plan`

```
/plan add magic-link login to the dashboard, keep the existing session cookie
```

Name the panel model in the prompt ("panel on grok", "use opus for the panel"); if you don't, it asks once before spawning anything. The main agent orchestrates; the panel does the lens work, in two waves:

1. **Analyse.** `architect` drafts the plan (caller's usage first, then data shapes, module map, sequenced steps). `reuse-scout` inventories what already exists so nothing gets written twice. `security-analyst` threat-models the change into concrete requirements. Situational members (`data-analyst`, `ux-api-designer`, `ops-analyst`, `perf-analyst`) join when the change touches their area.
2. **Review.** The orchestrator merges wave 1 into draft v1, then a fresh `code-reviewer` and `skeptic` attack it while the wave-1 members are resumed to check their own requirements landed.

The orchestrator integrates every finding (or records why it was rejected), runs a completeness audit, and delivers one plan: in plan mode it's the plan file, otherwise `docs/plans/<date>-<slug>.md`. The skill carries a harness table so the same phases run on Claude Code's `Agent` tool and Cursor's `Task` tool. Roster, prompt template, and plan shape are in [`skills/plan/references/`](./skills/plan/references/).

## Layout

```
.claude-plugin/              Claude Code manifest + marketplace.json
.cursor-plugin/plugin.json   Cursor manifest
skills/<name>/SKILL.md       the workflow (same files for both harnesses)
skills/<name>/references/    what sub-agents receive verbatim
agents/                      reusable sub-agent definitions (none yet)
AGENTS.md                    conventions; CLAUDE.md imports it
```

## Later

Ideas not built yet, kept here so they don't need re-deriving.

- **Saved panel-model default.** Today `/plan` takes the model from the prompt or asks once per run. pstack's alternative is a per-user config the skill reads first: `/setup-pstack` writes `~/.cursor/rules/pstack-models.mdc` (`alwaysApply: true`, one `role: model` line each; a list spawns one sub-agent per entry; `inherit-parent` means omit `model`). The equivalent here would be a `plan panel model: <slug>` line in `~/.claude/CLAUDE.md` (Claude Code) and an always-applied rule or `AGENTS.md` line (Cursor), with Phase A checking for it before asking. Prompt still overrides. Add it if the question starts to feel like friction.
