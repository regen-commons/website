-- Replay-only definition of the already applied runtime roles.
-- The historical operator migration supplied passwords. Credentials never belong
-- in source control; fresh environments provision LOGIN/passwords out of band.
-- Do not reapply this recorded version to Platform or change its live logins.
create role weave_platform_bridge nologin nosuperuser nocreaterole nocreatedb noreplication nobypassrls;
grant weave_auth_runtime to weave_platform_bridge;
create role weave_platform_app nologin nosuperuser nocreaterole nocreatedb noreplication nobypassrls;
grant weave_app_auth_runtime to weave_platform_app;
