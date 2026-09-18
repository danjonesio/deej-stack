# Standard: Secret protection

Two things leak from a public repo: credential-shaped secrets, which GitHub scans for free on public repos and blocks at push, and private values no scanner knows by shape (a tailnet hostname, an internal domain, a webhook URL). The second needs custom patterns, which GitHub sells only on org plans, so this standard greps for them on the machine, in a git `pre-push` hook that refuses the push before the value leaves.

The private patterns are local only. Nothing about them goes to GitHub: no workflow, no script in the tree, no repository secret, no required check. A CI grep on a public repo fires after the commit is already public, and a copy of the list in GitHub's secret store is one more place for it to live. The accepted cost: a push with `--no-verify`, from a machine without the hook, or an edit in the web editor is checked by nothing. Do not add a CI check back as an improvement.

## Applies when

Any of: the repo is public (Branch protection Fact 7) and `security-and-analysis` shows `secret_scanning_push_protection` other than `enabled`; the user pattern file is absent (Fact 2); the machine hook is absent or outdated (Fact 3); files from the retired CI check are present (Fact 4); the ask says `review` or `publish`.

Private repo: user-owned private repos get no server-side secret scanning outside Enterprise. Skip the **Server-side toggles** rule in one line naming the visibility fact; the pattern list and the machine hook are per machine, so those rules still apply.

`publish` is the ask for a repo about to go public: run every rule below as if the repo were public already, then the history scan in the Rules.

## Facts

`scripts/facts.sh` prints these under `security and protection` and `private patterns`; the commands are kept here so a line it marks unknown can be re-run by hand.

1. **Security toggles.** `gh api repos/OWNER/REPO -q '.security_and_analysis'`: the status of each of `secret_scanning`, `secret_scanning_push_protection`, `secret_scanning_non_provider_patterns`, `secret_scanning_ai_detection`, `secret_scanning_validity_checks`. A missing object means the token lacks admin: unknown.
2. **User pattern file.** `$DEEJ_PRIVATE_PATTERNS`, else `~/.config/deej-stack/private-patterns`: present or absent, and the count of lines that are not blank or `#` comments.
3. **Machine hook.** `git config --global --get core.hooksPath` (`global-hooks-path`); whether `pre-push` in that directory is byte-identical to `scripts/git-hooks/pre-push` (`pre-push-hook`: `current`, `outdated`, `absent`); `git config --local --get core.hooksPath` (`local-hooks-path`: husky and similar set it, and a local value hides the global directory from this clone).
4. **Retired CI check.** Versions before 0.10.0 wrote a CI grep. `retired-ci-files` lists any of `.github/workflows/private-patterns.yml`, `.github/scripts/private-patterns.sh`, and a `.pre-commit-config.yaml` naming the `private-patterns` hook; `private-patterns-secret` says whether `gh secret list -R OWNER/REPO` names `PRIVATE_PATTERNS`; `required-checks-on-<default>` lists the contexts the rules in force require.
5. **Tree hits.** With Fact 2 present: `git grep -IniE -f <patterns>` over the tree, as a count and up to twenty `path:line` entries. The matched text is never printed; the fact sheet may be pasted somewhere.

## Rules

**Server-side toggles.** `secret_scanning`, `secret_scanning_push_protection`, and `secret_scanning_non_provider_patterns` must be `enabled`. Any that is not is a question, recommended answer "enable now", one `PATCH` for all of them:

```bash
gh api -X PATCH repos/OWNER/REPO --input - <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"}}}
JSON
```

Read the statuses back afterwards. A refusal for one field (422 naming it), or a 200 that leaves the field `disabled`, means the plan does not include it: record it as unavailable on the plan, re-send without it, and do not ask again on later runs. `secret_scanning_validity_checks` and `secret_scanning_ai_detection` need Secret Protection on a Team or Enterprise plan; leave them alone and do not ask. Fact 1 unknown: put the command in the reply, run nothing.

**The pattern list.** Fact 2 absent: ask once, in the same question call as everything else, for the hostnames, domains, and URL fragments that must never appear in a public repo, one per line, with the default "save to `~/.config/deej-stack/private-patterns`". Write that file from the answer (create the directory, mode 700; the file mode 600), one ERE per line, a `#` header line saying what it is. The grep matches case-insensitively, so one spelling per value is enough. The facts script never writes it. When the user would rather write it themselves, point at the README's "Private patterns" section and move on. The file never goes anywhere else: not into the tree, not into a repository secret, not into the reply.

**Machine hook (Fact 3).** It is installed once per machine, not per repo, so it is checked on every run, private repos included.

