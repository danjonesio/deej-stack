# Secret Protection Standard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Secret protection" standard to `/d-github` that confirms GitHub's secret-scanning toggles, guards public repos against private hostnames with a CI job and a pre-commit hook that read patterns kept out of the tree, and scans history on a `publish` ask.

**Architecture:** One reference file in the four fixed sections, three generic output files the standard writes into a target repo (a grep script, a workflow that calls it with a repository secret, a `repo: local` pre-commit hook that calls it with the user-level pattern file), facts added to `scripts/facts.sh`, and the plumbing around the skill (table rows, triggers, version).

**Tech Stack:** Markdown prose, bash, GitHub REST via `gh`, GitHub Actions, pre-commit `language: script`.

**Spec:** `docs/superpowers/specs/2026-09-15-secret-protection-standard-design.md`

## Global Constraints

- Prose rules from `AGENTS.md`: tell the agent to do the thing; every sentence changes a decision; point at structural sources; delegate by path.
- Facts are commands and paths, never inference. Unknown is a valid value. Never fill an unknown with the likely answer.
- Every config key in a reference is verified against vendor docs with a date. Verified 2026-09-13: `security_and_analysis` fields `secret_scanning`, `secret_scanning_push_protection`, `secret_scanning_non_provider_patterns`, `secret_scanning_ai_detection`, `secret_scanning_validity_checks`, each `{ "status": "enabled" | "disabled" }`.
- Patterns never enter the tree. User file `~/.config/deej-stack/private-patterns` (override `DEEJ_PRIVATE_PATTERNS`); repository secret `PRIVATE_PATTERNS`.
- Pattern format: one POSIX ERE per line, `#` comments and blank lines stripped.
- `scripts/facts.sh` stays read-only.
- Version bumps to `0.7.0` in both manifests, in the last task.
- No harness-specific variables in skill prose; the Harness table names tools.

---

### Task 1: The reference file

**Files:**
- Create: `skills/d-github/references/secret-protection.md`

**Interfaces:**
- Produces: the section names `## Applies when`, `## Facts`, `## Rules`, `## Output`, `## Verified keys` that SKILL.md Phase B–D refer to; the fact labels `security-and-analysis`, `private-patterns-secret`, `user-pattern-file`, `script`, `workflow`, `pre-commit-config`, `pre-commit-binary`, `checkout-latest`, `tree-hits` that Task 2 prints.

- [ ] **Step 1: Write the file**

```markdown
# Standard: Secret protection

Two things leak from a public repo: credential-shaped secrets, which GitHub scans for free on public repos and blocks at push, and private values no scanner knows by shape (a tailnet hostname, an internal domain, a webhook URL). The second needs custom patterns, which GitHub sells only on org plans, so this standard catches them in the tree with a grep that runs in CI and before every commit. The patterns themselves never enter the tree: a committed denylist would publish the very hostnames it protects.

## Applies when

The repo is public (Branch protection Fact 7) and any of: `security-and-analysis` shows `secret_scanning_push_protection` other than `enabled`; `.github/workflows/private-patterns.yml` is absent; the ask says `review` or `publish`.

Private repo: user-owned private repos get no server-side secret scanning outside Enterprise, and a private repo may carry private URLs. Report the standard as skipped in one line naming the visibility fact, and stop.

`publish` is the ask for a repo about to go public: run every rule below as if the repo were public already, then the history scan in the Rules.

## Facts

`scripts/facts.sh` prints these under `security and protection` and `private patterns`; the commands are kept here so a line it marks unknown can be re-run by hand.

1. **Security toggles.** `gh api repos/OWNER/REPO -q '.security_and_analysis'`: the status of each of `secret_scanning`, `secret_scanning_push_protection`, `secret_scanning_non_provider_patterns`, `secret_scanning_ai_detection`, `secret_scanning_validity_checks`. A missing object means the token lacks admin: unknown.
2. **Repository secret.** `gh secret list -R OWNER/REPO` names `PRIVATE_PATTERNS` or not. A command error (no admin) is unknown.
3. **User pattern file.** `$DEEJ_PRIVATE_PATTERNS`, else `~/.config/deej-stack/private-patterns`: present or absent, and the count of lines that are not blank or `#` comments.
4. **Files in the tree.** `.github/scripts/private-patterns.sh`, `.github/workflows/private-patterns.yml`, `.pre-commit-config.yaml` (and whether it already names the `private-patterns` hook).
5. **Local tooling.** `pre-commit` on `PATH` or not.
6. **Latest checkout action.** `gh api repos/actions/checkout/releases/latest -q .tag_name`, then `gh api repos/actions/checkout/commits/<tag> -q .sha` for the full commit SHA that tag resolves to.
7. **Tree hits.** With Fact 3 present: `git grep -InE -f <patterns>` over the tree, excluding the script and the pre-commit config, as a count and up to twenty `path:line` entries. The matched text is never printed; the fact sheet may be pasted somewhere.
8. **Fork exposure.** Whether the workflow runs on `pull_request` (Output below): a fork's PR sees an empty secret.

