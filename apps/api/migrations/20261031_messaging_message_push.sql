-- #74 : alertes des nouveaux messages privés et du général, et préférences de messagerie de la personne.
-- Réutilise la file push des cours (#43/#44) et la table de préférences versionnée : aucun second stockage.
-- La charge reste générique (titre fixe, corps vide) : la messagerie est chiffrée de bout en bout, aucun contenu,
-- extrait, nom d'auteur ni nom de conversation n'est exposé sur l'écran verrouillé.
-- Migration purement additive : aucune table créée, aucune migration existante modifiée.
-- Décisions : docs/implementation/messaging-notifications-74.md.

ALTER TABLE drivy.push_notification DROP CONSTRAINT push_notification_category_check;
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_category_check
 CHECK(category IN('OFFER','REMINDER','CHANGE','STAFF','NEW_SESSION','MESSAGE_MENTION','MESSAGE_PRIVATE','MESSAGE_GENERAL'));
ALTER TABLE drivy.push_notification DROP CONSTRAINT push_notification_message_ref;
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_message_ref
 CHECK((category IN('MESSAGE_MENTION','MESSAGE_PRIVATE','MESSAGE_GENERAL'))=(message_id IS NOT NULL AND conversation_id IS NOT NULL));

-- Préférences : messages privés actifs par défaut, messages du général désactivés (les mentions restent actives, colonne
-- messaging_mentions de la migration 20261025). Une ligne absente vaut ces valeurs par défaut.
ALTER TABLE drivy.notification_preference
 ADD COLUMN messaging_private boolean NOT NULL DEFAULT true,
 ADD COLUMN messaging_general boolean NOT NULL DEFAULT false;
GRANT UPDATE(messaging_private,messaging_general,messaging_mentions) ON drivy.notification_preference TO drivy_app;

-- Éligibilité d'une paire moniteur/élève sans paramètre de session : le service d'envoi n'a pas d'identité scolaire.
-- Même règle que drivy.messaging_pair_eligible (contacts attribués), sans la comparaison à app.school_id.
CREATE FUNCTION drivy.push_pair_eligible(school uuid, a uuid, b uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT a<>b
  AND EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id JOIN drivy.school s ON s.id=m.school_id
    WHERE m.school_id=school AND m.person_id=a AND m.status='ACTIVE' AND p.status='ACTIVE' AND s.status='ACTIVE')
  AND EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id JOIN drivy.school s ON s.id=m.school_id
    WHERE m.school_id=school AND m.person_id=b AND m.status='ACTIVE' AND p.status='ACTIVE' AND s.status='ACTIVE')
  AND EXISTS(SELECT 1 FROM drivy.membership am JOIN drivy.membership pm ON pm.school_id=am.school_id
    WHERE am.school_id=school AND am.person_id=a AND am.status='ACTIVE' AND pm.person_id=b AND pm.status='ACTIVE'
      AND EXISTS(SELECT 1 FROM drivy.learner_profile lp JOIN drivy.training t ON t.school_id=lp.school_id AND t.learner_id=lp.id
        JOIN drivy.instructor_assignment ia ON ia.school_id=t.school_id AND ia.training_id=t.id
        WHERE lp.school_id=school AND lp.archived_at IS NULL AND t.status IN('ACTIVE','PAUSED')
          AND ia.valid_from<=statement_timestamp() AND (ia.valid_until IS NULL OR ia.valid_until>statement_timestamp())
          AND ((lp.person_id=a AND 'LEARNER'=ANY(am.roles) AND 'INSTRUCTOR'=ANY(pm.roles) AND ia.instructor_membership_id=pm.id)
            OR (lp.person_id=b AND 'LEARNER'=ANY(pm.roles) AND 'INSTRUCTOR'=ANY(am.roles) AND ia.instructor_membership_id=am.id))))
$$;
REVOKE ALL ON FUNCTION drivy.push_pair_eligible(uuid,uuid,uuid) FROM PUBLIC;

-- Mise en file à l'acceptation d'un message : une alerte par destinataire et par message, jamais pour l'auteur.
-- Les personnes mentionnées reçoivent seulement l'alerte de mention (déclencheur messaging_mention_enqueue) : pas de
-- doublon « mention + général », et une mention refusée ne retombe jamais sur la catégorie du général.
-- Les sondages sont des messages : ils suivent la catégorie de leur conversation. Votes et clôtures n'alertent pas.
-- N'est mis en file que ce qui est déjà autorisé par la préférence et par un appareil enregistré : le général compte
-- beaucoup de membres et sa catégorie est désactivée par défaut. La relecture à l'envoi reste la seule autorité.
-- L'alerte périme au bout de 15 minutes : une reprise tardive du service ne rejoue pas un arriéré de messages.
CREATE FUNCTION drivy.push_message_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
 INSERT INTO drivy.push_notification(person_id,school_id,category,dedupe_key,title,body,conversation_id,message_id,message_sequence,valid_until)
  SELECT l.person_id, NEW.school_id, CASE c.kind WHEN 'PRIVATE' THEN 'MESSAGE_PRIVATE' ELSE 'MESSAGE_GENERAL' END,
   'MessagingMessage:'||NEW.id, 'Nouveau message', '', NEW.conversation_id, NEW.id, NEW.sequence, statement_timestamp()+interval '15 minutes'
  FROM drivy.messaging_conversation c
  JOIN drivy.messaging_member_link l ON l.school_id=c.school_id AND l.conversation_id=c.id AND l.cut_sequence IS NULL
  LEFT JOIN drivy.notification_preference p ON p.person_id=l.person_id
  WHERE c.school_id=NEW.school_id AND c.id=NEW.conversation_id
   AND l.person_id<>NEW.sender_person_id AND NOT (l.person_id=ANY(NEW.mention_person_ids))
   AND CASE c.kind WHEN 'PRIVATE' THEN coalesce(p.messaging_private,true) ELSE coalesce(p.messaging_general,false) END
   AND EXISTS(SELECT 1 FROM drivy.push_device d WHERE d.person_id=l.person_id AND d.revoked_at IS NULL)
  ON CONFLICT(person_id,dedupe_key) DO NOTHING;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.push_message_enqueue() FROM PUBLIC;
