-- Operator-only provisioning. Run before the owner migration; no LOGIN or password here.
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_web_commands') THEN
    CREATE ROLE drivy_web_commands NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_web_maintenance') THEN
    CREATE ROLE drivy_web_maintenance NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('drivy_web_commands','drivy_web_maintenance')
    AND (rolcanlogin OR rolsuper OR rolcreatedb OR rolcreaterole OR rolbypassrls)) THEN
    RAISE EXCEPTION 'Unsafe command journal role';
  END IF;
END $$;
-- Grant drivy_web_commands ONLY to the dedicated runtime login (NOINHERIT).
-- Grant drivy_web_maintenance ONLY to the operator/owner used over SSH.
-- The runtime must not be a member of drivy_web_maintenance or the DDL owner.
