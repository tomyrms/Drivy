-- Identifiants persistés des notices, sans réécriture des preuves d'adoption.
ALTER TABLE drivy.school_data_policy ADD COLUMN notice_version_id uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE drivy.school_data_policy ADD CONSTRAINT data_policy_notice_id UNIQUE(notice_version_id);
ALTER TABLE drivy.school_data_policy ADD CONSTRAINT data_policy_school_notice UNIQUE(school_id,notice_version_id);
CREATE TABLE drivy.profile_field_policy (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), school_id uuid NOT NULL REFERENCES drivy.school(id),
  version integer NOT NULL DEFAULT 1 CHECK(version>0),
  status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','PUBLISHED','RETIRED')),
  effective_from timestamptz NOT NULL,fields jsonb NOT NULL CHECK(jsonb_typeof(fields)='array' AND jsonb_array_length(fields) BETWEEN 2 AND 7),
  notice_version_id uuid NOT NULL,approved_by_membership_id uuid,approved_at timestamptz,
  created_by_membership_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(school_id,id),FOREIGN KEY(school_id,notice_version_id) REFERENCES drivy.school_data_policy(school_id,notice_version_id),
  FOREIGN KEY(school_id,approved_by_membership_id) REFERENCES drivy.membership(school_id,id),
  FOREIGN KEY(school_id,created_by_membership_id) REFERENCES drivy.membership(school_id,id),
  CHECK((status='DRAFT' AND approved_at IS NULL AND approved_by_membership_id IS NULL)
    OR (status IN('PUBLISHED','RETIRED') AND approved_at IS NOT NULL AND approved_by_membership_id IS NOT NULL))
);
CREATE UNIQUE INDEX profile_policy_effective ON drivy.profile_field_policy(school_id,effective_from) WHERE status='PUBLISHED';
CREATE INDEX profile_policy_page ON drivy.profile_field_policy(school_id,created_at,id);
ALTER TABLE drivy.learner_profile ADD COLUMN profile_id uuid NOT NULL DEFAULT gen_random_uuid();
ALTER TABLE drivy.learner_profile ADD CONSTRAINT administrative_profile_identity UNIQUE(profile_id);
ALTER TABLE drivy.learner_profile ADD COLUMN first_name text CHECK(length(first_name) BETWEEN 1 AND 150);
ALTER TABLE drivy.learner_profile ADD COLUMN last_name text CHECK(length(last_name) BETWEEN 1 AND 150);
ALTER TABLE drivy.learner_profile ADD COLUMN birth_date date;
ALTER TABLE drivy.learner_profile ADD COLUMN postal_address jsonb;
ALTER TABLE drivy.learner_profile ADD COLUMN profile_photo_document_id uuid CHECK(profile_photo_document_id IS NULL);
ALTER TABLE drivy.learner_profile ADD COLUMN administrative_policy_id uuid;
ALTER TABLE drivy.learner_profile ADD COLUMN profile_updated_at timestamptz NOT NULL DEFAULT now();
ALTER TABLE drivy.learner_profile ADD COLUMN entered_by_membership_id uuid;
ALTER TABLE drivy.learner_profile ADD COLUMN entry_source text NOT NULL DEFAULT 'SELF' CHECK(entry_source IN('SELF','STAFF_ASSISTED'));
ALTER TABLE drivy.learner_profile ADD CONSTRAINT profile_policy_scope FOREIGN KEY(school_id,administrative_policy_id) REFERENCES drivy.profile_field_policy(school_id,id);
ALTER TABLE drivy.learner_profile ADD CONSTRAINT profile_author_scope FOREIGN KEY(school_id,entered_by_membership_id) REFERENCES drivy.membership(school_id,id);
CREATE TABLE drivy.onboarding_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,person_id uuid NOT NULL REFERENCES drivy.person(id),membership_id uuid NOT NULL,
  kind text NOT NULL CHECK(kind IN('STUDENT','STAFF')),version integer NOT NULL DEFAULT 1 CHECK(version>0),
  current_step text NOT NULL DEFAULT 'IDENTITY' CHECK(current_step IN('IDENTITY','FORMATIONS','INFORMATION','DEVICE','REVIEW')),
  skipped_optional_steps text[] NOT NULL DEFAULT '{}' CHECK(cardinality(skipped_optional_steps)<=3 AND skipped_optional_steps <@ ARRAY['PHOTO','NOTIFICATIONS','DEVICE']::text[]),
  policy_version_id uuid NOT NULL,last_saved_at timestamptz NOT NULL DEFAULT now(),completed_at timestamptz,
  return_destination_key text CHECK(return_destination_key IN('HOME','CALENDAR','COURSE','TRAINING')),return_resource_id uuid,
  UNIQUE(membership_id,kind),UNIQUE(school_id,id),
  FOREIGN KEY(school_id,membership_id,person_id) REFERENCES drivy.membership(school_id,id,person_id),
  FOREIGN KEY(school_id,policy_version_id) REFERENCES drivy.profile_field_policy(school_id,id)
);
ALTER TABLE drivy.profile_field_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.profile_field_policy FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.onboarding_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.onboarding_progress FORCE ROW LEVEL SECURITY;
DO $$ DECLARE item text; BEGIN
  FOREACH item IN ARRAY ARRAY['learner_profile','training','instructor_assignment'] LOOP
    EXECUTE format('CREATE POLICY g1d_owner_read ON drivy.%I FOR SELECT TO %I USING(true)',item,current_user);
  END LOOP;
  FOREACH item IN ARRAY ARRAY['profile_field_policy','onboarding_progress'] LOOP
    EXECUTE format('CREATE POLICY g1d_owner_initialize ON drivy.%I TO %I USING(true) WITH CHECK(true)',item,current_user);
  END LOOP;
  EXECUTE format('CREATE POLICY g1d_owner_profile_initialize ON drivy.learner_profile FOR UPDATE TO %I USING(true) WITH CHECK(true)',current_user);
