-- Relecture métier au moment de l'envoi, sans donner au worker accès aux tables scolaires.
-- Migration additive : ne modifie aucune empreinte de migration déjà appliquée.
-- Les clés de déduplication portent désormais la version de l'événement (offre réémise, horaire déplacé) : sinon
-- ON CONFLICT DO NOTHING ignorait la nouvelle notification. Les anciennes clés restent reconnues.

-- Un horaire déplacé rouvre ses rappels et l'alerte de minimum.
CREATE FUNCTION drivy.course_occurrence_moved() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
 DELETE FROM drivy.course_reminder_sent WHERE occurrence_id=NEW.id;
 RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.course_occurrence_moved() FROM PUBLIC;
CREATE TRIGGER course_occurrence_moved AFTER UPDATE OF starts_at ON drivy.course_occurrence
 FOR EACH ROW WHEN(OLD.starts_at IS DISTINCT FROM NEW.starts_at) EXECUTE FUNCTION drivy.course_occurrence_moved();

CREATE OR REPLACE FUNCTION drivy.course_notifications_tick() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE ev drivy.course_event_outbox; s drivy.course_series; person uuid; n integer:=0; sid uuid; o record;
BEGIN
 FOR sid IN SELECT DISTINCT series_id FROM drivy.course_seat_offer WHERE status='ACTIVE' AND expires_at<=statement_timestamp()
  UNION SELECT DISTINCT w.series_id FROM drivy.course_waitlist_entry w JOIN drivy.course_series x ON x.id=w.series_id
   WHERE w.status='WAITING' AND x.status='PUBLISHED' AND drivy.course_seats_taken_internal(x.id)<x.capacity LOOP
  PERFORM drivy.course_queue_advance_internal(sid);
 END LOOP;
 FOR ev IN SELECT * FROM drivy.course_event_outbox WHERE delivered_at IS NULL ORDER BY created_at LIMIT 200 FOR UPDATE SKIP LOCKED LOOP
  SELECT * INTO s FROM drivy.course_series WHERE id=ev.series_id;
  person:=NULL;
  IF ev.target_learner_id IS NOT NULL THEN SELECT person_id INTO person FROM drivy.learner_profile WHERE id=ev.target_learner_id; END IF;
  IF ev.event_type LIKE 'CourseSeatOffered:%' THEN
   PERFORM drivy.push_enqueue(person,s.school_id,'OFFER',ev.event_type||':'||ev.id,'Une place se libère',s.title||' : répondez avant l''échéance.',s.id,ev.valid_until);
  ELSIF ev.event_type='CourseEnrolled' THEN
   PERFORM drivy.push_enqueue(person,s.school_id,'CHANGE',ev.event_type||':'||ev.id,'Inscription confirmée',s.title,s.id,NULL);
  ELSIF ev.event_type LIKE 'CourseEnrollmentCancelled:%' THEN
   PERFORM drivy.push_enqueue(person,s.school_id,'CHANGE',ev.event_type,'Inscription annulée',s.title,s.id,NULL);
  ELSIF ev.event_type IN('CourseSeriesCancelled','CourseSeriesRescheduled') THEN
   FOR person IN SELECT l.person_id FROM drivy.course_enrollment e JOIN drivy.learner_profile l ON l.id=e.learner_id
    WHERE e.series_id=s.id AND (e.status='ACTIVE' OR (ev.event_type='CourseSeriesCancelled' AND e.cancel_kind='SERIES_CANCELLED')) LOOP
    PERFORM drivy.push_enqueue(person,s.school_id,'CHANGE',ev.event_type||':'||ev.series_version,
     CASE ev.event_type WHEN 'CourseSeriesCancelled' THEN 'Cours annulé' ELSE 'Dates modifiées' END,s.title,s.id,NULL);
   END LOOP;
  ELSIF ev.event_type='CourseSeriesPublished' THEN
   FOR person IN SELECT l.person_id FROM drivy.course_type_follow f JOIN drivy.learner_profile l ON l.id=f.learner_id
    WHERE f.type_id=s.type_id AND f.school_id=s.school_id AND l.archived_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM drivy.course_completion c WHERE c.learner_id=f.learner_id AND c.type_id=s.type_id AND c.revoked_at IS NULL) LOOP
    PERFORM drivy.push_enqueue(person,s.school_id,'NEW_SESSION','CourseSeriesPublished:'||s.id,'Nouvelle session',s.title,s.id,NULL);
   END LOOP;
  END IF;
  UPDATE drivy.course_event_outbox SET delivered_at=statement_timestamp() WHERE id=ev.id;
  n:=n+1;
 END LOOP;
 -- Rappels 24 h et 2 h ; la clé porte l'horaire, un rappel d'une date déplacée est donc distinct.
 FOR o IN SELECT x.id,x.series_id,x.starts_at,k.kind FROM drivy.course_occurrence x JOIN drivy.course_series s2 ON s2.id=x.series_id
  CROSS JOIN (VALUES('H24',interval '24 hours'),('H2',interval '2 hours')) k(kind,lead)
  WHERE s2.status='PUBLISHED' AND x.starts_at>statement_timestamp() AND x.starts_at<=statement_timestamp()+k.lead
  AND NOT EXISTS(SELECT 1 FROM drivy.course_reminder_sent r WHERE r.occurrence_id=x.id AND r.kind=k.kind) LOOP
  INSERT INTO drivy.course_reminder_sent(occurrence_id,kind) VALUES(o.id,o.kind) ON CONFLICT DO NOTHING;
  FOR person IN SELECT l.person_id FROM drivy.course_enrollment e JOIN drivy.learner_profile l ON l.id=e.learner_id WHERE e.series_id=o.series_id AND e.status='ACTIVE' LOOP
   SELECT * INTO s FROM drivy.course_series WHERE id=o.series_id;
   PERFORM drivy.push_enqueue(person,s.school_id,'REMINDER','Reminder:'||o.kind||':'||o.id||':'||floor(extract(epoch FROM o.starts_at))::bigint,
    CASE o.kind WHEN 'H24' THEN 'Cours demain' ELSE 'Cours dans 2 h' END,s.title,s.id,o.starts_at);
  END LOOP;
 END LOOP;
 FOR o IN SELECT s3.id AS series_id,s3.school_id,s3.title,s3.responsible_membership_id,(SELECT min(x.id::text) FROM drivy.course_occurrence x WHERE x.series_id=s3.id AND x.position=1)::uuid AS first_id,
   (SELECT min(starts_at) FROM drivy.course_occurrence x WHERE x.series_id=s3.id) AS first_start
  FROM drivy.course_series s3 WHERE s3.status='PUBLISHED' AND s3.min_participants IS NOT NULL
  AND (SELECT min(starts_at) FROM drivy.course_occurrence x WHERE x.series_id=s3.id) BETWEEN statement_timestamp() AND statement_timestamp()+interval '72 hours'
  AND (SELECT count(*) FROM drivy.course_enrollment e WHERE e.series_id=s3.id AND e.status='ACTIVE')<s3.min_participants LOOP
  CONTINUE WHEN o.first_id IS NULL OR EXISTS(SELECT 1 FROM drivy.course_reminder_sent r WHERE r.occurrence_id=o.first_id AND r.kind='MINIMUM');
  INSERT INTO drivy.course_reminder_sent(occurrence_id,kind) VALUES(o.first_id,'MINIMUM');
  SELECT m.person_id INTO person FROM drivy.membership m WHERE m.id=o.responsible_membership_id;
  PERFORM drivy.push_enqueue(person,o.school_id,'STAFF','Minimum:'||o.series_id||':'||floor(extract(epoch FROM o.first_start))::bigint,
   'Minimum non atteint',o.title||' : maintenir ou annuler.',o.series_id,NULL);
 END LOOP;
 UPDATE drivy.push_notification SET status='EXPIRED' WHERE status='PENDING' AND valid_until IS NOT NULL AND valid_until<=statement_timestamp();
 -- Une proposition n'est notifiable que tant qu'une offre active de la même entrée porte la même échéance.
 UPDATE drivy.push_notification p SET status='EXPIRED' WHERE p.status='PENDING' AND p.category='OFFER'
  AND NOT EXISTS(SELECT 1 FROM drivy.course_seat_offer so WHERE so.entry_id::text=split_part(p.dedupe_key,':',2)
   AND so.status='ACTIVE' AND so.expires_at=p.valid_until);
 RETURN n;
