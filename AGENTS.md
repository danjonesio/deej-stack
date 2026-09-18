# deej-stack

Dan's personal agent skills and automations, packaged as a plugin that loads in both Claude Code and Cursor. Modelled on cursor's `pstack`. There is no application code beyond a few scripts (`d-github`'s fact sheet and git hooks, the agent hooks): the product is the prose in `skills/*/SKILL.md` and the reference files those skills hand to sub-agents. Agent-facing prose has a higher bar than human prose; an unhelpful sentence becomes an instruction.

## Two harnesses, one repo

| | Claude Code | Cursor |
|---|---|---|
| Manifest | `.claude-plugin/plugin.json` (+ `marketplace.json` so the repo installs as its own marketplace) | `.cursor-plugin/plugin.json` |
| Skills | `skills/<name>/SKILL.md`, auto-discovered | same directory, auto-discovered |
| Agents | `agents/<name>.md`, auto-discovered | same directory, auto-discovered |
| Hooks | `hooks/hooks.json`, auto-discovered | `hooks/hooks-cursor.json`, named by `"hooks"` in the manifest, which switches off Cursor's own discovery of `hooks/hooks.json` |
| Skill invocation | `/deej-stack:d-plan` | `/d-plan` |
| Project instructions | `CLAUDE.md` (imports this file) | this file |
| Load from the working tree | `claude --plugin-dir .` | symlink at `~/.cursor/plugins/local/deej-stack`, then **Developer: Reload Window** |
| Install from GitHub | `claude plugin marketplace add danjonesio/deej-stack` then `claude plugin install deej-stack@deej-stack`; `/reload-plugins` or a new session | **Customize → Add Marketplace → Import from GitHub** with the repo URL, then **Add** on the plugin card |
| Update an install | snapshot keyed by `version` in `.claude-plugin/plugin.json`: bump it, then `claude plugin marketplace update deej-stack` and `claude plugin update deej-stack@deej-stack` (the second does not refresh the clone) | a GitHub import is pinned to its import-time commit: remove the marketplace and import it again (Uninstall + Add keeps the old commit); a marketplace install shadows a `plugins/local` copy of the same name |
| Validate | `claude plugin validate .` | open **Customize → Skills** and confirm `d-plan` is listed |

Skills and agents are the same files for both. Only the manifests and the project-instruction file differ. Hooks share their scripts and differ in the wiring file, because the two harnesses disagree on event names and on the JSON a hook prints.

## Layout

- `.claude-plugin/`, `.cursor-plugin/`: manifests. Both auto-discover `skills/` and `agents/`; do not list components in them. The one exception is `"hooks"` in the Cursor manifest.
- `skills/<name>/SKILL.md`: the workflow (phases, rules, delivery). Frontmatter `name` and `description` are required; `name` must match the folder.
- `skills/<name>/references/`: anything a skill passes verbatim to a sub-agent (rosters, prompt templates, output templates, rubrics), or reads as a standard it applies (`d-github`). SKILL.md points at these by relative path and never restates them.
- `skills/<name>/scripts/`: deterministic helpers a skill runs instead of composing the same commands every time (`d-github/scripts/facts.sh`). A script never writes to the repo or to GitHub; the judgement stays in the prose. One script writes at all, `d-github/scripts/install-git-hooks.sh`, and only to the machine (`~/.config/deej-stack/git-hooks`, global `core.hooksPath`), only after a question. `d-github/scripts/git-hooks/` is what it installs; `test-git-hooks.sh` must pass before a version bump.
- `hooks/`: `hooks.json` (Claude Code wiring), `hooks-cursor.json` (Cursor wiring), one script per concern that both call, and `test.sh` covering every script in both dialects.
- `agents/<name>.md`: reusable sub-agent definitions. None yet; today skills spawn general-purpose agents with inline prompts built from `references/`.

## Writing a skill that works in both

- Frontmatter both harnesses read: `name`, `description`, `disable-model-invocation`. Claude Code also reads `argument-hint`; Cursor ignores it. Do not use fields only one harness understands for anything the skill depends on.
- Reference files by relative path from the skill directory (`references/panel.md`). Never `${CLAUDE_SKILL_DIR}` or another harness variable.
- `$ARGUMENTS` substitutes in Claude Code and is not documented in Cursor. If a skill uses it, add the fallback line `skills/d-plan/SKILL.md` uses so an unsubstituted placeholder does not confuse the agent.
- Any skill that spawns, resumes, or explores carries a **Harness** table with a Claude Code column and a Cursor column, and the phases refer to the table instead of naming tools. `skills/d-plan/SKILL.md` is the template: Claude Code spawns with the `Agent` tool (`general-purpose`, `name`) and resumes with `SendMessage`; Cursor spawns with the `Task` tool (`generalPurpose`, `readonly: true`, `run_in_background: true`) and resumes by agent ID. Plan mode is a tool in Claude Code (`EnterPlanMode` / `ExitPlanMode`) and a user-chosen mode in Cursor (Shift+Tab); a skill must work without it.
- Never hardcode a sub-agent model or effort. The user names it in the prompt, or the skill asks once with the question tool before spawning; "same as this session" means omit `model`. Dan runs different models in each harness, and a skill must not assume either.
- Skills that spawn a panel set `disable-model-invocation: true`: they cost several model runs, so only the user starts them. A single-agent skill whose value is noticing something unprompted (`d-github` on a repo with no Dependabot config) leaves it off and puts the trigger in `description`.
- When `agents/` gets its first file, write the union of both frontmatter sets: `name`, `description`, `model` are shared; Claude Code adds `tools`; Cursor adds `readonly` and `is_background`. Cursor wants full model slugs; Claude Code accepts aliases like `opus`.

## How the multi-agent skills are built

`skills/d-plan` is the pattern the rest follow:

- The main agent is the orchestrator and final reviewer. It frames, grounds, synthesises, and audits; it never does the lens work itself and never writes code.
- Panel members are sub-agents on the user-chosen panel model, named from the roster in `references/panel.md`. All members of a wave go out in one message so they run concurrently. Wave 2 resumes wave-1 members rather than spawning fresh, so they keep the codebase context they built.
- Every member prompt comes from `references/reviewer-prompt.md` with placeholders filled; members are read-only and return the fixed output shape in that file.
- The deliverable shape and the orchestrator's completeness audit live in `references/plan-template.md`. A skill does not deliver with a failing audit line.

`skills/d-implement` consumes `/d-plan`'s deliverable and flips the roles: the main agent writes the code and commits one plan step at a time behind that step's Verify line; the panel runs once, at the end, read-only, against the diff, with its own roster and prompt under `skills/d-implement/references/`. It refers to plan sections by name, so a renamed heading in `plan-template.md` is a change to both skills.

## How the standards skill is built

`skills/d-github` is a single agent, no panel: it reads the repo, decides, writes a file, and explains the decision in that file's header. Its SKILL.md holds a table of standards; each standard is one file under `references/` with four fixed sections (**Applies when**, **Facts**, **Rules**, **Output**) that the phases refer to by name. Facts are commands and paths, never inference, and `scripts/facts.sh` runs all of them in one read-only pass so every run sees the same sheet; a new standard's facts are added to the script and documented in the reference; anything the rules cannot settle from facts is a question with a default; anything that changes repository settings is always a question. Each reference carries the vendor config keys it may use, verified against the docs on a stated date, because one unverified key invalidates the whole file. A standard whose real output is a repository setting (the ruleset) still writes a file to the tree as the record and makes applying it a question, so the setting is recreatable from the repo and never changed on a default.

Adding a standard: one reference file in that shape, one row in the SKILL.md table, and a check that the `description` still names the trigger for it. `hooks/d-github-offer.sh` makes it fire on entering a repo, so a standard that adds a missing-file trigger adds the same check there, with a case in `hooks/test.sh`; the description makes it fire mid-task.

## Hooks

These are agent-harness hooks. A guard that must hold whoever runs the command (you, an agent, an IDE) is a git hook instead: see `skills/d-github/scripts/git-hooks/`.

A hook is for what prose cannot guarantee: a check that must run in every project at session start, or an action that must never happen. Anything that needs judgement stays a skill. Build and prove a hook in Claude Code first, then add the Cursor wiring.

| | Claude Code | Cursor |
|---|---|---|
| Wiring | `hooks/hooks.json`; command paths through `${CLAUDE_PLUGIN_ROOT}`, because an install runs from the plugin cache | `hooks/hooks-cursor.json` (`"version": 1`); command paths relative to the plugin root (`./hooks/…`) |
| Session start | `SessionStart`, matcher on the source (`startup`); plain stdout becomes context | `sessionStart`, fire-and-forget; stdout must be `{"additional_context": "…"}` |
| Before a shell command | `PreToolUse` with matcher `Bash`; the command is `tool_input.command` | `beforeShellExecution`; the command is top-level `command`, and `matcher` is a regex on the command text, so the script only spawns when it can matter |
| Deny | `hookSpecificOutput.permissionDecision: "deny"` + `permissionDecisionReason` | `permission: "deny"` + `agent_message` (to the agent) + `user_message` (to Dan) |
| Allow | print nothing | print nothing. Never print `permission: "allow"`: Cursor merges hook answers into its own approval flow, and nothing documents that an explicit allow leaves the user's prompt in place |
| Project directory | `CLAUDE_PROJECT_DIR`, `cwd` on stdin | `CLAUDE_PROJECT_DIR` (alias, always set), `workspace_roots` on stdin |
| Which harness is calling | no `cursor_version` on stdin | `cursor_version` on stdin. Never decide from environment variables: Claude Code started in Cursor's terminal inherits Cursor's |
| Skill name in hook text | `/deej-stack:d-github` | `/d-github` |

Keys verified on 2026-09-18 against code.claude.com/docs/en/hooks and cursor.com/docs/hooks + cursor.com/docs/reference/plugins. The Claude Code column is also proven by a live run; the Cursor column is proven only by `hooks/test.sh` feeding the documented input, until someone watches it fire in Customize → Hooks.

- Scripts are read-only, print nothing when they have nothing to say, and fail open: a hook that errors or cannot parse its input exits 0 with no output, so a bug here never blocks work in another repo. Stay local; a network call needs a timeout and an answer it may not get, which is an unknown, never a "yes".
- Text a hook hands the agent is agent-facing prose and held to the prose rules below. A deny says what to do instead.
- State a hook must remember lives in the clone's git config under `deej-stack.*`, not in the tree.
- A Claude Code `PreToolUse` hook on `Bash` runs before every shell command in every project. Exit before any parsing when the command cannot be relevant.
- Every behaviour is a case in `hooks/test.sh`, in both dialects, which must pass before a version bump. Then load the tree with `claude --plugin-dir .` and watch it fire: `claude -p … --output-format stream-json --verbose --include-hook-events` prints each hook's stdout and exit code.

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
