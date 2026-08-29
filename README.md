# deej-stack

My personal Claude Code skills and automations. I kept typing the same planning and review prompts into every project; this is where they live now, as a plugin, so one `/plan` does what used to take a paragraph.

Modelled on [cursor's pstack](https://github.com/cursor/plugins/tree/main/pstack): a manifest, a `skills/` directory of `SKILL.md` workflows, and `references/` files that get handed to sub-agents verbatim.

## Install

From a checkout, for daily use:

```
/plugin marketplace add /path/to/deej-stack
/plugin install deej-stack
```

To try it without installing:

```bash
claude --plugin-dir /path/to/deej-stack
```

Skills are namespaced under the plugin: `/deej-stack:plan`.

## Skills

| skill | use it when |
|---|---|
| [`/deej-stack:plan`](./skills/plan/SKILL.md) | you're about to build a feature, an app, or a change that's more than a one-file edit, and you want the plan stress-tested before any code exists. |

### `/plan`

```
/deej-stack:plan add magic-link login to the dashboard, keep the existing session cookie
```

The main agent orchestrates; a panel of Opus sub-agents does the lens work, in two waves:

1. **Analyse.** `architect` drafts the plan (caller's usage first, then data shapes, module map, sequenced steps). `reuse-scout` inventories what already exists so nothing gets written twice. `security-analyst` threat-models the change into concrete requirements. Situational members (`data-analyst`, `ux-api-designer`, `ops-analyst`, `perf-analyst`) join when the change touches their area.
2. **Review.** The orchestrator merges wave 1 into draft v1, then a fresh `code-reviewer` and `skeptic` attack it while the wave-1 members are resumed to check their own requirements landed.

The orchestrator integrates every finding (or records why it was rejected), runs a completeness audit, and delivers one plan: in plan mode it's the plan file, otherwise `docs/plans/<date>-<slug>.md`. Roster, prompt template, and plan shape are in [`skills/plan/references/`](./skills/plan/references/).

## Layout

```
.claude-plugin/plugin.json   manifest (skills/ and agents/ are auto-discovered)
skills/<name>/SKILL.md       the workflow
skills/<name>/references/    what sub-agents receive verbatim
agents/                      reusable sub-agent definitions (none yet)
```

`CLAUDE.md` has the conventions for adding a skill.
