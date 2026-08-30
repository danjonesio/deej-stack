# deej-stack

Dan's personal agent skills and automations, packaged as a plugin that loads in both Claude Code and Cursor. Modelled on cursor's `pstack`. There is no application code: the product is the prose in `skills/*/SKILL.md` and the reference files those skills hand to sub-agents. Agent-facing prose has a higher bar than human prose; an unhelpful sentence becomes an instruction.

## Two harnesses, one repo

| | Claude Code | Cursor |
|---|---|---|
| Manifest | `.claude-plugin/plugin.json` (+ `marketplace.json` so the repo installs as its own marketplace) | `.cursor-plugin/plugin.json` |
| Skills | `skills/<name>/SKILL.md`, auto-discovered | same directory, auto-discovered |
| Agents | `agents/<name>.md`, auto-discovered | same directory, auto-discovered |
| Skill invocation | `/deej-stack:d-plan` | `/d-plan` |
| Project instructions | `CLAUDE.md` (imports this file) | this file |
| Load from the working tree | `claude --plugin-dir .` | symlink at `~/.cursor/plugins/local/deej-stack`, then **Developer: Reload Window** |
| Install from GitHub | `claude plugin marketplace add danjonesio/deej-stack` then `claude plugin install deej-stack@deej-stack`; `/reload-plugins` or a new session | **Customize → Add Marketplace → Import from GitHub** with the repo URL, then **Add** on the plugin card |
| Update an install | snapshot keyed by `version` in `.claude-plugin/plugin.json`: bump it, then `claude plugin marketplace update deej-stack` and `claude plugin update deej-stack@deej-stack` (the second does not refresh the clone) | a GitHub import is pinned to its import-time commit: remove the marketplace and import it again (Uninstall + Add keeps the old commit); a marketplace install shadows a `plugins/local` copy of the same name |
| Validate | `claude plugin validate .` | open **Customize → Skills** and confirm `d-plan` is listed |

Skills and agents are the same files for both. Only the manifests and the project-instruction file differ.

## Layout

- `.claude-plugin/`, `.cursor-plugin/`: manifests. Both auto-discover `skills/` and `agents/`; do not list components in them.
- `skills/<name>/SKILL.md`: the workflow (phases, rules, delivery). Frontmatter `name` and `description` are required; `name` must match the folder.
- `skills/<name>/references/`: anything a skill passes verbatim to a sub-agent (rosters, prompt templates, output templates, rubrics). SKILL.md points at these by relative path and never restates them.
- `agents/<name>.md`: reusable sub-agent definitions. None yet; today skills spawn general-purpose agents with inline prompts built from `references/`.

## Writing a skill that works in both

- Frontmatter both harnesses read: `name`, `description`, `disable-model-invocation`. Claude Code also reads `argument-hint`; Cursor ignores it. Do not use fields only one harness understands for anything the skill depends on.
- Reference files by relative path from the skill directory (`references/panel.md`). Never `${CLAUDE_SKILL_DIR}` or another harness variable.
- `$ARGUMENTS` substitutes in Claude Code and is not documented in Cursor. If a skill uses it, add the fallback line `skills/d-plan/SKILL.md` uses so an unsubstituted placeholder does not confuse the agent.
- Any skill that spawns, resumes, or explores carries a **Harness** table with a Claude Code column and a Cursor column, and the phases refer to the table instead of naming tools. `skills/d-plan/SKILL.md` is the template: Claude Code spawns with the `Agent` tool (`general-purpose`, `name`) and resumes with `SendMessage`; Cursor spawns with the `Task` tool (`generalPurpose`, `readonly: true`, `run_in_background: true`) and resumes by agent ID. Plan mode is a tool in Claude Code (`EnterPlanMode` / `ExitPlanMode`) and a user-chosen mode in Cursor (Shift+Tab); a skill must work without it.
- Never hardcode a sub-agent model or effort. The user names it in the prompt, or the skill asks once with the question tool before spawning; "same as this session" means omit `model`. Dan runs different models in each harness, and a skill must not assume either.
- Skills that spawn a panel set `disable-model-invocation: true`: they cost several model runs, so only the user starts them.
- When `agents/` gets its first file, write the union of both frontmatter sets: `name`, `description`, `model` are shared; Claude Code adds `tools`; Cursor adds `readonly` and `is_background`. Cursor wants full model slugs; Claude Code accepts aliases like `opus`.

## How the multi-agent skills are built

`skills/d-plan` is the pattern the rest follow:

- The main agent is the orchestrator and final reviewer. It frames, grounds, synthesises, and audits; it never does the lens work itself and never writes code.
- Panel members are sub-agents on the user-chosen panel model, named from the roster in `references/panel.md`. All members of a wave go out in one message so they run concurrently. Wave 2 resumes wave-1 members rather than spawning fresh, so they keep the codebase context they built.
- Every member prompt comes from `references/reviewer-prompt.md` with placeholders filled; members are read-only and return the fixed output shape in that file.
- The deliverable shape and the orchestrator's completeness audit live in `references/plan-template.md`. A skill does not deliver with a failing audit line.

`skills/d-implement` consumes `/d-plan`'s deliverable and flips the roles: the main agent writes the code and commits one plan step at a time behind that step's Verify line; the panel runs once, at the end, read-only, against the diff, with its own roster and prompt under `skills/d-implement/references/`. It refers to plan sections by name, so a renamed heading in `plan-template.md` is a change to both skills.

## Adding a skill

1. `skills/d-<name>/SKILL.md` with `name`, `description`, `disable-model-invocation` (if it spawns a panel), and `argument-hint`. The `d-` prefix is the namespace: Cursor runs skills unprefixed, so a bare `plan` or `review` collides with any other plugin's.
2. Put everything a sub-agent receives verbatim under `references/`.
3. `claude plugin validate .`, then a run in each harness: `claude --plugin-dir .` and a Cursor reload.
4. Add a row to the skills table in `README.md`.
5. Bump `version` in both `plugin.json` files together. Claude Code installs only refresh when it changes.

## Prose rules for skills

- Tell the agent to do the thing; explain only when the rule is confusing without a reason.
- Every sentence must change a decision. When in doubt, delete.
- Point at structural sources (paths, templates, config) rather than hardcoding details that go stale.
- Delegate to other skills or reference files by path; do not restate them.
