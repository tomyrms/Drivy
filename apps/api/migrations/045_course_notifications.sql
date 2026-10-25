-- Cours collectifs : notifications push et préférences (#43, #44), abonnement aux prochaines sessions (#40),
-- expiration autonome des propositions, alerte de minimum de participants. Valeurs de file approuvées par le porteur le
-- 24 octobre 2026 : 12 h par défaut, échéance au plus tard 2 h avant la première séance, seuil 30 min.
-- Contrat : docs/implementation/cours-collectifs-notifications-43-44.md. Aucun e-mail automatique.

-- Délai par défaut de 12 h pour les écoles sans politique enregistrée : la file prioritaire est active par défaut.
-- Une école qui a déjà enregistré une politique garde exactement son choix (aucune réécriture).
-- La version implicite 1 devient « 24 h, 720 min » ; drivy.course_queue_advance lit cette valeur par défaut.
CREATE OR REPLACE FUNCTION drivy.course_offer_response_minutes(school uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT CASE WHEN EXISTS(SELECT 1 FROM drivy.course_policy_version WHERE school_id=school)
  THEN (SELECT offer_response_minutes FROM drivy.course_policy_version WHERE school_id=school ORDER BY version DESC LIMIT 1) ELSE 720 END
$$;
REVOKE ALL ON FUNCTION drivy.course_offer_response_minutes(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_offer_response_minutes(uuid) TO drivy_app;

-- Appareils : un jeton APNs par appareil et par personne, révocable. Le jeton n'est lisible que par le service d'envoi.
CREATE TABLE drivy.push_device (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 person_id uuid NOT NULL REFERENCES drivy.person(id),
 platform text NOT NULL CHECK(platform='IOS'),
 environment text NOT NULL CHECK(environment IN('SANDBOX','PRODUCTION')),
 token text NOT NULL CHECK(token ~ '^[0-9a-f]{64,200}$'),
 created_at timestamptz NOT NULL DEFAULT now(),
 last_seen_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz,
 UNIQUE(token)
);
-- Préférences personnelles (#44) : par catégorie, par personne. Absence de ligne = valeurs par défaut (tout actif sauf
-- les annonces de nouvelles sessions, qui exigent un abonnement explicite).
CREATE TABLE drivy.notification_preference (
 person_id uuid PRIMARY KEY REFERENCES drivy.person(id),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 course_offers boolean NOT NULL DEFAULT true,
 course_reminders boolean NOT NULL DEFAULT true,
 course_changes boolean NOT NULL DEFAULT true,
 course_staff_alerts boolean NOT NULL DEFAULT true,
 updated_at timestamptz NOT NULL DEFAULT now()
);
-- Abonnement « prochaines sessions de ce type » (#40) : volontaire, révocable, indépendant de toute file ou inscription.
CREATE TABLE drivy.course_type_follow (
 school_id uuid NOT NULL,
 learner_id uuid NOT NULL,
 type_id uuid NOT NULL REFERENCES drivy.course_type(id),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(learner_id,type_id),
 FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id)
);
-- Notifications à envoyer : une ligne par personne et événement, issue de course_event_outbox. Jamais d'e-mail.
CREATE TABLE drivy.push_notification (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 person_id uuid NOT NULL REFERENCES drivy.person(id),
 school_id uuid NOT NULL REFERENCES drivy.school(id),
 category text NOT NULL CHECK(category IN('OFFER','REMINDER','CHANGE','STAFF','NEW_SESSION')),
 dedupe_key text NOT NULL,
 title text NOT NULL, body text NOT NULL,
 series_id uuid,
 valid_until timestamptz,
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','SENT','SKIPPED','FAILED','EXPIRED')),
 attempts integer NOT NULL DEFAULT 0,
 available_at timestamptz NOT NULL DEFAULT now(),
 created_at timestamptz NOT NULL DEFAULT now(),
 sent_at timestamptz,
 failure_code text,
 UNIQUE(person_id,dedupe_key)
);
CREATE INDEX push_notification_due ON drivy.push_notification(available_at) WHERE status='PENDING';
-- Rappels et alerte de minimum déjà émis : une seule fois par séance ou série.
CREATE TABLE drivy.course_reminder_sent (
 occurrence_id uuid NOT NULL, kind text NOT NULL CHECK(kind IN('H24','H2','MINIMUM')), sent_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(occurrence_id,kind)
);

DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['push_device','notification_preference','course_type_follow','push_notification','course_reminder_sent'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY push_owner_all ON drivy.%I TO %I USING(true) WITH CHECK(true)',t,current_user);
 END LOOP;
END $$;
-- L'application : la personne connectée gère ses appareils (sans relire les jetons), ses préférences et ses abonnements.
CREATE POLICY push_device_self ON drivy.push_device FOR ALL TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid) WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY notification_preference_self ON drivy.notification_preference FOR ALL TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid) WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY course_type_follow_self ON drivy.course_type_follow FOR ALL TO drivy_app
 USING(EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner_id AND l.person_id=nullif(current_setting('app.person_id',true),'')::uuid))
 WITH CHECK(EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner_id AND l.school_id=course_type_follow.school_id AND l.archived_at IS NULL
  AND l.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.current_school_member(l.school_id)));
