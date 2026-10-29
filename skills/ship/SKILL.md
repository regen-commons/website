---
name: ship
description: Validate and commit Regen Commons changes, or push and open a draft PR when requested. Use for explicit commit, publication, or readiness requests; ordinary coding does not authorize Git publication.
---

# Commit and publish Regen Commons changes

Use the [root guide](../../AGENTS.md) and the user's authorized scope. Complete
only the requested stage: a commit request ends after a verified local commit;
a push or draft-PR request includes the necessary publication steps. A readiness
question or dry run performs checks without Git mutations. Do not ask again for
actions the user has already authorized. Merge, deployment, remote schema changes,
and messages to other people require their own authorization.

## Establish ownership and Git context

Inspect the current branch, `git status --short`, staged diff, and task paths.
Before publication also verify the remote, existing PR, and its base/head. Use
the PR base when present; otherwise inspect the remote's default branch. Do not
import Green Goods' branch defaults or assume a branch from a previous task.

In a shared checkout, coordinate ownership and staging/commit timing with the
other authorized chat. Keep its files and index entries untouched. A dirty tree
outside the task's paths does not by itself block a bounded commit. If another
chat has staged files or changed the branch/head during preparation, resolve that
conflict before committing; never clear its index or switch its active branch.
Use `codex/` for new task branches when a new branch is needed and safe to create.

## Validate the actual change

Inspect the complete proposed diff, including new files. Follow the root checks:

- Implementation changes: `npm run check`, `npm test`, and `npm run smoke`, plus
  relevant behavioral proof from the owning guide.
- Documentation/agent guidance only: validate links, routing, skill metadata,
  referenced commands, and consistency with the owning code. A commit alone
  does not justify running application suites.

Use [site-development](../site-development/SKILL.md) for local browser evidence
and [review](../review/SKILL.md) when a change review is requested or needed.
Validate a self-contained snapshot if unrelated working changes could mask a
missing dependency. Label working-copy proof honestly and record unresolved
checks; a failed required check blocks a completion claim. Re-run proof when
the relevant files or dependencies change, not merely to increase check counts.

## Make the bounded commit

Stage exact task paths, then inspect the entire cached diff and run
`git diff --cached --check`. Exclude credentials, private records, generated local
artifacts, and unrelated changes. Preserve the `.agents/skills` symlink and its
canonical `skills/` files. Verify the staged path list immediately before commit.

Use `type(scope): description`, imperative mood, under 72 characters, without a
trailing period. Use the app's allowed types/scopes; `docs(agent)` fits guidance
and skills. After committing, inspect the commit's paths and verify that task
files match the commit while other chats' changes remain untouched. Do not amend,
rewrite history, or force-push as a shortcut around a conflict.

## Publish only when requested

Push the verified branch normally. For a PR, follow the
[PR template](../../.github/pull_request_template.md), use the same conventional
title format under 70 characters, open it as a draft, and apply `draft` and
`automated/codex` labels. If a required label does not exist, report the gap rather
than creating repository-wide configuration without authorization.

Keep the body focused on behavior, reason, verification results, and limits.
Use structured tool fields or a body file for multiline text. Link an issue only
when its identity and relationship are established. Verify the published PR's
head SHA, then inspect required CI for that exact revision. Pending or failed CI
and preview deployment failures must be reported separately from local checks;
do not change billing, access, or repository visibility to clear a deployment.

Finish with the commit SHA, branch, scope, proof, and any actual push/PR result.
Keep local commit success, CI status, and deployment status distinct. A local
commit-only task is complete without a push or CI run; it is not a claim of merge
or production readiness.
