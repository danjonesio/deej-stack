# The panel

Every panel member is an Opus 5 sub-agent spawned per the Harness table in `SKILL.md`, carrying a `name` from the tables below. Build each prompt from [`reviewer-prompt.md`](reviewer-prompt.md). Members never edit files; they read, search, and report.

The orchestrator decides the situational members in Phase A and records the decision in the plan's panel record. When in doubt, include the member: a wasted analyst costs minutes; a missed migration or auth gap costs the build.

## Wave 1: analysts

Run on the brief and the codebase map, before any draft exists. All wave-1 members run concurrently, spawned in one message.

| name | include | produces |
|---|---|---|
| `architect` | always | Draft plan v0 shaped per [`plan-template.md`](plan-template.md): caller's usage first, then data shapes, module map, interfaces and signatures, files to add or change (by path), and the work sequenced into units that each end in a verifiable state. Names the simplest design that meets the brief and one alternative it rejected, with the reason. |
| `reuse-scout` | always | Reuse inventory. Existing helpers, components, hooks, services, schemas, fixtures, and tests the plan must build on, each by path with a one-line note on what it does. Where the ask overlaps behaviour that already exists. Conventions the new code must follow (naming, error handling, state, styling, logging, config) with an example path for each. The dedup lens: the plan may not introduce a second way to do something the codebase already does. |
| `security-analyst` | always | Threat model for the change. Trust boundaries the work touches; auth and authz on every new or changed entry point; input validation and output encoding; secrets and config; data exposure in responses, logs, and errors; dependency and supply-chain risk; abuse and misuse cases. Output is a list of requirements the plan must satisfy, each tied to a route, file, table, or component. OWASP Top 10 / ASVS lens for web apps, platform security guides for mobile and desktop. |
| `data-analyst` | persistence, schema, migrations, caching, or external data touched | Schema changes and their migration order, backfills, rollback, indexes, constraints, data volume, consistency under concurrent writers, and what existing queries change. |
| `ux-api-designer` | user-facing UI, or an API another party consumes | Flows and screens; every state (empty, loading, error, partial, offline); accessibility; copy; API contract with request and response shapes, error shape, pagination, versioning, and backwards compatibility. |
| `ops-analyst` | CI, deploy, env vars, config, infra, feature flags, or third-party services touched | Env and config changes with where they are set; CI changes; deploy and rollout order; flags; observability (logs, metrics, alerts) for the new behaviour; rollback. |
| `perf-analyst` | hot paths, large data sets, realtime, N+1 risk, or a stated performance target | Baselines to measure first, budgets, query and render cost, caching, load shape, and what to instrument. |

## Wave 2: reviewers

Run on draft v1 (the orchestrator's synthesis of wave 1). All wave-2 members run concurrently.

| name | how | lens |
|---|---|---|
| `code-reviewer` | fresh | Would this plan, executed as written, produce correct code? Edge cases and error paths per step; every unit ends in a state the builder can check; verification steps are concrete commands, not "test it"; complexity budget (abstractions that serve one call site, config for cases that don't exist, "just in case" paths); steps that are vague enough to be implemented two different ways. |
| `skeptic` | fresh | Challenge the plan's assumptions and the brief's completeness. Requirements the plan silently drops or invents; the simpler design that was not considered; what else breaks (blast radius); questions that must be answered before building, as opposed to during; places where the plan trusts a self-report instead of an artifact. |
| `security-analyst` | resumed | Adversarial pass over the concrete steps: is every wave-1 requirement mapped to a step, and does any new step open a hole the threat model missed? |
| `reuse-scout` | resumed | Dedup pass: does any step re-implement something in the reuse inventory, or add an abstraction beside an existing one? |
| situational analysts | resumed | Each re-checks the draft through its own lens. |

Resume a wave-1 member (per the Harness table in `SKILL.md`) rather than spawning a new one; it already holds the codebase context it built. Spawn fresh only when the resume fails.

## Sizing

- Minimum panel: `architect`, `reuse-scout`, `security-analyst`, `code-reviewer`, `skeptic`. Five Opus runs plus two resumes.
- Typical web app feature: minimum plus `data-analyst` and `ux-api-designer`.
- The user can trim the panel ("just security and dedup") or swap the model ("use sonnet for the panel"). Record any deviation from the default in the panel record.
