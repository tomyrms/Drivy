-- Boucle pédagogique : préparation privée, souhait, constat et publication explicite.
ALTER TABLE drivy.lesson ADD COLUMN completion_anomaly_reason text;
ALTER TABLE drivy.lesson ADD CONSTRAINT lesson_actual_interval CHECK(
 (actual_start IS NULL AND actual_end IS NULL) OR (actual_start IS NOT NULL AND actual_end>actual_start));

CREATE TABLE drivy.lesson_preparation (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),goals jsonb NOT NULL DEFAULT '[]',
 administrative_check_note text,planned_waypoints jsonb NOT NULL DEFAULT '[]',
 UNIQUE(school_id,id),UNIQUE(lesson_id),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 CHECK(jsonb_typeof(goals)='array' AND jsonb_array_length(goals)<=3),
 CHECK(jsonb_typeof(planned_waypoints)='array' AND jsonb_array_length(planned_waypoints)<=20)
);
CREATE TABLE drivy.training_wish (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,training_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),lesson_id uuid,text text NOT NULL DEFAULT '' CHECK(char_length(text)<=500),
 UNIQUE(school_id,id),UNIQUE(training_id),FOREIGN KEY(school_id,training_id) REFERENCES drivy.training(school_id,id),
 FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id)
);
CREATE TABLE drivy.report_draft (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,author_membership_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),base_publication_version integer NOT NULL DEFAULT 0 CHECK(base_publication_version>=0),
 worked_on text NOT NULL DEFAULT '',observation_text text NOT NULL DEFAULT '',next_step text NOT NULL DEFAULT '',
 observations jsonb NOT NULL DEFAULT '[]',created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),UNIQUE(lesson_id,author_membership_id),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 FOREIGN KEY(school_id,author_membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(char_length(worked_on)<=4000 AND char_length(observation_text)<=4000 AND char_length(next_step)<=4000),
 CHECK(jsonb_typeof(observations)='array' AND jsonb_array_length(observations)<=100)
);
CREATE TABLE drivy.report_revision (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,author_membership_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version=1),sequence integer NOT NULL CHECK(sequence>0),published_at timestamptz NOT NULL DEFAULT now(),
 worked_on text NOT NULL,observation_text text NOT NULL,next_step text NOT NULL,observations jsonb NOT NULL,
 competency_snapshot jsonb NOT NULL,correction_reason text,operation_id uuid NOT NULL,
 UNIQUE(school_id,id),UNIQUE(lesson_id,sequence),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 FOREIGN KEY(school_id,author_membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(char_length(btrim(worked_on)) BETWEEN 1 AND 4000 AND char_length(btrim(observation_text)) BETWEEN 1 AND 4000 AND char_length(btrim(next_step)) BETWEEN 1 AND 4000),
 CHECK(sequence=1 OR char_length(btrim(correction_reason))>0),
 CHECK(jsonb_typeof(observations)='array' AND jsonb_array_length(observations)<=100)
);
ALTER TABLE drivy.lesson ADD CONSTRAINT lesson_current_revision_fk FOREIGN KEY(school_id,current_published_revision_id) REFERENCES drivy.report_revision(school_id,id);
CREATE TABLE drivy.lesson_account (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),planned_price_cents bigint NOT NULL CHECK(planned_price_cents BETWEEN 0 AND 9007199254740991),
 UNIQUE(school_id,id),UNIQUE(lesson_id),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id)
);
CREATE TABLE drivy.charge_entry (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,account_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version=1),kind text NOT NULL CHECK(kind IN('INITIAL','ADJUSTMENT','REVERSAL')),
 amount_signed_cents bigint NOT NULL CHECK(amount_signed_cents BETWEEN -9007199254740991 AND 9007199254740991),
 reason text,operation_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,account_id) REFERENCES drivy.lesson_account(school_id,id)
);
CREATE UNIQUE INDEX charge_initial_once ON drivy.charge_entry(account_id) WHERE kind='INITIAL';

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['lesson_preparation','training_wish','report_draft','report_revision','lesson_account','charge_entry'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY reports_owner ON drivy.%I FOR ALL TO %I USING(true) WITH CHECK(true)',t,current_user);
 END LOOP;
END $$;
-- Ces contrôles relisent les affectations courantes ; ADMIN seul n'accorde aucun droit pédagogique.
CREATE FUNCTION drivy.report_training_access(training uuid,learner_only boolean DEFAULT false) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND
 (('LEARNER'=ANY(m.roles) AND l.person_id=m.person_id) OR (NOT learner_only AND 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(
 SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=t.school_id AND a.training_id=t.id AND a.instructor_membership_id=m.id
 AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;
CREATE FUNCTION drivy.report_lesson_author(lesson uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id AND m.id=l.instructor_membership_id
 WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a
 WHERE a.school_id=l.school_id AND a.training_id=l.training_id AND a.instructor_membership_id=m.id
 AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))
$$;
CREATE FUNCTION drivy.report_lesson_read(lesson uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson AND drivy.report_training_access(l.training_id,false))
$$;
REVOKE ALL ON FUNCTION drivy.report_training_access(uuid,boolean),drivy.report_lesson_author(uuid),drivy.report_lesson_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.report_training_access(uuid,boolean),drivy.report_lesson_author(uuid),drivy.report_lesson_read(uuid) TO drivy_app;
CREATE POLICY report_assigned_lesson_read ON drivy.lesson FOR SELECT TO drivy_app USING(drivy.report_training_access(training_id,false));
CREATE POLICY preparation_read ON drivy.lesson_preparation FOR SELECT TO drivy_app USING(drivy.report_lesson_author(lesson_id));
CREATE POLICY preparation_update ON drivy.lesson_preparation FOR UPDATE TO drivy_app USING(drivy.report_lesson_author(lesson_id)) WITH CHECK(drivy.report_lesson_author(lesson_id));
CREATE POLICY wish_read ON drivy.training_wish FOR SELECT TO drivy_app USING(drivy.report_training_access(training_id,false));
CREATE POLICY wish_update ON drivy.training_wish FOR UPDATE TO drivy_app USING(drivy.report_training_access(training_id,true)) WITH CHECK(drivy.report_training_access(training_id,true));
CREATE POLICY draft_read ON drivy.report_draft FOR SELECT TO drivy_app USING(drivy.report_lesson_author(lesson_id) AND author_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY draft_insert ON drivy.report_draft FOR INSERT TO drivy_app WITH CHECK(drivy.report_lesson_author(lesson_id) AND author_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY draft_update ON drivy.report_draft FOR UPDATE TO drivy_app USING(drivy.report_lesson_author(lesson_id) AND author_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE')) WITH CHECK(drivy.report_lesson_author(lesson_id) AND author_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY revision_read ON drivy.report_revision FOR SELECT TO drivy_app USING(drivy.report_lesson_read(lesson_id));
CREATE POLICY revision_insert ON drivy.report_revision FOR INSERT TO drivy_app WITH CHECK(drivy.report_lesson_author(lesson_id) AND author_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY account_read ON drivy.lesson_account FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.school_id=lesson_account.school_id AND l.id=lesson_id AND drivy.lesson_access(l.training_id,l.instructor_membership_id,false)));
CREATE POLICY account_insert ON drivy.lesson_account FOR INSERT TO drivy_app WITH CHECK(drivy.report_lesson_author(lesson_id));
CREATE POLICY charge_read ON drivy.charge_entry FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.lesson_account a WHERE a.school_id=charge_entry.school_id AND a.id=account_id));
CREATE POLICY charge_insert ON drivy.charge_entry FOR INSERT TO drivy_app WITH CHECK(kind='INITIAL' AND amount_signed_cents>=0 AND EXISTS(SELECT 1 FROM drivy.lesson_account a WHERE a.school_id=charge_entry.school_id AND a.id=account_id AND drivy.report_lesson_author(a.lesson_id)));
CREATE POLICY reports_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN('SAVE_PREPARATION','SAVE_WISH','COMPLETE_LESSON','SAVE_REPORT_DRAFT','PUBLISH_REPORT_DRAFT'));
CREATE POLICY reports_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN('PreparationSaved','WishSaved','LessonCompleted','ReportDraftSaved','ReportPublished'));
GRANT SELECT ON drivy.lesson_preparation,drivy.training_wish,drivy.report_draft,drivy.report_revision,drivy.lesson_account,drivy.charge_entry TO drivy_app;
GRANT INSERT ON drivy.report_draft,drivy.report_revision,drivy.lesson_account,drivy.charge_entry TO drivy_app;
GRANT UPDATE(version,goals,administrative_check_note,planned_waypoints) ON drivy.lesson_preparation TO drivy_app;
GRANT UPDATE(version,text,lesson_id) ON drivy.training_wish TO drivy_app;
GRANT UPDATE(version,base_publication_version,worked_on,observation_text,next_step,observations) ON drivy.report_draft TO drivy_app;
GRANT UPDATE(actual_start,actual_end,completion_anomaly_reason,publication_version,current_published_revision_id) ON drivy.lesson TO drivy_app;

-- Initialisation transactionnelle vide : GET reste une lecture, sans approbation ni saisie déduite.
CREATE FUNCTION drivy.initialize_lesson_preparation() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN INSERT INTO drivy.lesson_preparation(school_id,lesson_id) VALUES(NEW.school_id,NEW.id); RETURN NEW; END $$;
CREATE FUNCTION drivy.initialize_training_wish() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN INSERT INTO drivy.training_wish(school_id,training_id) VALUES(NEW.school_id,NEW.id); RETURN NEW; END $$;
REVOKE ALL ON FUNCTION drivy.initialize_lesson_preparation(),drivy.initialize_training_wish() FROM PUBLIC;
CREATE TRIGGER lesson_prepare AFTER INSERT ON drivy.lesson FOR EACH ROW EXECUTE FUNCTION drivy.initialize_lesson_preparation();
CREATE TRIGGER training_wish AFTER INSERT ON drivy.training FOR EACH ROW EXECUTE FUNCTION drivy.initialize_training_wish();
INSERT INTO drivy.lesson_preparation(school_id,lesson_id) SELECT school_id,id FROM drivy.lesson;
INSERT INTO drivy.training_wish(school_id,training_id) SELECT school_id,id FROM drivy.training;

-- Une vue recalculable conserve l'ordre métier, même lorsqu'un ancien bilan arrive tard.
CREATE VIEW drivy.training_progress WITH(security_invoker=true) AS
 SELECT DISTINCT ON(l.school_id,l.training_id,item->>'competencyId') l.school_id,l.training_id,
 (item->>'competencyId')::uuid AS competency_id,item->>'level' AS level,item->>'context' AS context,
 (SELECT definition->>'label' FROM jsonb_array_elements(r.competency_snapshot) definition WHERE definition->>'id'=item->>'competencyId') AS label,
 l.actual_end AS observed_at,l.id AS source_lesson_id,r.id AS source_revision_id
 FROM drivy.lesson l JOIN drivy.report_revision r ON r.school_id=l.school_id AND r.id=l.current_published_revision_id
 CROSS JOIN LATERAL jsonb_array_elements(r.observations) item
 ORDER BY l.school_id,l.training_id,item->>'competencyId',l.actual_end DESC,l.id DESC;
GRANT SELECT ON drivy.training_progress TO drivy_app;
