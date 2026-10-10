-- G2 planning : explicit commercial versions, actual openings and atomic occupations.
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE drivy.commercial_terms_version (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),version integer NOT NULL CHECK(version>0),
 label text NOT NULL,terms_text text NOT NULL,valid_from date NOT NULL,valid_until date,approved boolean NOT NULL,
 approval_reason text NOT NULL,approved_by uuid,approved_at timestamptz,created_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),UNIQUE(school_id,version),FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id),
 FOREIGN KEY(school_id,approved_by) REFERENCES drivy.membership(school_id,id),
 CHECK(valid_until IS NULL OR valid_until>=valid_from),CHECK(approved=(approved_at IS NOT NULL AND approved_by IS NOT NULL))
);
CREATE TABLE drivy.service_product_version (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),version integer NOT NULL CHECK(version>0),
 product_key text NOT NULL,label text NOT NULL,type text NOT NULL CHECK(type IN('INDIVIDUAL_LESSON','COLLECTIVE_COURSE','EXAM_SUPPORT','EXTERNAL_SERVICE')),
 category_code text,site_id uuid,duration_minutes integer CHECK(duration_minutes BETWEEN 1 AND 1440),unit_label text NOT NULL,
 unit_price_cents bigint NOT NULL CHECK(unit_price_cents BETWEEN 0 AND 9007199254740991),valid_from date NOT NULL,valid_until date,
 terms_version_id uuid NOT NULL,enabled boolean NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),UNIQUE(school_id,product_key,version),FOREIGN KEY(school_id,terms_version_id) REFERENCES drivy.commercial_terms_version(school_id,id),
 CHECK(valid_until IS NULL OR valid_until>=valid_from),CHECK(type<>'INDIVIDUAL_LESSON' OR (category_code IS NOT NULL AND duration_minutes IS NOT NULL))
);
CREATE TABLE drivy.availability_rule (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),version integer NOT NULL DEFAULT 1 CHECK(version>0),
 instructor_membership_id uuid NOT NULL,weekdays integer[] NOT NULL,local_start time NOT NULL,local_end time NOT NULL,
 valid_from date NOT NULL,valid_until date,removed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,instructor_membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(cardinality(weekdays) BETWEEN 1 AND 7 AND weekdays<@ARRAY[1,2,3,4,5,6,7]),CHECK(local_end>local_start),CHECK(valid_until IS NULL OR valid_until>=valid_from)
);
CREATE TABLE drivy.closure (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),version integer NOT NULL DEFAULT 1 CHECK(version>0),
 instructor_membership_id uuid NOT NULL,starts_at timestamptz NOT NULL,ends_at timestamptz NOT NULL,reason text,removed_at timestamptz,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,instructor_membership_id) REFERENCES drivy.membership(school_id,id),CHECK(ends_at>starts_at)
);
CREATE TABLE drivy.lesson (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL REFERENCES drivy.school(id),version integer NOT NULL DEFAULT 1 CHECK(version>0),
 training_id uuid NOT NULL,learner_id uuid NOT NULL,learner_person_id uuid NOT NULL REFERENCES drivy.person(id),instructor_membership_id uuid NOT NULL,
 planned_start timestamptz NOT NULL,planned_end timestamptz NOT NULL,time_zone text NOT NULL,meeting_point text NOT NULL,
 status text NOT NULL DEFAULT 'PLANNED' CHECK(status IN('PLANNED','COMPLETED','CANCELLED','NO_SHOW')),
 price_cents_snapshot bigint NOT NULL CHECK(price_cents_snapshot BETWEEN 0 AND 9007199254740991),buffer_minutes_snapshot integer NOT NULL CHECK(buffer_minutes_snapshot BETWEEN 0 AND 240),
 policy_version_id uuid NOT NULL,commercial_selection jsonb NOT NULL,commercial_revision_version integer NOT NULL DEFAULT 1 CHECK(commercial_revision_version>0),
 publication_version integer NOT NULL DEFAULT 0 CHECK(publication_version>=0),current_published_revision_id uuid,
 actual_start timestamptz,actual_end timestamptz,cancel_reason_code text,cancel_comment text,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,training_id) REFERENCES drivy.training(school_id,id),FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id),
 FOREIGN KEY(school_id,instructor_membership_id) REFERENCES drivy.membership(school_id,id),FOREIGN KEY(school_id,policy_version_id) REFERENCES drivy.school_policy_version(school_id,id),
 CHECK(planned_end>planned_start AND planned_end<=planned_start+interval '8 hours')
);
-- Shared occupation primitive: person, not training, prevents overlaps across licences.
CREATE TABLE drivy.reservation (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,resource_id uuid NOT NULL REFERENCES drivy.person(id),
 resource_role text NOT NULL CHECK(resource_role IN('INSTRUCTOR','LEARNER')),during tstzrange NOT NULL,active boolean NOT NULL DEFAULT true,
 FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),CHECK(NOT isempty(during) AND lower_inc(during) AND NOT upper_inc(during)),
 EXCLUDE USING gist(school_id WITH =,resource_id WITH =,during WITH &&) WHERE(active)
);
CREATE INDEX lesson_schedule ON drivy.lesson(school_id,planned_start,id);
CREATE TABLE drivy.lesson_commercial_revision (
 school_id uuid NOT NULL,lesson_id uuid NOT NULL,revision integer NOT NULL,operation_id uuid NOT NULL,commercial_selection jsonb NOT NULL,
 price_cents bigint NOT NULL,duration_minutes integer NOT NULL,actor_membership_id uuid NOT NULL,reason text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(lesson_id,revision),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 FOREIGN KEY(school_id,actor_membership_id) REFERENCES drivy.membership(school_id,id)
);
CREATE TABLE drivy.lesson_event_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,lesson_version integer NOT NULL,event_type text NOT NULL,
 operation_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),delivered_at timestamptz,
 UNIQUE(lesson_id,lesson_version,event_type),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['commercial_terms_version','service_product_version','availability_rule','closure','lesson','reservation','lesson_commercial_revision','lesson_event_outbox'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY lesson_owner_read ON drivy.%I FOR SELECT TO %I USING(true)',t,current_user);
 END LOOP;
END $$;
CREATE FUNCTION drivy.lesson_catalogue_manage(school uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.current_school_member(school) AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id=school
 AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
 AND m.roles&&ARRAY['ADMIN','INSTRUCTOR']::text[] AND 'CONFIGURE_CATALOG'=ANY(m.grants))
$$;
CREATE FUNCTION drivy.lesson_instructor_manage(school uuid,instructor uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.current_school_member(school) AND EXISTS(SELECT 1 FROM drivy.membership target JOIN drivy.person p ON p.id=target.person_id
 WHERE target.school_id=school AND target.id=instructor AND target.status='ACTIVE' AND 'INSTRUCTOR'=ANY(target.roles) AND p.status='ACTIVE'
 AND (drivy.is_current_school_admin(school) OR target.person_id=nullif(current_setting('app.person_id',true),'')::uuid))
$$;
CREATE FUNCTION drivy.lesson_access(training uuid,instructor uuid,writing boolean) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.learner_profile l ON l.id=t.learner_id AND l.school_id=t.school_id
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND
 ('ADMIN'=ANY(m.roles) OR (NOT writing AND 'LEARNER'=ANY(m.roles) AND l.person_id=m.person_id) OR
 ('INSTRUCTOR'=ANY(m.roles) AND m.id=instructor AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=t.school_id AND a.training_id=t.id
 AND a.instructor_membership_id=m.id AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;
REVOKE ALL ON FUNCTION drivy.lesson_catalogue_manage(uuid),drivy.lesson_instructor_manage(uuid,uuid),drivy.lesson_access(uuid,uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_catalogue_manage(uuid),drivy.lesson_instructor_manage(uuid,uuid),drivy.lesson_access(uuid,uuid,boolean) TO drivy_app;
CREATE POLICY lesson_read ON drivy.lesson FOR SELECT TO drivy_app USING(drivy.lesson_access(training_id,instructor_membership_id,false));
CREATE POLICY lesson_insert ON drivy.lesson FOR INSERT TO drivy_app WITH CHECK(drivy.lesson_access(training_id,instructor_membership_id,true));
CREATE POLICY lesson_update ON drivy.lesson FOR UPDATE TO drivy_app USING(drivy.lesson_access(training_id,instructor_membership_id,true)) WITH CHECK(drivy.lesson_access(training_id,instructor_membership_id,true));
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['commercial_terms_version','service_product_version'] LOOP
  EXECUTE format('CREATE POLICY commercial_read ON drivy.%I FOR SELECT TO drivy_app USING(drivy.current_school_member(school_id))',t);
  EXECUTE format('CREATE POLICY commercial_insert ON drivy.%I FOR INSERT TO drivy_app WITH CHECK(drivy.lesson_catalogue_manage(school_id))',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['availability_rule','closure'] LOOP
  EXECUTE format('CREATE POLICY schedule_read ON drivy.%I FOR SELECT TO drivy_app USING(drivy.lesson_instructor_manage(school_id,instructor_membership_id))',t);
  EXECUTE format('CREATE POLICY schedule_insert ON drivy.%I FOR INSERT TO drivy_app WITH CHECK(drivy.lesson_instructor_manage(school_id,instructor_membership_id))',t);
  EXECUTE format('CREATE POLICY schedule_update ON drivy.%I FOR UPDATE TO drivy_app USING(drivy.lesson_instructor_manage(school_id,instructor_membership_id)) WITH CHECK(drivy.lesson_instructor_manage(school_id,instructor_membership_id))',t);
 END LOOP;
 FOREACH t IN ARRAY ARRAY['reservation','lesson_commercial_revision','lesson_event_outbox'] LOOP
  EXECUTE format('CREATE POLICY lesson_child_read ON drivy.%I FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson_id AND l.school_id=%I.school_id))',t,t);
  EXECUTE format('CREATE POLICY lesson_child_insert ON drivy.%I FOR INSERT TO drivy_app WITH CHECK(EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson_id AND l.school_id=%I.school_id AND drivy.lesson_access(l.training_id,l.instructor_membership_id,true)))',t,t);
 END LOOP;
END $$;
CREATE POLICY reservation_update ON drivy.reservation FOR UPDATE TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson_id AND l.school_id=reservation.school_id AND drivy.lesson_access(l.training_id,l.instructor_membership_id,true))) WITH CHECK(true);
CREATE POLICY lesson_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
 'CREATE_LESSON','MOVE_LESSON','CANCEL_LESSON','CREATE_COMMERCIAL_TERMS','CREATE_SERVICE_PRODUCT','CREATE_AVAILABILITY_RULE','UPDATE_AVAILABILITY_RULE','REMOVE_AVAILABILITY_RULE','CREATE_CLOSURE','REMOVE_CLOSURE'));
CREATE POLICY lesson_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN(
 'LessonCreated','LessonMoved','LessonCancelled','CommercialTermsCreated','ServiceProductCreated','AvailabilityCreated','AvailabilityUpdated','AvailabilityRemoved','ClosureCreated','ClosureRemoved'));
GRANT SELECT,INSERT ON drivy.commercial_terms_version,drivy.service_product_version,drivy.availability_rule,drivy.closure,drivy.lesson,drivy.reservation,drivy.lesson_commercial_revision,drivy.lesson_event_outbox TO drivy_app;
GRANT UPDATE(version,weekdays,local_start,local_end,valid_from,valid_until,removed_at) ON drivy.availability_rule TO drivy_app;
GRANT UPDATE(version,removed_at) ON drivy.closure TO drivy_app;
GRANT UPDATE(version,instructor_membership_id,planned_start,planned_end,time_zone,meeting_point,status,price_cents_snapshot,commercial_selection,commercial_revision_version,cancel_reason_code,cancel_comment) ON drivy.lesson TO drivy_app;
GRANT UPDATE(active) ON drivy.reservation TO drivy_app;

-- Draft commercial content is limited to the people explicitly allowed to configure it.
CREATE POLICY terms_draft_scope ON drivy.commercial_terms_version AS RESTRICTIVE FOR SELECT TO drivy_app
 USING(approved OR drivy.lesson_catalogue_manage(school_id));
CREATE POLICY products_draft_scope ON drivy.service_product_version AS RESTRICTIVE FOR SELECT TO drivy_app
 USING(enabled OR drivy.lesson_catalogue_manage(school_id) OR EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.school_id=service_product_version.school_id AND l.commercial_selection->>'serviceProductVersionId'=service_product_version.id::text));
CREATE FUNCTION drivy.lesson_learner_active(training uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
 JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=l.person_id JOIN drivy.person p ON p.id=l.person_id
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND drivy.catalogue_training_visible(t.id)
 AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles) AND p.status='ACTIVE')
$$;
REVOKE ALL ON FUNCTION drivy.lesson_learner_active(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_learner_active(uuid) TO drivy_app;
