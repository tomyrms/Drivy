-- #43/#44 : notifications push des demandes de leçon et des examens.
-- Réutilise la file push des cours (#43), la table versionnée des préférences (#44) et la revalidation d'envoi existante
-- (046_course_push_revalidation.sql, 20261025_messaging_mention_push.sql) : aucun second moteur d'envoi, aucun second stockage.
-- Migration additive : aucune migration existante n'est modifiée. Décisions et limites :
-- docs/implementation/cours-collectifs-notifications-43-44.md (§ Demandes de leçon et examens).
-- La charge ne porte ni nom, ni note, ni motif, ni résultat : seulement un titre et un corps génériques.

-- 1. Préférences : deux catégories de plus, actives par défaut. Facultatives à l'écriture (une ancienne app ou un ancien
-- onglet web ne les mentionne pas), toujours présentes en lecture. Elles ne réinitialisent aucun autre choix.
ALTER TABLE drivy.notification_preference
 ADD COLUMN lesson_requests boolean NOT NULL DEFAULT true,
 ADD COLUMN exam_updates boolean NOT NULL DEFAULT true;
GRANT UPDATE(lesson_requests,exam_updates) ON drivy.notification_preference TO drivy_app;

-- 2. File : trois catégories de plus et les références qui permettent la relecture juste avant l'envoi. La référence est
-- portée par la ligne, pas devinée depuis le texte : une demande de leçon, une réponse à cette demande, un examen.
ALTER TABLE drivy.push_notification DROP CONSTRAINT push_notification_category_check;
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_category_check
 CHECK(category IN('OFFER','REMINDER','CHANGE','STAFF','NEW_SESSION','MESSAGE_MENTION','MESSAGE_PRIVATE','MESSAGE_GENERAL',
  'LESSON_REQUEST','LESSON_REQUEST_ANSWER','EXAM'));
ALTER TABLE drivy.push_notification ADD COLUMN lesson_id uuid, ADD COLUMN exam_id uuid;
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_lesson_ref
 CHECK((lesson_id IS NOT NULL)=(category IN('LESSON_REQUEST','LESSON_REQUEST_ANSWER')));
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_exam_ref
 CHECK((exam_id IS NOT NULL)=(category='EXAM'));
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_lesson_fk
 FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id);
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_exam_fk
 FOREIGN KEY(school_id,exam_id) REFERENCES drivy.exam(school_id,id);
CREATE INDEX push_notification_lesson ON drivy.push_notification(lesson_id) WHERE lesson_id IS NOT NULL;
CREATE INDEX push_notification_exam ON drivy.push_notification(exam_id) WHERE exam_id IS NOT NULL;

-- 3. Destinataires, relus par la base : l'application ne lit pas les adhésions des autres membres (sécurité par ligne).
-- Une nouvelle demande va au moniteur actif de la leçon ; sans moniteur actif, aux administrateurs actifs de l'école.
CREATE FUNCTION drivy.lesson_push_recipients(school uuid,lesson uuid) RETURNS TABLE(person_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.person_id FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id AND m.id=l.instructor_membership_id
  JOIN drivy.person p ON p.id=m.person_id
  WHERE l.school_id=school AND l.id=lesson AND drivy.lesson_change_read(lesson) AND m.status='ACTIVE' AND p.status='ACTIVE'
 UNION
 SELECT m.person_id FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id JOIN drivy.person p ON p.id=m.person_id
  WHERE l.school_id=school AND l.id=lesson AND drivy.lesson_change_read(lesson) AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)
  AND NOT EXISTS(SELECT 1 FROM drivy.lesson l2 JOIN drivy.membership i ON i.school_id=l2.school_id AND i.id=l2.instructor_membership_id
   JOIN drivy.person ip ON ip.id=i.person_id WHERE l2.school_id=school AND l2.id=lesson AND i.status='ACTIVE' AND ip.status='ACTIVE')
