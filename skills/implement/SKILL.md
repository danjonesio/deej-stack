---
name: implement
description: "Build from a plan file written by /plan: re-audit the plan against the current tree, resolve its open questions on their stated defaults, execute the Changes steps in order with each step's Verify line as the gate and one commit per step, add the named tests, run the plan's Verification section, then put the diff in front of a read-only review panel on the model you name. Delivers a build record and a PR body. Use for /implement, 'build the plan', 'implement docs/plans/<file>'."
argument-hint: [plan path] [panel model]
disable-model-invocation: true
---

# Implement

**Ask**: $ARGUMENTS
(If that line still reads `$ARGUMENTS`, the harness did not substitute it; the ask is the message that invoked this skill.)

You are the builder and the orchestrator. You write the code, one plan step at a time, and commit each step once its Verify line passes. The panel runs once, at the end, read-only, against the diff. Nothing gets built that the plan did not ask for, and nothing the plan asked for gets skipped silently.

Read these before starting; they live beside this file and are the contract for every phase:

- `references/panel.md`: who reviews the build and what each member checks.
- `references/review-prompt.md`: the prompt every reviewer receives, and the re-check message.
- `references/build-record.md`: the shape of the deliverable and the build audit.

The plan you build from has the shape in `../plan/references/plan-template.md`. Its section names (**Changes**, **Verify**, **Tests to add**, **Verification**, **Security requirements**, **Risks and open questions**, **Out of scope**, **Panel record**) are what the phases below refer to.

## Harness

This skill runs in Claude Code and in Cursor. The phases below say *spawn*, *resume*, *explore*, *isolate*; this table says what that means where you are.

| | Claude Code | Cursor |
|---|---|---|
| Spawn a reviewer | `Agent` tool: `subagent_type: "general-purpose"`, `model: <panel model>`, `name: <roster name>` | `Task` tool: `subagent_type: generalPurpose`, `model: <panel model>`, `readonly: true`, `run_in_background: true` |
| Panel model form | an alias (`opus`, `sonnet`, `haiku`, `fable`) or a full model id; the `Agent` tool has no effort field | a full slug, with options in brackets as the user gave them (`<slug>[effort=high]` form) |
| Inherit the session model | omit `model` | omit `model` |
| Ask the user | `AskUserQuestion` | `AskQuestion` |
| Run a wave concurrently | every call in one message | every call in one message |
| Wait for a reviewer | its completion notification arrives; nothing before that is a result | the background task reports back; a partial output file is not a result |
| Resume a reviewer | `SendMessage` to its `name` | resume the agent ID the `Task` call returned |
| Explore the codebase | `Explore` agent, `very thorough` | the built-in `explore` subagent |
| Isolate the work | `EnterWorktree` when the tool exists; otherwise `git switch -c <branch>` | `git switch -c <branch>` |
| Read-only mode active | this skill writes files and commits; if plan mode is on, ask the user to leave it before Phase B | same; the user leaves Plan Mode (Shift+Tab) |
| Model rejected by the tool | read the valid options from the error, take the closest tier of the same family, tell the user in the reply, note it in the review record | same |

Where the harness has no `name` field, put the roster name on the first line of the prompt and keep the returned agent ID; re-checks need it.

## Start

Open a todo list with one entry per phase. When Phase D starts, expand its entry into one todo per plan step; the list is how the human sees which step is being built.

1. Load
2. Audit
3. Isolate
4. Build (one todo per step)
5. Test
6. Verify
7. Review
8. Deliver

## Phase A: Load

