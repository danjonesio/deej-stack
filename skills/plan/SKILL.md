---
name: plan
description: "Plan a feature, app, or change with a panel of sub-agents on the model you name (architect, reuse scout, security analyst, code reviewer, skeptic, plus situational lenses) while the main agent orchestrates, synthesises, and audits the plan for completeness. Use for /plan, 'plan this', 'make a plan for', or any build where starting with code would lock in the wrong shape."
argument-hint: <what to build or change> [panel model]
disable-model-invocation: true
---

# Plan

**Ask**: $ARGUMENTS
(If that line still reads `$ARGUMENTS`, the harness did not substitute it; the ask is the message that invoked this skill.)

You are the orchestrator and the final reviewer. The panel does the lens work in parallel; you frame the problem, ground it in the codebase, synthesise the members' output into one plan, put that plan back in front of the panel, and audit the result before it reaches the human. You do not write code. The only file you write is the plan.

Read these before starting; they live beside this file and are the contract for every phase:

- `references/panel.md`: who is on the panel, when, and what each member produces.
- `references/reviewer-prompt.md`: the prompt every member receives, and the wave-2 resume message.
- `references/plan-template.md`: the shape of the deliverable and the completeness audit.

## Harness

This skill runs in Claude Code and in Cursor. The phases below say *spawn*, *resume*, *explore*; this table says what that means where you are.

| | Claude Code | Cursor |
|---|---|---|
| Spawn a member | `Agent` tool: `subagent_type: "general-purpose"`, `model: <panel model>`, `name: <roster name>` | `Task` tool: `subagent_type: generalPurpose`, `model: <panel model>`, `readonly: true`, `run_in_background: true` |
| Panel model form | an alias (`opus`, `sonnet`, `haiku`, `fable`) or a full model id; the `Agent` tool has no effort field | a full slug, with options in brackets as the user gave them (`<slug>[effort=high]` form) |
| Inherit the session model | omit `model` | omit `model` |
| Ask the user | `AskUserQuestion` | `AskQuestion` |
| Run a wave concurrently | every call in one message | every call in one message |
| Wait for a member | its completion notification arrives; nothing before that is a result | the background task reports back; a partial output file is not a result |
| Resume a member | `SendMessage` to its `name` | resume the agent ID the `Task` call returned |
| Explore the codebase | `Explore` agent, `very thorough` | the built-in `explore` subagent |
| Enter read-only planning | `EnterPlanMode` | no tool; the user picks Plan Mode (Shift+Tab). This skill's rules are the guard |
| Hand the plan over | write the plan file the harness names, then `ExitPlanMode` | in Plan Mode, write the plan file the harness names; otherwise `docs/plans/` |
| Model rejected by the tool | read the valid options from the error, take the closest tier of the same family, tell the user in the reply, note it in the panel record | same |

Where the harness has no `name` field, put the roster name on the first line of the prompt and keep the returned agent ID; wave 2 needs it.

## Start

Open a todo list with one entry per phase. The list is how the human sees where the run is, and it keeps a phase from silently disappearing.

1. Frame
2. Ground
3. Analyse (wave 1)
4. Synthesise (draft v1)
5. Review (wave 2)
6. Enrich (draft v2 + audit)
7. Deliver

## Phase A: Frame

1. Enter read-only planning per the Harness table if the harness has a tool for it and the user did not say otherwise. With or without the tool, nothing in this skill writes a file except the plan.
2. Write the brief. Keep the ask in the user's words, then add: the outcome as a user or operator would recognise it; the done predicate; constraints the user named; what is explicitly out of scope. Ask the user a question only if two readings of the ask lead to materially different plans. Otherwise state the assumption in the brief and carry on.
3. Pick the panel from [`panel.md`](references/panel.md). The five minimum members always run. Add situational members by the "include" column; when unsure, include. Record the roster and the reasons in the panel record.
4. Panel model. Take it from the ask if the user named one: the model, and effort where the harness accepts it. If the ask names none, ask once with the question tool before anything is spawned: which model the panel should run on, offering what this harness accepts plus "same as this session" (omit `model` so members inherit). Never assume a default; the panel costs several runs and the model is the user's call. Record the choice in the panel record.

## Phase B: Ground

Explore the codebase (per the Harness table) for a map: stack and versions, entry points, the directories and files the brief touches, how build, lint, typecheck, and tests run, and anything the project instructions (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/`) point at. Cap the map at roughly sixty lines of paths and one-liners; it is context for the panel, not a report. Read the project instructions yourself while the map is built.

Greenfield: the map is the stack decision and the directory layout the user prefers. Still run the panel; a security analyst and a skeptic earn their keep on day one.

Do not read the codebase into your own context beyond the map. The members read; you integrate.

## Phase C: Analyse (wave 1)

Spawn every wave-1 member in one message so they run concurrently. Each prompt is built from [`reviewer-prompt.md`](references/reviewer-prompt.md) with every placeholder filled: role, brief verbatim, the map, the project root, and the member's lens copied from the roster row.

Wait for each member. A member's findings arrive in its result and nowhere else; never write them yourself. If a member fails, spawn it once more; if it fails again, proceed without it and say so in the panel record.

## Phase D: Synthesise (draft v1)

Start from the architect's draft and shape it per [`plan-template.md`](references/plan-template.md). Integrate every finding from every member:

- Accepted: it becomes a step, a requirement, a reuse entry, a test, or a risk. Critical findings become steps, never risks.
- Rejected: it goes in the panel record with the reason. "Out of scope" is a reason only if the brief says so.
- Two members disagree: you decide, and the plan says why.

Write draft v1 to the plan file if the harness gave you one, otherwise to a scratch file. Keep the panel's raw output out of the chat.

## Phase E: Review (wave 2)

In one message:

- Spawn fresh `code-reviewer` and `skeptic` members with the same prompt template. Their "Codebase map" section is the map; add a `## Draft under review` section containing draft v1 in full.
- Resume `security-analyst`, `reuse-scout`, and every situational member that ran in wave 1 with the wave-2 resume message from `reviewer-prompt.md`, draft v1 included in full.

Wait for all of them. A resume that fails gets one fresh spawn with the wave-1 prompt plus the draft.

## Phase F: Enrich (draft v2 + audit)

Integrate wave-2 findings exactly as in Phase D. Then run the completeness audit at the bottom of `plan-template.md`. Every line is a yes or a fix; do not deliver with a failing line. Check paths yourself with `ls` or a short explore run; the audit asks whether they exist, not whether a member said they do.

If wave 2 produced a `critical` that changes the design rather than a step, return to Phase D with the change and resume the affected members once more. One extra loop at most; after that, deliver with the disagreement stated as an open question with a default.

## Phase G: Deliver

Hand the plan over per the Harness table. Outside a plan mode, write it to `docs/plans/<yyyy-mm-dd>-<slug>.md` under the project root, or the path the user named.

Reply in chat with at most ten lines: the outcome, the panel that ran with counts of critical and warning findings accepted, the open questions that need the human, and where the plan lives. The plan is in the file; do not paste it.

## Rules

- Guard the context window. Members' output stays in their reports; read each once, integrate, move on.
- Evidence over assertion. Nothing enters the plan without a path, a command, or a config value behind it.
- Never block on the human after Phase A. The panel-model question is the one deliberate checkpoint; everything else proceeds on stated defaults, and every open question carries one.
- Never fabricate or predict a pending member's result. If the result has not arrived, the member is still running.
- The default panel is the default. The user can trim it ("just security and dedup") or skip wave 2 ("quick plan"). Record every deviation in the panel record.