$$;
REVOKE ALL ON FUNCTION drivy.lesson_push_recipients(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_push_recipients(uuid,uuid) TO drivy_app;
-- Personne de l'élève d'une formation, pour l'alerte d'examen. Lue par la base, jamais déduite du nom affiché.
CREATE FUNCTION drivy.exam_learner_person(training uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT l.person_id FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
  WHERE t.id=training AND drivy.exam_manage(t.id)
$$;
REVOKE ALL ON FUNCTION drivy.exam_learner_person(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.exam_learner_person(uuid) TO drivy_app;

-- 4. Mise en file dans la transaction de l'écriture durable. La préférence est lue ici, la relecture à l'envoi reste la
-- seule autorité. `valid_until` : une demande de leçon ne survit pas au début prévu de la leçon ni à 24 h ; les autres
-- événements valent 24 h. Une déduplication par personne et par événement évite les doublons d'un rejeu.
CREATE FUNCTION drivy.push_lesson_exam_enqueue(person uuid,school uuid,category text,dedupe text,title text,body text,
 lesson uuid,exam uuid) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE pref drivy.notification_preference; allowed boolean; expires timestamptz;
BEGIN
 IF person IS NULL OR school IS NULL OR category NOT IN('LESSON_REQUEST','LESSON_REQUEST_ANSWER','EXAM') THEN RETURN; END IF;
 SELECT * INTO pref FROM drivy.notification_preference WHERE person_id=person;
 allowed:=CASE category WHEN 'EXAM' THEN coalesce(pref.exam_updates,true) ELSE coalesce(pref.lesson_requests,true) END;
 IF NOT allowed THEN RETURN; END IF;
 expires:=statement_timestamp()+interval '24 hours';
 IF category='LESSON_REQUEST' THEN
  expires:=coalesce((SELECT least(l.planned_start,expires) FROM drivy.lesson l WHERE l.school_id=school AND l.id=lesson),expires);
 END IF;
 INSERT INTO drivy.push_notification(person_id,school_id,category,dedupe_key,title,body,lesson_id,exam_id,valid_until)
  VALUES(person,school,category,dedupe,title,body,lesson,exam,expires) ON CONFLICT(person_id,dedupe_key) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION drivy.push_lesson_exam_enqueue(uuid,uuid,text,text,text,text,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_lesson_exam_enqueue(uuid,uuid,text,text,text,text,uuid,uuid) TO drivy_app;

-- 5. Relecture juste avant l'envoi : la fonction existante est étendue, jamais doublée. Préférence encore active,
-- adhésion du destinataire encore active dans l'école, événement encore d'actualité (demande encore en attente sur une
-- leçon encore planifiée ; examen encore existant). Un refus marque la ligne SKIPPED avec son code.
CREATE OR REPLACE FUNCTION drivy.course_push_revalidate(notification uuid) RETURNS boolean
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
  WHEN 'LESSON_REQUEST' THEN coalesce(pref.lesson_requests,true)
  WHEN 'LESSON_REQUEST_ANSWER' THEN coalesce(pref.lesson_requests,true)
  WHEN 'EXAM' THEN coalesce(pref.exam_updates,true)
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
   WHEN 'LESSON_REQUEST' THEN
    -- La demande attend encore une réponse et la leçon n'a ni commencé ni quitté son état planifié.
    allowed:=EXISTS(SELECT 1 FROM drivy.lesson_change_request r JOIN drivy.lesson l ON l.school_id=r.school_id AND l.id=r.lesson_id
     WHERE r.school_id=n.school_id AND r.id::text=split_part(n.dedupe_key,':',2) AND r.status='PENDING'
      AND l.status='PLANNED' AND l.actual_start IS NULL AND l.planned_start>statement_timestamp());
   WHEN 'LESSON_REQUEST_ANSWER' THEN
    -- La réponse existe toujours : la demande n'a pas été retirée avant la réponse.
    allowed:=EXISTS(SELECT 1 FROM drivy.lesson_change_request r
     WHERE r.school_id=n.school_id AND r.id::text=split_part(n.dedupe_key,':',2) AND r.status IN('ACCEPTED','REFUSED'));
   WHEN 'EXAM' THEN
    allowed:=EXISTS(SELECT 1 FROM drivy.exam e WHERE e.school_id=n.school_id AND e.id=n.exam_id);
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
