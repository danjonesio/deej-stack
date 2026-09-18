---
name: d-github
description: "Bring a GitHub repo up to Dan's standing repo standards: a Dependabot config shaped around whether a merge to the default branch deploys, a default-branch ruleset (PR required, checks up to date, no bypass, no force-push or deletion), and secret protection (GitHub's secret-scanning toggles on, plus a machine-wide git pre-push hook and a CI job that grep for private hostnames kept out of the tree). Use for /d-github, 'set up dependabot', 'protect main', 'branch protection', 'ruleset', 'secret scanning', 'push protection', 'private patterns', 'pre-push hook', 'before making this public', 'standard repo setup', 'review our dependabot config', or whenever you notice a repo whose origin is on github.com has no .github/dependabot.yml, no .github/rulesets/, or is public with no .github/workflows/private-patterns.yml while working on its CI, dependencies, branches, or security settings: offer this skill before touching those by hand."
argument-hint: [standard name] [review|publish]
---

# GitHub standards

**Ask**: $ARGUMENTS
(If that line still reads `$ARGUMENTS`, the harness did not substitute it; the ask is the message that invoked this skill. An empty ask means: apply every standard that applies.)

You apply the standards in the table below to the repo you are in. Each standard is one reference file beside this one with the same four sections: **Applies when**, **Facts**, **Rules**, **Output**. You read the repo yourself; nothing here spawns a panel. The judgement in the Rules sections is the product; the files they produce are short.

| standard | applies when | reference |
|---|---|---|
| Dependabot | `.github/dependabot.yml` is missing, or the ask says `review` | [`references/dependabot.md`](references/dependabot.md) |
| Branch protection | the default branch has no active ruleset requiring a pull request, or the ask says `review` | [`references/branch-protection.md`](references/branch-protection.md) |
| Secret protection | the repo is public and push protection is off or `.github/workflows/private-patterns.yml` is missing, or the ask says `review` or `publish` | [`references/secret-protection.md`](references/secret-protection.md) |

## Harness

| | Claude Code | Cursor |
|---|---|---|
| Ask the user | `AskUserQuestion` | `AskQuestion` |
| GitHub API | `gh api` in the shell; a 404 or auth error is an unknown fact, not a "no" | same |
| Read the repo | your own file and search tools; do not spawn | same |
| Gather facts | `scripts/facts.sh` from the shell (needs `git`; `gh` logged in for the API lines) | same |

## Start

Open a todo list with one entry per phase.

1. Scope
2. Check
3. Decide
4. Write
5. Deliver

## Phase A: Scope

1. `git remote get-url origin` must name a github.com repo; take `OWNER/REPO` from it. Anything else: stop and say the repo is not on GitHub. Nothing in the table applies elsewhere. If `gh repo view OWNER/REPO` cannot see the repo (not pushed yet, private to another account, `gh` not logged in), carry on: every API-sourced fact is `unknown`, the reply says so once, and you do not retry or change auth.
2. Pick the standards. A standard named in the ask runs alone. Otherwise every row whose "applies when" holds runs; rows already met are reported as met in one line and skipped, and follow-ups their earlier run left in a file header are not re-reported. A `publish` ask runs every standard that applies as if the repo were public already; what that adds is defined in [`references/secret-protection.md`](references/secret-protection.md).
3. State in one line which standards run and why before reading anything else.

## Phase B: Check

Run `scripts/facts.sh <repo root>` (beside this file) once; it prints every fact the references' **Facts** sections ask for, read-only, as labelled lines, with `unknown (<reason>)` wherever the API or the tree gave no answer. Then read the **Facts** section of each selected standard to interpret those lines; run a command by hand only for a line the script marked unknown for a reason you can fix locally (a missing fetch, a wrong directory). A fact is a command output, a file path, or a config value. A fact you cannot establish (API refused, host config lives outside the repo, no signal either way) is recorded as `unknown`. An unknown that a rule depends on becomes a question in Phase C; an unknown that only feeds the header is written into the header as unknown and asked about nowhere. Never fill an unknown with the likely answer.

## Phase C: Decide

Apply the **Rules** section of each selected standard to its facts. Collect every question the rules raise across all standards and ask them in one call of the question tool, each with the default the rules give. Anything that changes repository settings rather than files in the tree (enabling alerts, security updates, branch protection), or the machine's global git config, is always a question, never an action taken on your own.

## Phase D: Write

Write the file each standard's **Output** section specifies. Where the format takes comments, the header carries the reasoning with the fact behind every decision, so the next reader does not have to re-derive it; where it does not (JSON), the reasoning is the reply and the commit message. Syntax-check with whatever parser the machine has (`python3 -c 'import yaml,sys; yaml.safe_load(open(sys.argv[1]))' <file>` for YAML when PyYAML is present, `python3 -m json.tool <file>` for JSON; otherwise say the check was skipped).

A standard whose real output is a repository setting (a ruleset) still writes its file to the tree as the record, and applying it is one of the Phase C questions; the file goes in first so the setting can be recreated from the repo alone. Commit, push, or open a PR only if the ask says so. Otherwise leave the file in the working tree and give the commit message in the reply. `review` mode writes nothing: it reports the differences between the existing file and the standard, and the user decides. `publish` mode writes as normal, then runs the history scan its reference defines and reports the hits; it never rewrites history.

## Phase E: Deliver

Reply as a list, no prose around it: one line per standard saying done, met, or skipped; one line per entry, skip, and deferred unknown, each with the fact behind it on the same line, except that unknowns sharing one cause (the API cannot see the repo) are one line naming the cause and the facts it took with it; one line per follow-up; the commit message; and what to check after the file lands (each Output section says where). The file is on disk; do not paste it.

## Rules

- Evidence over assertion. Every decision in a header comment names the command, path, or value that drove it.
- Never guess a config key. Each reference carries the keys verified against the vendor docs and the date; a key outside that list goes in as a follow-up, not a lane. One bad key can invalidate the whole file and take the working entries down with it.
- One run applies the standards in the table and nothing else. Adjacent good ideas you notice (pinning actions, tightening workflow permissions, linear history) go in the reply as follow-ups.
- Where the repo needs something different from the standard, do it and say why in the file header. A silent deviation is the one thing the next reader cannot recover from.
