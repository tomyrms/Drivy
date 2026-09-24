-- Un événement existe avant le brouillon ; les projections ne créent aucune table supplémentaire.
ALTER TABLE drivy.competency_definition ADD CONSTRAINT competency_school_id_unique UNIQUE(school_id,id);
CREATE TABLE drivy.geo_observation (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,version integer NOT NULL DEFAULT 1 CHECK(version>0),
 lesson_id uuid NOT NULL,training_id uuid NOT NULL,author_membership_id uuid NOT NULL,draft_id uuid,
 capture_id uuid,segment_id uuid,point_sequence integer CHECK(point_sequence>=0),competency_id uuid,
 text text,origin text NOT NULL CHECK(origin IN('LIVE','REVIEW')),observed_at timestamptz,
 event_kind text CHECK(event_kind IN('MARKER','QUALIFIED')),event_status text CHECK(event_status IN('ATTENTION','TO_REWORK','POSITIVE')),
 created_at timestamptz NOT NULL DEFAULT now(),removed_at timestamptz,
 UNIQUE(school_id,id),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 FOREIGN KEY(school_id,training_id) REFERENCES drivy.training(school_id,id),
 FOREIGN KEY(school_id,author_membership_id) REFERENCES drivy.membership(school_id,id),
 FOREIGN KEY(school_id,draft_id) REFERENCES drivy.report_draft(school_id,id),
 FOREIGN KEY(school_id,capture_id) REFERENCES drivy.capture_session(school_id,id),
 FOREIGN KEY(school_id,competency_id) REFERENCES drivy.competency_definition(school_id,id),
 CHECK((capture_id IS NULL AND segment_id IS NULL AND point_sequence IS NULL) OR (capture_id IS NOT NULL AND segment_id IS NOT NULL AND point_sequence IS NOT NULL)),
 CHECK(draft_id IS NOT NULL OR origin='LIVE'),
 CHECK(origin<>'LIVE' OR (observed_at IS NOT NULL AND event_kind IS NOT NULL)),
 CHECK(event_kind IS DISTINCT FROM 'MARKER' OR (origin='LIVE' AND competency_id IS NULL AND event_status IS NULL)),
 CHECK(origin<>'LIVE' OR event_kind<>'QUALIFIED' OR (competency_id IS NOT NULL AND event_status IS NOT NULL)),
 CHECK((removed_at IS NULL AND text IS NOT NULL AND char_length(btrim(text)) BETWEEN 1 AND 4000) OR (removed_at IS NOT NULL AND text IS NULL AND capture_id IS NULL))
);
CREATE INDEX geo_observation_lesson_order ON drivy.geo_observation(school_id,lesson_id,created_at,id) WHERE removed_at IS NULL;
CREATE INDEX geo_observation_draft ON drivy.geo_observation(draft_id) WHERE removed_at IS NULL;
CREATE INDEX geo_observation_capture ON drivy.geo_observation(capture_id,segment_id,point_sequence) WHERE capture_id IS NOT NULL;
ALTER TABLE drivy.geo_observation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.geo_observation FORCE ROW LEVEL SECURITY;
DO $$ BEGIN EXECUTE format('CREATE POLICY observations_owner ON drivy.geo_observation FOR ALL TO %I USING(true) WITH CHECK(true)',current_user); END $$;
CREATE POLICY observation_read ON drivy.geo_observation FOR SELECT TO drivy_app USING(
 drivy.report_lesson_author(lesson_id) AND author_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY observation_insert ON drivy.geo_observation FOR INSERT TO drivy_app WITH CHECK(
 drivy.report_lesson_author(lesson_id) AND author_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY observation_update ON drivy.geo_observation FOR UPDATE TO drivy_app USING(
 drivy.report_lesson_author(lesson_id) AND author_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid) WITH CHECK(
 drivy.report_lesson_author(lesson_id) AND author_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);
GRANT SELECT,INSERT ON drivy.geo_observation TO drivy_app;
GRANT UPDATE(version,draft_id,capture_id,segment_id,point_sequence,competency_id,text,origin,observed_at,event_kind,event_status,removed_at) ON drivy.geo_observation TO drivy_app;
CREATE POLICY observation_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN('CREATE_GEO_OBSERVATION','UPDATE_GEO_OBSERVATION','REMOVE_GEO_OBSERVATION'));
CREATE POLICY observation_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN('GeoObservationCreated','GeoObservationUpdated','GeoObservationRemoved'));

-- Les liens appartiennent au même contexte, y compris lors d'un rattachement par AP49.
CREATE FUNCTION drivy.observation_context() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NOT EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.school_id=NEW.school_id AND l.id=NEW.lesson_id AND l.training_id=NEW.training_id)
   OR (NEW.draft_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM drivy.report_draft d WHERE d.school_id=NEW.school_id AND d.id=NEW.draft_id AND d.lesson_id=NEW.lesson_id AND d.author_membership_id=NEW.author_membership_id))
   OR (NEW.capture_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM drivy.capture_session c WHERE c.school_id=NEW.school_id AND c.id=NEW.capture_id AND c.lesson_id=NEW.lesson_id))
  THEN RAISE EXCEPTION 'observation context mismatch' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END $$;
REVOKE ALL ON FUNCTION drivy.observation_context() FROM PUBLIC;
CREATE TRIGGER observation_context BEFORE INSERT OR UPDATE ON drivy.geo_observation FOR EACH ROW EXECUTE FUNCTION drivy.observation_context();

-- La destruction d'un lot détruit aussi ses ancres, sans déplacer une observation vers une autre mesure.
CREATE FUNCTION drivy.observation_forget_chunk() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF OLD.encrypted_points IS NOT NULL AND NEW.encrypted_points IS NULL THEN
   WITH changed AS (UPDATE drivy.geo_observation SET capture_id=NULL,segment_id=NULL,point_sequence=NULL,version=version+1
    WHERE capture_id=NEW.capture_id AND segment_id=NEW.segment_id AND point_sequence BETWEEN NEW.first_sequence AND NEW.last_sequence RETURNING draft_id)
   UPDATE drivy.report_draft SET version=version+1 WHERE id IN(SELECT draft_id FROM changed WHERE draft_id IS NOT NULL);
  END IF;
  RETURN NEW;
 END $$;
REVOKE ALL ON FUNCTION drivy.observation_forget_chunk() FROM PUBLIC;
CREATE TRIGGER observation_forget_chunk AFTER UPDATE OF encrypted_points ON drivy.capture_chunk FOR EACH ROW EXECUTE FUNCTION drivy.observation_forget_chunk();