## Rules

**Server-side toggles.** `secret_scanning`, `secret_scanning_push_protection`, and `secret_scanning_non_provider_patterns` must be `enabled`. Any that is not is a question, recommended answer "enable now", one `PATCH` for all of them:

    gh api -X PATCH repos/OWNER/REPO --input - <<'EOF'
    {"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"}}}
    EOF

A refusal for one field (422 naming it) means the plan does not include it: record it as unavailable on the plan and re-send without it. `secret_scanning_validity_checks` and `secret_scanning_ai_detection` need Secret Protection on a Team or Enterprise plan; leave them alone and do not ask. Fact 1 unknown: put the command in the reply, run nothing.

**The pattern list.** Fact 3 absent: ask once, in the same question call as everything else, for the hostnames, domains, and URL fragments that must never appear in a public repo, one per line, with the default "save to `~/.config/deej-stack/private-patterns`". Write that file from the answer (create the directory), one ERE per line, a `#` header line saying what it is. The facts script never writes it. Fact 3 present with zero patterns: say so and skip the secret and the files; a grep against nothing guards nothing.

**The repository secret.** Fact 2 absent and Fact 3 present with patterns: a question, recommended answer "set it now", action `gh secret set PRIVATE_PATTERNS -R OWNER/REPO < <user file>`. Fact 2 present in `review` mode: report whether it exists, nothing more; its value cannot be read back, so say the user file is the source of truth and re-set it after editing.

**Files.** Write the three files in Output when the workflow (Fact 4) is absent. Existing `.pre-commit-config.yaml` without the hook: append the hook under its `repo: local` block if one exists, otherwise add the block at the end; touch nothing else in the file. Existing config with the hook: met. Pin `actions/checkout` to the SHA from Fact 6 with the tag in a trailing comment; Fact 6 unknown: write `@v7` and add a follow-up line to pin it.

**Local install.** Fact 5 present: run `pre-commit install` in this clone after writing the config. Git hooks are local, not a repository setting, so this is not a question. Fact 5 absent: one follow-up line, `pipx install pre-commit && pre-commit install`.

**Tree hits (Fact 7).** Each `path:line` goes in the reply. Never edit them out: which are real leaks and which are false positives is the user's call, and the CI job will fail until they are resolved, which is the point.

**History scan (`publish` only).**

    git grep -InE -f <patterns> $(git rev-list --all) | cut -d: -f1,2,3 | sort -u

reported as commit, path, line, capped at fifty lines with the total. Never rewrite history. When there are hits, the reply says: the only cures are a history rewrite (`git filter-repo`, every clone re-cloned, every fork keeps the old objects) or a fresh repo from a clean tree, and that GitHub caches objects from deleted commits for a while after either.

**Branch protection interplay.** The job name `private-patterns` is an eligible check for `required_status_checks` in [`branch-protection.md`](branch-protection.md). Say in the reply that the ruleset picks it up on its next run.

**Dependabot interplay.** The workflow sits in the existing `github-actions` lane. A `repo: local` hook has nothing to bump: add no `pre-commit` entry for it.

**Fork PRs.** The step passes with a notice when the secret is empty, so a required check still reports and the fork's author is not blocked. The push run after merge catches what the fork run could not; say so in the reply.

**`review`.** Report each rule above as met or not with the fact beside it. Write nothing, set nothing.

## Output

Three files, verbatim, with `OWNER/REPO`, `<default>`, `<sha>`, `<tag>`, and `<date>` filled.

