# The review panel

Every reviewer is a sub-agent on the panel model the user chose in Phase A, spawned per the Harness table in `SKILL.md`, carrying a `name` from the table below. Build each prompt from [`review-prompt.md`](review-prompt.md). Reviewers never edit files; they read the plan, run `git diff`, run read-only commands, and report.

The panel runs once, after Phase F, against the finished diff. All members run concurrently, spawned in one message.

| name | include | lens |
|---|---|---|
| `security-analyst` | always | Every numbered entry in the plan's **Security requirements**: find the step that claimed it and the diff hunk that satisfies it. A requirement with no hunk is `critical`. Then the diff on its own terms: new entry points, inputs, outputs, secrets, config, and dependencies the plan's threat model did not cover. |
| `code-reviewer` | always | The diff as code. Correctness and error paths per step; edge cases the step's Verify line does not exercise; whether each **Tests to add** case tests the behaviour it is named for rather than the implementation; whether each commit stays inside its step's files; abstractions, config, or paths the plan did not ask for. |
| `skeptic` | always | Drift and self-report. Anything in the diff outside **Changes** or inside **Out of scope**. Each deviation in the build record: is the reason real, and does any deviation change **Design** without saying so. Verify lines satisfied in letter but not in spirit. Claims in the build record with no command output or commit behind them. |
| situational analysts | when the plan's **Panel record** ran them | `data-analyst`, `ux-api-designer`, `ops-analyst`, `perf-analyst`: each checks that the requirements it raised in the plan landed in the diff, through its own lens from `../../d-plan/references/panel.md`. |

Re-check: after fixing a member's findings, resume that member with the re-check message in `review-prompt.md` rather than spawning fresh; it already holds the diff context. Spawn fresh only when the resume fails.

## Sizing

- Minimum panel: `security-analyst`, `code-reviewer`, `skeptic`. Three fresh runs plus re-checks for members whose findings were fixed.
- Plans whose panel record ran situational analysts add the same members here.
- The user can trim the panel ("just security") or skip it ("no review"). Record any deviation in the review table.
