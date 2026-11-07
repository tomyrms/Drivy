-- Audit du 7 novembre 2026, lot A (#423, #439). Migration additive : aucune migration livrée n'est modifiée.
-- 1. Engagements d'un moniteur qui chevauchent une période de fermeture (congé) : leçons planifiées, séances de cours publiées,
--    accompagnements d'examens prévus. Lecture seule, réservée à qui peut gérer ce moniteur (même droit que la création du congé).
--    Intervalles semi-ouverts [début, fin) : un engagement qui commence quand le congé finit ne le chevauche pas.
CREATE FUNCTION drivy.closure_bookings(school uuid,instructor uuid,starts timestamptz,ends timestamptz) RETURNS TABLE(lessons integer,courses integer,exams integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
 IF NOT drivy.lesson_instructor_manage(school,instructor) THEN RAISE EXCEPTION USING ERRCODE='42501',MESSAGE='ACCESS_DENIED'; END IF;
 RETURN QUERY SELECT
  (SELECT count(*)::integer FROM drivy.lesson l WHERE l.school_id=school AND l.instructor_membership_id=instructor AND l.status='PLANNED'
    AND tstzrange(l.planned_start,l.planned_end,'[)')&&tstzrange(starts,ends,'[)')),
  (SELECT count(*)::integer FROM drivy.course_occurrence o JOIN drivy.course_series s ON s.id=o.series_id AND s.school_id=o.school_id
    WHERE o.school_id=school AND o.instructor_membership_id=instructor AND s.status='PUBLISHED'
    AND tstzrange(o.starts_at,o.ends_at,'[)')&&tstzrange(starts,ends,'[)')),
  (SELECT count(*)::integer FROM drivy.exam e WHERE e.school_id=school AND e.escort_instructor_membership_id=instructor AND e.status='SCHEDULED'
    AND e.escort_starts_at IS NOT NULL AND tstzrange(e.escort_starts_at,e.escort_ends_at,'[)')&&tstzrange(starts,ends,'[)'));
END $$;
REVOKE ALL ON FUNCTION drivy.closure_bookings(uuid,uuid,timestamptz,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.closure_bookings(uuid,uuid,timestamptz,timestamptz) TO drivy_app;

-- 2. Changement de dates d'une série publiée : mêmes règles que 043, avec en plus
--    * bijection vérifiée ICI (appel interne compris) entre les positions reçues et celles de la série, avant toute écriture :
--      une position répétée, manquante ou inconnue est refusée, même à cardinalité égale (#439) ;
--    * refus d'une séance qui recouvre une fermeture du moniteur (#423).
--    Les dates décalées de 100 ans ne sont qu'un état intermédiaire de la transaction : tout refus annule tout.
CREATE OR REPLACE FUNCTION drivy.course_reschedule(series uuid,changes jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership; item jsonb; first_start timestamptz; enrollment uuid; received integer[]; existing integer[];
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL OR NOT drivy.can_manage_courses(s.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 IF s.status<>'PUBLISHED' THEN PERFORM drivy.course_fail('COURSE_NOT_PUBLISHED'); END IF;
 IF drivy.course_first_start(series)<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_STARTED'); END IF;
 IF jsonb_typeof(changes) IS DISTINCT FROM 'array' THEN PERFORM drivy.course_fail('INVALID_REQUEST'); END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(changes) e WHERE jsonb_typeof(e) IS DISTINCT FROM 'object' OR jsonb_typeof(e->'position') IS DISTINCT FROM 'number'
   OR (e->>'position') !~ '^[1-9][0-9]{0,5}$') THEN PERFORM drivy.course_fail('COURSE_POSITIONS_MISMATCH'); END IF;
 IF jsonb_array_length(changes)<>(SELECT count(*) FROM drivy.course_occurrence WHERE series_id=series) THEN PERFORM drivy.course_fail('COURSE_OCCURRENCE_COUNT'); END IF;
 SELECT coalesce(array_agg((e->>'position')::integer ORDER BY (e->>'position')::integer),'{}') INTO received FROM jsonb_array_elements(changes) e;
 SELECT coalesce(array_agg(position ORDER BY position),'{}') INTO existing FROM drivy.course_occurrence WHERE series_id=series;
 IF received IS DISTINCT FROM existing THEN PERFORM drivy.course_fail('COURSE_POSITIONS_MISMATCH'); END IF;
 UPDATE drivy.reservation r SET active=false FROM drivy.course_occurrence o WHERE r.course_occurrence_id=o.id AND o.series_id=series AND r.active;
 -- Positions décalées d'abord pour ne pas heurter l'exclusion interne pendant la réécriture.
 UPDATE drivy.course_occurrence SET starts_at=starts_at+interval '100 years',ends_at=ends_at+interval '100 years' WHERE series_id=series;
 FOR item IN SELECT * FROM jsonb_array_elements(changes) LOOP
  IF (item->>'startsAt')::timestamptz<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_IN_PAST'); END IF;
  IF NOT EXISTS(SELECT 1 FROM drivy.course_instructors(s.school_id) i WHERE i.membership_id=(item->>'instructorMembershipId')::uuid) THEN PERFORM drivy.course_fail('INSTRUCTOR_NOT_ACTIVE'); END IF;
  IF EXISTS(SELECT 1 FROM drivy.closure c WHERE c.school_id=s.school_id AND c.instructor_membership_id=(item->>'instructorMembershipId')::uuid AND c.removed_at IS NULL
    AND tstzrange(c.starts_at,c.ends_at,'[)')&&tstzrange((item->>'startsAt')::timestamptz,(item->>'endsAt')::timestamptz,'[)')) THEN PERFORM drivy.course_fail('COURSE_INSTRUCTOR_CLOSED'); END IF;
  UPDATE drivy.course_occurrence SET starts_at=(item->>'startsAt')::timestamptz,ends_at=(item->>'endsAt')::timestamptz,
   instructor_membership_id=(item->>'instructorMembershipId')::uuid WHERE series_id=series AND position=(item->>'position')::integer;
  IF NOT FOUND THEN PERFORM drivy.course_fail('COURSE_POSITIONS_MISMATCH'); END IF;
 END LOOP;
 INSERT INTO drivy.reservation(school_id,course_occurrence_id,resource_id,resource_role,during)
  SELECT o.school_id,o.id,m.person_id,'INSTRUCTOR',tstzrange(o.starts_at,o.ends_at,'[)') FROM drivy.course_occurrence o JOIN drivy.membership m ON m.school_id=o.school_id AND m.id=o.instructor_membership_id
  WHERE o.series_id=series;
 first_start:=drivy.course_first_start(series);
 FOR enrollment IN SELECT id FROM drivy.course_enrollment WHERE series_id=series AND status='ACTIVE' ORDER BY id LOOP
  PERFORM drivy.course_occupy_learner(enrollment);
  UPDATE drivy.course_enrollment SET self_cancel_deadline=greatest(self_cancel_deadline,first_start-make_interval(hours=>self_cancel_hours)),version=version+1 WHERE id=enrollment;
 END LOOP;
 UPDATE drivy.course_waitlist_entry w SET status='WAITING' FROM drivy.course_seat_offer o WHERE o.entry_id=w.id AND o.series_id=series AND o.status='ACTIVE';
 UPDATE drivy.course_seat_offer SET status='REVOKED',resolved_at=statement_timestamp() WHERE series_id=series AND status='ACTIVE';
 UPDATE drivy.course_series SET version=version+1,updated_at=statement_timestamp() WHERE id=series;
 INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,operation_id) VALUES(s.school_id,series,s.version+1,'CourseSeriesRescheduled',gen_random_uuid());
 PERFORM drivy.course_queue_advance(series);
END $$;
