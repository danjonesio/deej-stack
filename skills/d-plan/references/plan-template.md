# Plan template

The final plan is written for two readers: the human who approves it and the agent who builds from it in a fresh session with no memory of the panel. Every decision the panel settled is stated as a fact; every unknown is stated as a question. No section may say "handle errors appropriately", "add tests", or "follow best practices": name the error, the test, the practice.

Drop a section only when it is empty for a reason worth one line ("No schema changes.").

---

# {Title}

{One line: tracker link, branch, who merges, if known.}

## Context

The problem in one paragraph, with the evidence that it is real (paths, commands, error text). Then the outcome: what is true after this ships, in terms a user or operator would recognise.

## Findings from exploration

Bullets, each with a path and line or a command. What the code does today that constrains the design. Include the surprising facts the panel found; these save the builder from rediscovering them.

## Design

- **Caller's usage first**: two or three real call sites, screens, or requests as they will look after the change.
- **Data shapes**: the types, tables, or schemas, derived from the usage above.
- **Module map**: files to add and change, by path, with one line each on ownership.
- **Interfaces**: signatures and contracts at each boundary.
- **Rejected alternative**: the simplest design that was considered and not chosen, and why.

## Reuse

Existing code this plan builds on, by path, and what each contributes. Anything the panel found that would otherwise be duplicated.

## Security requirements

Numbered. Each names the entry point, table, or component it protects and the step below that satisfies it.

## Changes

Numbered steps in build order. Each step:

- one file or one coherent set of files, by path
- what changes, with the code or config that settles a decision (a signature, a schema, a route, a query)
- **Verify**: the command or check that proves this step is done, before the next step starts

Each step must leave the tree in a state the builder can check. Order so that the sequence proves itself to a reviewer.

## Verification

Build, lint, typecheck, and test commands as they run in this project. Manual checks with the exact URL, click, or request. What "done" looks like end to end.

## Tests to add

Named test cases, each mapped to a finding or a security requirement. Behaviour, not implementation.

## Risks and open questions

- Risks the plan accepts, with the mitigation or the reason none is needed.
- Questions only the human can answer. Each with a default the builder takes if no answer comes.

## Out of scope

What was deliberately left out, so the builder does not drift into it.

## Panel record

| member | model | wave | findings | accepted | rejected (reason) |
|---|---|---|---|---|---|

Deviations from the default panel and why.

---

## Orchestrator's completeness audit

Run this against the final draft before delivery. Every line is a yes or a fix.

- [ ] Every panel finding is either integrated into a step or listed as rejected with a reason in the panel record.
- [ ] Every security requirement names the step that satisfies it.
- [ ] Every reuse item is used by a step, or the plan says why not.
- [ ] Every path in Changes either exists today (checked) or is marked new.
- [ ] Every step has a Verify line that is a command or a concrete check.
- [ ] Steps are in an order that builds; no step depends on a later one.
- [ ] No vague verbs: "handle", "ensure", "properly", "as needed", "etc."
- [ ] Data shapes are derived from the caller's usage, not the other way round.
- [ ] Open questions are real unknowns, each with a default.
- [ ] The rejected alternative is stated.
- [ ] A fresh agent could build from this plan without the conversation.