END $$;
-- Une seule décision de portée pour RLS et service, sans dépendance récursive aux politiques runtime.
CREATE FUNCTION drivy.profile_access(learner uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT CASE WHEN 'ADMIN'=ANY(m.roles) OR ('LEARNER'=ANY(m.roles) AND l.person_id=m.person_id) THEN 'FULL'
    WHEN 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.instructor_assignment a ON a.school_id=t.school_id AND a.training_id=t.id
      WHERE t.school_id=l.school_id AND t.learner_id=l.id AND a.instructor_membership_id=m.id
      AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())) THEN 'CONTACT' END
  FROM drivy.learner_profile l JOIN drivy.membership m ON m.school_id=l.school_id JOIN drivy.person p ON p.id=m.person_id
  WHERE l.id=learner AND l.school_id=nullif(current_setting('app.school_id',true),'')::uuid
    AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND p.status='ACTIVE'
$$;
CREATE FUNCTION drivy.profile_target_person() RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT l.person_id FROM drivy.learner_profile l WHERE l.id=nullif(current_setting('app.learner_id',true),'')::uuid AND drivy.profile_access(l.id) IS NOT NULL
$$;
CREATE FUNCTION drivy.profile_fields_writable(learner uuid,first_name_value text,last_name_value text,birth_date_value date,address_value jsonb,photo_value uuid,display_value text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.profile_access(learner)='FULL' OR (drivy.profile_access(learner)='CONTACT' AND EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner
    AND l.first_name IS NOT DISTINCT FROM first_name_value AND l.last_name IS NOT DISTINCT FROM last_name_value
    AND l.birth_date IS NOT DISTINCT FROM birth_date_value AND l.postal_address IS NOT DISTINCT FROM address_value
    AND l.profile_photo_document_id IS NOT DISTINCT FROM photo_value AND l.display_name=display_value))