CREATE POLICY push_notification_self_read ON drivy.push_notification FOR SELECT TO drivy_app USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid);
GRANT SELECT(id,person_id,platform,environment,created_at,last_seen_at,revoked_at) ON drivy.push_device TO drivy_app;
GRANT SELECT,INSERT ON drivy.notification_preference TO drivy_app;
GRANT UPDATE(version,course_offers,course_reminders,course_changes,course_staff_alerts,updated_at) ON drivy.notification_preference TO drivy_app;
GRANT SELECT,INSERT,DELETE ON drivy.course_type_follow TO drivy_app;
GRANT SELECT(id,person_id,school_id,category,title,body,series_id,valid_until,status,created_at,sent_at) ON drivy.push_notification TO drivy_app;

-- Un jeton APNs repris par une autre personne sur le même appareil (changement de compte) est réattribué : l'ancienne
-- personne ne reçoit plus rien sur cet appareil.
CREATE FUNCTION drivy.push_device_claim(person uuid,device_token text,device_environment text) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 INSERT INTO drivy.push_device(person_id,platform,environment,token) SELECT person,'IOS',device_environment,device_token
  WHERE person=nullif(current_setting('app.person_id',true),'')::uuid
 ON CONFLICT(token) DO UPDATE SET person_id=EXCLUDED.person_id,environment=EXCLUDED.environment,revoked_at=NULL,last_seen_at=now()
