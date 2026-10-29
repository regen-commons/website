---
name: plan
description: Plan multi-step Regen Commons changes, compare architecture options, or assess progress against acceptance criteria. Use for work spanning UI, API, or data boundaries; routine edits do not need a written plan.
---

# Plan Regen Commons work

Read the [root guide](../../AGENTS.md) and the scoped guides it routes to. Ground
the plan in the owning code, callers, tests, and the user's current decisions.
Use [debug](../debug/SKILL.md) first when the work starts with unexplained failure.

## Establish the intended outcome

- Identify observable acceptance criteria, affected surfaces, and consequential
  unknowns. Separate confirmed requirements from implementation suggestions.
- Inspect local sources before asking for facts. Resolve routine reversible
  choices with judgment; ask about missing product authority or decisions that
  materially change scope while continuing independent work.
- For architecture exploration, describe the current problem, affected callers,
  a small viable change, its tradeoffs, and evidence of benefit. Present options
  when a real choice exists. Exploration alone does not authorize implementation.

## Keep one useful plan

[docs/work-plan.md](../../docs/work-plan.md) owns repository priorities and
acceptance criteria. Reuse an existing linked feature plan. Add a focused document
under `docs/` only when the work needs durable detail beyond that list, and link
it from the work plan. A short task can keep its plan in the chat.

Record only what the next contributor needs:

- Outcome, scope, and explicit exclusions or unresolved decisions.
- Ordered steps with owning paths, dependencies, and observable proof.
- Consequential decisions and their rationale.
- Current progress, remaining work, and evidence or blockers.

Keep steps independently verifiable where practical. Sequence contract changes
through the owning data/API boundary, fixtures, and browser caller; preserve a
working path between steps. For provider migrations, distinguish schema creation,
data reconciliation, private steward access, public reads, intake writes, and
cutover. Plan compatibility and recovery before changing an active provider.
Consult the [database guide](../../supabase/AGENTS.md) for data semantics and
authorization; do not treat a profile draft as an acceptance decision.

## Execute and coordinate

When implementation is authorized, carry the accepted work through verification.
Do not impose approval pauses after an arbitrary number of steps. Update the
plan when evidence changes the approach or reveals a genuine blocker.

For concurrent work, agree on owning paths and interface dependencies. When the
user authorizes chat coordination, send a bounded handoff with the objective,
files, contract, and expected proof. Share completion evidence before another
chat consumes the result. Do not switch a shared branch, stage another chat's
files, or start extra agents merely because the plan has multiple steps.

## Assess progress and close

Compare acceptance criteria with implementation and evidence, marking each as
complete, partial, blocked, or outside scope. File existence is not completion.
Use the [root verification rules](../../AGENTS.md#workflow) and
[site-development](../site-development/SKILL.md) to select proof.

Record what changed, checks actually run, remaining dependencies, and the next
action. Separate implementation, commit, PR, merge, deployment, and live-provider
verification; completing one does not establish the others. Update the owning
plan without deleting history or silently dropping unfinished criteria. Route
authorized commits or PR work through [ship](../ship/SKILL.md). External issue
updates and messages follow the user's authorization, not the plan's existence.
