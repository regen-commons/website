-- Every table in an exposed schema has row-level security on.
--
-- A schema is exposed when the anon or authenticated role may use it: a table
-- there is one grant away from the Data API, so row-level security must already
-- be on. Supabase's own schemas are left to Supabase.
--
-- known_gaps is a shrink-only baseline of tables that lacked row-level security
-- when this check was added. It may only lose entries: the check fails on a new
-- gap, and on an entry that is fixed or gone, so the list is trimmed in the
-- same change that fixes it. Never add an entry to make a new table pass.
begin;

do $$
declare
  known_gaps constant text[] := array[]::text[];
  managed constant text[] := array[
    'pg_catalog', 'information_schema', 'pg_toast',
    'auth', 'storage', 'realtime', '_realtime', 'extensions', 'graphql',
    'graphql_public', 'vault', 'pgsodium', 'pgsodium_masks', 'net',
    'supabase_functions', 'supabase_migrations', 'cron', 'pgbouncer', 'pgtle'
  ];
  new_gaps text;
  stale text;
  checked integer;
begin
  with exposed_tables as (
    select format('%I.%I', n.nspname, c.relname) as name, c.relrowsecurity as protected
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where c.relkind in ('r', 'p')
      and n.nspname <> all (managed)
      and n.nspname not like 'pg\_temp\_%'
      and (has_schema_privilege('anon', n.oid, 'USAGE')
        or has_schema_privilege('authenticated', n.oid, 'USAGE'))
  )
  select count(*), string_agg(name, ', ' order by name) filter (where not protected and name <> all (known_gaps))
  into checked, new_gaps
  from exposed_tables;

  if checked = 0 then
    raise exception 'No exposed tables found: the anon and authenticated roles or the migrations are missing, so this check proves nothing.';
  end if;

  if new_gaps is not null then
    raise exception 'Row-level security is off on exposed tables: %. Enable it in a new migration (alter table ... enable row level security) with policies and grants for each caller, and prove denial in a SQL suite.', new_gaps;
  end if;

  select string_agg(gap, ', ' order by gap) into stale
  from unnest(known_gaps) as gap
  where not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where format('%I.%I', n.nspname, c.relname) = gap
      and not c.relrowsecurity
      and (has_schema_privilege('anon', n.oid, 'USAGE')
        or has_schema_privilege('authenticated', n.oid, 'USAGE'))
  );

  if stale is not null then
    raise exception 'Remove from known_gaps in supabase/tests/row-level-security.sql, now protected, unexposed or gone: %', stale;
  end if;

  raise notice 'Row-level security is on for all % exposed tables.', checked;
end
$$;

rollback;