$$;
CREATE FUNCTION drivy.current_school_member(school uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT school=nullif(current_setting('app.school_id',true),'')::uuid AND EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
    WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND p.status='ACTIVE')
$$;
CREATE FUNCTION drivy.applicable_profile_policy(school uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT id FROM drivy.profile_field_policy WHERE school_id=school AND drivy.current_school_member(school)
    AND status='PUBLISHED' AND effective_from<=statement_timestamp() ORDER BY effective_from DESC LIMIT 1
$$;
REVOKE ALL ON FUNCTION drivy.profile_access(uuid),drivy.profile_target_person(),drivy.profile_fields_writable(uuid,text,text,date,jsonb,uuid,text),drivy.current_school_member(uuid),drivy.applicable_profile_policy(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.profile_access(uuid),drivy.profile_target_person(),drivy.profile_fields_writable(uuid,text,text,date,jsonb,uuid,text),drivy.current_school_member(uuid),drivy.applicable_profile_policy(uuid) TO drivy_app;
CREATE POLICY profile_read_scope ON drivy.learner_profile AS RESTRICTIVE FOR SELECT TO drivy_app USING(drivy.profile_access(id) IS NOT NULL);
CREATE POLICY profile_person_read ON drivy.person FOR SELECT TO drivy_app USING(id=drivy.profile_target_person());
CREATE POLICY profile_person_lock ON drivy.person FOR UPDATE TO drivy_app USING(id=drivy.profile_target_person()) WITH CHECK(false);
CREATE POLICY profile_school_lock ON drivy.school FOR UPDATE TO drivy_app USING(drivy.current_school_member(id)) WITH CHECK(false);
CREATE POLICY profile_member_read ON drivy.profile_field_policy FOR SELECT TO drivy_app USING(drivy.current_school_member(school_id)
  AND (id=drivy.applicable_profile_policy(school_id) OR drivy.is_current_school_admin(school_id)));
CREATE POLICY profile_policy_insert ON drivy.profile_field_policy FOR INSERT TO drivy_app WITH CHECK(drivy.is_current_school_admin(school_id)
  AND status='DRAFT' AND created_by_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY profile_policy_publish ON drivy.profile_field_policy FOR UPDATE TO drivy_app USING(drivy.is_current_school_admin(school_id) AND status='DRAFT')
  WITH CHECK(drivy.is_current_school_admin(school_id) AND status='PUBLISHED' AND approved_by_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY approved_notice_member_read ON drivy.school_data_policy FOR SELECT TO drivy_app USING(approved_at IS NOT NULL AND drivy.current_school_member(school_id));
CREATE POLICY profile_update ON drivy.learner_profile FOR UPDATE TO drivy_app USING(drivy.profile_access(id) IS NOT NULL AND archived_at IS NULL)
  WITH CHECK(drivy.profile_fields_writable(id,first_name,last_name,birth_date,postal_address,profile_photo_document_id,display_name)
    AND entered_by_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY onboarding_member_read ON drivy.onboarding_progress FOR SELECT TO drivy_app USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND drivy.current_school_member(school_id));
CREATE POLICY onboarding_member_update ON drivy.onboarding_progress FOR UPDATE TO drivy_app USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND drivy.current_school_member(school_id)) WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.current_school_member(school_id));
CREATE POLICY profile_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id)
  AND command_type IN('UPDATE_ADMINISTRATIVE_PROFILE','UPDATE_LEARNER','SAVE_ONBOARDING','COMPLETE_ONBOARDING'));
CREATE POLICY profile_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id)
  AND action IN('AdministrativeProfileUpdated','LearnerUpdated','OnboardingSaved','OnboardingCompleted'));
