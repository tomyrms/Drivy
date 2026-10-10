-- Un départ est une commande durable, distincte du créneau et du résultat final.
-- Conserve PLANNED pendant la conduite pour compatibilité du contrat canonique 3.11.0.
ALTER TABLE drivy.lesson DROP CONSTRAINT lesson_actual_interval;
ALTER TABLE drivy.lesson ADD CONSTRAINT lesson_actual_interval CHECK(
 (actual_start IS NULL AND actual_end IS NULL)
 OR (actual_start IS NOT NULL AND (actual_end IS NULL OR actual_end>actual_start)));

CREATE POLICY start_lesson_operation_insert ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND command_type='START_LESSON');
CREATE POLICY start_lesson_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND action='LessonStarted');

-- Répare uniquement les départs explicitement enregistrés dans des preuves existantes.
-- L'heure prévue seule n'est jamais une preuve. Aucune leçon close n'est réinterprétée.
-- NO FORCE est local à la transaction de migration pour l'écriture du propriétaire ;
-- les politiques et FORCE sont rétablies avant le commit.
ALTER TABLE drivy.lesson NO FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.operation NO FORCE ROW LEVEL SECURITY;
WITH evidence AS (
 SELECT school_id,resource_id AS lesson_id,(response_data->>'plannedStart')::timestamptz AS started_at
 FROM drivy.operation WHERE command_type='START_LESSON_NOW' AND response_data->>'plannedStart' IS NOT NULL
 UNION ALL
 SELECT school_id,lesson_id,authorized_at FROM drivy.capture_session
), starts AS (
 SELECT school_id,lesson_id,min(started_at) AS started_at FROM evidence GROUP BY school_id,lesson_id
)
UPDATE drivy.lesson l SET actual_start=s.started_at,version=l.version+1 FROM starts s
WHERE l.school_id=s.school_id AND l.id=s.lesson_id AND l.status='PLANNED' AND l.actual_start IS NULL;
ALTER TABLE drivy.operation FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.lesson FORCE ROW LEVEL SECURITY;

-- Un rendez-vous dépassé mais jamais démarré reste déplaçable explicitement.
CREATE OR REPLACE FUNCTION drivy.lesson_slot_conflict(school uuid,training uuid,instructor uuid,
 starts timestamptz,ends timestamptz,buffer_minutes integer,excluded_lesson uuid DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE learner_person uuid; instructor_person uuid;
BEGIN
 IF drivy.current_school_member(school) IS DISTINCT FROM true
    OR drivy.lesson_access(training,instructor,true) IS DISTINCT FROM true
    OR drivy.lesson_instructor_manage(school,instructor) IS DISTINCT FROM true THEN
  RAISE EXCEPTION 'Planning access required' USING ERRCODE='42501';
 END IF;
 IF starts IS NULL OR ends IS NULL OR NOT isfinite(starts) OR NOT isfinite(ends)
    OR ends<=starts OR ends>starts+interval '8 hours'
    OR buffer_minutes IS NULL OR buffer_minutes NOT BETWEEN 0 AND 240 THEN
  RAISE EXCEPTION 'Invalid planning interval' USING ERRCODE='22023';
 END IF;
 SELECT l.person_id INTO learner_person FROM drivy.training t
 JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
 WHERE t.school_id=school AND t.id=training AND t.status='ACTIVE' AND l.archived_at IS NULL;
 SELECT m.person_id INTO instructor_person FROM drivy.membership m WHERE m.school_id=school AND m.id=instructor;
 IF learner_person IS NULL OR instructor_person IS NULL THEN
  RAISE EXCEPTION 'Planning access required' USING ERRCODE='42501';
 END IF;
 IF excluded_lesson IS NOT NULL AND NOT EXISTS(SELECT 1 FROM drivy.lesson l
    WHERE l.school_id=school AND l.id=excluded_lesson AND l.training_id=training
    AND l.status='PLANNED' AND l.actual_start IS NULL
    AND l.buffer_minutes_snapshot=buffer_minutes
    AND drivy.lesson_access(l.training_id,l.instructor_membership_id,true)) THEN
  RAISE EXCEPTION 'Planning access required' USING ERRCODE='42501';
 END IF;
 RETURN EXISTS(SELECT 1 FROM drivy.reservation r WHERE r.school_id=school AND r.active
  AND r.lesson_id IS DISTINCT FROM excluded_lesson
  AND ((r.resource_id=learner_person AND r.during&&tstzrange(starts,ends,'[)'))
    OR (r.resource_id=instructor_person AND r.during&&tstzrange(starts,ends+make_interval(mins=>buffer_minutes),'[)'))));
END $$;
REVOKE ALL ON FUNCTION drivy.lesson_slot_conflict(uuid,uuid,uuid,timestamptz,timestamptz,integer,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_slot_conflict(uuid,uuid,uuid,timestamptz,timestamptz,integer,uuid) TO drivy_app;
