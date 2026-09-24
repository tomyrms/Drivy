-- F02 : invitation, acceptation explicite et livraison séparée du commit métier.
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_invitation_mailer') THEN
  CREATE ROLE drivy_invitation_mailer NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;
END IF; END $$;
ALTER TABLE drivy.membership ADD COLUMN invitation_email text;
ALTER TABLE drivy.membership ADD COLUMN onboarding jsonb NOT NULL DEFAULT '{}';
ALTER TABLE drivy.membership ADD CONSTRAINT membership_school_person_identity UNIQUE(school_id,id,person_id);
ALTER TABLE drivy.operation ADD COLUMN resource_version integer NOT NULL DEFAULT 1 CHECK(resource_version>0);
DO $$ BEGIN
  EXECUTE format('CREATE POLICY g1c_version_backfill ON drivy.operation TO %I USING(true) WITH CHECK(true)',current_user);
END $$;
UPDATE drivy.operation SET resource_version=coalesce((response_data->>'version')::integer,1);
DROP POLICY g1c_version_backfill ON drivy.operation;
CREATE TABLE drivy.invitation (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  email text NOT NULL CHECK(length(email) BETWEEN 3 AND 254 AND email=lower(btrim(email))),
  roles text[] NOT NULL CHECK(cardinality(roles) BETWEEN 1 AND 3 AND roles <@ ARRAY['ADMIN','INSTRUCTOR','LEARNER']::text[]),
  token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  status text NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','ACCEPTED','REVOKED')),
  version integer NOT NULL DEFAULT 1 CHECK(version>0),
  expires_at timestamptz NOT NULL,
  inviter_membership_id uuid NOT NULL,
  inviter_person_id uuid NOT NULL REFERENCES drivy.person(id),
  accepted_by_person_id uuid REFERENCES drivy.person(id),
  notice_version integer NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_reason text CHECK(length(revoked_reason) BETWEEN 1 AND 1000),
  UNIQUE(school_id,id),
  FOREIGN KEY(school_id,inviter_membership_id,inviter_person_id) REFERENCES drivy.membership(school_id,id,person_id),
  FOREIGN KEY(school_id,accepted_by_person_id) REFERENCES drivy.membership(school_id,person_id),
  FOREIGN KEY(school_id,notice_version) REFERENCES drivy.school_data_policy(school_id,version),
  CHECK((status='ACCEPTED')=(accepted_by_person_id IS NOT NULL))
);
CREATE INDEX invitation_page ON drivy.invitation(school_id,created_at,id);
CREATE INDEX invitation_email ON drivy.invitation(school_id,email);
CREATE TRIGGER invitation_unique_roles BEFORE INSERT OR UPDATE OF roles ON drivy.invitation
  FOR EACH ROW EXECUTE FUNCTION drivy.validate_membership_roles();
CREATE TABLE drivy.invitation_mail (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  invitation_id uuid NOT NULL REFERENCES drivy.invitation(id),
  invitation_version integer NOT NULL,
  payload bytea,
  status text NOT NULL DEFAULT 'QUEUED' CHECK(status IN('QUEUED','PROCESSING','SENT','FAILED','CANCELLED')),
  attempts integer NOT NULL DEFAULT 0 CHECK(attempts BETWEEN 0 AND 5),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_id uuid,
  lease_until timestamptz,
  sent_at timestamptz,
  failure_code text CHECK(failure_code IN('SMTP_FAILED','PAYLOAD_INVALID','RETRY_EXHAUSTED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(invitation_id,invitation_version),
  FOREIGN KEY(school_id,invitation_id) REFERENCES drivy.invitation(school_id,id),
  CHECK((status IN('SENT','CANCELLED') AND payload IS NULL) OR status IN('QUEUED','PROCESSING','FAILED'))
);
ALTER TABLE drivy.invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.invitation FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.invitation_mail ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.invitation_mail FORCE ROW LEVEL SECURITY;
-- Les fonctions scalaires évitent la récursion entre les politiques d'adhésion et d'invitation.
-- Le propriétaire DDL demeure soumis à FORCE RLS avec ses seules politiques explicites.
DO $$ DECLARE item text; BEGIN
  FOREACH item IN ARRAY ARRAY['person','identity_link','invitation','invitation_mail'] LOOP
    EXECUTE format('CREATE POLICY g1c_owner_read ON drivy.%I FOR SELECT TO %I USING(true)',item,current_user);
  END LOOP;
END $$;
CREATE FUNCTION drivy.invitation_staff(school uuid,inviter uuid DEFAULT NULL) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT school=nullif(current_setting('app.school_id',true),'')::uuid AND EXISTS(
    SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
    WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
      AND m.status='ACTIVE' AND p.status='ACTIVE'
      AND ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND (inviter IS NULL OR inviter=m.id))))
