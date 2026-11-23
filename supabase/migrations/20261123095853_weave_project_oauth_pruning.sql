-- Records Weave's supabase/candidates/weave-project-oauth-pruning.sql. Applied to the shared Platform
-- project (ztygpuzldujfsqrubxic) on 23 November 2026 as plain SQL, as postgres, the table's owner, so
-- Platform runs job weave-project-oauth-prune before its migration history lists this version.
-- Running it again there leaves that one job as it is.
--
-- weave_project_oauth.records holds short-lived consent state and the Certified project grants, all
-- encrypted. Every read already ignores a row past its expires_at, and signing out deletes that
-- session's grants. A session that lapses without a sign-out leaves its grant behind, and nothing
-- else removes expired rows. This job deletes them once a day, so an expired grant's tokens do not
-- stay in the database.
--
-- The job runs as the role that schedules it. The table has row-level security with a policy for the
-- runtime role only, so it must be scheduled by the table's owner (or a role that bypasses row-level
-- security): any other role's job deletes nothing and reports no error. This migration refuses to
-- schedule it as any other role. It needs no new grant for weave_project_oauth_runtime, and it
-- touches no other table.
--
-- pg_cron installs only in the database its cron.database_name setting names, postgres on Platform,
-- and runs jobs only there. In any other database, such as the disposable one CI replays migrations
-- into, there is no scheduler, so this migration schedules nothing and says so in a notice.
--
-- cron.schedule with a name the scheduling role already uses updates that job in place, so the same
-- name, schedule and command keep one job with its existing jobid.
do $migration$
begin
  if current_database() is distinct from current_setting('cron.database_name', true) then
    raise notice 'weave-project-oauth-prune not scheduled: % is not the pg_cron database', current_database();
    return;
  end if;

  create extension if not exists pg_cron;

  if current_user <> (
    select pg_get_userbyid(relowner) from pg_class where oid = 'weave_project_oauth.records'::regclass
  ) and not (select rolsuper or rolbypassrls from pg_roles where rolname = current_user) then
    raise exception 'schedule weave-project-oauth-prune as the owner of weave_project_oauth.records, not %', current_user;
  end if;

  perform cron.schedule(
    'weave-project-oauth-prune',
    '17 3 * * *',
    $$delete from weave_project_oauth.records where expires_at <= now()$$
  );

  if (select count(*) from cron.job where jobname = 'weave-project-oauth-prune') <> 1 then
    raise exception 'expected exactly one weave-project-oauth-prune job';
  end if;
end
$migration$;
-- To check that it is scheduled: select jobname, schedule, active from cron.job where jobname = 'weave-project-oauth-prune';
-- To check that it ran and deleted rows: select status, return_message, start_time from cron.job_run_details
--   where jobid = (select jobid from cron.job where jobname = 'weave-project-oauth-prune') order by start_time desc limit 5;
-- To remove: select cron.unschedule('weave-project-oauth-prune');
