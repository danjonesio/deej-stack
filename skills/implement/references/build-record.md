# Build record template

The build record is written for the reviewer who never saw the run and the human who merges. Every line is backed by a command output, a path, or a commit SHA; a line without one is a claim, and claims do not go in the record.

Drop a section only when it is empty for a reason worth one line ("No deviations.").

---

# Build record: {plan title}

Plan: `{plan path}`. Branch `{branch}` from base `{base sha}`, head `{head sha}`. {Tracker link, who merges, if the plan named them.}

## Questions resolved

| question | answer | source |
|---|---|---|

Source is `default` (the plan's stated default) or `user`.

## Audit

Result of the plan's completeness audit run against the current tree in Phase B. Paths that moved, commands that changed, and what was done about each.

## Steps

| # | step | commit | verify | result |
|---|---|---|---|---|

One row per **Changes** step, in order. `verify` is the command as run; `result` is pass, or the failing output's first line and what the run did next.

## Tests

| case | covers | file | commit |
|---|---|---|---|

One row per **Tests to add** case. `covers` is the finding or security requirement the plan mapped it to.

## Verification

| check | command or action | result |
|---|---|---|

The plan's **Verification** section, one row each. Manual checks the run could not perform are `needs human` with the exact URL, click, or request.

## Deviations

| # | step | plan said | done instead | why |
|---|---|---|---|---|

Mechanical only. A deviation that changes **Design** is not recorded here; it stops the run.

## Review

| member | model | critical | warning | nit | fixed (commits) | deferred (reason) |
|---|---|---|---|---|---|---|

Deviations from the default panel and why.

## Noticed, not done

Things the run saw that the plan did not ask for. One line each, with a path. These are input to the next plan, not to this branch.

## PR body

```
{title}

{Three to six lines: what changed and why, in terms the plan's Context used.}

Plan: {plan path}
Steps: {N} commits, one per plan step
Verification: {one line}
Needs human: {manual checks, or "none"}
```

---

## Build audit

Run this against the record before delivery. Every line is a yes or a fix.

- [ ] Every **Changes** step has a commit and a passing Verify result in the steps table.
- [ ] Every step commit touches only the files its step names, or the deviation table says why.
- [ ] Every **Security requirements** entry is `met` in the security-analyst's requirement check.
- [ ] Every **Tests to add** case exists, passes, and names what it covers.
- [ ] Every **Verification** row ran, or is `needs human` with an exact action.
- [ ] Every deviation has plan-said, done-instead, and why; none changes **Design**.
- [ ] Every review finding is fixed with a commit or deferred with a reason; no `critical` is deferred.
- [ ] `git diff {base}...HEAD --stat` shows nothing under **Out of scope**.
- [ ] Every open question from the plan is in the questions table with a source.
- [ ] The record stands alone: a reader with the record and `git log` can audit the build without this conversation.
