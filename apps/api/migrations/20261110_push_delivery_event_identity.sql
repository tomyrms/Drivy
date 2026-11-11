-- Audit du 10 novembre 2026, lot G (#429, #448). Migration additive : aucune migration livrée n'est modifiée.
--
-- 1. #429 : identité d'une notification d'annulation ou de replanification de série.
--    La clé était `type:version` avec UNIQUE(person_id, dedupe_key) : deux séries distinctes (même école ou non) annulées ou
--    replanifiées à la même version, pour la même personne, ne donnaient qu'UNE notification. La clé porte désormais l'identifiant
--    de la série (unique globalement, donc aussi la portée d'école) : `type:série:version`. Rejouer le même événement reproduit la
--    même clé, donc une seule notification (ON CONFLICT DO NOTHING).
--    Transition : seul le tick change. Les événements déjà traités (delivered_at renseigné) ne sont jamais relus et aucune
--    notification existante n'est modifiée ni supprimée : les anciennes clés `type:version` restent en base, aucune relecture de
--    code ne les analyse (la revalidation ne découpe que les clés de rappel, d'offre, de demande de leçon). Un événement encore
--    en attente au moment du déploiement est traité une seule fois avec la nouvelle clé : pas de réémission d'un événement
--    déjà notifié, et une nouvelle annulation de même version dans une autre série n'est plus ignorée.
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
    PERFORM drivy.push_enqueue(person,s.school_id,'CHANGE',ev.event_type||':'||ev.series_id||':'||ev.series_version,
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

-- 2. #448 : état d'envoi PAR DESTINATION. Une ligne par couple (notification, appareil), créée au premier passage pour les
--    appareils actifs de ce moment : un appareil enregistré plus tard ne reçoit pas une alerte ancienne.
--    États : PENDING (reprise valide restante), SENT (acceptée par APNs : ni lecture ni affichage), REJECTED (erreur
--    définitive : jeton invalide, appareil révoqué par le fournisseur), REVOKED (appareil retiré ou réattribué, droits ou
--    préférences retirés, événement obsolète), EXPIRED (échéance de la notification passée ou politique de reprise épuisée).
--    La notification n'est close que lorsqu'aucune destination n'est PENDING. Aucun jeton ni contenu n'est copié ici.
CREATE TABLE drivy.push_delivery (
 notification_id uuid NOT NULL REFERENCES drivy.push_notification(id) ON DELETE CASCADE,
 device_id uuid NOT NULL REFERENCES drivy.push_device(id) ON DELETE CASCADE,
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','SENT','REJECTED','REVOKED','EXPIRED')),
 attempts integer NOT NULL DEFAULT 0 CHECK(attempts>=0),
 failure_code text,
 created_at timestamptz NOT NULL DEFAULT now(),
 completed_at timestamptz,
 PRIMARY KEY(notification_id,device_id),
 CHECK((status='PENDING')=(completed_at IS NULL))
);
ALTER TABLE drivy.push_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.push_delivery FORCE ROW LEVEL SECURITY;
CREATE POLICY push_owner_all ON drivy.push_delivery TO CURRENT_USER USING(true) WITH CHECK(true);
CREATE POLICY push_worker_delivery ON drivy.push_delivery TO drivy_course_worker USING(true) WITH CHECK(true);
GRANT SELECT,INSERT ON drivy.push_delivery TO drivy_course_worker;
GRANT UPDATE(status,attempts,failure_code,completed_at) ON drivy.push_delivery TO drivy_course_worker;

-- Toute clôture d'une notification (périmée, refusée par la relecture, regroupée, échouée) clôt aussi ses destinations en
-- attente : jamais de reprise orpheline. Révocation de droits, de préférence ou d'événement : REVOKED ; échéance : EXPIRED.
CREATE FUNCTION drivy.push_delivery_close() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
 UPDATE drivy.push_delivery SET status=CASE NEW.status WHEN 'EXPIRED' THEN 'EXPIRED' ELSE 'REVOKED' END,
  failure_code=coalesce(NEW.failure_code,'NOTIFICATION_'||NEW.status),completed_at=statement_timestamp()
  WHERE notification_id=NEW.id AND status='PENDING';
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.push_delivery_close() FROM PUBLIC;
CREATE TRIGGER push_delivery_close AFTER UPDATE OF status ON drivy.push_notification
 FOR EACH ROW WHEN(OLD.status='PENDING' AND NEW.status<>'PENDING') EXECUTE FUNCTION drivy.push_delivery_close();
