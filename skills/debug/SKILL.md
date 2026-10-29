---
name: debug
description: Diagnose and fix Regen Commons UI, API, local-development, or data-access failures with a reproducible symptom and evidence of the cause. Use for bug reports, failing tests, or unexpected behavior.
---

# Debug Regen Commons

Read the [root guide](../../AGENTS.md), the owning scoped guide, and
[local setup](../../docs/development.md). Preserve the requested posture:
investigation reports findings; an authorized fix includes implementation and
verification. Urgency does not authorize deployment or live data changes.

## Reproduce at the failing boundary

Capture expected versus observed behavior, the route or command, inputs, and
environment. Use synthetic equivalents for private records; keep codes, tokens,
and application answers out of logs and shared evidence. Inspect focused diffs
and history rather than assuming concurrent edits caused the failure.

- **Visible UI or interaction:** start with the rendered page and actual control.
  Inspect geometry, computed styles, focus, event handling, and whether state
  changes. Trace from that element into the script and request only as evidence
  requires. An invisible control is not automatically missing data.
- **Read/write or authentication:** start with the failing status and response.
  Trace caller → handler → provider → policy/schema. Verify the environment and
  current authorization boundary before changing code. Do not bypass role checks
  or row-level security to make an empty query return data.
- **Local tooling:** check the documented Node version, package scripts, port
  ownership, and fixture/live mode before changing dependencies or configuration.

For frontend reproduction, inspect both the page's inline code and shared
scripts. Use [site-development](../site-development/SKILL.md) for local execution.
The scenario controls in `scripts/lib/scenarios.js` support repeatable failures;
inspect which routes each scenario affects. Scenario state is shared by all tabs
on that server: coordinate its use or start an owned server on a free port, and
restore the normal scenario afterward. Do not stop another chat's server.

## Test a concrete hypothesis

Establish a repeatable signal that fails for the reported symptom, not an
unrelated setup problem. State a specific cause hypothesis and run a small check
that could disprove it. Change one causal variable at a time. If successive fixes
do not alter the signal, revisit the hypothesis and boundary instead of stacking
workarounds. Record what is unknown when reproduction is unavailable.

Read the full failure before treating generic network errors as a diagnosis.
Distinguish request rejection, provider failure, empty data, session denial, and
rendering failure. For saves, distinguish confirmed persistence from notification
failure or an uncertain response; a retry can duplicate a remote write.

## Fix and prove the result

Apply the smallest coherent fix within the authorized scope. Add a regression
check at the layer that owns the defect when it protects meaningful behavior;
show that the original trigger fails before the fix and passes afterward when
feasible. Check direct consumers for the same cause without expanding into an
unrelated cleanup. Use [plan](../plan/SKILL.md) when a repair needs a consequential
cross-layer design decision.

Run the root checks for implementation changes, then repeat the original failing
flow. For UI fixes, inspect the rendered interaction and relevant retry/empty/
loading states at the affected widths. For database policies, use the
[database guide](../../supabase/AGENTS.md): fixture tests do not prove SQL access
control. Report the cause, fix, exact evidence, and remaining uncertainty.
Do not claim the original symptom is fixed from a different passing test.