CREATE TRIGGER push_message_enqueue AFTER INSERT ON drivy.messaging_message
 FOR EACH ROW EXECUTE FUNCTION drivy.push_message_enqueue();

-- Faits relus juste avant l'envoi d'une alerte de messagerie. La décision (catégorie, préférence, sourdine) est prise par
-- decideMessagingNotification (apps/api/src/messaging-notifications.ts) à partir de ces faits ; cette fonction ne décide pas.
-- Verrouille la notification, la périme si son échéance est passée, et ne renvoie aucune ligne si elle n'est plus en attente.
-- Ne dépend pas des paramètres de session : le worker n'a pas d'identité scolaire. Aucune donnée de message n'est renvoyée.
CREATE FUNCTION drivy.push_messaging_snapshot(notification uuid)
RETURNS TABLE(conversation_kind text, mentions_recipient boolean, recipient_eligible boolean, event_available boolean,
 conversation_silenced boolean, preference_version integer, pref_private boolean, pref_general boolean, pref_mentions boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE n drivy.push_notification; c drivy.messaging_conversation; msg drivy.messaging_message; pref drivy.notification_preference;
 open_link drivy.messaging_member_link; read_to bigint; muted boolean; eligible boolean;
BEGIN
 SELECT * INTO n FROM drivy.push_notification WHERE id=notification FOR UPDATE;
 IF NOT FOUND OR n.status<>'PENDING' OR n.category NOT IN('MESSAGE_MENTION','MESSAGE_PRIVATE','MESSAGE_GENERAL') THEN RETURN; END IF;
 IF n.valid_until IS NOT NULL AND n.valid_until<=statement_timestamp() THEN
  UPDATE drivy.push_notification SET status='EXPIRED' WHERE id=n.id;
  RETURN;
 END IF;
 SELECT * INTO c FROM drivy.messaging_conversation WHERE school_id=n.school_id AND id=n.conversation_id;
 SELECT * INTO msg FROM drivy.messaging_message WHERE school_id=n.school_id AND conversation_id=n.conversation_id AND id=n.message_id;
 SELECT * INTO pref FROM drivy.notification_preference WHERE person_id=n.person_id;
 SELECT * INTO open_link FROM drivy.messaging_member_link WHERE school_id=n.school_id AND conversation_id=n.conversation_id
  AND person_id=n.person_id AND cut_sequence IS NULL;
 SELECT rs.last_read_sequence, coalesce(rs.muted_until>statement_timestamp(),false) INTO read_to, muted
  FROM drivy.messaging_read_state rs WHERE rs.school_id=n.school_id AND rs.conversation_id=n.conversation_id AND rs.person_id=n.person_id;
 eligible:=coalesce(
  EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id JOIN drivy.school s ON s.id=m.school_id
   WHERE m.school_id=n.school_id AND m.person_id=n.person_id AND m.status='ACTIVE' AND p.status='ACTIVE' AND s.status='ACTIVE')
  AND open_link.person_id IS NOT NULL
  AND CASE c.kind
   WHEN 'GENERAL' THEN NOT EXISTS(SELECT 1 FROM drivy.messaging_general_removal r
    JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.membership_id AND m.status='ACTIVE'
    WHERE r.school_id=n.school_id AND r.person_id=n.person_id)
   WHEN 'PRIVATE' THEN n.person_id IN(c.person_low,c.person_high) AND drivy.push_pair_eligible(n.school_id,c.person_low,c.person_high)
   ELSE false END,false);
 RETURN QUERY SELECT c.kind, coalesce(n.person_id=ANY(msg.mention_person_ids),false), eligible,
  -- Message présent, non supprimé pour tous, dans la plage lisible du lien ouvert et pas déjà lu (sur un autre appareil).
  coalesce(msg.id IS NOT NULL AND msg.deleted_at IS NULL AND open_link.person_id IS NOT NULL
   AND msg.sequence>open_link.readable_after AND msg.sequence>coalesce(read_to,0),false),
  coalesce(muted,false), coalesce(pref.version,1), coalesce(pref.messaging_private,true),
  coalesce(pref.messaging_general,false), coalesce(pref.messaging_mentions,true);
END $$;
REVOKE ALL ON FUNCTION drivy.push_messaging_snapshot(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_messaging_snapshot(uuid) TO drivy_course_worker;
