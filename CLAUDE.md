# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Claude Code plugin holding Dan's personal skills and automations, modelled on cursor's `pstack`. There is no application code: the product is the prose in `skills/*/SKILL.md` and the reference files those skills hand to sub-agents. Agent-facing prose has a higher bar than human prose; an unhelpful sentence becomes an instruction.

## Commands

There is no build or test suite. Validate and try the plugin with:

```bash
claude plugin validate .            # manifest + skill/agent frontmatter checks
claude --plugin-dir .               # run a session with this plugin loaded from the working tree
```

Installed as a plugin, skills are namespaced: `/deej-stack:plan`. Agents (when added under `agents/`) appear as `subagent_type: "deej-stack:<name>"`. A skill symlinked into `~/.claude/skills/<name>` is invoked unnamespaced as `/<name>` instead.

Local install for daily use: `/plugin marketplace add /home/danjones/other/deej-stack` then `/plugin install deej-stack`.

## Layout

- `.claude-plugin/plugin.json`: manifest. `skills/` and `agents/` are auto-discovered; do not list them in the manifest.
- `skills/<name>/SKILL.md`: the workflow (phases, rules, delivery). Frontmatter `name` and `description` are required.
- `skills/<name>/references/`: anything a skill passes verbatim to a sub-agent (rosters, prompt templates, output templates, rubrics). SKILL.md points at these by path and never restates them.
- `agents/<name>.md`: reusable sub-agent definitions. None yet; today skills spawn `general-purpose` agents with inline prompts built from `references/`.

## How the multi-agent skills are built

`skills/plan` is the pattern the rest will follow:

- The main agent is the orchestrator and final reviewer. It frames, grounds, synthesises, and audits; it never does the lens work itself and never writes code.
- Panel members are spawned with the Agent tool, `subagent_type: "general-purpose"`, `model: "opus"`, and a `name` from the roster in `references/panel.md`. All members of a wave go out in one message so they run concurrently. Wave 2 resumes wave-1 members with `SendMessage` by name rather than spawning fresh, so they keep the codebase context they built.
- Every member prompt comes from `references/reviewer-prompt.md` with placeholders filled; members are read-only and return the fixed output shape in that file.
- The deliverable shape and the orchestrator's completeness audit live in `references/plan-template.md`. A skill does not deliver with a failing audit line.
- Skills that spawn a panel set `disable-model-invocation: true`: they cost several Opus runs, so only the user starts them.

## Adding a skill

1. `skills/<name>/SKILL.md` with `name`, `description`, and `argument-hint` in frontmatter. `$ARGUMENTS` substitutes in the body; reference files by `${CLAUDE_SKILL_DIR}/references/<file>`.
2. Put everything a sub-agent receives verbatim under `references/`.
3. `claude plugin validate .` and a run with `claude --plugin-dir .`.
4. Add a row to the skills table in `README.md`.

## Prose rules for skills

- Tell the agent to do the thing; explain only when the rule is confusing without a reason.
- Every sentence must change a decision. When in doubt, delete.
- Point at structural sources (paths, templates, config) rather than hardcoding details that go stale.
- Delegate to other skills or reference files by path; do not restate them.
