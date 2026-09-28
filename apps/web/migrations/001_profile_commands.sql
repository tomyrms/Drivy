CREATE TABLE drivy_web.profile_command (
  operation_id uuid PRIMARY KEY,
  issuer text NOT NULL CHECK(length(issuer) BETWEEN 1 AND 2048),
  subject text NOT NULL CHECK(length(subject) BETWEEN 1 AND 255),
  person_id uuid NOT NULL,
  school_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  access_epoch integer NOT NULL CHECK(access_epoch>0),
  kind text NOT NULL CHECK(kind IN('PROFILE','POLICY_CREATE','POLICY_PUBLISH')),
  target_id uuid NOT NULL,
  expected_version integer NOT NULL CHECK(expected_version>0),
  key_id text NOT NULL CHECK(key_id ~ '^[A-Za-z0-9._-]{1,64}$'),
  sealed bytea NOT NULL CHECK(octet_length(sealed)>28),
  state text NOT NULL DEFAULT 'PREPARED' CHECK(state IN('PREPARED','SUBMITTED','UNCERTAIN','COMMITTED','REJECTED','CANCELLED')),
  revision integer NOT NULL DEFAULT 1 CHECK(revision>0),
  review_hash text CHECK(review_hash ~ '^[a-f0-9]{64}$'),
  review_session_hash text CHECK(review_session_hash ~ '^[a-f0-9]{64}$'),
  lease_id uuid,
  lease_until timestamptz,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  updated_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  finished_at timestamptz,
  CHECK((lease_id IS NULL)=(lease_until IS NULL)),
  CHECK((review_hash IS NULL)=(review_session_hash IS NULL)),
  CHECK((state IN('COMMITTED','REJECTED','CANCELLED'))=(finished_at IS NOT NULL))
);
CREATE UNIQUE INDEX command_one_open_owner ON drivy_web.profile_command(issuer,subject)
  WHERE state IN('PREPARED','SUBMITTED','UNCERTAIN');
CREATE INDEX command_owner_recent ON drivy_web.profile_command(issuer,subject,created_at DESC,operation_id);
ALTER TABLE drivy_web.profile_command ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy_web.profile_command FORCE ROW LEVEL SECURITY;
CREATE POLICY command_identity_scope ON drivy_web.profile_command TO drivy_web_commands
  USING(issuer=nullif(current_setting('web.issuer',true),'') AND subject=nullif(current_setting('web.subject',true),''))
  WITH CHECK(issuer=nullif(current_setting('web.issuer',true),'') AND subject=nullif(current_setting('web.subject',true),''));
CREATE POLICY command_maintenance ON drivy_web.profile_command TO drivy_web_maintenance USING(true) WITH CHECK(true);
GRANT USAGE ON SCHEMA drivy_web TO drivy_web_commands,drivy_web_maintenance;
GRANT SELECT,INSERT ON drivy_web.profile_command TO drivy_web_commands;
GRANT UPDATE(state,revision,review_hash,review_session_hash,lease_id,lease_until,updated_at,finished_at)
  ON drivy_web.profile_command TO drivy_web_commands;
GRANT SELECT ON drivy_web.profile_command TO drivy_web_maintenance;
GRANT UPDATE(key_id,sealed,revision,updated_at) ON drivy_web.profile_command TO drivy_web_maintenance;
-- Purge is limited further by a restrictive RLS policy. Unknown outcomes are never deletable by maintenance.
CREATE POLICY command_purge_known ON drivy_web.profile_command AS RESTRICTIVE FOR DELETE TO drivy_web_maintenance
  USING(state IN('COMMITTED','REJECTED','CANCELLED') AND lease_id IS NULL);
GRANT DELETE ON drivy_web.profile_command TO drivy_web_maintenance;
