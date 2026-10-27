-- #101 : alerte ciblée aux personnes mentionnées dans un message accepté.
-- Réutilise la file push des cours (#43/#44). Aucun contenu, extrait ni nom d'auteur dans la charge :
-- la messagerie est chiffrée de bout en bout et aucune règle existante n'autorise à exposer l'auteur dans un push.
ALTER TABLE drivy.push_notification DROP CONSTRAINT push_notification_category_check;
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_category_check
 CHECK(category IN('OFFER','REMINDER','CHANGE','STAFF','NEW_SESSION','MESSAGE_MENTION'));
ALTER TABLE drivy.push_notification ADD COLUMN conversation_id uuid, ADD COLUMN message_id uuid,
 ADD COLUMN message_sequence bigint CHECK(message_sequence IS NULL OR message_sequence>0);
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_message_ref
 CHECK((category='MESSAGE_MENTION')=(message_id IS NOT NULL AND conversation_id IS NOT NULL));
-- Préférence de mention, active par défaut comme les catégories de cours.
ALTER TABLE drivy.notification_preference ADD COLUMN messaging_mentions boolean NOT NULL DEFAULT true;
GRANT UPDATE(messaging_mentions) ON drivy.notification_preference TO drivy_app;

-- Mise en file à l'acceptation : une seule alerte par personne et par message, jamais pour l'auteur.
CREATE FUNCTION drivy.messaging_mention_enqueue() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
 INSERT INTO drivy.push_notification(person_id,school_id,category,dedupe_key,title,body,conversation_id,message_id,message_sequence)
  SELECT DISTINCT target, NEW.school_id, 'MESSAGE_MENTION', 'MessagingMention:'||NEW.id, 'Quelqu''un vous a mentionné', '',
   NEW.conversation_id, NEW.id, NEW.sequence
  FROM unnest(NEW.mention_person_ids) AS t(target)
  WHERE target<>NEW.sender_person_id
  ON CONFLICT(person_id,dedupe_key) DO NOTHING;
 RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.messaging_mention_enqueue() FROM PUBLIC;
CREATE TRIGGER messaging_mention_enqueue AFTER INSERT ON drivy.messaging_message
 FOR EACH ROW WHEN (cardinality(NEW.mention_person_ids)>0) EXECUTE FUNCTION drivy.messaging_mention_enqueue();

-- Relecture juste avant l'envoi : préférences, adhésion, lien ouvert, retrait du général, sourdine, message non supprimé.
-- Ne dépend pas des paramètres de session : le worker n'a pas d'identité scolaire.
CREATE FUNCTION drivy.push_revalidate(notification uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE n drivy.push_notification; reason text;
BEGIN
 SELECT * INTO n FROM drivy.push_notification WHERE id=notification FOR UPDATE;
 IF NOT FOUND OR n.status<>'PENDING' THEN RETURN false; END IF;
 IF n.category<>'MESSAGE_MENTION' THEN RETURN drivy.course_push_revalidate(notification); END IF;
 IF NOT coalesce((SELECT p.messaging_mentions FROM drivy.notification_preference p WHERE p.person_id=n.person_id),true) THEN
  reason:='PREFERENCE_DISABLED';
 ELSIF NOT EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id JOIN drivy.school s ON s.id=m.school_id
   WHERE m.school_id=n.school_id AND m.person_id=n.person_id AND m.status='ACTIVE' AND p.status='ACTIVE' AND s.status='ACTIVE')
  OR EXISTS(SELECT 1 FROM drivy.messaging_general_removal r JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.membership_id AND m.status='ACTIVE'
   WHERE r.school_id=n.school_id AND r.person_id=n.person_id) THEN
  reason:='RECIPIENT_INELIGIBLE';
 ELSIF NOT EXISTS(SELECT 1 FROM drivy.messaging_message msg JOIN drivy.messaging_member_link l
   ON l.school_id=msg.school_id AND l.conversation_id=msg.conversation_id AND l.person_id=n.person_id AND l.cut_sequence IS NULL
   WHERE msg.school_id=n.school_id AND msg.conversation_id=n.conversation_id AND msg.id=n.message_id
    AND msg.deleted_at IS NULL AND msg.sequence>l.readable_after AND n.person_id=ANY(msg.mention_person_ids)) THEN
  reason:='EVENT_OBSOLETE';
 ELSIF EXISTS(SELECT 1 FROM drivy.messaging_read_state rs WHERE rs.school_id=n.school_id AND rs.conversation_id=n.conversation_id
   AND rs.person_id=n.person_id AND rs.muted_until>statement_timestamp()) THEN
  reason:='SILENCED';
 END IF;
 IF reason IS NOT NULL THEN
  UPDATE drivy.push_notification SET status='SKIPPED',failure_code=reason WHERE id=n.id;
  RETURN false;
 END IF;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION drivy.push_revalidate(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_revalidate(uuid) TO drivy_course_worker;
