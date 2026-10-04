-- Prévalidation anonyme : les contraintes d'exclusion voient les occupations que la RLS
-- masque au moniteur. Cette fonction ne renvoie qu'un booléen et conserve ces lectures privées.
CREATE FUNCTION drivy.lesson_slot_conflict(school uuid,training uuid,instructor uuid,
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
    AND l.status='PLANNED' AND l.planned_start>statement_timestamp() AND l.actual_start IS NULL
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
