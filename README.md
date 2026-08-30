# deej-stack

My personal agent skills and automations, for Claude Code and Cursor. I kept typing the same planning and review prompts into every project; this is where they live now, as a plugin, so one `/d-plan` does what used to take a paragraph.

Modelled on [cursor's pstack](https://github.com/cursor/plugins/tree/main/pstack) by Poteto: a manifest, a `skills/` directory of `SKILL.md` workflows, and `references/` files that get handed to sub-agents verbatim.

## Install

The repo is its own marketplace, so both harnesses install straight from GitHub. A local checkout also loads in both if you want to edit the skills.

**Claude Code**

```bash
claude plugin marketplace add danjonesio/deej-stack
claude plugin install deej-stack@deej-stack
```

Both commands default to `--scope user`, so the plugin is available in every project. To enable it for one repo instead, add `--scope project` to both (writes to that repo's `.claude/settings.json`, so it travels with the repo) or `--scope local` (gitignored `.claude/settings.local.json`).

Then `/reload-plugins` in an open session, or start a new one. Skills are namespaced: `/deej-stack:d-plan`. The same two steps are available in-session via `/plugin` (Marketplaces tab, then Discover).

**Updating**

```bash
claude plugin marketplace update deej-stack
claude plugin update deej-stack@deej-stack
```

Both lines are needed: `plugin update` reads the local marketplace clone and does not refresh it. Then `/reload-plugins` or a new session. To skip this in future, `/plugin` → **Marketplaces** → `deej-stack` → **Enable auto-update** (off by default for non-Anthropic marketplaces). Either way the install is a snapshot keyed by `version` in `.claude-plugin/plugin.json`, so a push without a version bump does not reach installed copies.

To work from a checkout instead, `claude --plugin-dir /path/to/deej-stack` loads it for that session with nothing cached.

**Cursor**

Open **Customize** from the sidebar, then **Add Marketplace → Import from GitHub**, paste `https://github.com/danjonesio/deej-stack`, and press **Add** on the `deej-stack` card. Skills run unprefixed: `/d-plan`.

To work from a checkout instead:

```bash
ln -s /path/to/deej-stack ~/.cursor/plugins/local/deej-stack
```

then **Developer: Reload Window**. A marketplace install of the same name takes precedence over the local copy, so keep one or the other.

**Updating**: a personal GitHub import is pinned to the commit Cursor saw when you imported it; Uninstall + Add, Update, and Reinstall all put that same commit back (Cursor staff on the forum, no fix as of August 2026). To move to the current commit: Customize → Browse → the **Danjonesio Deej Stack** heading → **⋯ → Remove**, then **Add Marketplace → Import from GitHub** again and **Add** the plugin. Same with the Cursor CLI: `agent plugin marketplace remove <name from agent plugin marketplace list>`, `agent plugin marketplace add https://github.com/danjonesio/deej-stack`, then reinstall from `/plugin`. For a checkout, `git pull` then **Developer: Reload Window**.

## Skills

| skill | use it when |
|---|---|
| [`/d-plan`](./skills/d-plan/SKILL.md) | you're about to build a feature, an app, or a change that's more than a one-file edit, and you want the plan stress-tested before any code exists. |
| [`/d-implement`](./skills/d-implement/SKILL.md) | you have a plan from `/d-plan` and want it built step by step, each step verified and committed, with a review panel on the finished diff. |

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

- **`/d-review`.** The `/d-implement` review panel (`skills/d-implement/references/panel.md` and `review-prompt.md`) run on its own against any diff, branch, or PR, no plan needed. Cursor has no built-in code review, so this is the one that earns its cross-harness keep. Mostly a thin `SKILL.md` pointing at the references that already exist.
- **Saved panel-model default.** Today `/d-plan` takes the model from the prompt or asks once per run. pstack's alternative is a per-user config the skill reads first: `/setup-pstack` writes `~/.cursor/rules/pstack-models.mdc` (`alwaysApply: true`, one `role: model` line each; a list spawns one sub-agent per entry; `inherit-parent` means omit `model`). The equivalent here would be a `plan panel model: <slug>` line in `~/.claude/CLAUDE.md` (Claude Code) and an always-applied rule or `AGENTS.md` line (Cursor), with Phase A checking for it before asking. Prompt still overrides. Add it if the question starts to feel like friction.
