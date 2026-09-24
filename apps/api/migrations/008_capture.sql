-- Capture privée : choix append-only, qualification, autorisation bornée et lots chiffrés.
CREATE TABLE drivy.capture_installation (
 device_id uuid PRIMARY KEY,person_id uuid NOT NULL REFERENCES drivy.person(id),created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE drivy.capture_device_assessment (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,version integer NOT NULL DEFAULT 1 CHECK(version=1),
 device_id uuid NOT NULL REFERENCES drivy.capture_installation(device_id),membership_id uuid NOT NULL,person_id uuid NOT NULL REFERENCES drivy.person(id),
 platform text NOT NULL CHECK(platform IN('IOS','ANDROID')),device_class text NOT NULL CHECK(device_class IN('PHONE','TABLET')),
 model_code text NOT NULL,os_version text NOT NULL,app_build text NOT NULL,qualification_profile_version text NOT NULL,
 status text NOT NULL CHECK(status IN('QUALIFIED','UNSUPPORTED','NEEDS_CHECK')),assessed_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL,blockers jsonb NOT NULL,
 UNIQUE(school_id,id),FOREIGN KEY(school_id,membership_id) REFERENCES drivy.membership(school_id,id),CHECK(expires_at>assessed_at),
 CHECK(jsonb_typeof(blockers)='array' AND jsonb_array_length(blockers)<=20)
);
CREATE TABLE drivy.recording_choice (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,version integer NOT NULL CHECK(version>0),learner_id uuid NOT NULL,lesson_id uuid,
 status text NOT NULL CHECK(status IN('ALLOWED','REFUSED','UNKNOWN')),notice_version_id uuid NOT NULL,recorded_by uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now(),source text NOT NULL CHECK(source IN('SELF','RECORDED_VERBAL')),
 UNIQUE(school_id,id),UNIQUE(learner_id,version),FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id),
 FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),FOREIGN KEY(school_id,notice_version_id) REFERENCES drivy.school_data_policy(school_id,notice_version_id),
 FOREIGN KEY(school_id,recorded_by) REFERENCES drivy.membership(school_id,id)
);
CREATE TABLE drivy.capture_session (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,version integer NOT NULL DEFAULT 1 CHECK(version>0),
 lesson_id uuid NOT NULL,learner_id uuid NOT NULL,instructor_membership_id uuid NOT NULL,person_id uuid NOT NULL REFERENCES drivy.person(id),device_id uuid NOT NULL REFERENCES drivy.capture_installation(device_id),
 choice_id uuid NOT NULL,notice_version_id uuid NOT NULL,device_assessment_id uuid NOT NULL,
 authorized_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL,upload_deadline timestamptz NOT NULL,
 stopped_at timestamptz,cutoff_at timestamptz,capture_state text NOT NULL DEFAULT 'AUTHORIZED' CHECK(capture_state IN('AUTHORIZED','STOPPED','REVOKED','EXPIRED')),
 sync_state text NOT NULL DEFAULT 'LOCAL_ONLY' CHECK(sync_state IN('LOCAL_ONLY','UPLOADING','SYNCED','PARTIAL','REJECTED')),
 publication_state text NOT NULL DEFAULT 'PRIVATE' CHECK(publication_state IN('PRIVATE','WITHDRAWN','DELETED')),
 manifest jsonb,finalized_at timestamptz,reconstruction_version integer NOT NULL DEFAULT 1 CHECK(reconstruction_version>0),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id),
 FOREIGN KEY(school_id,instructor_membership_id) REFERENCES drivy.membership(school_id,id),FOREIGN KEY(school_id,choice_id) REFERENCES drivy.recording_choice(school_id,id),
 FOREIGN KEY(school_id,notice_version_id) REFERENCES drivy.school_data_policy(school_id,notice_version_id),FOREIGN KEY(school_id,device_assessment_id) REFERENCES drivy.capture_device_assessment(school_id,id),
 CHECK(expires_at>authorized_at AND expires_at<=authorized_at+interval '3 hours' AND upload_deadline>=expires_at),
 CHECK(cutoff_at IS NULL OR cutoff_at<=expires_at),CHECK(stopped_at IS NULL OR stopped_at>=authorized_at),
 CHECK(manifest IS NULL OR (jsonb_typeof(manifest)='array' AND jsonb_array_length(manifest)<=200))
);
CREATE UNIQUE INDEX capture_one_lesson ON drivy.capture_session(lesson_id) WHERE capture_state='AUTHORIZED';
CREATE UNIQUE INDEX capture_one_instructor ON drivy.capture_session(instructor_membership_id) WHERE capture_state='AUTHORIZED';
CREATE UNIQUE INDEX capture_one_device ON drivy.capture_session(device_id) WHERE capture_state='AUTHORIZED';
CREATE TABLE drivy.capture_chunk (
 school_id uuid NOT NULL,capture_id uuid NOT NULL,segment_id uuid NOT NULL,chunk_index integer NOT NULL CHECK(chunk_index BETWEEN 0 AND 999),
 segment_index integer NOT NULL CHECK(segment_index BETWEEN 0 AND 199),segment_started_at timestamptz NOT NULL,
 segment_start_reason text NOT NULL CHECK(segment_start_reason IN('START','RESUME','RESTART','PERMISSION_RESTORED','SIGNAL_RECOVERED')),
 content_hash text NOT NULL CHECK(content_hash ~ '^[a-f0-9]{64}$'),point_count integer NOT NULL CHECK(point_count BETWEEN 1 AND 1000),
 first_sequence integer NOT NULL CHECK(first_sequence>=0),last_sequence integer NOT NULL CHECK(last_sequence>=first_sequence),
 first_elapsed_ms integer NOT NULL CHECK(first_elapsed_ms>=0),last_elapsed_ms integer NOT NULL CHECK(last_elapsed_ms>=first_elapsed_ms),
 first_captured_at timestamptz NOT NULL,last_captured_at timestamptz NOT NULL CHECK(last_captured_at>=first_captured_at),
 encrypted_points bytea,key_id text NOT NULL,acknowledged_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(capture_id,segment_id,chunk_index),FOREIGN KEY(school_id,capture_id) REFERENCES drivy.capture_session(school_id,id),
 CHECK(encrypted_points IS NULL OR octet_length(encrypted_points) BETWEEN 29 AND 524288),
 EXCLUDE USING gist(capture_id WITH =,segment_id WITH =,int8range(first_sequence::bigint,last_sequence::bigint+1,'[)') WITH &&)
);
CREATE INDEX capture_chunks_order ON drivy.capture_chunk(capture_id,segment_index,first_sequence);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['capture_installation','capture_device_assessment','recording_choice','capture_session','capture_chunk'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);
  EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY capture_owner ON drivy.%I FOR ALL TO %I USING(true) WITH CHECK(true)',t,current_user);
 END LOOP;
