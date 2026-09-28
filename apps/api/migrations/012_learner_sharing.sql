-- Partage automatique avec l'élève, décidé par le porteur le 28 septembre 2026 (remplace la publication explicite).
-- Trajet, observations et bilan d'une leçon réalisée sont lisibles par l'élève, sauf ce que le moniteur garde privé.
ALTER TABLE drivy.lesson ADD COLUMN report_private boolean NOT NULL DEFAULT false;
ALTER TABLE drivy.lesson ADD COLUMN capture_hidden boolean NOT NULL DEFAULT false;
ALTER TABLE drivy.lesson ADD COLUMN sharing_version integer NOT NULL DEFAULT 1 CHECK(sharing_version>0);
ALTER TABLE drivy.geo_observation ADD COLUMN private boolean NOT NULL DEFAULT false;
GRANT UPDATE(report_private,capture_hidden,sharing_version) ON drivy.lesson TO drivy_app;
GRANT UPDATE(private) ON drivy.geo_observation TO drivy_app;

-- Un bilan partagé automatiquement peut ne contenir qu'une partie des trois textes, ou seulement des appréciations.
DO $$ DECLARE c text; BEGIN
 SELECT conname INTO c FROM pg_constraint WHERE conrelid='drivy.report_revision'::regclass AND contype='c'
  AND pg_get_constraintdef(oid) LIKE '%btrim(worked_on)%' AND pg_get_constraintdef(oid) LIKE '%btrim(next_step)%';
 IF c IS NULL THEN RAISE EXCEPTION 'report_revision text constraint not found'; END IF;
 EXECUTE format('ALTER TABLE drivy.report_revision DROP CONSTRAINT %I',c);
END $$;
ALTER TABLE drivy.report_revision ADD CONSTRAINT report_revision_content CHECK(
 char_length(worked_on)<=4000 AND char_length(observation_text)<=4000 AND char_length(next_step)<=4000
 AND (char_length(btrim(worked_on||observation_text||next_step))>0 OR jsonb_array_length(observations)>0));

-- Leçon réalisée de l'élève connecté ; `capture` exclut aussi un trajet masqué par le moniteur.
CREATE FUNCTION drivy.learner_shared_lesson(lesson uuid,kind text) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.learner_profile lp ON lp.school_id=l.school_id AND lp.id=l.learner_id
  JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=lp.person_id
  WHERE l.id=lesson AND l.status='COMPLETED' AND drivy.current_school_member(l.school_id)
  AND lp.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles)
  AND (kind<>'capture' OR NOT l.capture_hidden))
$$;
REVOKE ALL ON FUNCTION drivy.learner_shared_lesson(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.learner_shared_lesson(uuid,text) TO drivy_app;

CREATE POLICY observation_learner_read ON drivy.geo_observation FOR SELECT TO drivy_app
 USING(NOT private AND removed_at IS NULL AND drivy.learner_shared_lesson(lesson_id,'observation'));
-- Les lots suivent la session par leur politique existante : un trajet visible donne accès à ses mesures, rien d'autre.
CREATE POLICY capture_learner_read ON drivy.capture_session FOR SELECT TO drivy_app
 USING(publication_state='PRIVATE' AND finalized_at IS NOT NULL AND sync_state IN('SYNCED','PARTIAL') AND drivy.learner_shared_lesson(lesson_id,'capture'));
-- Les objectifs de la leçon sont montrés à l'élève ; la note administrative reste masquée par l'API.
CREATE POLICY preparation_learner_read ON drivy.lesson_preparation FOR SELECT TO drivy_app
 USING(EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.school_id=lesson_preparation.school_id AND l.id=lesson_id AND drivy.report_training_access(l.training_id,true)));

CREATE POLICY sharing_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type='UPDATE_LESSON_SHARING');
CREATE POLICY sharing_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action='LessonSharingUpdated');
