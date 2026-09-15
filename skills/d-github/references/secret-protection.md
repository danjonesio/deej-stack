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

```bash
gh api -X PATCH repos/OWNER/REPO --input - <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"}}}
JSON
```

A refusal for one field (422 naming it) means the plan does not include it: record it as unavailable on the plan and re-send without it. `secret_scanning_validity_checks` and `secret_scanning_ai_detection` need Secret Protection on a Team or Enterprise plan; leave them alone and do not ask. Fact 1 unknown: put the command in the reply, run nothing.

**The pattern list.** Fact 3 absent: ask once, in the same question call as everything else, for the hostnames, domains, and URL fragments that must never appear in a public repo, one per line, with the default "save to `~/.config/deej-stack/private-patterns`". Write that file from the answer (create the directory), one ERE per line, a `#` header line saying what it is. The facts script never writes it. Fact 3 present with zero patterns: say so and skip the secret and the files; a grep against nothing guards nothing.

**The repository secret.** Fact 2 absent and Fact 3 present with patterns: a question, recommended answer "set it now", action `gh secret set PRIVATE_PATTERNS -R OWNER/REPO < <user file>`. Fact 2 present in `review` mode: report whether it exists, nothing more; its value cannot be read back, so say the user file is the source of truth and re-set it after editing.

**Files.** Write the three files in Output when the workflow (Fact 4) is absent. Existing `.pre-commit-config.yaml` without the hook: append the hook under its `repo: local` block if one exists, otherwise add the block at the end; touch nothing else in the file. Existing config with the hook: met. Pin `actions/checkout` to the SHA from Fact 6 with the tag in a trailing comment; Fact 6 unknown: write `@v7` and add a follow-up line to pin it.

**Local install.** Fact 5 present: run `pre-commit install` in this clone after writing the config. Git hooks are local, not a repository setting, so this is not a question. Fact 5 absent: one follow-up line, `pipx install pre-commit && pre-commit install`.

**Tree hits (Fact 7).** Each `path:line` goes in the reply. Never edit them out: which are real leaks and which are false positives is the user's call, and the CI job will fail until they are resolved, which is the point.

**History scan (`publish` only).**

```bash
git grep -InE -f <patterns> $(git rev-list --all) | cut -d: -f1,2,3 | sort -u
```

reported as commit, path, line, capped at fifty lines with the total. Never rewrite history. When there are hits, the reply says: the only cures are a history rewrite (`git filter-repo`, every clone re-cloned, every fork keeps the old objects) or a fresh repo from a clean tree, and that GitHub caches objects from deleted commits for a while after either.

**Branch protection interplay.** The job name `private-patterns` is an eligible check for `required_status_checks` in [`branch-protection.md`](branch-protection.md). Say in the reply that the ruleset picks it up on its next run.

**Dependabot interplay.** The workflow sits in the existing `github-actions` lane. A `repo: local` hook has nothing to bump: add no `pre-commit` entry for it.

**Fork PRs.** The step passes with a notice when the secret is empty, so a required check still reports and the fork's author is not blocked. The push run after merge catches what the fork run could not; say so in the reply.

**`review`.** Report each rule above as met or not with the fact beside it. Write nothing, set nothing.

## Output

Three files, verbatim, with `OWNER/REPO`, `<default>`, `<sha>`, `<tag>`, and `<date>` filled.

`.github/scripts/private-patterns.sh`, mode `755` (`chmod +x` then `git update-index --chmod=+x` after adding):

```bash
#!/usr/bin/env bash
# private-patterns: fail when a private pattern appears in the tree. Written by /d-github on <date>.
# Patterns come from $PRIVATE_PATTERNS (CI: the repository secret), else the file named by
# $DEEJ_PRIVATE_PATTERNS, else ~/.config/deej-stack/private-patterns. One POSIX extended regex
# per line; '#' comments and blank lines are ignored. With file arguments (pre-commit) it greps
# those files; without, the whole tree. Prints path:line per hit, never the matched text.
set -u
self=".github/scripts/private-patterns.sh"
tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT
f="${DEEJ_PRIVATE_PATTERNS:-$HOME/.config/deej-stack/private-patterns}"
if [ -n "${PRIVATE_PATTERNS:-}" ]; then
  printf '%s\n' "$PRIVATE_PATTERNS" | grep -vE '^[[:space:]]*(#|$)' > "$tmp"
elif [ -r "$f" ]; then
  grep -vE '^[[:space:]]*(#|$)' "$f" > "$tmp"
else
  echo "::notice::private-patterns: no patterns ($f missing, PRIVATE_PATTERNS unset); nothing checked"
  exit 0
fi
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
```

`.github/workflows/private-patterns.yml`:

```yaml
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
```

`.pre-commit-config.yaml` (the hook; the whole file when none exists):

```yaml
repos:
  - repo: local
    hooks:
      - id: private-patterns
        name: private patterns
        language: script
        entry: .github/scripts/private-patterns.sh
        exclude: ^(\.github/scripts/private-patterns\.sh|\.pre-commit-config\.yaml)$
```

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