- `pre-push-hook: absent` and `global-hooks-path: unset`: a question, recommended answer "install now", action `scripts/install-git-hooks.sh`. It sets the global `core.hooksPath`, which changes how every clone on the machine finds its hooks, so it is never run on a default. Say in the question what that costs: the installed chain hooks keep each repo's own `.git/hooks` running, but `pre-commit install` refuses while a global `core.hooksPath` is set (run it as `GIT_CONFIG_GLOBAL=/dev/null pre-commit install`).
- `pre-push-hook: outdated`: a question, recommended answer "update now", same script.
- `global-hooks-path` set to a directory without our `pre-push`: the installer refuses. Put its message in the reply and change nothing.
- `local-hooks-path` set: the machine hook does not run in this clone. One follow-up line: add a `pre-push` to that directory that runs `~/.config/deej-stack/git-hooks/pre-push "$@"` (husky: `.husky/pre-push`).
- `current`: met.

What the hook scans, how it decides visibility, and its bypass are in the header of `scripts/git-hooks/pre-push`; do not restate them.

**Tree hits (Fact 5).** Each `path:line` goes in the reply. Never edit them out: which are real leaks and which are false positives is the user's call. A hit already on the remote is already public; the hook only stops new ones.

**Retired CI check (Fact 4).** Anything it lists is removed, in this order, because a required check whose workflow is gone never reports and blocks every merge:

1. `required-checks-on-<default>` names `private-patterns`: a question, recommended answer "drop it now". Remove that context from `.github/rulesets/default-branch.json` (the whole `required_status_checks` rule when it was the only context), then `gh api -X PUT repos/OWNER/REPO/rulesets/<id> --input .github/rulesets/default-branch.json`, and read `rules/branches/<default>` back. Declined: stop here and leave the files, saying why.
2. Delete the files `retired-ci-files` lists. In a `.pre-commit-config.yaml`, remove only the `private-patterns` hook, and the file only when nothing else is left in it.
3. `private-patterns-secret: present`: a question, recommended answer "delete it now", action `gh secret delete PRIVATE_PATTERNS -R OWNER/REPO`.

**History scan (`publish` only).**

```bash
git grep -IniE -f <patterns> $(git rev-list --all) | cut -d: -f1,2,3 | sort -u
```

reported as commit, path, line, capped at fifty lines with the total. Never rewrite history. When there are hits, the reply says: the only cures are a history rewrite (`git filter-repo`, every clone re-cloned, every fork keeps the old objects) or a fresh repo from a clean tree, and that GitHub caches objects from deleted commits for a while after either.

**`review`.** Report each rule above as met or not with the fact beside it. Write nothing, set nothing.

## Output

Nothing in the tree. What a run leaves behind is on the machine (`~/.config/deej-stack/private-patterns`, the hooks directory, the global `core.hooksPath`) and in the repository settings (the toggles). The decision record is the reply.

Afterwards: `facts.sh` reports `user-pattern-file: present`, `pre-push-hook: current`, `retired-ci-files: none`; **Settings → Code security** shows secret scanning and push protection on. Say this in the reply.

## Verified keys

Checked on 2026-09-13 against the repositories REST reference (<https://docs.github.com/en/rest/repos/repos>, "Update a repository", `security_and_analysis`) and the supported-patterns page (<https://docs.github.com/en/code-security/secret-scanning/introduction/supported-secret-scanning-patterns>). Re-check before using a field that is not here.

| field under `security_and_analysis` | value | plan |
|---|---|---|
| `secret_scanning` | `{ "status": "enabled" \| "disabled" }` | free on public repos; user-owned private repos: not available |
| `secret_scanning_push_protection` | same | free on public repos, on by default |
| `secret_scanning_non_provider_patterns` | same | public repos; a 422, or a 200 that leaves it `disabled` (seen on a user-owned public repo, 2026-09-18), means not on this plan |
| `secret_scanning_ai_detection` | same | Secret Protection, Team or Enterprise: never sent |
| `secret_scanning_validity_checks` | read only here | Secret Protection, Team or Enterprise: never sent |

Custom secret-scanning patterns: Secret Protection on org-owned repos only, which is why the denylist is a local grep and not a GitHub setting.

Git hook facts the machine hook depends on, verified against `git help hooks` and `git help config` (git 2.53) on 2026-09-18: `pre-push` receives the remote name and URL as arguments and one `<local ref> <local sha> <remote ref> <remote sha>` line per ref on stdin, with an all-zero sha for a delete (local) or a new ref (remote); a non-zero exit aborts the push; `--no-verify` skips it; `core.hooksPath` replaces `$GIT_DIR/hooks` for every hook name, and a local value overrides the global one.

`PUT /repos/{owner}/{repo}/rulesets/{ruleset_id}` (update a ruleset, full body) verified against <https://docs.github.com/en/rest/repos/rules> on 2026-09-18.