$$;
CREATE FUNCTION drivy.invitation_target() RETURNS SETOF drivy.invitation
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT i.* FROM drivy.invitation i WHERE i.token_hash=current_setting('app.invitation_hash',true)
    AND i.email=current_setting('app.verified_email',true)
$$;
CREATE FUNCTION drivy.invitation_member_exists(school uuid,address text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.invitation_staff(school,NULL) AND EXISTS(SELECT 1 FROM drivy.membership m
    WHERE m.school_id=school AND m.status='ACTIVE' AND m.invitation_email=address)
$$;
CREATE FUNCTION drivy.invitation_pending_exists(school uuid,address text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.invitation_staff(school,NULL) AND EXISTS(SELECT 1 FROM drivy.invitation i
    WHERE i.school_id=school AND i.email=address AND i.status='PENDING' AND i.expires_at>now())
$$;
REVOKE ALL ON FUNCTION drivy.invitation_pending_exists(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_pending_exists(uuid,text) TO drivy_app;
REVOKE ALL ON FUNCTION drivy.invitation_staff(uuid,uuid),drivy.invitation_target(),drivy.invitation_member_exists(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_staff(uuid,uuid),drivy.invitation_target(),drivy.invitation_member_exists(uuid,text) TO drivy_app;
CREATE POLICY invitation_staff_read ON drivy.invitation FOR SELECT TO drivy_app USING(
  drivy.invitation_staff(school_id,inviter_membership_id));
CREATE POLICY invitation_target_read ON drivy.invitation FOR SELECT TO drivy_app USING(
  token_hash=current_setting('app.invitation_hash',true) AND email=current_setting('app.verified_email',true));
CREATE POLICY invitation_staff_insert ON drivy.invitation FOR INSERT TO drivy_app WITH CHECK(
  drivy.invitation_staff(school_id,inviter_membership_id) AND inviter_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY invitation_staff_update ON drivy.invitation FOR UPDATE TO drivy_app
  USING(drivy.invitation_staff(school_id,inviter_membership_id)) WITH CHECK(drivy.invitation_staff(school_id,inviter_membership_id));
CREATE POLICY invitation_target_update ON drivy.invitation FOR UPDATE TO drivy_app
  USING(token_hash=current_setting('app.invitation_hash',true) AND email=current_setting('app.verified_email',true))
  WITH CHECK(token_hash=current_setting('app.invitation_hash',true) AND email=current_setting('app.verified_email',true)
    AND status='ACCEPTED' AND accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY invitation_school_read ON drivy.school FOR SELECT TO drivy_app USING(
  EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.school_id=school.id));
CREATE POLICY invitation_school_lock ON drivy.school FOR UPDATE TO drivy_app USING(
  drivy.invitation_staff(id,NULL) OR EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.school_id=school.id)) WITH CHECK(false);
CREATE POLICY invitation_policy_read ON drivy.school_data_policy FOR SELECT TO drivy_app USING(
  drivy.invitation_staff(school_id,NULL) OR EXISTS(SELECT 1 FROM drivy.invitation_target() i
    WHERE i.school_id=school_data_policy.school_id AND i.notice_version=school_data_policy.version));
CREATE POLICY invitation_person_read ON drivy.person FOR SELECT TO drivy_app USING(
  EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.inviter_person_id=person.id));
CREATE POLICY invitation_person_lock ON drivy.person FOR UPDATE TO drivy_app USING(
  EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.inviter_person_id=person.id)) WITH CHECK(false);
CREATE POLICY invitation_person_insert ON drivy.person FOR INSERT TO drivy_app WITH CHECK(
  id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE'
  AND EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.status='PENDING' AND i.expires_at>now()));
CREATE POLICY invitation_identity_insert ON drivy.identity_link FOR INSERT TO drivy_app WITH CHECK(
  issuer=current_setting('app.issuer',true) AND subject=current_setting('app.subject',true)
  AND person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.status='PENDING' AND i.expires_at>now()));
CREATE POLICY invitation_membership_read ON drivy.membership FOR SELECT TO drivy_app USING(
  EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.inviter_membership_id=membership.id));
CREATE POLICY invitation_membership_lock ON drivy.membership FOR UPDATE TO drivy_app USING(
  EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.inviter_membership_id=membership.id)) WITH CHECK(false);
CREATE POLICY invitation_membership_insert ON drivy.membership FOR INSERT TO drivy_app WITH CHECK(
  person_id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE' AND cardinality(grants)=0
  AND EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.school_id=membership.school_id AND i.status='PENDING'
    AND i.expires_at>now() AND membership.roles <@ i.roles));
CREATE POLICY invitation_membership_update ON drivy.membership FOR UPDATE TO drivy_app USING(
  person_id=nullif(current_setting('app.person_id',true),'')::uuid AND EXISTS(SELECT 1 FROM drivy.invitation_target() i
    WHERE i.school_id=membership.school_id AND i.status='PENDING' AND i.expires_at>now()))
  WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE'
    AND EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.school_id=membership.school_id AND i.status='PENDING' AND i.expires_at>now()));