GRANT SELECT,INSERT ON drivy.profile_field_policy TO drivy_app;
GRANT UPDATE(status,version,approved_by_membership_id,approved_at) ON drivy.profile_field_policy TO drivy_app;
GRANT SELECT ON drivy.onboarding_progress TO drivy_app;
GRANT UPDATE(current_step,version,skipped_optional_steps,policy_version_id,last_saved_at,completed_at,return_destination_key,return_resource_id) ON drivy.onboarding_progress TO drivy_app;
GRANT UPDATE(display_name,contact_email,contact_phone,version,profile_readiness,first_name,last_name,birth_date,postal_address,profile_photo_document_id,
  administrative_policy_id,profile_updated_at,entered_by_membership_id,entry_source) ON drivy.learner_profile TO drivy_app;

CREATE FUNCTION drivy.initialize_profile_context(target_school uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE selected_policy uuid; BEGIN
  SELECT id INTO selected_policy FROM drivy.profile_field_policy WHERE school_id=target_school AND status='PUBLISHED'
    ORDER BY (effective_from<=now()) DESC,CASE WHEN effective_from<=now() THEN effective_from END DESC,effective_from ASC LIMIT 1;
  IF selected_policy IS NULL THEN RETURN; END IF;
  UPDATE drivy.learner_profile l SET administrative_policy_id=selected_policy,entered_by_membership_id=m.id
    FROM drivy.membership m WHERE l.school_id=target_school AND l.administrative_policy_id IS NULL
      AND m.school_id=l.school_id AND m.person_id=l.person_id;
  INSERT INTO drivy.onboarding_progress(school_id,person_id,membership_id,kind,policy_version_id)
    SELECT m.school_id,m.person_id,m.id,k.kind,selected_policy FROM drivy.membership m CROSS JOIN (VALUES('STUDENT'),('STAFF')) k(kind)
    WHERE m.school_id=target_school AND m.status='ACTIVE' AND ((k.kind='STUDENT' AND 'LEARNER'=ANY(m.roles))
      OR (k.kind='STAFF' AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[])) ON CONFLICT(membership_id,kind) DO NOTHING;
END $$;
CREATE FUNCTION drivy.profile_context_after_policy() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF NEW.status='PUBLISHED' THEN PERFORM drivy.initialize_profile_context(NEW.school_id); END IF;RETURN NEW;
END $$;
CREATE FUNCTION drivy.profile_context_after_member() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF NEW.status='ACTIVE' THEN PERFORM drivy.initialize_profile_context(NEW.school_id); END IF;RETURN NEW;
END $$;
CREATE FUNCTION drivy.profile_context_before_learner() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  SELECT id INTO NEW.entered_by_membership_id FROM drivy.membership WHERE school_id=NEW.school_id AND person_id=NEW.person_id;
  SELECT id INTO NEW.administrative_policy_id FROM drivy.profile_field_policy WHERE school_id=NEW.school_id AND status='PUBLISHED'
    ORDER BY (effective_from<=now()) DESC,CASE WHEN effective_from<=now() THEN effective_from END DESC,effective_from ASC LIMIT 1;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.initialize_profile_context(uuid),drivy.profile_context_after_policy(),drivy.profile_context_after_member(),drivy.profile_context_before_learner() FROM PUBLIC;
CREATE TRIGGER initialize_profile_context AFTER INSERT OR UPDATE OF status ON drivy.profile_field_policy FOR EACH ROW EXECUTE FUNCTION drivy.profile_context_after_policy();
CREATE TRIGGER initialize_member_profile_context AFTER INSERT OR UPDATE OF roles,status ON drivy.membership FOR EACH ROW EXECUTE FUNCTION drivy.profile_context_after_member();
CREATE TRIGGER initialize_learner_profile_context BEFORE INSERT ON drivy.learner_profile FOR EACH ROW EXECUTE FUNCTION drivy.profile_context_before_learner();
UPDATE drivy.learner_profile l SET entered_by_membership_id=m.id FROM drivy.membership m WHERE m.school_id=l.school_id AND m.person_id=l.person_id;
