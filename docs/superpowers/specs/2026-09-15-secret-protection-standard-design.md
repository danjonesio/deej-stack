# Secret protection standard for /d-github

Date: 2026-09-15. Facts below verified against GitHub docs and the live API on 2026-09-13.

## Problem

A public repo leaks two kinds of thing: credential-shaped secrets, and private values that no scanner recognises by shape (tailnet hostnames, internal domains, webhook URLs, workspace links). GitHub handles the first for free on public repos and not at all on user-owned private repos. The second needs custom patterns, which GitHub sells only on org plans, so it has to be caught in the tree. In Dan's workflow the likeliest leaker is an agent copying a hostname from context into a README or config.

## Verified facts (2026-09-13)

- Public repos: secret scanning runs automatically and free; push protection is on by default. This repo (`danjonesio/deej-stack`) shows `secret_scanning` and `secret_scanning_push_protection` enabled, `secret_scanning_non_provider_patterns` and `secret_scanning_validity_checks` disabled.
- User-owned private repos: secret scanning unavailable outside Enterprise Cloud with EMU.
- Validity checks: Team or Enterprise with Secret Protection only.
- Custom patterns: Secret Protection on Team or Enterprise, org-owned repos. Not available to user-owned public repos.
- `PATCH /repos/{owner}/{repo}` accepts `security_and_analysis` with `secret_scanning`, `secret_scanning_push_protection`, `secret_scanning_non_provider_patterns`, `secret_scanning_ai_detection`, each `{ "status": "enabled" | "disabled" }`. `GET` returns the same plus `secret_scanning_validity_checks`.

## Decisions

1. **One standard, "Secret protection"**, one row in the d-github table, one reference `skills/d-github/references/secret-protection.md` in the four fixed sections.
2. **Patterns never enter the tree.** A committed denylist would publish the hostnames it protects. The standing list lives in `~/.config/deej-stack/private-patterns` (override: `DEEJ_PRIVATE_PATTERNS` env var). CI reads the same content from a repository secret `PRIVATE_PATTERNS`; the pre-commit hook reads the user file. The repo carries only generic files, so the setup is recreatable from the tree plus one `gh secret set`.
3. **Pattern format**: one POSIX extended regex per line; `#` comments and blank lines are stripped before use. Same format in the user file and the secret, so `gh secret set PRIVATE_PATTERNS -R OWNER/REPO < ~/.config/deej-stack/private-patterns` is the whole action.
4. **Enforcement**: one script `.github/scripts/private-patterns.sh` used by both a workflow `.github/workflows/private-patterns.yml` and a `repo: local` pre-commit hook. One source, two callers.
5. **Applies when**: the repo is public and any of: push protection not enabled; the workflow absent; the ask says `review` or `publish`. Private repo: one reply line saying the server-side features are unavailable on the plan, and the standard is skipped (a private repo may carry private URLs).
6. **History scan** only on a `publish` ask: `git grep -I -E -f <patterns> $(git rev-list --all)`, reported as commit, path, line. Never rewrites history; the reply states what a rewrite or a fresh repo involves.
7. **Repository settings are questions**: enabling the three toggles (`PATCH`), setting the secret (`gh secret set`). One question call carries all of them. An API refusal on a toggle is recorded as unavailable on the plan, not retried.
8. **Missing user file** is one question: the hostnames to protect, saved to the user file with "yes" as the default. The facts script never writes it; the skill does, after the answer.
9. **Local install**: when `pre-commit` is on PATH, the skill runs `pre-commit install` in the clone. Git hooks are local, not repository settings, so no question.
10. **Branch protection interplay**: the job name `private-patterns` becomes an eligible check for `required_status_checks`; the reference says so and the branch-protection standard picks it up on its next run.
11. **Dependabot interplay**: the workflow lives in the existing `github-actions` lane; a `repo: local` hook has nothing to bump, so no `pre-commit` entry is added for it.
12. **Fork PRs** see an empty secret. The step passes with a `::notice::` so a required check still reports; the push-to-default run after merge catches anything the fork run could not.
13. **Tree hits** found at write time are listed as file and line in the reply. The skill never edits them out.
14. **d-implement** gains one rule line: a hostname, URL, or credential not already in the tree goes in as an env var or placeholder, never a literal.

## Outputs the standard writes

### `.github/scripts/private-patterns.sh`

Read-only. Patterns from `$PRIVATE_PATTERNS` (CI), else the file `$DEEJ_PRIVATE_PATTERNS` or `~/.config/deej-stack/private-patterns`. No patterns available: print a notice, exit 0. With file arguments (pre-commit): `grep -InE -f` over them. Without (CI): `git grep -InE -f` over the tree. Prints `path:line` per hit, never the matched text, exits 1 on any hit. Excludes itself and `.pre-commit-config.yaml`.

### `.github/workflows/private-patterns.yml`

`on: pull_request` and `push` to the default branch. `permissions: contents: read`. One job `private-patterns`, `actions/checkout` pinned to the full SHA the skill resolves from `gh api repos/actions/checkout/git/ref/tags/<latest v-major>` at write time (with the tag in a trailing comment), then one step running the script with `PRIVATE_PATTERNS: ${{ secrets.PRIVATE_PATTERNS }}` in `env`.

### `.pre-commit-config.yaml`

A `repo: local` hook `private-patterns`, `language: script`, `entry: .github/scripts/private-patterns.sh`, `exclude: ^(\.github/scripts/private-patterns\.sh|\.pre-commit-config\.yaml)$`. An existing config gets the hook appended under a new or existing `repo: local` block; nothing else changes.

## Facts added to `scripts/facts.sh`

Under `security and protection`: the five `security_and_analysis` statuses from `GET /repos/OWNER/REPO`; whether `gh secret list -R OWNER/REPO` names `PRIVATE_PATTERNS`. New section `private patterns`: user file path and whether it exists; count of non-comment lines; whether the script, workflow, and `.pre-commit-config.yaml` exist and whether the config already carries the hook; whether `pre-commit` is on PATH; tree hits from the user file as a count and up to 20 `path:line` entries, never the matched text.

## Around the skill

- `SKILL.md`: new table row; `argument-hint: [standard name] [review|publish]`; the `publish` ask defined next to `review` in Phase A and Phase D; description gains "secret scanning", "push protection", "private patterns", "before making this public".
- `README.md`: skills-table row and the CLAUDE.md trigger line gain the new standard.
- `~/.claude/CLAUDE.md` trigger line updated to match.
- `skills/d-implement/SKILL.md`: the rule line in decision 14.
- Version 0.7.0 in both manifests.

## Verification

`claude plugin validate .`; `bash -n` and a run of `scripts/facts.sh` on this repo; a `/d-github secret protection` run on this repo (public, push protection already on) exercising the met line, the secret question, and the file writes; a `publish` run on a repo with a known historical hit.