$$;
REVOKE ALL ON FUNCTION drivy.push_device_claim(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_device_claim(uuid,text,text) TO drivy_app;
CREATE FUNCTION drivy.push_device_revoke(person uuid,device_token text) RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 UPDATE drivy.push_device SET revoked_at=now() WHERE person_id=person AND token=device_token AND revoked_at IS NULL
  AND person=nullif(current_setting('app.person_id',true),'')::uuid
$$;
REVOKE ALL ON FUNCTION drivy.push_device_revoke(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_device_revoke(uuid,text) TO drivy_app;

-- Rôle du service d'envoi : connexion propre, sans BYPASSRLS ; lit les jetons et marque les notifications. Aucune autre table.
-- Comme drivy_invitation_mailer, le rôle est préparé par l'exploitation (scripts/prepare-course-worker.sql) ; la migration le crée
-- seulement s'il manque, sans connexion.
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_course_worker') THEN
 CREATE ROLE drivy_course_worker NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$;
GRANT USAGE ON SCHEMA drivy TO drivy_course_worker;
GRANT SELECT ON drivy.push_device,drivy.push_notification,drivy.notification_preference TO drivy_course_worker;
GRANT UPDATE(status,attempts,available_at,sent_at,failure_code) ON drivy.push_notification TO drivy_course_worker;
GRANT UPDATE(revoked_at) ON drivy.push_device TO drivy_course_worker;
CREATE POLICY push_worker_device ON drivy.push_device TO drivy_course_worker USING(true) WITH CHECK(true);
CREATE POLICY push_worker_notification ON drivy.push_notification TO drivy_course_worker USING(true) WITH CHECK(true);
CREATE POLICY push_worker_preference ON drivy.notification_preference FOR SELECT TO drivy_course_worker USING(true);

-- Catégorie d'un événement et respect des préférences. Une notification ne vaut ni lecture ni inscription.
CREATE FUNCTION drivy.push_enqueue(person uuid,school uuid,category text,dedupe text,title text,body text,series uuid,valid_until timestamptz) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE pref drivy.notification_preference; allowed boolean;
BEGIN
 SELECT * INTO pref FROM drivy.notification_preference WHERE person_id=person;
 allowed:=CASE category WHEN 'OFFER' THEN coalesce(pref.course_offers,true) WHEN 'NEW_SESSION' THEN coalesce(pref.course_offers,true)
  WHEN 'REMINDER' THEN coalesce(pref.course_reminders,true) WHEN 'CHANGE' THEN coalesce(pref.course_changes,true)
  WHEN 'STAFF' THEN coalesce(pref.course_staff_alerts,true) END;
 IF NOT allowed THEN RETURN; END IF;
 INSERT INTO drivy.push_notification(person_id,school_id,category,dedupe_key,title,body,series_id,valid_until)
  VALUES(person,school,category,dedupe,title,body,series,valid_until) ON CONFLICT(person_id,dedupe_key) DO NOTHING;
END $$;
REVOKE ALL ON FUNCTION drivy.push_enqueue(uuid,uuid,text,text,text,text,uuid,timestamptz) FROM PUBLIC;

-- Traduction de l'outbox des cours en notifications ciblées, puis tâches temporelles. Exécutée par le service d'envoi.
-- Une proposition de place n'est notifiée qu'à son destinataire ; une notification dont l'échéance est passée est EXPIRED.
CREATE FUNCTION drivy.course_notifications_tick() RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE ev drivy.course_event_outbox; s drivy.course_series; person uuid; n integer:=0; sid uuid; o record;
BEGIN
 -- Expiration autonome des propositions et passage au suivant, sans attendre une action d'utilisateur.
 FOR sid IN SELECT DISTINCT series_id FROM drivy.course_seat_offer WHERE status='ACTIVE' AND expires_at<=statement_timestamp()
  UNION SELECT DISTINCT w.series_id FROM drivy.course_waitlist_entry w JOIN drivy.course_series x ON x.id=w.series_id
   WHERE w.status='WAITING' AND x.status='PUBLISHED' AND drivy.course_seats_taken_internal(x.id)<x.capacity LOOP
  PERFORM drivy.course_queue_advance_internal(sid);
 END LOOP;
 FOR ev IN SELECT * FROM drivy.course_event_outbox WHERE delivered_at IS NULL ORDER BY created_at LIMIT 200 FOR UPDATE SKIP LOCKED LOOP
  SELECT * INTO s FROM drivy.course_series WHERE id=ev.series_id;
  IF ev.target_learner_id IS NOT NULL THEN SELECT person_id INTO person FROM drivy.learner_profile WHERE id=ev.target_learner_id; END IF;
  IF ev.event_type LIKE 'CourseSeatOffered:%' THEN
   PERFORM drivy.push_enqueue(person,s.school_id,'OFFER',ev.event_type,'Une place se libère',s.title||' : répondez avant l''échéance.',s.id,ev.valid_until);
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
   -- Nouvelle session : seulement aux abonnés du type, pas déjà validés, sans inscription implicite.
   FOR person IN SELECT l.person_id FROM drivy.course_type_follow f JOIN drivy.learner_profile l ON l.id=f.learner_id
    WHERE f.type_id=s.type_id AND f.school_id=s.school_id AND l.archived_at IS NULL
    AND NOT EXISTS(SELECT 1 FROM drivy.course_completion c WHERE c.learner_id=f.learner_id AND c.type_id=s.type_id AND c.revoked_at IS NULL) LOOP
    PERFORM drivy.push_enqueue(person,s.school_id,'NEW_SESSION','CourseSeriesPublished:'||s.id,'Nouvelle session',s.title,s.id,NULL);
   END LOOP;
  END IF;
  UPDATE drivy.course_event_outbox SET delivered_at=statement_timestamp() WHERE id=ev.id;
  n:=n+1;
 END LOOP;
 -- Rappels 24 h et 2 h avant chaque séance, aux inscrits actifs.
 FOR o IN SELECT x.id,x.series_id,x.starts_at,k.kind FROM drivy.course_occurrence x JOIN drivy.course_series s2 ON s2.id=x.series_id
  CROSS JOIN (VALUES('H24',interval '24 hours'),('H2',interval '2 hours')) k(kind,lead)
  WHERE s2.status='PUBLISHED' AND x.starts_at>statement_timestamp() AND x.starts_at<=statement_timestamp()+k.lead
  AND NOT EXISTS(SELECT 1 FROM drivy.course_reminder_sent r WHERE r.occurrence_id=x.id AND r.kind=k.kind) LOOP
  INSERT INTO drivy.course_reminder_sent(occurrence_id,kind) VALUES(o.id,o.kind) ON CONFLICT DO NOTHING;
  FOR person IN SELECT l.person_id FROM drivy.course_enrollment e JOIN drivy.learner_profile l ON l.id=e.learner_id WHERE e.series_id=o.series_id AND e.status='ACTIVE' LOOP
   SELECT * INTO s FROM drivy.course_series WHERE id=o.series_id;
   PERFORM drivy.push_enqueue(person,s.school_id,'REMINDER','Reminder:'||o.kind||':'||o.id,
    CASE o.kind WHEN 'H24' THEN 'Cours demain' ELSE 'Cours dans 2 h' END,s.title,s.id,o.starts_at);
  END LOOP;
 END LOOP;
 -- Alerte de minimum, 72 h avant la première séance, au responsable de la série. Aucune annulation automatique.
 FOR o IN SELECT s3.id AS series_id,s3.school_id,s3.title,s3.responsible_membership_id,(SELECT min(x.id::text) FROM drivy.course_occurrence x WHERE x.series_id=s3.id AND x.position=1)::uuid AS first_id
  FROM drivy.course_series s3 WHERE s3.status='PUBLISHED' AND s3.min_participants IS NOT NULL
  AND (SELECT min(starts_at) FROM drivy.course_occurrence x WHERE x.series_id=s3.id) BETWEEN statement_timestamp() AND statement_timestamp()+interval '72 hours'
  AND (SELECT count(*) FROM drivy.course_enrollment e WHERE e.series_id=s3.id AND e.status='ACTIVE')<s3.min_participants LOOP
  CONTINUE WHEN o.first_id IS NULL OR EXISTS(SELECT 1 FROM drivy.course_reminder_sent r WHERE r.occurrence_id=o.first_id AND r.kind='MINIMUM');
  INSERT INTO drivy.course_reminder_sent(occurrence_id,kind) VALUES(o.first_id,'MINIMUM');
  SELECT m.person_id INTO person FROM drivy.membership m WHERE m.id=o.responsible_membership_id;
  PERFORM drivy.push_enqueue(person,o.school_id,'STAFF','Minimum:'||o.series_id,'Minimum non atteint',o.title||' : maintenir ou annuler.',o.series_id,NULL);
 END LOOP;
 -- Notifications périmées : jamais envoyées après leur échéance.
 UPDATE drivy.push_notification SET status='EXPIRED' WHERE status='PENDING' AND valid_until IS NOT NULL AND valid_until<=statement_timestamp();
 -- Une proposition révoquée ou acceptée invalide sa notification en attente.
 UPDATE drivy.push_notification p SET status='EXPIRED' FROM drivy.course_seat_offer so JOIN drivy.course_waitlist_entry w ON w.id=so.entry_id
  WHERE p.status='PENDING' AND p.category='OFFER' AND p.dedupe_key='CourseSeatOffered:'||w.id AND so.status<>'ACTIVE';
 RETURN n;
END $$;

-- Versions internes sans contrôle d'appartenance, réservées au tick (le service d'envoi n'est membre d'aucune école).
CREATE FUNCTION drivy.course_seats_taken_internal(series uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT ((SELECT count(*) FROM drivy.course_enrollment e WHERE e.series_id=series AND e.status='ACTIVE')
  +(SELECT count(*) FROM drivy.course_seat_offer o WHERE o.series_id=series AND o.status='ACTIVE' AND o.expires_at>statement_timestamp()))::integer
$$;
CREATE FUNCTION drivy.course_queue_advance_internal(series uuid) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; response integer; first_start timestamptz; deadline timestamptz; entry drivy.course_waitlist_entry; offered integer:=0;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN RETURN 0; END IF;
 WITH expired AS (UPDATE drivy.course_seat_offer SET status='EXPIRED',resolved_at=statement_timestamp()
   WHERE series_id=series AND status='ACTIVE' AND expires_at<=statement_timestamp() RETURNING entry_id)
 UPDATE drivy.course_waitlist_entry w SET status='EXPIRED',resolved_at=statement_timestamp() FROM expired WHERE w.id=expired.entry_id AND w.status='OFFERED';
 IF s.status<>'PUBLISHED' THEN RETURN 0; END IF;
 SELECT min(starts_at) INTO first_start FROM drivy.course_occurrence WHERE series_id=series;
 IF first_start IS NULL OR first_start<=statement_timestamp() THEN RETURN 0; END IF;
 response:=drivy.course_offer_response_minutes(s.school_id);
 IF response IS NULL THEN RETURN 0; END IF;
 deadline:=least(statement_timestamp()+make_interval(mins=>response),first_start-interval '2 hours');
 IF deadline<statement_timestamp()+interval '30 minutes' THEN RETURN 0; END IF;
 WHILE drivy.course_seats_taken_internal(series)<s.capacity LOOP
  SELECT * INTO entry FROM drivy.course_waitlist_entry WHERE series_id=series AND status='WAITING' ORDER BY queued_at,seq LIMIT 1 FOR UPDATE;
  EXIT WHEN NOT FOUND;
  IF EXISTS(SELECT 1 FROM drivy.course_completion c WHERE c.learner_id=entry.learner_id AND c.type_id=s.type_id AND c.revoked_at IS NULL)
   OR EXISTS(SELECT 1 FROM drivy.course_enrollment e WHERE e.series_id=series AND e.learner_id=entry.learner_id AND e.status='ACTIVE')
   OR NOT EXISTS(SELECT 1 FROM drivy.learner_profile l JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=l.person_id
    WHERE l.id=entry.learner_id AND l.archived_at IS NULL AND m.status='ACTIVE' AND 'LEARNER'=ANY(m.roles)) THEN
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
-- La version applicative de la file utilise la même source de délai (défaut 720 min sans politique enregistrée).
CREATE OR REPLACE FUNCTION drivy.course_queue_advance(series uuid) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE school uuid;
BEGIN
 SELECT school_id INTO school FROM drivy.course_series WHERE id=series;
 IF school IS NULL OR drivy.current_school_member(school) IS DISTINCT FROM true THEN RETURN 0; END IF;
 RETURN drivy.course_queue_advance_internal(series);
END $$;
-- Entrée en file : même règle d'activation que la file.
CREATE OR REPLACE FUNCTION drivy.course_join_waitlist(series uuid,learner uuid) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s drivy.course_series; actor drivy.membership; reason text; entry uuid;
BEGIN
 SELECT * INTO s FROM drivy.course_series WHERE id=series FOR UPDATE;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 actor:=drivy.course_actor_membership(s.school_id);
 IF actor.id IS NULL OR NOT EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner AND l.school_id=s.school_id AND l.person_id=actor.person_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 PERFORM drivy.course_queue_advance(series);
 IF drivy.course_offer_response_minutes(s.school_id) IS NULL THEN PERFORM drivy.course_fail('COURSE_WAITLIST_DISABLED'); END IF;
 IF s.status<>'PUBLISHED' OR drivy.course_first_start(series)<=statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_NOT_OPEN'); END IF;
 reason:=drivy.course_learner_admissible(series,learner);
 IF reason IS NOT NULL THEN PERFORM drivy.course_fail(reason); END IF;
 IF drivy.course_seats_taken(series)<s.capacity THEN PERFORM drivy.course_fail('COURSE_SEATS_AVAILABLE'); END IF;
 SELECT id INTO entry FROM drivy.course_waitlist_entry WHERE series_id=series AND learner_id=learner AND status IN('WAITING','OFFERED');
 IF entry IS NOT NULL THEN RETURN entry; END IF;
 INSERT INTO drivy.course_waitlist_entry(school_id,series_id,learner_id) VALUES(s.school_id,series,learner) RETURNING id INTO entry;
 RETURN entry;
END $$;

REVOKE ALL ON FUNCTION drivy.course_notifications_tick(),drivy.course_seats_taken_internal(uuid),drivy.course_queue_advance_internal(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_notifications_tick() TO drivy_course_worker;

