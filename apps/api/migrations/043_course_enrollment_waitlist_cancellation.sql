-- Cours collectifs : inscriptions (#39), file prioritaire (#40), annulations et changements de dates (#41).
-- Décisions : docs/implementation/cours-collectifs-cadrage-79.md ; contrat : cours-collectifs-inscriptions-39-41.md.
-- Toutes les mutations passent par des fonctions SECURITY DEFINER qui relisent les droits, verrouillent la série et utilisent le
-- seul compteur drivy.course_seats_taken. Les occupations élèves vont dans drivy.reservation : l'exclusion partagée avec les
-- leçons refuse tout chevauchement, y compris en concurrence, et annule toute la transaction (pas de réservation partielle).
-- Aucune donnée existante n'est modifiée.

-- Erreurs métier : SQLSTATE P0001, message = code stable lu par l'API.
CREATE FUNCTION drivy.course_fail(code text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE=code; END $$;
-- Les fonctions ci-dessous s'exécutent comme propriétaire du schéma : écriture des occupations sous la même exclusion.
DO $$ BEGIN EXECUTE format('CREATE POLICY course_owner_reservation ON drivy.reservation TO %I USING(true) WITH CHECK(true)',current_user); END $$;

CREATE FUNCTION drivy.course_actor_membership(school uuid) RETURNS drivy.membership LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.* FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND p.status='ACTIVE'
  AND drivy.current_school_member(school)
$$;

-- Élève admissible : appartenance LEARNER active, dossier non archivé, type non validé, pas déjà inscrit à la série
-- ni à une autre série active à venir du même type (#79, proposition : pas d'inscriptions équivalentes simultanées).
CREATE FUNCTION drivy.course_learner_admissible(series uuid,learner uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT CASE
  WHEN NOT EXISTS(SELECT 1 FROM drivy.learner_profile l JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=l.person_id JOIN drivy.person p ON p.id=l.person_id
   WHERE l.id=learner AND l.school_id=s.school_id AND l.archived_at IS NULL AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles) AND p.status='ACTIVE') THEN 'LEARNER_NOT_ACTIVE'
  WHEN EXISTS(SELECT 1 FROM drivy.course_completion c WHERE c.learner_id=learner AND c.type_id=s.type_id AND c.revoked_at IS NULL) THEN 'COURSE_ALREADY_COMPLETED'
  WHEN EXISTS(SELECT 1 FROM drivy.course_enrollment e WHERE e.series_id=s.id AND e.learner_id=learner AND e.status='ACTIVE') THEN 'COURSE_ALREADY_ENROLLED'
  WHEN EXISTS(SELECT 1 FROM drivy.course_enrollment e JOIN drivy.course_series o ON o.id=e.series_id
   WHERE e.learner_id=learner AND e.status='ACTIVE' AND o.type_id=s.type_id AND o.id<>s.id AND o.status='PUBLISHED'
   AND EXISTS(SELECT 1 FROM drivy.course_occurrence x WHERE x.series_id=o.id AND x.ends_at>statement_timestamp())) THEN 'COURSE_EQUIVALENT_ENROLLED'
  END
 FROM drivy.course_series s WHERE s.id=series
$$;

CREATE FUNCTION drivy.course_first_start(series uuid) RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT min(starts_at) FROM drivy.course_occurrence WHERE series_id=series
$$;

-- Moteur de file (#40). Idempotent, appelé sous le verrou de la série par chaque commande qui la touche et par les lectures.
-- 1. Propositions échues : EXPIRED, entrée EXPIRED (la personne quitte la file).
-- 2. Tant qu'il reste une place libre et que la file est activée : proposer au premier WAITING admissible (ordre d'entrée).
--    Échéance = min(maintenant + délai de l'école, première séance - 2 h). Moins de 30 min possibles : aucune proposition,
--    la place reste libre pour une inscription directe. Valeurs 2 h et 30 min : propositions provisoires (#79).
--    Une entrée devenue non admissible est retirée (REMOVED) et la file avance.
CREATE FUNCTION drivy.course_queue_advance(series uuid) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; response integer; first_start timestamptz; deadline timestamptz; entry drivy.course_waitlist_entry; offered integer:=0; reason text;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND OR drivy.current_school_member(s.school_id) IS DISTINCT FROM true THEN RETURN 0; END IF;
 WITH expired AS (UPDATE drivy.course_seat_offer SET status='EXPIRED',resolved_at=statement_timestamp()
   WHERE series_id=series AND status='ACTIVE' AND expires_at<=statement_timestamp() RETURNING entry_id)
 UPDATE drivy.course_waitlist_entry w SET status='EXPIRED',resolved_at=statement_timestamp() FROM expired WHERE w.id=expired.entry_id AND w.status='OFFERED';
 IF s.status<>'PUBLISHED' THEN RETURN 0; END IF;
 first_start:=drivy.course_first_start(series);
 IF first_start IS NULL OR first_start<=statement_timestamp() THEN RETURN 0; END IF;
 SELECT offer_response_minutes INTO response FROM drivy.course_policy_version WHERE school_id=s.school_id ORDER BY version DESC LIMIT 1;
 IF response IS NULL THEN RETURN 0; END IF;
 deadline:=least(statement_timestamp()+make_interval(mins=>response),first_start-interval '2 hours');
 IF deadline<statement_timestamp()+interval '30 minutes' THEN RETURN 0; END IF;
 WHILE drivy.course_seats_taken(series)<s.capacity LOOP
  SELECT * INTO entry FROM drivy.course_waitlist_entry WHERE series_id=series AND status='WAITING' ORDER BY queued_at,seq LIMIT 1 FOR UPDATE;
  EXIT WHEN NOT FOUND;
  reason:=drivy.course_learner_admissible(series,entry.learner_id);
  IF reason IS NOT NULL THEN
   UPDATE drivy.course_waitlist_entry SET status='REMOVED',resolved_at=statement_timestamp() WHERE id=entry.id; CONTINUE;
  END IF;
  UPDATE drivy.course_waitlist_entry SET status='OFFERED' WHERE id=entry.id;
  INSERT INTO drivy.course_seat_offer(school_id,series_id,entry_id,expires_at) VALUES(s.school_id,series,entry.id,deadline);
  INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,target_learner_id,valid_until,operation_id)
   VALUES(s.school_id,series,s.version,'CourseSeatOffered:'||entry.id,entry.learner_id,deadline,gen_random_uuid());
  offered:=offered+1;
 END LOOP;
 RETURN offered;
END $$;

-- Avance toutes les files d'une école (lectures de l'agenda) : rend visibles les propositions dues sans attendre une commande.
CREATE FUNCTION drivy.course_queue_advance_school(school uuid) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE total integer:=0; sid uuid;
BEGIN
 IF drivy.current_school_member(school) IS DISTINCT FROM true THEN RETURN 0; END IF;
 FOR sid IN SELECT DISTINCT s.id FROM drivy.course_series s WHERE s.school_id=school AND s.status='PUBLISHED' AND (
   EXISTS(SELECT 1 FROM drivy.course_seat_offer o WHERE o.series_id=s.id AND o.status='ACTIVE' AND o.expires_at<=statement_timestamp())
   OR (EXISTS(SELECT 1 FROM drivy.course_waitlist_entry w WHERE w.series_id=s.id AND w.status='WAITING') AND drivy.course_seats_taken(s.id)<s.capacity))
  ORDER BY s.id LOOP
  total:=total+drivy.course_queue_advance(sid);
 END LOOP;
 RETURN total;
END $$;

-- Occupation de l'élève sur toutes les séances futures. Un chevauchement lève 23P01 et annule toute la commande.
CREATE FUNCTION drivy.course_occupy_learner(enrollment uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 INSERT INTO drivy.reservation(school_id,course_occurrence_id,course_enrollment_id,resource_id,resource_role,during)
 SELECT e.school_id,o.id,e.id,l.person_id,'LEARNER',tstzrange(o.starts_at,o.ends_at,'[)')
 FROM drivy.course_enrollment e JOIN drivy.learner_profile l ON l.id=e.learner_id JOIN drivy.course_occurrence o ON o.series_id=e.series_id
 WHERE e.id=enrollment AND o.ends_at>statement_timestamp() ORDER BY o.position
$$;
CREATE FUNCTION drivy.course_release_learner(enrollment uuid) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 UPDATE drivy.reservation SET active=false WHERE course_enrollment_id=enrollment AND active AND upper(during)>statement_timestamp()
$$;

-- Inscription (#39) : élève pour lui-même (SELF), personnel habilité à la demande de l'élève (STAFF), acceptation d'une
-- proposition (OFFER, via course_accept_offer). Toute la série, une seule place, conditions copiées.
CREATE FUNCTION drivy.course_enroll(series uuid,learner uuid,source text,offer uuid DEFAULT NULL) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership; first_start timestamptz; reason text; taken integer; enrollment uuid; own_offer boolean:=false;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 IF source='STAFF' THEN
  IF NOT drivy.can_manage_courses(s.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 ELSIF source IN('SELF','OFFER') THEN
  IF NOT EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner AND l.school_id=s.school_id AND l.person_id=actor.person_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 ELSE PERFORM drivy.course_fail('INVALID_REQUEST'); END IF;
 -- Un brouillon n'existe pas pour l'élève (même règle que la lecture).
 IF s.status='DRAFT' AND NOT drivy.can_manage_courses(s.school_id) THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 -- Propositions échues et passage au suivant d'abord : une place promise n'est jamais prise par une inscription directe.
 PERFORM drivy.course_queue_advance(series);
 SELECT * INTO s FROM drivy.course_series WHERE id=series;
 IF s.status<>'PUBLISHED' THEN PERFORM drivy.course_fail('COURSE_NOT_OPEN'); END IF;
 first_start:=drivy.course_first_start(series);
 IF first_start IS NULL OR first_start<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_STARTED'); END IF;
 reason:=drivy.course_learner_admissible(series,learner);
 IF reason IS NOT NULL THEN PERFORM drivy.course_fail(reason); END IF;
 IF offer IS NOT NULL THEN
  own_offer:=EXISTS(SELECT 1 FROM drivy.course_seat_offer o JOIN drivy.course_waitlist_entry w ON w.id=o.entry_id
   WHERE o.id=offer AND o.series_id=series AND o.status='ACTIVE' AND o.expires_at>statement_timestamp() AND w.learner_id=learner);
  IF NOT own_offer THEN PERFORM drivy.course_fail('COURSE_OFFER_EXPIRED'); END IF;
 END IF;
 taken:=drivy.course_seats_taken(series)-CASE WHEN own_offer THEN 1 ELSE 0 END;
 IF taken>=s.capacity THEN PERFORM drivy.course_fail('COURSE_FULL'); END IF;
 INSERT INTO drivy.course_enrollment(school_id,series_id,learner_id,source,policy_version,self_cancel_hours,self_cancel_deadline,created_by)
  VALUES(s.school_id,series,learner,source,s.policy_version,s.self_cancel_hours,first_start-make_interval(hours=>s.self_cancel_hours),actor.id) RETURNING id INTO enrollment;
 PERFORM drivy.course_occupy_learner(enrollment);
 -- Une inscription confirmée retire la personne de l'attente de cette série seulement.
 UPDATE drivy.course_seat_offer o SET status=CASE WHEN o.id=offer THEN 'ACCEPTED' ELSE 'REVOKED' END,resolved_at=statement_timestamp(),
  enrollment_id=CASE WHEN o.id=offer THEN enrollment END
  FROM drivy.course_waitlist_entry w WHERE w.id=o.entry_id AND o.series_id=series AND o.status='ACTIVE' AND w.learner_id=learner;
 UPDATE drivy.course_waitlist_entry SET status='ACCEPTED',resolved_at=statement_timestamp() WHERE series_id=series AND learner_id=learner AND status IN('WAITING','OFFERED');
 UPDATE drivy.course_series SET version=version+1 WHERE id=series;
 INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,target_learner_id,operation_id)
  VALUES(s.school_id,series,s.version+1,'CourseEnrolled',learner,gen_random_uuid());
 RETURN enrollment;
END $$;

-- File (#40) : entrée volontaire seulement quand la série est complète et la file activée ; retrait libre.
CREATE FUNCTION drivy.course_join_waitlist(series uuid,learner uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership; reason text; entry uuid; response integer;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL OR NOT EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner AND l.school_id=s.school_id AND l.person_id=actor.person_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 PERFORM drivy.course_queue_advance(series);
 SELECT offer_response_minutes INTO response FROM drivy.course_policy_version WHERE school_id=s.school_id ORDER BY version DESC LIMIT 1;
 IF response IS NULL THEN PERFORM drivy.course_fail('COURSE_WAITLIST_DISABLED'); END IF;
 IF s.status<>'PUBLISHED' OR drivy.course_first_start(series)<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_NOT_OPEN'); END IF;
 reason:=drivy.course_learner_admissible(series,learner);
 IF reason IS NOT NULL THEN PERFORM drivy.course_fail(reason); END IF;
 IF drivy.course_seats_taken(series)<s.capacity THEN PERFORM drivy.course_fail('COURSE_SEATS_AVAILABLE'); END IF;
 SELECT id INTO entry FROM drivy.course_waitlist_entry WHERE series_id=series AND learner_id=learner AND status IN('WAITING','OFFERED');
 IF entry IS NOT NULL THEN RETURN entry; END IF;
 INSERT INTO drivy.course_waitlist_entry(school_id,series_id,learner_id) VALUES(s.school_id,series,learner) RETURNING id INTO entry;
 RETURN entry;
END $$;
CREATE FUNCTION drivy.course_leave_waitlist(series uuid,learner uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL OR NOT EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner AND l.school_id=s.school_id AND l.person_id=actor.person_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 UPDATE drivy.course_seat_offer o SET status='DECLINED',resolved_at=statement_timestamp() FROM drivy.course_waitlist_entry w
  WHERE w.id=o.entry_id AND o.series_id=series AND o.status='ACTIVE' AND w.learner_id=learner;
 UPDATE drivy.course_waitlist_entry SET status='WITHDRAWN',resolved_at=statement_timestamp() WHERE series_id=series AND learner_id=learner AND status IN('WAITING','OFFERED');
 PERFORM drivy.course_queue_advance(series);
END $$;
-- Acceptation : conversion atomique en inscription via la règle unique de #39. Refus : passage au suivant.
CREATE FUNCTION drivy.course_accept_offer(offer uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE o drivy.course_seat_offer; learner uuid;
BEGIN
 SELECT * INTO o FROM drivy.course_seat_offer WHERE id=offer;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 PERFORM 1 FROM drivy.course_series WHERE id=o.series_id FOR UPDATE;
 SELECT w.learner_id INTO learner FROM drivy.course_waitlist_entry w JOIN drivy.learner_profile l ON l.id=w.learner_id
  WHERE w.id=o.entry_id AND l.person_id=nullif(current_setting('app.person_id',true),'')::uuid;
 IF learner IS NULL THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 RETURN drivy.course_enroll(o.series_id,learner,'OFFER',offer);
END $$;
CREATE FUNCTION drivy.course_decline_offer(offer uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE o drivy.course_seat_offer;
BEGIN
 SELECT * INTO o FROM drivy.course_seat_offer WHERE id=offer;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM drivy.course_waitlist_entry w JOIN drivy.learner_profile l ON l.id=w.learner_id
   WHERE w.id=o.entry_id AND l.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.current_school_member(l.school_id)) THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 PERFORM 1 FROM drivy.course_series WHERE id=o.series_id FOR UPDATE;
 PERFORM drivy.course_queue_advance(o.series_id);
 UPDATE drivy.course_seat_offer SET status='DECLINED',resolved_at=statement_timestamp() WHERE id=offer AND status='ACTIVE';
 IF NOT FOUND THEN PERFORM drivy.course_fail('COURSE_OFFER_EXPIRED'); END IF;
 UPDATE drivy.course_waitlist_entry SET status='DECLINED',resolved_at=statement_timestamp() WHERE id=o.entry_id;
 PERFORM drivy.course_queue_advance(o.series_id);
END $$;

-- Annulation d'une inscription (#41). SELF : l'élève, seulement jusqu'à l'échéance acceptée incluse (heure serveur).
-- STAFF : personnel habilité, à tout moment avant la fin de la série, motif obligatoire. Place libérée une seule fois.
CREATE FUNCTION drivy.course_cancel_enrollment(enrollment uuid,kind text,reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE e drivy.course_enrollment; actor drivy.membership;
BEGIN
 SELECT * INTO e FROM drivy.course_enrollment WHERE id=enrollment;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(e.school_id);
 IF actor.id IS NULL THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 PERFORM 1 FROM drivy.course_series WHERE id=e.series_id FOR UPDATE;
 SELECT * INTO e FROM drivy.course_enrollment WHERE id=enrollment FOR UPDATE;
 IF kind='SELF' THEN
  IF NOT EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=e.learner_id AND l.person_id=actor.person_id) THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
  IF e.status<>'ACTIVE' THEN PERFORM drivy.course_fail('COURSE_ENROLLMENT_CLOSED'); END IF;
  IF statement_timestamp()>e.self_cancel_deadline THEN PERFORM drivy.course_fail('COURSE_SELF_CANCEL_CLOSED'); END IF;
 ELSIF kind='STAFF' THEN
  IF NOT drivy.can_manage_courses(e.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
  IF e.status<>'ACTIVE' THEN PERFORM drivy.course_fail('COURSE_ENROLLMENT_CLOSED'); END IF;
  IF reason IS NULL OR btrim(reason)='' THEN PERFORM drivy.course_fail('COURSE_REASON_REQUIRED'); END IF;
 ELSE PERFORM drivy.course_fail('INVALID_REQUEST'); END IF;
 UPDATE drivy.course_enrollment SET status='CANCELLED',version=version+1,cancelled_at=statement_timestamp(),cancelled_by=actor.id,cancel_kind=kind,cancel_reason=nullif(btrim(reason),'')
  WHERE id=enrollment;
 PERFORM drivy.course_release_learner(enrollment);
 UPDATE drivy.course_series SET version=version+1 WHERE id=e.series_id;
 INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,target_learner_id,operation_id)
  SELECT e.school_id,e.series_id,version,'CourseEnrollmentCancelled:'||enrollment,e.learner_id,gen_random_uuid() FROM drivy.course_series WHERE id=e.series_id;
 PERFORM drivy.course_queue_advance(e.series_id);
END $$;

-- Annulation de la série par l'école (#41) : inscriptions annulées (SERIES_CANCELLED), file fermée, propositions révoquées,
-- occupations futures libérées. L'historique et les présences restent.
CREATE FUNCTION drivy.course_cancel_series(series uuid,reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL OR NOT drivy.can_manage_courses(s.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 IF s.status<>'PUBLISHED' THEN PERFORM drivy.course_fail('COURSE_NOT_PUBLISHED'); END IF;
 IF reason IS NULL OR btrim(reason)='' THEN PERFORM drivy.course_fail('COURSE_REASON_REQUIRED'); END IF;
 UPDATE drivy.course_enrollment SET status='CANCELLED',version=version+1,cancelled_at=statement_timestamp(),cancelled_by=actor.id,cancel_kind='SERIES_CANCELLED',cancel_reason=btrim(reason)
  WHERE series_id=series AND status='ACTIVE';
 UPDATE drivy.course_seat_offer SET status='REVOKED',resolved_at=statement_timestamp() WHERE series_id=series AND status='ACTIVE';
 UPDATE drivy.course_waitlist_entry SET status='REMOVED',resolved_at=statement_timestamp() WHERE series_id=series AND status IN('WAITING','OFFERED');
 UPDATE drivy.reservation r SET active=false FROM drivy.course_occurrence o WHERE r.course_occurrence_id=o.id AND o.series_id=series AND r.active AND upper(r.during)>statement_timestamp();
 UPDATE drivy.course_series SET status='CANCELLED',cancelled_at=statement_timestamp(),cancel_reason=btrim(reason),version=version+1,updated_at=statement_timestamp() WHERE id=series;
 INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,operation_id) VALUES(s.school_id,series,s.version+1,'CourseSeriesCancelled',gen_random_uuid());
END $$;

-- Changement de dates d'une série publiée (#41). Même nombre de séances, mise à jour par position. Toutes les occupations
-- (formateurs et inscrits) sont recréées ; un conflit annule tout (pas de mise à jour partielle, pas de désinscription).
-- Échéances existantes : gardées, sauf si la nouvelle est plus favorable (plus tardive). Propositions actives révoquées puis
-- réémises sur les nouvelles dates : une réponse à une ancienne proposition est refusée.
CREATE FUNCTION drivy.course_reschedule(series uuid,changes jsonb) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership; item jsonb; first_start timestamptz; enrollment uuid;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL OR NOT drivy.can_manage_courses(s.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 IF s.status<>'PUBLISHED' THEN PERFORM drivy.course_fail('COURSE_NOT_PUBLISHED'); END IF;
 IF drivy.course_first_start(series)<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_STARTED'); END IF;
 IF jsonb_array_length(changes)<>(SELECT count(*) FROM drivy.course_occurrence WHERE series_id=series) THEN PERFORM drivy.course_fail('COURSE_OCCURRENCE_COUNT'); END IF;
 UPDATE drivy.reservation r SET active=false FROM drivy.course_occurrence o WHERE r.course_occurrence_id=o.id AND o.series_id=series AND r.active;
 -- Positions décalées d'abord pour ne pas heurter l'exclusion interne pendant la réécriture.
 UPDATE drivy.course_occurrence SET starts_at=starts_at+interval '100 years',ends_at=ends_at+interval '100 years' WHERE series_id=series;
 FOR item IN SELECT * FROM jsonb_array_elements(changes) LOOP
  IF (item->>'startsAt')::timestamptz<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_IN_PAST'); END IF;
  IF NOT EXISTS(SELECT 1 FROM drivy.course_instructors(s.school_id) i WHERE i.membership_id=(item->>'instructorMembershipId')::uuid) THEN PERFORM drivy.course_fail('INSTRUCTOR_NOT_ACTIVE'); END IF;
  UPDATE drivy.course_occurrence SET starts_at=(item->>'startsAt')::timestamptz,ends_at=(item->>'endsAt')::timestamptz,
   instructor_membership_id=(item->>'instructorMembershipId')::uuid WHERE series_id=series AND position=(item->>'position')::integer;
  IF NOT FOUND THEN PERFORM drivy.course_fail('COURSE_OCCURRENCE_COUNT'); END IF;
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

-- Rang dans la file pour l'élève lui-même : un nombre, jamais les autres personnes (RLS les lui masque).
CREATE FUNCTION drivy.course_waitlist_rank(entry uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT count(*)::integer FROM drivy.course_waitlist_entry w JOIN drivy.course_waitlist_entry me ON me.id=entry AND me.series_id=w.series_id
 JOIN drivy.learner_profile l ON l.id=me.learner_id
 WHERE w.status IN('WAITING','OFFERED') AND (w.queued_at,w.seq)<=(me.queued_at,me.seq)
  AND (l.person_id=nullif(current_setting('app.person_id',true),'')::uuid OR drivy.can_manage_courses(me.school_id))
$$;
REVOKE ALL ON FUNCTION drivy.course_waitlist_rank(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_waitlist_rank(uuid) TO drivy_app;

DO $$ DECLARE f text; BEGIN
 FOREACH f IN ARRAY ARRAY['course_fail(text)','course_actor_membership(uuid)','course_learner_admissible(uuid,uuid)','course_first_start(uuid)','course_queue_advance(uuid)',
  'course_queue_advance_school(uuid)','course_occupy_learner(uuid)','course_release_learner(uuid)','course_enroll(uuid,uuid,text,uuid)','course_join_waitlist(uuid,uuid)',
  'course_leave_waitlist(uuid,uuid)','course_accept_offer(uuid)','course_decline_offer(uuid)','course_cancel_enrollment(uuid,text,text)','course_cancel_series(uuid,text)','course_reschedule(uuid,jsonb)'] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION drivy.%s FROM PUBLIC',f);
 END LOOP;
 -- Seules les commandes et l'avance de file sont appelables par l'application ; les aides internes restent privées.
 FOREACH f IN ARRAY ARRAY['course_queue_advance(uuid)','course_queue_advance_school(uuid)','course_enroll(uuid,uuid,text,uuid)','course_join_waitlist(uuid,uuid)',
  'course_leave_waitlist(uuid,uuid)','course_accept_offer(uuid)','course_decline_offer(uuid)','course_cancel_enrollment(uuid,text,text)','course_cancel_series(uuid,text)',
  'course_reschedule(uuid,jsonb)','course_learner_admissible(uuid,uuid)'] LOOP
  EXECUTE format('GRANT EXECUTE ON FUNCTION drivy.%s TO drivy_app',f);
 END LOOP;
END $$;
-- course_enroll n'est pas appelable directement avec la source OFFER : seule course_accept_offer fournit une proposition valide,
-- et course_enroll revérifie que la proposition appartient à l'élève appelant.

-- Reçus et audit des nouvelles commandes : élèves pour leurs propres commandes, personnel habilité pour les siennes.
CREATE POLICY course_learner_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
 'ENROLL_COURSE','JOIN_COURSE_WAITLIST','LEAVE_COURSE_WAITLIST','ACCEPT_COURSE_OFFER','DECLINE_COURSE_OFFER','CANCEL_COURSE_ENROLLMENT'));
CREATE POLICY course_learner_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN(
 'CourseEnrolled','CourseWaitlistJoined','CourseWaitlistLeft','CourseOfferAccepted','CourseOfferDeclined','CourseEnrollmentCancelled'));
CREATE POLICY course_staff_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.can_manage_courses(school_id) AND command_type IN(
 'STAFF_ENROLL_COURSE','STAFF_CANCEL_COURSE_ENROLLMENT','CANCEL_COURSE_SERIES','RESCHEDULE_COURSE_SERIES'));
CREATE POLICY course_staff_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.can_manage_courses(school_id) AND action IN(
 'CourseEnrolledByStaff','CourseEnrollmentCancelledByStaff','CourseSeriesCancelled','CourseSeriesRescheduled'));