CREATE POLICY invitation_learner_insert ON drivy.learner_profile FOR INSERT TO drivy_app WITH CHECK(
  person_id=nullif(current_setting('app.person_id',true),'')::uuid AND EXISTS(SELECT 1 FROM drivy.invitation_target() i
    WHERE i.school_id=learner_profile.school_id AND i.status='PENDING' AND i.expires_at>now() AND 'LEARNER'=ANY(i.roles)));
CREATE POLICY invitation_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(
  (command_type IN('CREATE_INVITATION','RESEND_INVITATION','REVOKE_INVITATION') AND drivy.invitation_staff(school_id,NULL))
  OR (command_type='ACCEPT_INVITATION' AND EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.school_id=operation.school_id
    AND i.status='ACCEPTED' AND i.accepted_by_person_id=operation.actor_person_id)));
CREATE POLICY invitation_audit_read ON drivy.audit_event FOR SELECT TO drivy_app USING(
  actor_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND school_id=nullif(current_setting('app.school_id',true),'')::uuid);
CREATE POLICY invitation_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(
  action IN('InvitationCreated','InvitationResent','InvitationRevoked','InvitationAccepted','InvitationAcceptanceConfirmed'));
DROP POLICY audit_actor_insert ON drivy.audit_event;
CREATE POLICY audit_actor_insert ON drivy.audit_event AS RESTRICTIVE FOR INSERT TO drivy_app WITH CHECK(
  actor_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND EXISTS(SELECT 1 FROM drivy.membership m
    WHERE m.id=actor_membership_id AND m.school_id=audit_event.school_id AND m.person_id=actor_person_id AND m.status='ACTIVE'));
CREATE POLICY invitation_mail_read ON drivy.invitation_mail FOR SELECT TO drivy_app USING(
  EXISTS(SELECT 1 FROM drivy.invitation i WHERE i.id=invitation_id AND drivy.invitation_staff(i.school_id,i.inviter_membership_id))
  OR EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.id=invitation_id));
CREATE POLICY invitation_mail_insert ON drivy.invitation_mail FOR INSERT TO drivy_app WITH CHECK(
  EXISTS(SELECT 1 FROM drivy.invitation i WHERE i.id=invitation_id AND i.school_id=invitation_mail.school_id AND drivy.invitation_staff(i.school_id,i.inviter_membership_id)));
CREATE POLICY invitation_mail_cancel ON drivy.invitation_mail FOR UPDATE TO drivy_app
  USING(EXISTS(SELECT 1 FROM drivy.invitation i WHERE i.id=invitation_id AND drivy.invitation_staff(i.school_id,i.inviter_membership_id))
    OR EXISTS(SELECT 1 FROM drivy.invitation_target() i WHERE i.id=invitation_id))
  WITH CHECK(status='CANCELLED' AND payload IS NULL);
GRANT SELECT,INSERT ON drivy.invitation,drivy.invitation_mail TO drivy_app;
GRANT UPDATE(token_hash,status,version,expires_at,accepted_by_person_id,notice_version,revoked_reason) ON drivy.invitation TO drivy_app;
GRANT UPDATE(status,payload,lease_id,lease_until) ON drivy.invitation_mail TO drivy_app;
GRANT INSERT ON drivy.person,drivy.identity_link,drivy.membership,drivy.learner_profile TO drivy_app;
GRANT UPDATE(roles,status,grants,version,access_epoch,invitation_email,onboarding) ON drivy.membership TO drivy_app;
-- Le worker n'usurpe aucune identité utilisateur et ne peut modifier le métier.
GRANT USAGE ON SCHEMA drivy TO drivy_invitation_mailer;
GRANT SELECT ON drivy.invitation,drivy.invitation_mail TO drivy_invitation_mailer;
GRANT SELECT(id,status) ON drivy.school,drivy.person TO drivy_invitation_mailer;
GRANT SELECT(id,person_id,status,roles) ON drivy.membership TO drivy_invitation_mailer;
GRANT UPDATE(status,payload,attempts,available_at,lease_id,lease_until,sent_at,failure_code) ON drivy.invitation_mail TO drivy_invitation_mailer;
DO $$ DECLARE item text; BEGIN
  FOREACH item IN ARRAY ARRAY['invitation','invitation_mail','school','person','membership'] LOOP
    EXECUTE format('CREATE POLICY invitation_worker_read ON drivy.%I FOR SELECT TO drivy_invitation_mailer USING(true)',item);
  END LOOP;
END $$;
CREATE POLICY invitation_worker_update ON drivy.invitation_mail FOR UPDATE TO drivy_invitation_mailer USING(true) WITH CHECK(true);
