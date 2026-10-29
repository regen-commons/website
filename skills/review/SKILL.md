---
name: review
description: Review a Regen Commons diff, branch, PR, or named files for regressions, requirement gaps, and verification quality. Use for change reviews and readiness questions; remain read-only unless fixes are authorized.
---

# Review Regen Commons changes

Read the [root guide](../../AGENTS.md) and applicable scoped guides. Resolve the
reviewed paths or commit range and the requirement baseline before drawing a
conclusion. Use the user's request, explicit acceptance criteria, PR description,
and relevant [work-plan](../../docs/work-plan.md) item; never infer requirements
or issue identity from a branch name alone.

For working-copy review, inspect staged, unstaged, and relevant untracked files.
For a PR, verify its actual base and head and inspect the complete changed range.
Report the scope and any unreviewed portion. Read direct callers and affected
contracts; keep a focused diff review bounded to that change.

## Check regressions and boundaries

Trace observable behavior through the owning layers. Prioritize these when the
diff touches them:

- Save feedback, duplicate/retried writes, stale async results, and independent
  loading, empty, error, and retry states.
- Public versus private projections, current steward/session authorization,
  cookie/origin/cache behavior, and RLS coverage. Read every changed line in
  authorization, migration, or private-data handling paths.
- Provider error and timeout handling; distinguish saved data from delivery of
  email or other notifications. Local fixtures must not fall through to live
  services.
- Separation of submitted answers, curated profiles, review decisions, and
  publication; do not invent authority to fill an intentional product boundary.
- Changes to dependencies, CI, agent instructions, or verification scripts that
  weaken checks, expand permissions, or rely on uncommitted companion files.

For new abstractions, compare the closest existing implementation and the actual
behavior gap. Report concrete coupling or maintenance harm, not a preference for
a framework, file size, or extra layers. For tests, ask which distinct failure
the assertion catches; mocked answers alone do not prove the mocked boundary.

## Check completeness against intent

Map the acceptance criteria to implementation and evidence. Separate missing
work, blocked proof, and intentionally excluded behavior. Check affected route
wiring, setup instructions, environment examples, fixtures, and error states.
For guidance or skills, verify local references, command availability, discovery,
instruction hierarchy, and authorization boundaries. Do not require runtime tests
for prose-only changes.

## Obtain proportionate evidence

Run targeted, non-destructive checks needed to establish or reject findings.
Use the root verification rules for implemented changes and
[site-development](../site-development/SKILL.md) for browser proof. Report commands,
results, tested revision or working-copy state, and material limits. Tests that
write to a remote provider need the user's authorized target and scope.

For an explicit PR/merge-readiness assessment, require applicable local proof and
passing required CI on the PR's current head SHA. Pending, unavailable, failed,
or stale-head checks do not support approval. A local-only review may establish
local evidence; fixture success does not establish hosted auth, delivery, or
deployment readiness. Do not post a GitHub review unless the user requests it.

## Report and close findings

Lead with actionable findings in severity order. Each needs a path and line,
concrete failure or missing requirement, its impact, and a credible next step.
State evidence gaps separately. If none are found, say so with the reviewed
scope and limits instead of inventing issues.

When fixes are authorized, address the root cause, check direct consumers for
recurrence, and rerun the relevant proof. Recheck the final diff before closing
the finding. Review permission alone does not authorize edits, issue creation,
merge, deployment, or publishing review comments.
