# Standard: Branch protection

The default branch of every GitHub repo is covered by a ruleset that someone chose: every change arrives by pull request, the checks that exist must pass on an up-to-date branch, nobody bypasses, and the branch can be neither force-pushed nor deleted. Rulesets, not classic branch protection: rulesets are what GitHub develops now, they layer (an org ruleset stacks on a repo ruleset), and they export and import as JSON, so the repo can carry its own copy.

## Applies when

The default branch has no active ruleset with a `pull_request` rule (Fact 2), or the ask says `review`. When the API cannot see the repo, the absence of `.github/rulesets/default-branch.json` stands in.

Private repo on a Free plan (Fact 7): rulesets are not enforced there. Write the file so it is ready, apply nothing, and say why in the reply.

## Facts

`scripts/facts.sh` prints all of these under its `repo`, `actions`, and `security and protection` sections; the commands below are what it runs, kept here so a line it marks unknown can be re-run by hand.

1. **Repo and default branch.** As Dependabot Fact 1, in [`dependabot.md`](dependabot.md).
2. **Existing rulesets.** `gh api repos/OWNER/REPO/rulesets` for the repo's own; `gh api repos/OWNER/REPO/rules/branches/<default>` for every rule in force on the branch, org-level included. Record each rule type in force and which ruleset it came from.
3. **Classic protection.** `gh api repos/OWNER/REPO/branches/<default>/protection`: 200 with a body means a classic rule exists (record `required_pull_request_reviews`, `required_status_checks`, `enforce_admins`, `allow_force_pushes`, `allow_deletions`); 404 means none.
4. **Checks that can be required.** Two sources, and the second is the truth:
   - Workflows: jobs in workflows whose `on:` includes `pull_request`. A job behind a `paths:` filter or an `if:` may not run on a given PR, and a required check that never reports blocks the merge forever; such jobs are recorded as ineligible with the filter that makes them so.
   - Check-run names as GitHub saw them on the latest default-branch commit: `gh api repos/OWNER/REPO/commits/$(git rev-parse origin/<default> 2>/dev/null || git rev-parse HEAD)/check-runs -q '.check_runs[].name' | sort -u`. The `context` a ruleset requires is this name (the job's `name:` when set, otherwise the job key, with matrix values in brackets), not the workflow name. When this call is unknown, the workflow-derived names stand in, and the reply says to confirm them in the first PR's merge box.
5. **Merge methods.** `gh repo view OWNER/REPO --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`. Linear history needs squash or rebase allowed, and is free only when merge commits are already off.
6. **People.** `gh api users/OWNER -q .type` (`User` or `Organization`), `gh api repos/OWNER/REPO/collaborators -q length`, and whether `.github/CODEOWNERS`, `CODEOWNERS`, or `docs/CODEOWNERS` exists.
7. **Plan and visibility.** `gh repo view OWNER/REPO --json visibility,isPrivate`, then `gh api user -q .plan.name` for a `User` owner or `gh api orgs/OWNER -q .plan.name` for an `Organization`. An empty plan value means the token lacks the scope to read it: unknown. A public repo makes the plan irrelevant; skip the plan call.

## Rules

**One ruleset, named `default-branch`.** `target: branch`, `enforcement: active`, `bypass_actors: []`, `conditions.ref_name.include: ["~DEFAULT_BRANCH"]`. No bypass is the standing decision: editing or disabling the ruleset in Settings is the escape hatch, and it leaves a trail.

**Rules in it, in this order:**

- `deletion` and `non_fast_forward`, always.
- `pull_request`, always. `required_approving_review_count` is `0` when Fact 6 counts one collaborator or is unknown (a PR author cannot approve their own PR, so `1` would lock a solo repo, and a missed review is recoverable where a locked branch is not); with more than one collaborator it is a question, default `1`. `dismiss_stale_reviews_on_push: true`, `require_code_owner_review: true` only when a CODEOWNERS file exists, `require_last_push_approval: false`, `required_review_thread_resolution: true`. Omit `allowed_merge_methods`; the repo setting governs.
- `required_status_checks`, only when Fact 4 yields at least one eligible name. `strict_required_status_checks_policy: true`. One `context` per eligible check-run name; no `integration_id` (the checks come from Actions, and pinning the app id is a value this reference has not verified). No eligible checks: leave the rule out and say in the reply that the ruleset requires PRs but nothing runs on them.
- `required_linear_history`, only when Fact 5 shows merge commits already disallowed. Otherwise leave it out and list it as a follow-up: turning it on changes how every PR merges, which is the user's call, not a default.

**Existing classic protection (Fact 3 is 200).** Report it beside the ruleset, setting by setting, and ask one question: migrate (create the ruleset, then delete the classic rule once Fact 2 shows the ruleset in force), or leave both. Default when the question cannot be asked: create nothing, delete nothing, leave the file and the reply. Fact 3 unknown: the apply line in the reply says to check `Settings → Branches` for a classic rule first and decide migrate or leave both before running the create command.

**Existing ruleset with a `pull_request` rule.** The standard is met. In `review` mode, diff its rules against the list above and report each difference; write nothing.

**An org ruleset already in force (Fact 2 shows a rule with a source other than this repo).** A repo ruleset stacks on it, the stricter setting wins, and the repo copy is still worth having: it survives the repo leaving the org. Say in the reply which rules the org already enforces.

**Applying is a question.** Creating the ruleset is a repository-settings change: ask, with "create it now" as the recommended answer. The action is `gh api -X POST repos/OWNER/REPO/rulesets --input .github/rulesets/default-branch.json`. When the question cannot be asked, write the file and put the command in the reply; never run it on a default.

## Output

`.github/rulesets/default-branch.json`: the request body for the create call, which also imports through **Settings → Rules → Rulesets → New ruleset → Import a ruleset**. JSON carries no comments, so the decision record for this standard is the reply and the commit message, one line per rule with the fact behind it.

```json
{
  "name": "default-branch",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [],
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [
          { "context": "web" },
          { "context": "backend" }
        ]
      }
    }
  ]
}
```

After it is applied: `gh api repos/OWNER/REPO/rules/branches/<default> -q '.[].type'` lists every rule in force; the four types above (three without checks) must appear. Then the next PR shows the required checks in its merge box. Say this in the reply.

## Verified keys

Checked against the REST reference for repository rules and the rulesets docs on 2026-09-12: <https://docs.github.com/en/rest/repos/rules> and <https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets>. Re-check before using anything not listed here; do not extend this from memory.

| field | verified values and notes |
|---|---|
| top level | `name`, `target` (`branch`), `enforcement` (`disabled`, `active`, `evaluate`; `evaluate` is Enterprise only), `bypass_actors` (array; `actor_id`, `actor_type`, `bypass_mode`), `conditions`, `rules` |
| `conditions.ref_name` | `include` and `exclude` arrays of ref names or patterns; `~DEFAULT_BRANCH` and `~ALL` accepted in `include` |
| rule `deletion` | no parameters |
| rule `non_fast_forward` | no parameters (this is "block force pushes") |
| rule `required_linear_history` | no parameters; the repo must allow squash or rebase merging first |
| rule `pull_request` | required parameters: `dismiss_stale_reviews_on_push`, `require_code_owner_review`, `require_last_push_approval`, `required_approving_review_count`, `required_review_thread_resolution`; optional `allowed_merge_methods` (`merge`, `squash`, `rebase`) |
| rule `required_status_checks` | `strict_required_status_checks_policy` (required), `required_status_checks` array of `{context, integration_id?}`, `do_not_enforce_on_create` (optional) |
| endpoints | `POST /repos/{owner}/{repo}/rulesets` (201), `GET /repos/{owner}/{repo}/rulesets`, `GET /repos/{owner}/{repo}/rulesets/{id}`, `GET /repos/{owner}/{repo}/rules/branches/{branch}` |
| availability | public repos on every plan; private repos on Pro, Team, and Enterprise Cloud |
