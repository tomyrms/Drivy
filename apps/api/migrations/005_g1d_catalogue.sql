-- Versions saisies et approuvées explicitement ; aucun contenu de catalogue fabriqué au backfill.
CREATE TABLE drivy.curriculum_version (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),category_code text NOT NULL,
 version integer NOT NULL DEFAULT 1,revision integer NOT NULL,approved boolean NOT NULL,approval_reason text NOT NULL,
 created_by uuid NOT NULL,approved_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),UNIQUE(school_id,category_code,revision),FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id),
 CHECK(version>0 AND revision>0),CHECK(approved=(approved_at IS NOT NULL))
);
CREATE TABLE drivy.competency_definition (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,curriculum_version_id uuid NOT NULL,version integer NOT NULL DEFAULT 1,
 stable_key text NOT NULL,label text NOT NULL,description text NOT NULL,sort_order integer NOT NULL CHECK(sort_order>=0),
 UNIQUE(curriculum_version_id,stable_key),FOREIGN KEY(school_id,curriculum_version_id) REFERENCES drivy.curriculum_version(school_id,id)
);
CREATE TABLE drivy.school_policy_version (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),category_code text NOT NULL,
 version integer NOT NULL CHECK(version>0),procedure_text text NOT NULL,cancellation_policy_text text NOT NULL,source_urls text[] NOT NULL,
 approved boolean NOT NULL,approval_reason text NOT NULL,created_by uuid NOT NULL,approved_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),UNIQUE(school_id,category_code,version),FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id),
 CHECK(approved=(approved_at IS NOT NULL))
);
ALTER TABLE drivy.offering_version ADD COLUMN curriculum_version_id uuid;
ALTER TABLE drivy.offering_version ADD COLUMN policy_version_id uuid;
ALTER TABLE drivy.offering_version ADD COLUMN default_duration_minutes integer CHECK(default_duration_minutes BETWEEN 1 AND 480);
ALTER TABLE drivy.offering_version ADD COLUMN default_price_cents bigint CHECK(default_price_cents BETWEEN 0 AND 9007199254740991);
ALTER TABLE drivy.offering_version ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE drivy.offering_version ADD FOREIGN KEY(school_id,curriculum_version_id) REFERENCES drivy.curriculum_version(school_id,id);
ALTER TABLE drivy.offering_version ADD FOREIGN KEY(school_id,policy_version_id) REFERENCES drivy.school_policy_version(school_id,id);
ALTER TABLE drivy.offering_version ADD CONSTRAINT enabled_catalogue_complete CHECK(NOT enabled OR
 (curriculum_version_id IS NOT NULL AND policy_version_id IS NOT NULL AND default_duration_minutes IS NOT NULL AND default_price_cents IS NOT NULL));