`.github/scripts/private-patterns.sh`, mode `755` (`chmod +x` then `git update-index --chmod=+x` after adding):

    #!/usr/bin/env bash
    # private-patterns: fail when a private pattern appears in the tree. Written by /d-github on <date>.
    # Patterns come from $PRIVATE_PATTERNS (CI: the repository secret), else the file named by
    # $DEEJ_PRIVATE_PATTERNS, else ~/.config/deej-stack/private-patterns. One POSIX extended regex
    # per line; '#' comments and blank lines are ignored. With file arguments (pre-commit) it greps
    # those files; without, the whole tree. Prints path:line per hit, never the matched text.
    set -u
    self=".github/scripts/private-patterns.sh"
    tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
    if [ -n "${PRIVATE_PATTERNS:-}" ]; then
      printf '%s\n' "$PRIVATE_PATTERNS"
    else
      f="${DEEJ_PRIVATE_PATTERNS:-$HOME/.config/deej-stack/private-patterns}"
      if [ ! -r "$f" ]; then
        echo "::notice::private-patterns: no patterns ($f missing, PRIVATE_PATTERNS unset); nothing checked"
        exit 0
      fi
      cat "$f"
    fi | grep -vE '^[[:space:]]*(#|$)' > "$tmp"
    if [ ! -s "$tmp" ]; then
      echo "::notice::private-patterns: pattern list is empty; nothing checked"
      exit 0
    fi
    if [ $# -gt 0 ]; then
      hits=$(grep -IHnE -f "$tmp" -- "$@" 2>/dev/null | cut -d: -f1,2)
    else
      hits=$(git grep -InE -f "$tmp" -- . ":!$self" ':!.pre-commit-config.yaml' | cut -d: -f1,2)
    fi
    [ -z "$hits" ] && exit 0
    printf 'private-patterns: hit at\n%s\n' "$hits" >&2
    exit 1

`.github/workflows/private-patterns.yml`:

    # Greps the tree for private hostnames and URLs. Written by /d-github on <date>.
    # Patterns live in the PRIVATE_PATTERNS repository secret (source: ~/.config/deej-stack/private-patterns
    # on the maintainer's machine), never in this repo. A fork's PR sees an empty secret and passes with a notice.
    name: private-patterns
    on:
      pull_request:
      push:
        branches: [<default>]
    permissions:
      contents: read
    jobs:
      private-patterns:
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@<sha> # <tag>
          - name: Grep the tree for private patterns
            env:
              PRIVATE_PATTERNS: ${{ secrets.PRIVATE_PATTERNS }}
            run: .github/scripts/private-patterns.sh

`.pre-commit-config.yaml` (the hook; the whole file when none exists):

    repos:
      - repo: local
        hooks:
          - id: private-patterns
            name: private patterns
            language: script
            entry: .github/scripts/private-patterns.sh
            exclude: ^(\.github/scripts/private-patterns\.sh|\.pre-commit-config\.yaml)$

After the files land: the first PR shows a `private-patterns` check; **Settings → Secrets and variables → Actions** lists `PRIVATE_PATTERNS`; **Settings → Code security** shows secret scanning, push protection, and non-provider patterns on. Say this in the reply.

## Verified keys

Checked on 2026-09-13 against the repositories REST reference (<https://docs.github.com/en/rest/repos/repos>, "Update a repository", `security_and_analysis`) and the supported-patterns page (<https://docs.github.com/en/code-security/secret-scanning/introduction/supported-secret-scanning-patterns>). Re-check before using a field that is not here.

| field under `security_and_analysis` | value | plan |
|---|---|---|
| `secret_scanning` | `{ "status": "enabled" \| "disabled" }` | free on public repos; user-owned private repos: not available |
| `secret_scanning_push_protection` | same | free on public repos, on by default |
| `secret_scanning_non_provider_patterns` | same | public repos; a 422 means not on this plan |
| `secret_scanning_ai_detection` | same | Secret Protection, Team or Enterprise: never sent |
| `secret_scanning_validity_checks` | read only here | Secret Protection, Team or Enterprise: never sent |

Custom secret-scanning patterns: Secret Protection on org-owned repos only, which is why the denylist is a grep and not a GitHub setting.

Pre-commit `language: script`: `entry` is a path relative to the repo root, run directly; the hook receives staged file paths as arguments. Verified against the pre-commit docs on 2026-09-13.
```

- [ ] **Step 2: Check the four sections and the table render**

Run: `grep -nE '^## ' skills/d-github/references/secret-protection.md`
Expected: `Applies when`, `Facts`, `Rules`, `Output`, `Verified keys` in that order.

- [ ] **Step 3: Commit**

```bash
git add skills/d-github/references/secret-protection.md
git commit -m "d-github: secret-protection reference (toggles, private-patterns grep, publish scan)"
```

### Task 2: Facts

**Files:**
- Modify: `skills/d-github/scripts/facts.sh` (the `security and protection` section and a new `private patterns` section before `docker`)

**Interfaces:**
- Consumes: `$API`, `$SLUG`, `say`, `section` from the top of the script.
- Produces: the labels named in Task 1's Facts.

- [ ] **Step 1: Add the API-side facts inside the `if [ "$API" = yes ]` block of `security and protection`**

After the `say "rulesets-file"` line is too late (it is outside the block); insert after the `say "plan"` lines and before the `else`:

```bash
  sa=$(gh api "repos/$SLUG" -q '.security_and_analysis | to_entries | map("\(.key)=\(.value.status)") | join(" ")' 2>/dev/null)
  say "security-and-analysis" "${sa:-unknown (api error, or token lacks admin)}"
  if out=$(gh secret list -R "$SLUG" 2>/dev/null); then
    say "private-patterns-secret" "$(printf '%s\n' "$out" | grep -q '^PRIVATE_PATTERNS' && echo present || echo absent)"
  else
    say "private-patterns-secret" "unknown (gh secret list failed; needs admin)"
  fi
```

And add `security-and-analysis private-patterns-secret` to the `for k in ...` unknown loop in the `else` branch.

- [ ] **Step 2: Add the `private patterns` section before `# ---------- docker ----------`**

```bash
# ---------- private patterns ----------
section "private patterns"
PF="${DEEJ_PRIVATE_PATTERNS:-$HOME/.config/deej-stack/private-patterns}"
if [ -r "$PF" ]; then
  say "user-pattern-file" "present: $PF ($(grep -cvE '^[[:space:]]*(#|$)' "$PF") patterns)"
else
  say "user-pattern-file" "absent ($PF)"
fi
say "script" "$([ -f .github/scripts/private-patterns.sh ] && echo present || echo absent)"
say "workflow" "$([ -f .github/workflows/private-patterns.yml ] && echo present || echo absent)"
if [ -f .pre-commit-config.yaml ]; then
  say "pre-commit-config" "present, hook $(grep -q 'id: private-patterns' .pre-commit-config.yaml && echo present || echo absent)"
else
  say "pre-commit-config" "absent"
fi
say "pre-commit-binary" "$(command -v pre-commit >/dev/null 2>&1 && echo present || echo absent)"
if [ "$GH" = yes ]; then
  tag=$(gh api repos/actions/checkout/releases/latest -q .tag_name 2>/dev/null)
  sha=$([ -n "$tag" ] && gh api "repos/actions/checkout/commits/$tag" -q .sha 2>/dev/null)
  say "checkout-latest" "${tag:-unknown} ${sha:-unknown (api error)}"
else
  say "checkout-latest" "unknown (gh unavailable)"
fi
if [ -r "$PF" ]; then
  pats=$(mktemp); grep -vE '^[[:space:]]*(#|$)' "$PF" > "$pats"
  if [ -s "$pats" ]; then
    hits=$(git grep -InE -f "$pats" -- . ':!.github/scripts/private-patterns.sh' ':!.pre-commit-config.yaml' 2>/dev/null | cut -d: -f1,2)
    say "tree-hits" "$(printf '%s' "$hits" | grep -c .) (path:line only; matched text is never printed)"
    [ -n "$hits" ] && printf '%s\n' "$hits" | head -20 | sed 's/^/  /'
  else
    say "tree-hits" "unknown (pattern file has no patterns)"
  fi
  rm -f "$pats"
else
  say "tree-hits" "unknown (no user pattern file)"
fi
```

- [ ] **Step 3: Syntax-check and run on this repo**

Run: `bash -n skills/d-github/scripts/facts.sh && skills/d-github/scripts/facts.sh . | sed -n '/## security/,/## docker/p'`
Expected: a `security-and-analysis:` line listing five `key=status` pairs, `private-patterns-secret: absent`, and a `## private patterns` section with `user-pattern-file: absent (...)`, `checkout-latest: v7.0.1 3d3c42e5aac5ba805825da76410c181273ba90b1`, `tree-hits: unknown (no user pattern file)`.

- [ ] **Step 4: Run with a scratch pattern file to prove the hit path**

```bash
printf '# test\n\nrefreshsurplus\n' > "$SCRATCH/patterns"
DEEJ_PRIVATE_PATTERNS="$SCRATCH/patterns" skills/d-github/scripts/facts.sh . | sed -n '/## private/,/## docker/p'
```
Expected: `user-pattern-file: present: ... (1 patterns)` and `tree-hits: N` with `path:line` entries indented below, no matched text.

- [ ] **Step 5: Commit**

```bash
git add skills/d-github/scripts/facts.sh
git commit -m "d-github: facts for secret protection (toggles, secret, pattern file, tree hits, checkout sha)"
```

### Task 3: Prove the output script in a scratch repo

**Files:**
- None in this repo. Scratch only: `$SCRATCH/repo`.

- [ ] **Step 1: Build the scratch repo from the reference's script block**

```bash
R="$SCRATCH/repo"; rm -rf "$R"; mkdir -p "$R/.github/scripts"; cd "$R"; git init -q
awk '/^`.github\/scripts\/private-patterns.sh`/{f=1;next} f&&/^`.github\/workflows/{exit} f&&/^    /{sub(/^    /,"");print}' \
  /home/danjones/other/deej-stack/skills/d-github/references/secret-protection.md > .github/scripts/private-patterns.sh
chmod +x .github/scripts/private-patterns.sh
printf 'hello\n' > clean.md; printf 'see https://foo.example.ts.net/x\n' > leak.md
git add -A; git -c user.email=t@t -c user.name=t commit -qm init
```

- [ ] **Step 2: Run the four cases**

```bash
unset PRIVATE_PATTERNS DEEJ_PRIVATE_PATTERNS
DEEJ_PRIVATE_PATTERNS=/nonexistent .github/scripts/private-patterns.sh; echo "no-file exit=$?"
printf '\\.ts\\.net\n' > "$SCRATCH/p"
DEEJ_PRIVATE_PATTERNS="$SCRATCH/p" .github/scripts/private-patterns.sh; echo "tree exit=$?"
DEEJ_PRIVATE_PATTERNS="$SCRATCH/p" .github/scripts/private-patterns.sh clean.md; echo "clean-file exit=$?"
PRIVATE_PATTERNS="$(cat $SCRATCH/p)" .github/scripts/private-patterns.sh leak.md; echo "env-leak-file exit=$?"
```
Expected: `no-file exit=0` with a notice; `tree exit=1` printing `leak.md:1` only; `clean-file exit=0`; `env-leak-file exit=1` printing `leak.md:1`. The URL text never appears.

- [ ] **Step 3: Run the pre-commit hook for real**

```bash
awk '/^`.pre-commit-config.yaml`/{f=1;next} f&&/^After the files land/{exit} f&&/^    /{sub(/^    /,"");print}' \
  /home/danjones/other/deej-stack/skills/d-github/references/secret-protection.md > .pre-commit-config.yaml
git add .pre-commit-config.yaml
DEEJ_PRIVATE_PATTERNS="$SCRATCH/p" pre-commit run --all-files; echo "pre-commit exit=$?"
```
Expected: the hook fails with `leak.md:1`, exit 1. Then `git rm -q leak.md && DEEJ_PRIVATE_PATTERNS="$SCRATCH/p" pre-commit run --all-files` passes.

No commit in this repo for this task. Any fix goes into Task 1's file with a commit `d-github: fix private-patterns script (<what>)`.

### Task 4: Wire the standard into SKILL.md

**Files:**
- Modify: `skills/d-github/SKILL.md` (frontmatter description and argument-hint; the standards table; Phase A step 2; Phase D's `review` sentence)

- [ ] **Step 1: Frontmatter**

Replace the `description` with:

```
description: "Bring a GitHub repo up to Dan's standing repo standards: a Dependabot config shaped around whether a merge to the default branch deploys, a default-branch ruleset (PR required, checks up to date, no bypass, no force-push or deletion), and secret protection (GitHub's secret-scanning toggles on, plus a CI job and pre-commit hook that grep for private hostnames kept out of the tree). Use for /d-github, 'set up dependabot', 'protect main', 'branch protection', 'ruleset', 'secret scanning', 'push protection', 'private patterns', 'before making this public', 'standard repo setup', 'review our dependabot config', or whenever you notice a repo whose origin is on github.com has no .github/dependabot.yml, no .github/rulesets/, or is public with no .github/workflows/private-patterns.yml while working on its CI, dependencies, branches, or security settings: offer this skill before touching those by hand."
argument-hint: [standard name] [review|publish]
```

- [ ] **Step 2: Table row**

Add after the Branch protection row:

```
| Secret protection | the repo is public and push protection is off or `.github/workflows/private-patterns.yml` is missing, or the ask says `review` or `publish` | [`references/secret-protection.md`](references/secret-protection.md) |
```

- [ ] **Step 3: Phase A step 2 and Phase D**

In Phase A step 2, append: `A \`publish\` ask runs every standard that applies as if the repo were public already; what that adds is defined in [\`references/secret-protection.md\`](references/secret-protection.md).`

In Phase D, after the `review` sentence, append: `\`publish\` mode writes as normal, then runs the history scan its reference defines and reports the hits; it never rewrites history.`

- [ ] **Step 4: Validate and commit**

Run: `claude plugin validate .`
Expected: passes.

```bash
git add skills/d-github/SKILL.md
git commit -m "d-github: add secret-protection row, publish ask, triggers"
```

### Task 5: README, trigger lines, d-implement rule

**Files:**
- Modify: `README.md:53` (the `/d-github` row) and `README.md:72` (the trigger line)
- Modify: `/home/danjones/.claude/CLAUDE.md` (the same trigger line)
- Modify: `skills/d-implement/SKILL.md` Rules section

- [ ] **Step 1: README row**

Replace the "Today:" sentence in the `/d-github` row with:

```
Today: a Dependabot config (version updates where merges deploy nothing, grouped security-only updates where they do), a default-branch ruleset (PR required, checks up to date, no bypass, no force-push or deletion), and secret protection (GitHub's secret-scanning toggles on; a CI job and pre-commit hook that grep for private hostnames from a pattern list that never enters the tree; `publish` scans history before a repo goes public).
```

- [ ] **Step 2: Trigger line, both places**

Replace the sentence in README.md and in `~/.claude/CLAUDE.md` with:

```
In a repo whose origin is on github.com and that has no .github/dependabot.yml, no .github/rulesets/, or is public with no .github/workflows/private-patterns.yml, offer /deej-stack:d-github once, then drop it if declined.
```

- [ ] **Step 3: d-implement rule**

Append to the Rules list in `skills/d-implement/SKILL.md`:

```
- A hostname, URL, or credential that is not already in the tree goes in as an environment variable or a placeholder, never a literal. Public repos carry a private-patterns check (`/d-github`); a literal fails it after the commit, a placeholder never reaches it.
```

- [ ] **Step 4: Commit**

```bash
git add README.md skills/d-implement/SKILL.md
git commit -m "README, d-implement: secret-protection trigger line and no-literal-hostnames rule"
```

### Task 6: Version bump and final validation

**Files:**
- Modify: `.claude-plugin/plugin.json:3`, `.cursor-plugin/plugin.json:4`

- [ ] **Step 1: Bump**

```bash
sed -i 's/"version": "0.6.0"/"version": "0.7.0"/' .claude-plugin/plugin.json .cursor-plugin/plugin.json
grep -n version .claude-plugin/plugin.json .cursor-plugin/plugin.json
```
Expected: both `0.7.0`.

- [ ] **Step 2: Validate everything**

```bash
claude plugin validate . && bash -n skills/d-github/scripts/facts.sh && skills/d-github/scripts/facts.sh . >/dev/null && echo ok
```
Expected: `ok`.

- [ ] **Step 3: Commit**

```bash
git add .claude-plugin/plugin.json .cursor-plugin/plugin.json
git commit -m "Version 0.7.0: secret-protection standard"
```
