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
| [`/d-github`](./skills/d-github/SKILL.md) | a repo on GitHub is missing one of the standing standards, or you want what it has checked against them. Today: a Dependabot config (version updates where merges deploy nothing, grouped security-only updates where they do), a default-branch ruleset (PR required, checks up to date, no bypass, no force-push or deletion), and secret protection (GitHub's secret-scanning toggles on; a machine-wide git `pre-push` hook that refuses to push a private hostname to a public remote, reading a pattern list that stays on your machine: never in the tree, CI, or a repository secret; `publish` scans history before a repo goes public). Single agent, no panel; the model may offer it on its own. Standards to come land as rows in its table. |

## Layout

```
.claude-plugin/              Claude Code manifest + marketplace.json
.cursor-plugin/plugin.json   Cursor manifest
skills/<name>/SKILL.md       the workflow (same files for both harnesses)
skills/<name>/references/    what sub-agents receive verbatim, or a standard a skill applies
skills/<name>/scripts/       helpers (d-github's fact sheet, its git hooks and their installer)
hooks/                       hooks.json (Claude Code), hooks-cursor.json (Cursor), shared scripts, test.sh
agents/                      reusable sub-agent definitions (none yet)
AGENTS.md                    conventions; CLAUDE.md imports it
```

## Hooks

They load with the plugin in both harnesses, so a user-scope install runs them in every project; nothing is added to a repo, to `settings.json`, or to `~/.cursor/hooks.json`. The scripts are shared; `hooks/hooks.json` wires them into Claude Code and `hooks/hooks-cursor.json` into Cursor, where the skill is offered as `/d-github`. The Claude Code side has been watched firing; the Cursor side is built to Cursor's documented hook contract and tested against it, so after installing, open **Customize → Hooks** and the **Hooks** output channel once to confirm all three are listed and run.

| hook | event | what it does |
|---|---|---|
| [`d-github-offer.sh`](./hooks/d-github-offer.sh) | session start | In a repo whose origin is on github.com and that has no `.github/dependabot.yml` or no ruleset file under `.github/rulesets/`, tells the model to offer `/d-github` once. It makes the same offer when this machine lacks the standard's git `pre-push` hook or has an older copy than the plugin ships (a "no" to that alone is stored per machine: `git config --global deej-stack.pre-push-offer declined`). Say no and it records `deej-stack.d-github-offer=declined` in that clone's git config and stays quiet there; `git config --local --unset deej-stack.d-github-offer` brings it back. |
| [`default-branch.py`](./hooks/default-branch.py) `session-start` | session start | When HEAD is on the default branch, tells the model to create a branch before the first change it will commit. |
| [`default-branch.py`](./hooks/default-branch.py) `pre-push` | before a shell command | Denies any `git push` that would update the default branch, `main`, or `master`: explicit refspecs, `HEAD:main`, a bare push from `main`, `--all`, `--mirror`, deletes, and the same inside `cd … &&`, `git -C`, or `bash -c`. No exception, a new repo's first push included; a push to `main` is one you run yourself. It guards the agent, not the remote: the `/d-github` ruleset is what stops everyone else. |

`/d-github` is also the one skill the model may invoke unprompted: its description covers the mid-task case (you are editing CI or dependencies in a repo with no Dependabot config). The session-start hook replaces the trigger line earlier versions asked you to put in `~/.claude/CLAUDE.md`; delete that line (and the matching Cursor User Rule) once 0.8.0 is installed, or the offer arrives twice.

`hooks/test.sh` runs every case above against throwaway repos. Needs `python3`, `jq`, `git`.

## Private patterns

Hostnames, internal domains, and URL fragments that must never reach a public repo. There is one list per machine, not per project. It lives in your home directory and nowhere else: not in any repo, not in CI, not in a GitHub secret. One thing reads it, the git `pre-push` hook. (A shell or direnv that sets `DEEJ_PRIVATE_PATTERNS` is the only per-project override.)

**1. Write the list.** One POSIX extended regex per line, `#` comments allowed. Use your editor, not a chat window or a PR.

```bash
mkdir -p ~/.config/deej-stack && chmod 700 ~/.config/deej-stack
$EDITOR ~/.config/deej-stack/private-patterns && chmod 600 ~/.config/deej-stack/private-patterns
```

```
# private patterns: never commit this file
tail1a2b3\.ts\.net
\.corp\.example\.com
hooks\.slack\.com/services/
```

Escape dots (`\.`), or `a.b` also matches `aXb`. Prefer the shared suffix (the tailnet name, the internal domain) over single hosts, so new machines are covered without an edit. Matching ignores case, so one spelling per value is enough. `DEEJ_PRIVATE_PATTERNS=/other/path` overrides the location.

**2. That is all the git hook needs.** The machine-wide `pre-push` hook (installed by `/d-github`, or `skills/d-github/scripts/install-git-hooks.sh`) reads the file on every push and refuses one that would publish a match to a public remote. It prints commit and path, never the matched text.

**3. Check what is already out there.** `/d-github` in a repo lists any `path:line` in the tree that already matches. The hook only stops new pushes; a match already on a public remote is already public.

**4. Before making a private repo public:** `/d-github publish` also greps the whole history.

Check what is in place with `skills/d-github/scripts/facts.sh` in any repo: `user-pattern-file`, `pre-push-hook`, `tree-hits`.

What this does not cover, on purpose: a push with `--no-verify`, from a machine without the hook, or an edit in GitHub's web editor. Earlier versions added a CI grep for those; it was removed because it only fires after the commit is public and needed a copy of the list in GitHub's secret store. `/d-github` removes the leftovers (workflow, script, required check, secret) from repos that still have them.

## Later

Ideas not built yet, kept here so they don't need re-deriving.

- **`/d-github` standards to add.** The Actions posture that belongs in the same conversation as Dependabot and branch protection: every third-party action pinned by full commit SHA, `permissions: {}` at workflow top level with per-job grants, and no `pull_request_target`. Each is one reference file with the four fixed sections and one row in the skill's table. Linear history is deliberately a follow-up in the ruleset standard, not a rule; promote it if squash-only merging becomes the norm.
- **`/d-review`.** The `/d-implement` review panel (`skills/d-implement/references/panel.md` and `review-prompt.md`) run on its own against any diff, branch, or PR, no plan needed. Cursor has no built-in code review, so this is the one that earns its cross-harness keep. Mostly a thin `SKILL.md` pointing at the references that already exist.
- **Saved panel-model default.** Today `/d-plan` takes the model from the prompt or asks once per run. pstack's alternative is a per-user config the skill reads first: `/setup-pstack` writes `~/.cursor/rules/pstack-models.mdc` (`alwaysApply: true`, one `role: model` line each; a list spawns one sub-agent per entry; `inherit-parent` means omit `model`). The equivalent here would be a `plan panel model: <slug>` line in `~/.claude/CLAUDE.md` (Claude Code) and an always-applied rule or `AGENTS.md` line (Cursor), with Phase A checking for it before asking. Prompt still overrides. Add it if the question starts to feel like friction.