ALTER TABLE drivy.instructor_assignment ADD COLUMN version integer NOT NULL DEFAULT 1 CHECK(version>0);
ALTER TABLE drivy.instructor_assignment ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE drivy.membership ADD COLUMN created_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE drivy.audit_event ADD COLUMN reason text CHECK(reason IS NULL OR length(reason) BETWEEN 1 AND 1000);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['curriculum_version','competency_definition','school_policy_version'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY catalogue_owner_read ON drivy.%I FOR SELECT TO %I USING(true)',t,current_user);
 END LOOP;
 EXECUTE format('CREATE POLICY catalogue_owner_read ON drivy.offering_version FOR SELECT TO %I USING(true)',current_user);
END $$;
-- La lecture ADMIN des appartenances ne doit pas réentrer dans ses propres politiques.
CREATE OR REPLACE FUNCTION drivy.is_current_school_admin(target_school uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT target_school=nullif(current_setting('app.school_id',true),'')::uuid AND EXISTS(
  SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=target_school
  AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
$$;
CREATE FUNCTION drivy.catalogue_training_visible(training uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id AND l.school_id=t.school_id
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND
 ('ADMIN'=ANY(m.roles) OR ('LEARNER'=ANY(m.roles) AND l.person_id=m.person_id) OR ('INSTRUCTOR'=ANY(m.roles) AND EXISTS(
 SELECT 1 FROM drivy.instructor_assignment a WHERE a.training_id=t.id AND a.school_id=t.school_id AND a.instructor_membership_id=m.id
 AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;
CREATE FUNCTION drivy.catalogue_offering_visible(offering uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.offering_version o WHERE o.id=offering AND drivy.current_school_member(o.school_id) AND
 (drivy.is_current_school_admin(o.school_id) OR EXISTS(SELECT 1 FROM drivy.training t WHERE t.offering_id=o.id AND drivy.catalogue_training_visible(t.id)) OR
 (o.enabled AND o.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key)
 AND EXISTS(SELECT 1 FROM drivy.curriculum_version c JOIN drivy.school_policy_version p ON p.school_id=c.school_id WHERE c.id=o.curriculum_version_id
 AND p.id=o.policy_version_id AND c.approved AND p.approved)) ))
$$;
CREATE FUNCTION drivy.catalogue_reference_visible(reference uuid,kind text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.offering_version o WHERE (CASE WHEN kind='curriculum' THEN o.curriculum_version_id ELSE o.policy_version_id END)=reference
 AND drivy.catalogue_offering_visible(o.id))
$$;
CREATE FUNCTION drivy.catalogue_offering_ready(offering uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.offering_version o JOIN drivy.curriculum_version c ON c.id=o.curriculum_version_id
 JOIN drivy.school_policy_version p ON p.id=o.policy_version_id WHERE o.id=offering AND drivy.current_school_member(o.school_id)
 AND o.enabled AND c.approved AND p.approved AND o.version=(SELECT max(v.version) FROM drivy.offering_version v WHERE v.school_id=o.school_id AND v.offering_key=o.offering_key))
$$;
CREATE FUNCTION drivy.catalogue_learner_active(learner uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.learner_profile l JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=l.person_id
 JOIN drivy.person p ON p.id=m.person_id WHERE l.id=learner AND l.archived_at IS NULL AND drivy.profile_access(l.id) IS NOT NULL
 AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles) AND p.status='ACTIVE')
$$;
REVOKE ALL ON FUNCTION drivy.catalogue_offering_ready(uuid),drivy.catalogue_learner_active(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.catalogue_offering_ready(uuid),drivy.catalogue_learner_active(uuid) TO drivy_app;
REVOKE ALL ON FUNCTION drivy.catalogue_training_visible(uuid),drivy.catalogue_offering_visible(uuid),drivy.catalogue_reference_visible(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.catalogue_training_visible(uuid),drivy.catalogue_offering_visible(uuid),drivy.catalogue_reference_visible(uuid,text) TO drivy_app;
CREATE POLICY curriculum_read ON drivy.curriculum_version FOR SELECT TO drivy_app USING(drivy.is_current_school_admin(school_id) OR (approved AND drivy.catalogue_reference_visible(id,'curriculum')));
CREATE POLICY competencies_read ON drivy.competency_definition FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.curriculum_version c WHERE c.id=curriculum_version_id));
CREATE POLICY category_policy_read ON drivy.school_policy_version FOR SELECT TO drivy_app USING(drivy.is_current_school_admin(school_id) OR (approved AND drivy.catalogue_reference_visible(id,'policy')));
CREATE POLICY offering_scope ON drivy.offering_version AS RESTRICTIVE FOR SELECT TO drivy_app USING(drivy.is_current_school_admin(school_id) OR drivy.catalogue_offering_visible(id));
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['curriculum_version','school_policy_version'] LOOP
  EXECUTE format('CREATE POLICY catalogue_admin_insert ON drivy.%I FOR INSERT TO drivy_app WITH CHECK(drivy.is_current_school_admin(school_id) AND created_by=nullif(current_setting(''app.membership_id'',true),'''')::uuid)',t);
 END LOOP;
END $$;
CREATE POLICY competencies_insert ON drivy.competency_definition FOR INSERT TO drivy_app WITH CHECK(drivy.is_current_school_admin(school_id));
CREATE POLICY offering_insert ON drivy.offering_version FOR INSERT TO drivy_app WITH CHECK(drivy.is_current_school_admin(school_id)
 AND curriculum_version_id IS NOT NULL AND policy_version_id IS NOT NULL AND default_duration_minutes IS NOT NULL AND default_price_cents IS NOT NULL
 AND EXISTS(SELECT 1 FROM drivy.curriculum_version c JOIN drivy.school_policy_version p ON p.school_id=c.school_id WHERE c.id=curriculum_version_id
 AND p.id=policy_version_id AND c.school_id=offering_version.school_id AND c.category_code=offering_version.category_code AND p.category_code=offering_version.category_code
 AND (NOT offering_version.enabled OR (c.approved AND p.approved))));
CREATE POLICY catalogue_member_read ON drivy.membership FOR SELECT TO drivy_app USING(drivy.is_current_school_admin(school_id));
CREATE POLICY catalogue_member_update ON drivy.membership FOR UPDATE TO drivy_app USING(drivy.is_current_school_admin(school_id) AND status='ACTIVE')
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND status='ACTIVE');
CREATE POLICY catalogue_person_read ON drivy.person FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.membership m WHERE m.person_id=person.id AND drivy.is_current_school_admin(m.school_id)));
CREATE POLICY catalogue_person_lock ON drivy.person FOR UPDATE TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.membership m WHERE m.person_id=person.id AND drivy.is_current_school_admin(m.school_id))) WITH CHECK(false);
CREATE POLICY catalogue_learner_insert ON drivy.learner_profile FOR INSERT TO drivy_app WITH CHECK((drivy.is_current_school_admin(school_id) OR person_id=nullif(current_setting('app.person_id',true),'')::uuid) AND EXISTS(
 SELECT 1 FROM drivy.membership m WHERE m.school_id=learner_profile.school_id AND m.person_id=learner_profile.person_id AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles)));
CREATE POLICY catalogue_training_insert ON drivy.training FOR INSERT TO drivy_app WITH CHECK(drivy.invitation_staff(school_id,NULL) AND drivy.catalogue_learner_active(learner_id) AND drivy.catalogue_offering_ready(offering_id));
CREATE POLICY catalogue_assignment_insert ON drivy.instructor_assignment FOR INSERT TO drivy_app WITH CHECK(drivy.is_current_school_admin(school_id));
CREATE POLICY catalogue_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN('CREATE_TRAINING','UPDATE_MEMBER'));
CREATE POLICY catalogue_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN('TrainingCreated','MembershipChanged'));
GRANT SELECT,INSERT ON drivy.curriculum_version,drivy.competency_definition,drivy.school_policy_version TO drivy_app;
GRANT INSERT ON drivy.offering_version,drivy.training,drivy.instructor_assignment TO drivy_app;
