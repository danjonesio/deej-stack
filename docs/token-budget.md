# Token budget: where the skills spend, and depth modifiers

Working note, 2026-09-08. An audit of where `/d-plan` and `/d-implement` burn tokens today, ranked by size, and a sketch of user-facing depth modifiers. Nothing here is implemented yet.

## Where the tokens go

A standard `/d-plan` run is ~7 fresh spawns + 3 resumes; `/d-implement` adds 3+ reviewers + re-checks. Ranked by estimated cost:

1. **Every wave-1 member re-explores the codebase independently.** Five members each read and search the repo from scratch. This is the dominant cost and is mostly by design — independent lenses are the product. Wave-2 resumes already avoid paying it twice; keep that. The only real dial here is panel size (see modifiers).

2. **Draft v1 is pasted in full into ~5 wave-2 messages** (`skills/d-plan/SKILL.md` Phase E; `{DRAFT_V1}` in `reviewer-prompt.md`). The draft already exists on disk by Phase D. Pass the file path and "read it" instead: members have repo access and pay the read either way, but the orchestrator stops emitting the whole plan five times and its own window stays small. `/d-implement` already has the right rule for the diff ("give reviewers the diff command, not the diff") — this is the same rule applied to the draft.

3. **`/d-implement` Phase G pastes "the plan in full, the build record so far" into every reviewer prompt** (×3+, plus re-checks). Both are files (the record is even committed). Same fix: paths, not text. Extend the existing diff-command rule to cover plan and record.

4. **Brief + codebase map duplicated into every wave-1 prompt** (×7). Could be one briefing file referenced by path. Smaller win than 2–3 because the map is capped at ~60 lines; only worth doing if 2–3 land anyway, since it is the same mechanism.

5. **Fixed panel size regardless of task size.** A five-string copy sweep pays the same 9–10 runs as a new subsystem. This is the modifier problem below, not a prose fix.

Already token-conscious, keep as is: the 60-line map cap, "read each report once, integrate, move on", resumes over fresh spawns, the one-extra-loop cap in Phase F, re-checks limited to members whose findings were fixed.

## Depth modifiers

The Rules already let the user trim in free text ("just security and dedup", "quick plan", "no review"). Named tiers make that predictable and give the orchestrator a number instead of a judgement call.

Constraints: harness-neutral (plain words in the ask, no flags only one harness parses); folds into the existing single question round (d-plan Phase A.4, d-implement Phase A.3 — both question tools take multiple questions in one call, so "depth" rides along with "panel model" when the ask names neither); counts live in each `panel.md` `## Sizing` section only, so there is one source.

### `/d-plan <ask> [quick|standard|deep]`

| tier | wave 1 | wave 2 | ~runs |
|---|---|---|---|
| quick | `architect`, `skeptic` (+ `security-analyst` if the brief touches an entry point, auth, or user input) | none; orchestrator runs the completeness audit itself | 2–3 |
| standard (default) | the five minimum | 2 fresh + resumes | 9–10 |
| deep | five + situational per the include column | full, + the Phase F loop when earned | 12+ |

The plan template stays identical across tiers — it is the contract `/d-implement` reads. Quick changes who stress-tests the plan, not what the plan contains. Panel record notes the tier.

### `/d-implement <plan> [review: none|quick|standard|deep]`

| tier | panel | ~runs |
|---|---|---|
| none | skip Phase G, recorded in the review table | 0 |
| quick | `code-reviewer` | 1 + re-check |
| standard (default) | `security-analyst`, `code-reviewer`, `skeptic` | 3 + re-checks |
| deep | standard + situational analysts from the plan's panel record | 4+ |

### Open questions

- Does quick d-plan keep `security-analyst` always, rather than conditionally? Cheapest safe answer is always (3 runs); the conditional saves one run and adds a judgement call.
- Should quick also default the panel model to "same as session" and skip the question entirely? That removes the one deliberate checkpoint; leaning no — fold, don't skip.
- Tier words in the ask vs. always asking: proposal is words win, question only when absent, mirroring how the panel model works today.

## Related

These edits should land together with the Cursor-compliance hardening from the 2026-09-07 session (roster names in the todo template, spawn config inlined at the spawn points, "do not hand a step to a sub-agent" moved to the intro, d-implement writing a chat-pasted plan to `docs/plans/` before building). Both touch the same phases in both SKILL.md files; one pass, one version bump.
