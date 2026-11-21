## Why

What problem this solves, in one or two sentences.

## Measured

The numbers or observations that show the problem, and what changed.

- Agent: <agent>, model <model>, effort <effort>

<!-- An agent fills the line above with what `~/.agents/evals/bin/agent-model --pr` prints, read from its own session log; `dev evals scoreboard` reads it. Leave it out for work no agent made. -->

## Verification

Tier: <critical | sensitive | routine> (`.agents/merge-policy.json`)

The checks that ran, with their commands and results. Routine: a targeted
check plus the required CI checks. Sensitive: also a fresh agent's adversarial
review naming the head SHA. Critical: the full gate (CI `check` and `database`,
rendered proof for UI) and that review, then afo's go before merging, because
a merge into `main` is the production release. Label UI proof with browser,
viewport (375 and 1280 wide) and color scheme, as rendered local fixtures.

## Not verified

What was not checked, and why: for example live email, Telegram or Vercel
behavior that fixtures cannot prove. The repository is public: no real
applicant data, contact details or private captures here.