END $$;
CREATE FUNCTION drivy.capture_learner_access(learner uuid,own_only boolean DEFAULT false) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.learner_profile l JOIN drivy.membership m ON m.school_id=l.school_id
 WHERE l.id=learner AND drivy.current_school_member(l.school_id) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
 AND (('LEARNER'=ANY(m.roles) AND l.person_id=m.person_id) OR (NOT own_only AND 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(
 SELECT 1 FROM drivy.training t JOIN drivy.instructor_assignment a ON a.school_id=t.school_id AND a.training_id=t.id
 WHERE t.learner_id=l.id AND a.instructor_membership_id=m.id AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;
CREATE FUNCTION drivy.capture_private_access(lesson uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id
 WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a
 WHERE a.school_id=l.school_id AND a.training_id=l.training_id AND a.instructor_membership_id=m.id
 AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))
$$;
-- Les refus SELF restent prioritaires ; un accord SELF de séance peut lever un refus général.
CREATE FUNCTION drivy.capture_effective_choice(school uuid,learner uuid,lesson uuid) RETURNS uuid
 LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 DECLARE g drivy.recording_choice; s drivy.recording_choice; self_g drivy.recording_choice; self_s drivy.recording_choice;
 BEGIN
  IF school<>nullif(current_setting('app.school_id',true),'')::uuid OR NOT drivy.capture_learner_access(learner,false) THEN RETURN NULL; END IF;
  SELECT * INTO g FROM drivy.recording_choice WHERE school_id=school AND learner_id=learner AND lesson_id IS NULL ORDER BY version DESC LIMIT 1;
  SELECT * INTO self_g FROM drivy.recording_choice WHERE school_id=school AND learner_id=learner AND lesson_id IS NULL AND source='SELF' ORDER BY version DESC LIMIT 1;
  SELECT * INTO s FROM drivy.recording_choice WHERE school_id=school AND learner_id=learner AND lesson_id=lesson ORDER BY version DESC LIMIT 1;
  SELECT * INTO self_s FROM drivy.recording_choice WHERE school_id=school AND learner_id=learner AND lesson_id=lesson AND source='SELF' ORDER BY version DESC LIMIT 1;
  IF self_g.status='REFUSED' THEN g:=self_g; END IF;
  IF self_s.status='REFUSED' THEN s:=self_s; END IF;
  IF s.status='REFUSED' THEN RETURN s.id; END IF;
  IF g.status='REFUSED' AND NOT coalesce(s.source='SELF' AND s.status='ALLOWED',false) THEN RETURN g.id; END IF;
  RETURN coalesce(s.id,g.id);
 END $$;
REVOKE ALL ON FUNCTION drivy.capture_learner_access(uuid,boolean),drivy.capture_private_access(uuid),drivy.capture_effective_choice(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.capture_learner_access(uuid,boolean),drivy.capture_private_access(uuid),drivy.capture_effective_choice(uuid,uuid,uuid) TO drivy_app;
CREATE POLICY installation_read ON drivy.capture_installation FOR SELECT TO drivy_app USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY installation_insert ON drivy.capture_installation FOR INSERT TO drivy_app WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY assessment_read ON drivy.capture_device_assessment FOR SELECT TO drivy_app USING(drivy.current_school_member(school_id) AND person_id=nullif(current_setting('app.person_id',true),'')::uuid AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.id=capture_device_assessment.membership_id AND m.person_id=capture_device_assessment.person_id AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)));
CREATE POLICY assessment_insert ON drivy.capture_device_assessment FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND person_id=nullif(current_setting('app.person_id',true),'')::uuid AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id=capture_device_assessment.school_id AND m.id=capture_device_assessment.membership_id AND m.person_id=capture_device_assessment.person_id AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)));
CREATE POLICY choice_read ON drivy.recording_choice FOR SELECT TO drivy_app USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND drivy.capture_learner_access(learner_id,false));
CREATE POLICY choice_insert ON drivy.recording_choice FOR INSERT TO drivy_app WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND drivy.capture_learner_access(learner_id,source='SELF') AND recorded_by=nullif(current_setting('app.membership_id',true),'')::uuid AND (source='SELF' OR EXISTS(SELECT 1 FROM drivy.membership m WHERE m.id=recording_choice.recorded_by AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles))));
CREATE POLICY capture_read ON drivy.capture_session FOR SELECT TO drivy_app USING(drivy.capture_private_access(lesson_id));
CREATE POLICY capture_insert ON drivy.capture_session FOR INSERT TO drivy_app WITH CHECK(drivy.report_lesson_author(lesson_id) AND person_id=nullif(current_setting('app.person_id',true),'')::uuid AND instructor_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY capture_update ON drivy.capture_session FOR UPDATE TO drivy_app USING(drivy.report_lesson_author(lesson_id) AND person_id=nullif(current_setting('app.person_id',true),'')::uuid) WITH CHECK(drivy.report_lesson_author(lesson_id) AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY chunk_read ON drivy.capture_chunk FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.capture_session c WHERE c.school_id=capture_chunk.school_id AND c.id=capture_id));
CREATE POLICY chunk_insert ON drivy.capture_chunk FOR INSERT TO drivy_app WITH CHECK(EXISTS(SELECT 1 FROM drivy.capture_session c WHERE c.school_id=capture_chunk.school_id AND c.id=capture_id AND drivy.report_lesson_author(c.lesson_id) AND c.person_id=nullif(current_setting('app.person_id',true),'')::uuid));
CREATE POLICY capture_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN('ASSESS_CAPTURE_DEVICE','RECORD_RECORDING_CHOICE','START_CAPTURE','UPLOAD_TRACK_CHUNK','STOP_CAPTURE','FINALIZE_CAPTURE'));
CREATE POLICY capture_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN('CaptureDeviceAssessed','RecordingChoiceRecorded','CaptureAuthorized','TrackChunkAccepted','CaptureStopped','CaptureFinalized'));
GRANT SELECT ON drivy.capture_installation,drivy.capture_device_assessment,drivy.recording_choice,drivy.capture_session,drivy.capture_chunk TO drivy_app;
GRANT INSERT ON drivy.capture_installation,drivy.capture_device_assessment,drivy.recording_choice,drivy.capture_session,drivy.capture_chunk TO drivy_app;
GRANT UPDATE(device_id) ON drivy.capture_installation TO drivy_app;
CREATE POLICY installation_lock ON drivy.capture_installation FOR UPDATE TO drivy_app USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid) WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid);
GRANT UPDATE(version,capture_state,sync_state,stopped_at,cutoff_at,manifest,finalized_at,reconstruction_version) ON drivy.capture_session TO drivy_app;
-- Une borne resserrée détruit les lots touchés ; elle ne réécrit pas leur hash/accusé historique.
CREATE FUNCTION drivy.capture_enforce_cutoff() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.cutoff_at IS NOT NULL AND (OLD.cutoff_at IS NULL OR NEW.cutoff_at<OLD.cutoff_at) THEN
   UPDATE drivy.capture_chunk SET encrypted_points=NULL WHERE capture_id=NEW.id AND last_captured_at>=NEW.cutoff_at;
   NEW.reconstruction_version:=OLD.reconstruction_version+1;
   IF EXISTS(SELECT 1 FROM drivy.capture_chunk WHERE capture_id=NEW.id AND encrypted_points IS NULL) THEN NEW.sync_state:='PARTIAL'; END IF;
  END IF;
  IF OLD.cutoff_at IS NOT NULL AND (NEW.cutoff_at IS NULL OR NEW.cutoff_at>OLD.cutoff_at) THEN RAISE EXCEPTION 'capture cutoff cannot increase' USING ERRCODE='23514'; END IF;
  IF OLD.capture_state<>'AUTHORIZED' AND NEW.capture_state='AUTHORIZED' THEN RAISE EXCEPTION 'capture cannot restart' USING ERRCODE='23514'; END IF;
  RETURN NEW;
 END $$;
