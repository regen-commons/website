# Import the Notion exports

The supplied exports and four recovered application messages were imported into
Regen Commons / Website Supabase on 29 October 2026, after local PostgreSQL 17
rehearsals and explicit user approval of the schema and import. The applied
[content-management migration](../supabase/migrations/20261030030022_content_management.sql)
matches hosted migration version `20261030030022`. The production website has
not switched providers; runtime configuration and production cutover remain open.

## Reconciled scope

| Data | Prepared result |
| --- | --- |
| Membership source pages | 25, including one explicitly approved duplicate merge |
| Member profiles | 24: 19 published, 5 unpublished; 20 individuals and 4 organizations |
| Private membership requests | 19 completed source applications and 4 recovered pending submissions |
| Seeds | 17 published; missing authors remain anonymous |
| Contributions | 10 published, with 17 contributor links |
| Affiliations | 2 individual-to-organization links |
| Participant feedback | 8 responses retained privately |
| Source files | 68 CSV/Markdown files, 246,576 bytes, all verified by SHA-256 |

The full and view CSVs were compared as multisets, allowing column and row
reordering. The feedback view omits fields that exist in the full export; those
fields are preserved. Markdown pages were matched to CSV rows through their
properties and source IDs. Both directions of contributor relationships agree.
No unmatched rows or relations remain. The six missing member types and one
duplicate merge were confirmed by the user; the decisions are in the private
import manifest, not in source code.

Only source status `Active` becomes published. Blank source statuses stay draft.
An active source application receives descriptive state `legacy_active`; this
does not invent an acceptance event or decision authority. Recovered submissions
remain pending, with their supplied answers and failure reason preserved. They
do not create member profiles, Auth accounts, roles, or notification jobs.

The exports provide application dates without time zones or times. Member
`applied_at` retains those calendar dates, as do the original application answers.
Exact application submission timestamps stay null. Missing Contribution dates
also stay null. New database creation timestamps describe import-time row
creation, not an inferred historical creation time.

## Prepare a private import

Keep the supplied folders and paired CSVs together. The current importer supports
the four supplied collection folders: Membership Application Database,
Contributions, Seeds, and Participant Feedback. Other portal folders are outside
this import. Unknown files, attachments, or nested folders stop preparation;
they must be mapped before proceeding. These supplied collections contain only
CSV and Markdown files, with no attachment bytes to upload to Storage.

```sh
node scripts/prepare-notion-import.js /absolute/path/to/portal \
  /private/path/to/decisions.json /private/path/to/recovered.json \
  artifacts/private-notion-import
```

The decisions file uses `version: 1`, `member_types` keyed by source page ID, and
`member_aliases` mapping each explicitly approved duplicate to its canonical
source page. The recovered file is an array of objects with a stable `source_id`,
the supplied `error`, and an `answers` object using the membership form's keys.
Use an empty array when there are no recovered submissions. Keep both files
private. Preparation rejects overlapping recovery emails for explicit
reconciliation; it never merges applications by matching email or name.

The command prints counts and digests only. It creates a new private directory
under ignored `artifacts/`, with mode 700 and files mode 600. It refuses to reuse
an existing output directory. It performs no database or notification calls.

- `plan.json` contains the reviewed mapping and source evidence.
- `import.sql` applies the complete import in one transaction.
- `stage-*.sql` transfers bounded pieces into the private import archive;
  `apply-staged.sql` checks their combined digest and applies the same complete
  import in one transaction. A partial or corrupted transfer cannot create
  operational records. Temporary staging rows are removed on success.

Do not commit any of these outputs. CSV and Markdown source files, including
full text, headers, otherwise unmapped fields such as Contribution links, and
file checksums are retained in `private.import_records`. This preserves the
source beyond the operational projections. Feedback is an archive in this
slice; the dashboard does not yet provide a feedback-management view.

## Apply and reconcile

First verify the intended Supabase project, apply the approved versioned schema,
and inspect its advisors. The importer requires initially empty operational
tables and refuses a different existing import batch. It uses a short lock
timeout and one transaction to insert profiles, private requests, content,
relations, source evidence, and a batch receipt. It does not overwrite existing
production records. Source text is quoted data throughout, never SQL or agent
instructions.

A repeat of the exact reviewed plan skips entity writes, preserving subsequent
steward edits. Changing a source export or mapping produces a different plan
identity and requires explicit reconciliation. This tool is an initial import,
not an ongoing Notion synchronization process.

After application, compare row counts and states against the manifest, check all
file byte lengths and SHA-256 digests, compare private original answers, inspect
public projections as `anon`, and verify that notification jobs remain empty.
Retain the batch receipt. Hosted PostgREST, real Auth, and final production
cutover need their own verification; local SQL does not establish them.

The [content-management gates](content-management.md#export-inventory-and-migration-gates)
still own environment provisioning, the final source delta/write pause, cache
purge, deployment, live-provider proof, and eventual Notion credential retirement.
Do not delete or retire the source while those gates are open.

## Verification

`npm test` covers CSV projection conflicts, same-name identity handling, explicit
merges, missing types, recovered-email overlap, unknown attachments, symlinks,
exact source-file hashes, deterministic plans, and modified-plan rejection.

In an empty disposable PostgreSQL database, apply the test-only Auth stubs and
the versioned migrations, then run:

```sh
REGEN_IMPORT_SQL_TEST=synthetic-local-only node scripts/verify-notion-import-replay.js
```

This writes synthetic records and must not run against hosted Supabase. It uses
the normal `psql` connection environment. CI runs it after the SQL permission
suites. It verifies incomplete-transfer rejection, rejection of nonempty
targets, successful staged import, preserved Unicode and quoting, repeat imports
after a steward edit, changed-plan rejection, and anonymous read boundaries.

The actual supplied dataset was also rehearsed in two separate disposable local
databases, using both direct and staged transfers. Both produced the counts above,
verified all 68 source file digests and original application answers, exposed
only the 19 published members/17 Seeds/10 Contributions to `anon`, and created
no notification jobs or fabricated authorship events. Those private rehearsals
are separate from the synthetic tests committed to Git.

## Hosted reconciliation

The hosted import receipt records plan checksum
`24e1f132b9a28df3b0517b8c42da08e324a073cbc8c2df183640b88598b7d68b`
and source snapshot checksum
`2c4b970c984ae46645fc86a9331de953c0fc9029476d4f40f81679c47c679db6`.
One batch is recorded and no temporary staging rows remain. Hosted counts match
the table above. All source file byte lengths and SHA-256 digests, original
application answers, and recovered answers match the prepared import. There are
no notification jobs or fabricated content-authorship events.

Queries under the actual `anon` database role expose 19 members, 17 Seeds, and
10 Contributions. Anonymous access to applications and the source archive is
denied, and the archive is also denied to ordinary authenticated users. All
exposed tables have RLS enabled. The website's real Supabase SDK adapter was
also exercised against hosted PostgREST using the project's publishable key;
public reads return those same counts without private fields, and private HTTP
reads are rejected.

Post-change advisors report intentionally closed private tables with RLS and no
client policies, plus unused-index information for the new workload. The
pre-existing [leaked-password protection setting](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
is unchanged. No Auth users or steward roles were created, and no real mail or
Telegram messages were sent. The intake capability remains unprovisioned until
runtime configuration and cutover are authorized.
