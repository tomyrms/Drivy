-- Restore cluster only: minimal roles referenced by the canonical migrations
-- (GRANT ... TO / CREATE POLICY ... TO). NOLOGIN, no password, no attribute
-- copied from any other cluster. pg_dump does not export global roles.
CREATE ROLE drivy_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
CREATE ROLE drivy_invitation_mailer NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;