CREATE TRIGGER capture_cutoff BEFORE UPDATE ON drivy.capture_session FOR EACH ROW EXECUTE FUNCTION drivy.capture_enforce_cutoff();
-- Une installation personnelle peut quitter une ancienne école après expiration de son bail.
-- Cette fonction ne révèle aucune ressource de l'autre école et ne coupe jamais un bail valide.
CREATE FUNCTION drivy.expire_capture_device(device uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NOT drivy.current_school_member(nullif(current_setting('app.school_id',true),'')::uuid) OR NOT EXISTS(SELECT 1 FROM drivy.capture_installation i WHERE i.device_id=device AND i.person_id=nullif(current_setting('app.person_id',true),'')::uuid) THEN RETURN; END IF;
  UPDATE drivy.capture_session SET capture_state='EXPIRED',cutoff_at=least(coalesce(cutoff_at,expires_at),expires_at),version=version+1
  WHERE device_id=device AND person_id=nullif(current_setting('app.person_id',true),'')::uuid AND capture_state='AUTHORIZED' AND expires_at<=statement_timestamp();
 END $$;
REVOKE ALL ON FUNCTION drivy.expire_capture_device(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.expire_capture_device(uuid) TO drivy_app;
CREATE FUNCTION drivy.capture_choice_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
  WHERE c.school_id=NEW.school_id AND c.learner_id=NEW.learner_id AND c.capture_state='AUTHORIZED' AND NOT EXISTS(
   SELECT 1 FROM drivy.recording_choice r WHERE r.id=drivy.capture_effective_choice(c.school_id,c.learner_id,c.lesson_id) AND r.status='ALLOWED');
  RETURN NEW;
 END $$;
CREATE TRIGGER capture_choice_changed AFTER INSERT ON drivy.recording_choice FOR EACH ROW EXECUTE FUNCTION drivy.capture_choice_changed();
-- La clôture métier borne les données même si l'arrêt réseau du collecteur arrive ensuite.
CREATE FUNCTION drivy.capture_lesson_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF (NEW.planned_start,NEW.planned_end,NEW.instructor_membership_id) IS DISTINCT FROM (OLD.planned_start,OLD.planned_end,OLD.instructor_membership_id)
   AND EXISTS(SELECT 1 FROM drivy.capture_session WHERE lesson_id=OLD.id AND capture_state='AUTHORIZED' AND expires_at>statement_timestamp()) THEN
   RAISE EXCEPTION 'active capture prevents lesson move' USING ERRCODE='23514';
  END IF;
  IF NEW.status<>'PLANNED' THEN
   UPDATE drivy.capture_session SET capture_state=CASE WHEN NEW.status='COMPLETED' THEN 'STOPPED' ELSE 'REVOKED' END,
    cutoff_at=least(coalesce(cutoff_at,expires_at),coalesce(NEW.actual_end,statement_timestamp())),version=version+1
    WHERE lesson_id=NEW.id AND capture_state='AUTHORIZED';
  END IF;RETURN NEW;
 END $$;
CREATE TRIGGER capture_lesson_changed BEFORE UPDATE ON drivy.lesson FOR EACH ROW EXECUTE FUNCTION drivy.capture_lesson_changed();
CREATE FUNCTION drivy.capture_membership_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF (NEW.status,NEW.roles,NEW.access_epoch) IS DISTINCT FROM (OLD.status,OLD.roles,OLD.access_epoch) THEN
   UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
   WHERE c.school_id=NEW.school_id AND c.capture_state='AUTHORIZED' AND (c.instructor_membership_id=NEW.id OR EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=c.learner_id AND l.person_id=NEW.person_id));
  END IF;RETURN NEW;
 END $$;
CREATE TRIGGER capture_membership_changed AFTER UPDATE ON drivy.membership FOR EACH ROW EXECUTE FUNCTION drivy.capture_membership_changed();
CREATE FUNCTION drivy.capture_assignment_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
  FROM drivy.lesson l WHERE c.lesson_id=l.id AND c.instructor_membership_id=OLD.instructor_membership_id AND l.training_id=OLD.training_id AND c.capture_state='AUTHORIZED';
  RETURN NULL;
 END $$;
CREATE TRIGGER capture_assignment_changed AFTER UPDATE OR DELETE ON drivy.instructor_assignment FOR EACH ROW EXECUTE FUNCTION drivy.capture_assignment_changed();
CREATE FUNCTION drivy.capture_school_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.status<>'ACTIVE' OR NOT coalesce((NEW.modules->>'gpsEnabled')::boolean,false) THEN
   UPDATE drivy.capture_session SET capture_state='REVOKED',cutoff_at=least(coalesce(cutoff_at,expires_at),statement_timestamp()),version=version+1 WHERE school_id=NEW.id AND capture_state='AUTHORIZED';
  END IF;RETURN NEW;
 END $$;
CREATE TRIGGER capture_school_changed AFTER UPDATE ON drivy.school FOR EACH ROW EXECUTE FUNCTION drivy.capture_school_changed();
CREATE FUNCTION drivy.capture_training_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.status<>'ACTIVE' THEN
   UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
   FROM drivy.lesson l WHERE c.lesson_id=l.id AND l.training_id=NEW.id AND c.capture_state='AUTHORIZED';
  END IF;RETURN NEW;
 END $$;
CREATE TRIGGER capture_training_changed AFTER UPDATE ON drivy.training FOR EACH ROW EXECUTE FUNCTION drivy.capture_training_changed();
CREATE FUNCTION drivy.capture_notice_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.approved_at IS NOT NULL THEN
   UPDATE drivy.capture_session SET capture_state='REVOKED',cutoff_at=least(coalesce(cutoff_at,expires_at),statement_timestamp()),version=version+1 WHERE school_id=NEW.school_id AND capture_state='AUTHORIZED';
  END IF;RETURN NEW;
 END $$;
CREATE TRIGGER capture_notice_changed AFTER INSERT ON drivy.school_data_policy FOR EACH ROW EXECUTE FUNCTION drivy.capture_notice_changed();
CREATE FUNCTION drivy.capture_person_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.status<>'ACTIVE' THEN
   UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
   WHERE c.capture_state='AUTHORIZED' AND (c.person_id=NEW.id OR EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=c.learner_id AND l.person_id=NEW.id));
  END IF;RETURN NEW;
 END $$;