1. Find the plan. A path in the ask wins; otherwise the newest file in `docs/plans/` under the project root. No plan: stop and say so; this skill does not plan.
2. Read the plan in full and the project instructions (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`). The plan is the spec; the project instructions are the conventions.
3. Collect the one round of questions, then ask it in a single call of the question tool:
   - Every entry in **Risks and open questions** that has no default. Entries with a default take the default; record each in the build record's questions table with source `default`.
   - The panel model for Phase G, unless the ask named one. Offer what this harness accepts, "same as the plan's panel" (the model in the plan's **Panel record**), and "same as this session" (omit `model`). Never assume; the panel costs several runs.
   Nothing else in this skill blocks on the human.

## Phase B: Audit

1. `git status --porcelain` must be empty. A dirty tree means someone's uncommitted work would end up in a step commit; stop and say what is dirty.
2. Run the completeness audit at the bottom of `../plan/references/plan-template.md` against the current tree, not the tree the plan was written against. Check every path in **Changes** and **Findings from exploration** with `ls` or a short explore run; line numbers drift, files move.
3. A mechanical mismatch (a path moved, a signature renamed, a command that changed name) is fixed in your working copy of the step and recorded as a deviation. A mismatch that changes **Design** (a data shape, an interface, the module map) is not yours to fix: write the build record with the audit result, and tell the user to re-run the plan skill with what changed.

## Phase C: Isolate

Branch name: the branch the plan's first line names, else the plan file's slug (the part after the date). Isolate per the Harness table. Record the base commit (`git rev-parse HEAD`) in the build record; every diff the reviewers see is measured from it.

## Phase D: Build

For each numbered step in **Changes**, in order:

1. Mark its todo in progress.
2. Make the change the step states, in the files it names. Where the step gives code, config, a signature, or a schema, use it as written; the panel settled it. Where the step names a decision, do not reopen it.
3. Run the step's **Verify** line. It passes before the next step starts. If it fails, fix within the step's files and run it again. If it still fails after the fix you believe in, stop the run: write the build record with the step marked failed and the output, and report. Never weaken a Verify line, skip it, or mark it passed on a partial result.
4. Commit the step's files by path, not `git add -A`. Message: `<slug> step <N>: <step title>`, body: the Verify command and its result on one line each, then any deviation. Follow the project's commit conventions where the project instructions set them.
5. Record the step in the build record: commit SHA, Verify command, result.

Deviations: anything the tree forced you to do differently from the step's text goes in the record with what the plan said, what was done, and why. A deviation that would change **Design** stops the run as in Phase B. Anything you notice that the plan did not ask for goes under "Noticed, not done"; **Out of scope** is a wall.

You write the code. Do not hand a step to a sub-agent; the Verify and the commit are yours.

## Phase E: Test

Write every case in **Tests to add**. Each case names, in the test name or a comment per the project's convention, the finding or security requirement it covers. Cases the plan attached to a step were written in that step; write the rest here, run them, and commit as `<slug> tests: <what>`. A case that cannot be written as named is a deviation, not an omission.

## Phase F: Verify

Run the **Verification** section verbatim: build, lint, typecheck, test, in the project's own commands. Manual checks: do the ones a shell or browser tool can do; the rest go in the build record as "needs human" with the exact URL, click, or request. Fix failures and commit as `<slug> verify: <what>`; re-run the Verify line of any step the fix touched.

## Phase G: Review

Spawn every reviewer in [`panel.md`](references/panel.md) in one message. Each prompt is built from [`review-prompt.md`](references/review-prompt.md) with every placeholder filled: role, the plan in full, the build record so far, the base commit, the project root, and the member's lens copied from the roster row. Give reviewers the diff command, not the diff: they run `git diff <base>...HEAD` themselves and read what they need.

Wait for each reviewer. Integrate:

- `critical` and `warning`: fix, commit as `<slug> review: <finding title>`, re-run the Verify line of any step the fix touched.
- `nit`: fix if it is one edit; otherwise defer with a reason.
- Rejected: only with a reason in the review table. "The plan said so" is a reason only when the plan actually says so.

Resume each member whose findings you fixed with the re-check message from `review-prompt.md`. One re-check round; after that, an unresolved finding is deferred with the disagreement stated.

## Phase H: Deliver

Run the build audit at the bottom of `build-record.md`. Every line is a yes or a fix; do not deliver with a failing line.

Write the record to `docs/plans/<plan file basename>.build.md` beside the plan and commit it as `<slug> build record`. Do not push and do not open a PR unless the user asked; the record's PR body is ready to paste.

Reply in chat with at most ten lines: the branch and base, steps built with commit count, verification result, review counts by severity with how many were fixed, deviations, manual checks that need the human, and where the record lives. The record is in the file; do not paste it.

## Rules

- One step at a time. Step N+1 does not start while step N's Verify is failing.
- Evidence over assertion. Every line in the build record is a command output, a path, or a commit SHA.
- Guard the context window. The diff stays in git; reviewers read it from there. Reviewers' output stays in their reports; read each once, integrate, move on.
- Never fabricate or predict a pending reviewer's result. If the result has not arrived, the reviewer is still running.
- The plan is the spec. Improve it by recording a deviation or a "noticed, not done" line, never by quietly doing something else.
- The default panel is the default. The user can trim it ("just security") or skip it ("no review"). Record every deviation in the review table.