END $$;

CREATE FUNCTION drivy.course_push_revalidate(notification uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE n drivy.push_notification; pref drivy.notification_preference; s drivy.course_series;
 allowed boolean; reason text;
BEGIN
 SELECT * INTO n FROM drivy.push_notification WHERE id=notification FOR UPDATE;
 IF NOT FOUND OR n.status<>'PENDING' THEN RETURN false; END IF;
 IF n.valid_until IS NOT NULL AND n.valid_until<=statement_timestamp() THEN
  UPDATE drivy.push_notification SET status='EXPIRED' WHERE id=n.id;
  RETURN false;
 END IF;
 SELECT * INTO pref FROM drivy.notification_preference WHERE person_id=n.person_id;
 allowed:=CASE n.category
  WHEN 'OFFER' THEN coalesce(pref.course_offers,true)
  WHEN 'NEW_SESSION' THEN coalesce(pref.course_offers,true)
  WHEN 'REMINDER' THEN coalesce(pref.course_reminders,true)
  WHEN 'CHANGE' THEN coalesce(pref.course_changes,true)
  WHEN 'STAFF' THEN coalesce(pref.course_staff_alerts,true)
  ELSE false END;
 IF NOT allowed THEN reason:='PREFERENCE_DISABLED';
 ELSIF NOT EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id=n.school_id
  AND m.person_id=n.person_id AND m.status='ACTIVE') THEN reason:='RECIPIENT_INELIGIBLE';
 ELSE
  SELECT * INTO s FROM drivy.course_series WHERE id=n.series_id AND school_id=n.school_id;
  CASE n.category
   WHEN 'NEW_SESSION' THEN
    allowed:=s.status='PUBLISHED'
     AND EXISTS(SELECT 1 FROM drivy.course_occurrence x WHERE x.series_id=s.id)
     AND NOT EXISTS(SELECT 1 FROM drivy.course_occurrence x WHERE x.series_id=s.id AND x.starts_at<=statement_timestamp())
     AND EXISTS(SELECT 1 FROM drivy.course_type_follow f JOIN drivy.learner_profile l ON l.id=f.learner_id AND l.school_id=f.school_id
      JOIN drivy.membership m ON m.person_id=l.person_id AND m.school_id=l.school_id
      WHERE f.type_id=s.type_id AND f.school_id=s.school_id AND l.person_id=n.person_id AND l.archived_at IS NULL
      AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles)
      AND NOT EXISTS(SELECT 1 FROM drivy.course_completion c WHERE c.school_id=s.school_id AND c.learner_id=l.id
       AND c.type_id=s.type_id AND c.revoked_at IS NULL));
   WHEN 'REMINDER' THEN
    allowed:=s.status='PUBLISHED'
     AND EXISTS(SELECT 1 FROM drivy.course_occurrence x WHERE x.series_id=s.id AND x.starts_at=n.valid_until
      AND x.starts_at>statement_timestamp() AND split_part(n.dedupe_key,':',3)=x.id::text)
     AND EXISTS(SELECT 1 FROM drivy.course_enrollment e JOIN drivy.learner_profile l ON l.id=e.learner_id AND l.school_id=e.school_id
      WHERE e.series_id=s.id AND e.status='ACTIVE' AND l.person_id=n.person_id AND l.archived_at IS NULL);
   WHEN 'OFFER' THEN
    allowed:=s.status='PUBLISHED' AND EXISTS(SELECT 1 FROM drivy.course_seat_offer o
     JOIN drivy.course_waitlist_entry w ON w.id=o.entry_id AND w.school_id=o.school_id
     JOIN drivy.learner_profile l ON l.id=w.learner_id AND l.school_id=w.school_id
     WHERE o.series_id=s.id AND o.status='ACTIVE' AND o.expires_at>statement_timestamp()
      AND w.status='OFFERED' AND l.person_id=n.person_id AND l.archived_at IS NULL
      AND o.expires_at=n.valid_until AND split_part(n.dedupe_key,':',2)=w.id::text);
   WHEN 'STAFF' THEN
    allowed:=s.status='PUBLISHED' AND s.min_participants IS NOT NULL
     AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.id=s.responsible_membership_id
      AND m.school_id=s.school_id AND m.person_id=n.person_id AND m.status='ACTIVE')
     AND (SELECT min(x.starts_at) FROM drivy.course_occurrence x WHERE x.series_id=s.id)>statement_timestamp()
     AND (SELECT count(*) FROM drivy.course_enrollment e WHERE e.series_id=s.id AND e.status='ACTIVE')<s.min_participants;
   ELSE
    -- Une confirmation d'inscription annulée avant l'envoi serait fausse. Les annulations restent notifiables.
    allowed:=n.dedupe_key NOT LIKE 'CourseEnrolled:%' OR EXISTS(SELECT 1 FROM drivy.course_enrollment e
     JOIN drivy.learner_profile l ON l.id=e.learner_id AND l.school_id=e.school_id
     WHERE e.series_id=s.id AND e.status='ACTIVE' AND l.person_id=n.person_id);
  END CASE;
  IF allowed IS DISTINCT FROM true THEN reason:='EVENT_OBSOLETE'; END IF;
 END IF;
 IF reason IS NOT NULL THEN
  UPDATE drivy.push_notification SET status='SKIPPED',failure_code=reason WHERE id=n.id;
  RETURN false;
 END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION drivy.course_push_revalidate(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_push_revalidate(uuid) TO drivy_course_worker;