CREATE TRIGGER capture_person_changed AFTER UPDATE ON drivy.person FOR EACH ROW EXECUTE FUNCTION drivy.capture_person_changed();
CREATE FUNCTION drivy.capture_assessment_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
  FROM drivy.capture_device_assessment a WHERE c.device_assessment_id=a.id AND c.device_id=NEW.device_id AND c.capture_state='AUTHORIZED'
  AND (NEW.status<>'QUALIFIED' OR (a.platform,a.device_class,a.model_code,a.os_version,a.app_build,a.qualification_profile_version) IS DISTINCT FROM (NEW.platform,NEW.device_class,NEW.model_code,NEW.os_version,NEW.app_build,NEW.qualification_profile_version));
  RETURN NEW;
 END $$;
CREATE TRIGGER capture_assessment_changed AFTER INSERT ON drivy.capture_device_assessment FOR EACH ROW EXECUTE FUNCTION drivy.capture_assessment_changed();
REVOKE ALL ON FUNCTION drivy.capture_enforce_cutoff(),drivy.capture_choice_changed(),drivy.capture_lesson_changed(),drivy.capture_membership_changed(),drivy.capture_assignment_changed(),drivy.capture_school_changed(),drivy.capture_training_changed(),drivy.capture_notice_changed(),drivy.capture_person_changed(),drivy.capture_assessment_changed() FROM PUBLIC;
