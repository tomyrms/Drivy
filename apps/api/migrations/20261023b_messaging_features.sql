-- Messagerie #65, décisions du 23 octobre 2026 : fin du lien, membres du général, modération, réactions, sondages, signalements.
-- Aucune colonne en clair : le serveur ne voit que des métadonnées acceptées (décision 1). API toujours désactivée hors tests.
-- Codes d'erreur internes : DV403 refus, DV404 introuvable, DV409 conflit d'état (traduits par l'API).

-- 1. Fin du lien : une séquence de coupure par membre et par conversation.
ALTER TABLE drivy.messaging_conversation ADD COLUMN members_epoch bigint NOT NULL DEFAULT 0 CHECK(members_epoch>=0);
CREATE TABLE drivy.messaging_member_link (
  school_id uuid NOT NULL, conversation_id uuid NOT NULL, person_id uuid NOT NULL REFERENCES drivy.person(id),
  link_number integer NOT NULL CHECK(link_number>0),
  -- Messages lisibles : readable_after < sequence <= cut_sequence (ou sans limite tant que le lien est ouvert).
  readable_after bigint NOT NULL CHECK(readable_after>=0), cut_sequence bigint CHECK(cut_sequence IS NULL OR cut_sequence>=readable_after),
  opened_at timestamptz NOT NULL DEFAULT now(), cut_at timestamptz,
  PRIMARY KEY(school_id,conversation_id,person_id,link_number),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id),
  CHECK((cut_sequence IS NULL)=(cut_at IS NULL))
);
CREATE UNIQUE INDEX messaging_one_open_link ON drivy.messaging_member_link(school_id,conversation_id,person_id) WHERE cut_sequence IS NULL;

-- 4. Retrait du général et administrateurs du groupe, liés à l'adhésion : une nouvelle adhésion repart des valeurs par défaut.
CREATE TABLE drivy.messaging_general_removal (
  school_id uuid NOT NULL, membership_id uuid NOT NULL, person_id uuid NOT NULL REFERENCES drivy.person(id),
  removed_by_person_id uuid NOT NULL REFERENCES drivy.person(id), removed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,membership_id),
  FOREIGN KEY(school_id,membership_id) REFERENCES drivy.membership(school_id,id)
);
CREATE TABLE drivy.messaging_general_admin (
  school_id uuid NOT NULL, membership_id uuid NOT NULL, person_id uuid NOT NULL REFERENCES drivy.person(id),
  is_admin boolean NOT NULL, changed_by_person_id uuid NOT NULL REFERENCES drivy.person(id), changed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,membership_id),
  FOREIGN KEY(school_id,membership_id) REFERENCES drivy.membership(school_id,id)
);
CREATE TABLE drivy.messaging_general_audit (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY, school_id uuid NOT NULL REFERENCES drivy.school(id),
  actor_person_id uuid NOT NULL REFERENCES drivy.person(id), target_person_id uuid NOT NULL REFERENCES drivy.person(id),
  action text NOT NULL CHECK(action IN('ADMIN_GRANTED','ADMIN_REVOKED','MEMBER_REMOVED')),
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- 5/6. Tombstone, réponse citée, épinglage. L'enveloppe devient NULL après suppression pour tout le monde.
ALTER TABLE drivy.messaging_message ALTER COLUMN envelope DROP NOT NULL;
ALTER TABLE drivy.messaging_message ADD COLUMN deleted_at timestamptz, ADD COLUMN deleted_by_person_id uuid REFERENCES drivy.person(id),
  ADD COLUMN reply_to_message_id uuid REFERENCES drivy.messaging_message(id),
  ADD COLUMN pinned_at timestamptz, ADD COLUMN pinned_by_person_id uuid REFERENCES drivy.person(id),
  ADD CONSTRAINT messaging_message_tombstone CHECK((deleted_at IS NULL)=(envelope IS NOT NULL) AND (deleted_at IS NULL)=(deleted_by_person_id IS NULL)),
  ADD CONSTRAINT messaging_message_pin CHECK((pinned_at IS NULL)=(pinned_by_person_id IS NULL) AND (deleted_at IS NULL OR pinned_at IS NULL)),
  ADD CONSTRAINT messaging_message_reply CHECK(reply_to_message_id IS DISTINCT FROM id);
CREATE TABLE drivy.messaging_hidden_message (
  school_id uuid NOT NULL, conversation_id uuid NOT NULL, message_id uuid NOT NULL REFERENCES drivy.messaging_message(id),
  person_id uuid NOT NULL REFERENCES drivy.person(id), hidden_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,message_id,person_id),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id)
);
CREATE TABLE drivy.messaging_reaction (
  school_id uuid NOT NULL, conversation_id uuid NOT NULL, message_id uuid NOT NULL REFERENCES drivy.messaging_message(id),
  person_id uuid NOT NULL REFERENCES drivy.person(id),
  emoji text NOT NULL CHECK(emoji IN('👍','❤️','😂','😮','😢','🙏')), created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,message_id,person_id,emoji),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id)
);

-- 7. Sondages : question et libellés chiffrés dans l'enveloppe ; le serveur ne connaît que le nombre d'options et les indices votés.
CREATE TABLE drivy.messaging_poll (
  school_id uuid NOT NULL, conversation_id uuid NOT NULL, message_id uuid PRIMARY KEY REFERENCES drivy.messaging_message(id),
  creator_person_id uuid NOT NULL REFERENCES drivy.person(id),
  option_count integer NOT NULL CHECK(option_count BETWEEN 2 AND 12), multiple boolean NOT NULL DEFAULT false,
  closed_at timestamptz,
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id)
);
CREATE TABLE drivy.messaging_poll_vote (
  school_id uuid NOT NULL, conversation_id uuid NOT NULL, message_id uuid NOT NULL REFERENCES drivy.messaging_poll(message_id),
  person_id uuid NOT NULL REFERENCES drivy.person(id), option_index integer NOT NULL CHECK(option_index BETWEEN 0 AND 11),
  voted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(message_id,person_id,option_index),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id)
);

-- 8. Signalements : seulement les messages choisis, rechiffrés pour les administrateurs de l'école.
CREATE TABLE drivy.messaging_report (
  id uuid PRIMARY KEY, school_id uuid NOT NULL REFERENCES drivy.school(id), conversation_id uuid NOT NULL,
  reporter_person_id uuid NOT NULL REFERENCES drivy.person(id), client_report_id uuid NOT NULL,
  fingerprint text NOT NULL CHECK(fingerprint ~ '^[0-9a-f]{64}$'), created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(school_id,reporter_person_id,client_report_id), UNIQUE(school_id,id),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id)
);
CREATE TABLE drivy.messaging_report_item (
  school_id uuid NOT NULL, report_id uuid NOT NULL, message_id uuid NOT NULL REFERENCES drivy.messaging_message(id),
  envelope jsonb NOT NULL CHECK(jsonb_typeof(envelope)='object' AND envelope ?& ARRAY['scheme','keyId','payload']
    AND envelope - 'scheme' - 'keyId' - 'payload'='{}'::jsonb AND length(envelope->>'payload') BETWEEN 4 AND 12000),
  PRIMARY KEY(report_id,message_id),
  FOREIGN KEY(school_id,report_id) REFERENCES drivy.messaging_report(school_id,id)
);
CREATE INDEX messaging_report_inbox ON drivy.messaging_report(school_id,created_at DESC,id DESC);

-- Éligibilité non liée à l'acteur : réservée aux fonctions SECURITY DEFINER, jamais accordée à drivy_app.
-- Plus de contact ADMIN dédié (décision 2) : un élève ne voit que ses moniteurs attribués.
CREATE FUNCTION drivy.messaging_pair_eligible(school uuid, a uuid, b uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT a<>b AND drivy.messaging_member(school,a) AND drivy.messaging_member(school,b)
  AND EXISTS(SELECT 1 FROM drivy.membership am JOIN drivy.membership pm ON pm.school_id=am.school_id
    WHERE am.school_id=school AND am.person_id=a AND am.status='ACTIVE' AND pm.person_id=b AND pm.status='ACTIVE'
      AND EXISTS(SELECT 1 FROM drivy.learner_profile lp JOIN drivy.training t ON t.school_id=lp.school_id AND t.learner_id=lp.id
        JOIN drivy.instructor_assignment ia ON ia.school_id=t.school_id AND ia.training_id=t.id
        WHERE lp.school_id=school AND lp.archived_at IS NULL AND t.status IN('ACTIVE','PAUSED')
          AND ia.valid_from<=statement_timestamp() AND (ia.valid_until IS NULL OR ia.valid_until>statement_timestamp())
          AND ((lp.person_id=a AND 'LEARNER'=ANY(am.roles) AND 'INSTRUCTOR'=ANY(pm.roles) AND ia.instructor_membership_id=pm.id)
            OR (lp.person_id=b AND 'LEARNER'=ANY(pm.roles) AND 'INSTRUCTOR'=ANY(am.roles) AND ia.instructor_membership_id=am.id))))
$$;
CREATE OR REPLACE FUNCTION drivy.messaging_private_allowed(school uuid, actor uuid, peer uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_pair_eligible(school,actor,peer)
$$;
CREATE FUNCTION drivy.messaging_general_participant(school uuid, person uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.messaging_member(school,person) AND NOT EXISTS(SELECT 1 FROM drivy.messaging_general_removal r
   JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.membership_id AND m.status='ACTIVE'
   WHERE r.school_id=school AND r.person_id=person)
$$;
-- Par défaut, les administrateurs de l'école ; une décision explicite sur l'adhésion courante l'emporte.
CREATE FUNCTION drivy.messaging_is_group_admin(school uuid, person uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.messaging_general_participant(school,person) AND EXISTS(SELECT 1 FROM drivy.membership m
   LEFT JOIN drivy.messaging_general_admin g ON g.school_id=m.school_id AND g.membership_id=m.id
   WHERE m.school_id=school AND m.person_id=person AND m.status='ACTIVE' AND COALESCE(g.is_admin,'ADMIN'=ANY(m.roles)))
$$;
CREATE FUNCTION drivy.messaging_school_admin(school uuid, person uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.messaging_member(school,person) AND EXISTS(SELECT 1 FROM drivy.membership m
   WHERE m.school_id=school AND m.person_id=person AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
$$;
CREATE FUNCTION drivy.messaging_eligible_members(school uuid, target uuid) RETURNS TABLE(person_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT DISTINCT m.person_id FROM drivy.messaging_conversation c JOIN drivy.membership m ON m.school_id=c.school_id AND m.status='ACTIVE'
  WHERE c.school_id=school AND c.id=target AND school=nullif(current_setting('app.school_id',true),'')::uuid
    AND ((c.kind='GENERAL' AND drivy.messaging_general_participant(school,m.person_id))
      OR (c.kind='PRIVATE' AND m.person_id IN(c.person_low,c.person_high) AND drivy.messaging_pair_eligible(school,c.person_low,c.person_high)))
$$;

-- Applique les arrivées, départs et retours. Coupure = dernière séquence acceptée avant la synchronisation.
-- Toute écriture synchronise sous le verrou de la conversation avant d'allouer la séquence suivante :
-- aucun message postérieur à la fin du lien n'entre dans la plage lisible d'un ancien membre.
CREATE FUNCTION drivy.messaging_sync_links(school uuid, target uuid) RETURNS bigint
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE last bigint; epoch bigint; cut_count integer; return_count integer;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid
   OR NOT drivy.messaging_member(school,nullif(current_setting('app.person_id',true),'')::uuid) THEN
   RAISE EXCEPTION 'messaging_scope_denied' USING ERRCODE='42501';
 END IF;
 IF NOT EXISTS(SELECT 1 FROM drivy.messaging_eligible_members(school,target) e WHERE NOT EXISTS(SELECT 1 FROM drivy.messaging_member_link l
     WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=e.person_id AND l.cut_sequence IS NULL))
   AND NOT EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.cut_sequence IS NULL
     AND l.person_id NOT IN(SELECT e.person_id FROM drivy.messaging_eligible_members(school,target) e)) THEN
   SELECT members_epoch INTO epoch FROM drivy.messaging_conversation WHERE school_id=school AND id=target;
   IF NOT FOUND THEN RAISE EXCEPTION 'messaging_not_found' USING ERRCODE='DV404'; END IF;
   RETURN epoch;
 END IF;
 SELECT last_sequence,members_epoch INTO last,epoch FROM drivy.messaging_conversation WHERE school_id=school AND id=target FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'messaging_not_found' USING ERRCODE='DV404'; END IF;
 UPDATE drivy.messaging_member_link l SET cut_sequence=last,cut_at=now()
  WHERE l.school_id=school AND l.conversation_id=target AND l.cut_sequence IS NULL
    AND l.person_id NOT IN(SELECT e.person_id FROM drivy.messaging_eligible_members(school,target) e);
 GET DIAGNOSTICS cut_count=ROW_COUNT;
 SELECT count(*) INTO return_count FROM drivy.messaging_eligible_members(school,target) e
  WHERE EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=e.person_id)
    AND NOT EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=e.person_id AND l.cut_sequence IS NULL);
 INSERT INTO drivy.messaging_member_link(school_id,conversation_id,person_id,link_number,readable_after)
  SELECT school,target,e.person_id,COALESCE(max(l.link_number),0)+1,CASE WHEN count(l.link_number)=0 THEN 0 ELSE last END
  FROM drivy.messaging_eligible_members(school,target) e
  LEFT JOIN drivy.messaging_member_link l ON l.school_id=school AND l.conversation_id=target AND l.person_id=e.person_id
  GROUP BY e.person_id HAVING bool_and(l.cut_sequence IS NOT NULL) OR count(l.link_number)=0;
 -- Première arrivée : pas d'incrément. Chaque départ et chaque retour : +1.
 epoch := epoch+cut_count+return_count;
 UPDATE drivy.messaging_conversation SET members_epoch=epoch WHERE school_id=school AND id=target;
 RETURN epoch;
END $$;

CREATE OR REPLACE FUNCTION drivy.messaging_conversation_allowed(school uuid, actor uuid, target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_member(school,actor)
   AND EXISTS(SELECT 1 FROM drivy.messaging_conversation c WHERE c.school_id=school AND c.id=target)
   AND (EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=actor)
     OR actor IN(SELECT e.person_id FROM drivy.messaging_eligible_members(school,target) e))
$$;
CREATE FUNCTION drivy.messaging_can_write(school uuid, actor uuid, target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_member(school,actor)
   AND EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=actor AND l.cut_sequence IS NULL)
   AND actor IN(SELECT e.person_id FROM drivy.messaging_eligible_members(school,target) e)
$$;
CREATE FUNCTION drivy.messaging_readable_sequence(school uuid, actor uuid, target uuid, seq bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_member(school,actor)
   AND EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=actor
     AND seq>l.readable_after AND (l.cut_sequence IS NULL OR seq<=l.cut_sequence))
$$;
-- Message lisible par l'acteur et non supprimé pour tout le monde.
CREATE FUNCTION drivy.messaging_message_open(school uuid, actor uuid, target uuid, message uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.messaging_message m WHERE m.school_id=school AND m.conversation_id=target AND m.id=message
   AND m.deleted_at IS NULL AND drivy.messaging_readable_sequence(school,actor,target,m.sequence))
$$;
CREATE OR REPLACE FUNCTION drivy.messaging_mentions_allowed(school uuid, actor uuid, target uuid, mentions uuid[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_can_write(school,actor,target)
   AND cardinality(mentions)<=8 AND cardinality(mentions)=(SELECT count(DISTINCT ids.person_id) FROM unnest(mentions) AS ids(person_id))
   AND (cardinality(mentions)=0 OR (EXISTS(SELECT 1 FROM drivy.messaging_conversation c
     WHERE c.school_id=school AND c.id=target AND c.kind='GENERAL')
     AND NOT EXISTS(SELECT 1 FROM unnest(mentions) AS target_person(person_id)
       WHERE NOT drivy.messaging_general_participant(school,target_person.person_id))))
$$;
-- Membres en écriture (liens ouverts) et époque, pour la rotation Megolm du relais de clés.
CREATE FUNCTION drivy.messaging_conversation_members(school uuid, actor uuid, target uuid) RETURNS TABLE(person_id uuid, members_epoch bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT l.person_id,c.members_epoch FROM drivy.messaging_conversation c JOIN drivy.messaging_member_link l
   ON l.school_id=c.school_id AND l.conversation_id=c.id AND l.cut_sequence IS NULL
  WHERE c.school_id=school AND c.id=target AND drivy.messaging_conversation_allowed(school,actor,target)
$$;
-- Annuaire du général : nom, photo si visible (#64), rôle d'administrateur du groupe. Aucune autre donnée.
CREATE FUNCTION drivy.messaging_general_directory(school uuid, actor uuid)
RETURNS TABLE(person_id uuid, display_name text, photo_version integer, is_group_admin boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.id,p.display_name,
   -- person_photo a une RLS forcée réservée à drivy_app : la version publiée vient de person.photo_version.
   CASE WHEN p.photo_version>0 AND drivy.person_photo_visible(p.id) THEN p.photo_version END,
   drivy.messaging_is_group_admin(school,p.id)
 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_member(school,actor)
   AND m.school_id=school AND m.status='ACTIVE' AND p.status='ACTIVE' AND drivy.messaging_general_participant(school,p.id)
$$;
-- Accusés de lecture visibles (décision 7), plafonnés à ce que l'acteur peut lui-même lire.
CREATE FUNCTION drivy.messaging_read_receipts(school uuid, actor uuid, target uuid) RETURNS TABLE(person_id uuid, last_read_sequence bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 WITH cap AS (SELECT CASE WHEN bool_or(l.cut_sequence IS NULL) THEN c.last_sequence ELSE max(l.cut_sequence) END AS value
   FROM drivy.messaging_conversation c JOIN drivy.messaging_member_link l ON l.school_id=c.school_id AND l.conversation_id=c.id AND l.person_id=actor
   WHERE c.school_id=school AND c.id=target GROUP BY c.last_sequence)
 SELECT s.person_id,LEAST(s.last_read_sequence,cap.value) FROM drivy.messaging_read_state s CROSS JOIN cap
 WHERE drivy.messaging_conversation_allowed(school,actor,target) AND s.school_id=school AND s.conversation_id=target
   AND s.person_id<>actor AND s.last_read_sequence>0
   AND EXISTS(SELECT 1 FROM drivy.messaging_member_link l WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=s.person_id AND l.cut_sequence IS NULL)
$$;

-- Mutations sensibles : vérifiées dans la base sous verrou, jamais seulement par l'interface.
CREATE FUNCTION drivy.messaging_delete_for_everyone(school uuid, target uuid, message uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; row record;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT m.sender_person_id,m.sequence,m.deleted_at,c.kind INTO row FROM drivy.messaging_message m
   JOIN drivy.messaging_conversation c ON c.school_id=m.school_id AND c.id=m.conversation_id
   WHERE m.school_id=school AND m.conversation_id=target AND m.id=message FOR UPDATE OF m;
 IF NOT FOUND OR NOT drivy.messaging_readable_sequence(school,actor,target,row.sequence) THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF row.deleted_at IS NOT NULL THEN RETURN; END IF;
 IF NOT drivy.messaging_can_write(school,actor,target)
   OR NOT (row.sender_person_id=actor OR (row.kind='GENERAL' AND drivy.messaging_is_group_admin(school,actor))) THEN
   RAISE EXCEPTION 'denied' USING ERRCODE='DV403';
 END IF;
 DELETE FROM drivy.messaging_reaction WHERE school_id=school AND message_id=message;
 DELETE FROM drivy.messaging_poll_vote WHERE school_id=school AND message_id=message;
 DELETE FROM drivy.messaging_poll WHERE school_id=school AND message_id=message;
 UPDATE drivy.messaging_message SET envelope=NULL,deleted_at=now(),deleted_by_person_id=actor,pinned_at=NULL,pinned_by_person_id=NULL
  WHERE school_id=school AND id=message;
END $$;
CREATE FUNCTION drivy.messaging_set_pinned(school uuid, target uuid, message uuid, pinned boolean) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; row record;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT m.sequence,m.deleted_at,c.kind INTO row FROM drivy.messaging_message m
   JOIN drivy.messaging_conversation c ON c.school_id=m.school_id AND c.id=m.conversation_id
   WHERE m.school_id=school AND m.conversation_id=target AND m.id=message FOR UPDATE OF m;
 IF NOT FOUND OR NOT drivy.messaging_readable_sequence(school,actor,target,row.sequence) OR row.deleted_at IS NOT NULL THEN
   RAISE EXCEPTION 'missing' USING ERRCODE='DV404';
 END IF;
 -- Privé : chacun des deux. Général : administrateurs du groupe.
 IF NOT drivy.messaging_can_write(school,actor,target) OR (row.kind='GENERAL' AND NOT drivy.messaging_is_group_admin(school,actor)) THEN
   RAISE EXCEPTION 'denied' USING ERRCODE='DV403';
 END IF;
 UPDATE drivy.messaging_message SET pinned_at=CASE WHEN pinned THEN COALESCE(pinned_at,now()) END,
   pinned_by_person_id=CASE WHEN pinned THEN COALESCE(pinned_by_person_id,actor) END
  WHERE school_id=school AND id=message;
END $$;
CREATE FUNCTION drivy.messaging_set_group_admin(school uuid, target_person uuid, admin boolean) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; target_membership uuid; remaining integer;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 -- Le général sérialise toutes les décisions de groupe de l'école.
 PERFORM 1 FROM drivy.messaging_conversation WHERE school_id=school AND kind='GENERAL' FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF NOT drivy.messaging_is_group_admin(school,actor) THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT m.id INTO target_membership FROM drivy.membership m WHERE m.school_id=school AND m.person_id=target_person AND m.status='ACTIVE' FOR SHARE;
 IF target_membership IS NULL OR NOT drivy.messaging_general_participant(school,target_person) THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF drivy.messaging_is_group_admin(school,target_person)=admin THEN RETURN; END IF;
 IF NOT admin THEN
   SELECT count(*) INTO remaining FROM drivy.membership m WHERE m.school_id=school AND m.status='ACTIVE' AND m.person_id<>target_person
     AND drivy.messaging_is_group_admin(school,m.person_id);
   IF remaining=0 THEN RAISE EXCEPTION 'last_admin' USING ERRCODE='DV409'; END IF;
 END IF;
 INSERT INTO drivy.messaging_general_admin(school_id,membership_id,person_id,is_admin,changed_by_person_id)
  VALUES(school,target_membership,target_person,admin,actor)
  ON CONFLICT(school_id,membership_id) DO UPDATE SET is_admin=EXCLUDED.is_admin,changed_by_person_id=EXCLUDED.changed_by_person_id,changed_at=now();
 INSERT INTO drivy.messaging_general_audit(school_id,actor_person_id,target_person_id,action)
  VALUES(school,actor,target_person,CASE WHEN admin THEN 'ADMIN_GRANTED' ELSE 'ADMIN_REVOKED' END);
END $$;
CREATE FUNCTION drivy.messaging_remove_general_member(school uuid, target_person uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; general uuid; target_membership uuid; remaining integer;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT id INTO general FROM drivy.messaging_conversation WHERE school_id=school AND kind='GENERAL' FOR UPDATE;
 IF general IS NULL THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF NOT drivy.messaging_is_group_admin(school,actor) OR target_person=actor THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT m.id INTO target_membership FROM drivy.membership m WHERE m.school_id=school AND m.person_id=target_person AND m.status='ACTIVE' FOR SHARE;
 IF target_membership IS NULL THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF NOT drivy.messaging_general_participant(school,target_person) THEN RETURN; END IF;
 IF drivy.messaging_is_group_admin(school,target_person) THEN
   SELECT count(*) INTO remaining FROM drivy.membership m WHERE m.school_id=school AND m.status='ACTIVE' AND m.person_id<>target_person
     AND drivy.messaging_is_group_admin(school,m.person_id);
   IF remaining=0 THEN RAISE EXCEPTION 'last_admin' USING ERRCODE='DV409'; END IF;
 END IF;
 INSERT INTO drivy.messaging_general_removal(school_id,membership_id,person_id,removed_by_person_id)
  VALUES(school,target_membership,target_person,actor) ON CONFLICT DO NOTHING;
 INSERT INTO drivy.messaging_general_audit(school_id,actor_person_id,target_person_id,action) VALUES(school,actor,target_person,'MEMBER_REMOVED');
 PERFORM drivy.messaging_sync_links(school,general);
END $$;

-- Votes : remplace l'ensemble des choix de l'acteur sous le verrou du sondage (vide = retrait).
-- Fonction plutôt que politique : un votant n'a pas le droit de verrouiller la ligne du sondage.
CREATE FUNCTION drivy.messaging_set_poll_votes(school uuid, target uuid, message uuid, indexes integer[]) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; poll record;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT p.option_count,p.multiple,p.closed_at INTO poll FROM drivy.messaging_poll p
  WHERE p.school_id=school AND p.conversation_id=target AND p.message_id=message FOR UPDATE;
 IF NOT FOUND OR NOT drivy.messaging_message_open(school,actor,target,message) THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF NOT drivy.messaging_can_write(school,actor,target) THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 IF poll.closed_at IS NOT NULL THEN RAISE EXCEPTION 'closed' USING ERRCODE='DV409'; END IF;
 IF cardinality(indexes)<>(SELECT count(DISTINCT i) FROM unnest(indexes) i) OR (NOT poll.multiple AND cardinality(indexes)>1)
   OR EXISTS(SELECT 1 FROM unnest(indexes) i WHERE i IS NULL OR i<0 OR i>=poll.option_count) THEN
   RAISE EXCEPTION 'invalid' USING ERRCODE='22023';
 END IF;
 DELETE FROM drivy.messaging_poll_vote v WHERE v.message_id=message AND v.person_id=actor AND NOT v.option_index=ANY(indexes);
 INSERT INTO drivy.messaging_poll_vote(school_id,conversation_id,message_id,person_id,option_index)
  SELECT school,target,message,actor,i FROM unnest(indexes) i ON CONFLICT DO NOTHING;
END $$;
CREATE FUNCTION drivy.messaging_close_poll(school uuid, target uuid, message uuid) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; poll record;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 SELECT p.creator_person_id,p.closed_at INTO poll FROM drivy.messaging_poll p
  WHERE p.school_id=school AND p.conversation_id=target AND p.message_id=message FOR UPDATE;
 IF NOT FOUND OR NOT drivy.messaging_message_open(school,actor,target,message) THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF poll.creator_person_id<>actor OR NOT drivy.messaging_can_write(school,actor,target) THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 IF poll.closed_at IS NULL THEN UPDATE drivy.messaging_poll SET closed_at=now() WHERE message_id=message; END IF;
END $$;

DO $$ DECLARE fn text; BEGIN
 FOREACH fn IN ARRAY ARRAY['messaging_pair_eligible(uuid,uuid,uuid)','messaging_eligible_members(uuid,uuid)'] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION drivy.%s FROM PUBLIC',fn);
 END LOOP;
 FOREACH fn IN ARRAY ARRAY['messaging_general_participant(uuid,uuid)','messaging_is_group_admin(uuid,uuid)','messaging_school_admin(uuid,uuid)',
   'messaging_sync_links(uuid,uuid)','messaging_can_write(uuid,uuid,uuid)','messaging_readable_sequence(uuid,uuid,uuid,bigint)',
   'messaging_message_open(uuid,uuid,uuid,uuid)','messaging_conversation_members(uuid,uuid,uuid)','messaging_general_directory(uuid,uuid)',
   'messaging_read_receipts(uuid,uuid,uuid)','messaging_delete_for_everyone(uuid,uuid,uuid)','messaging_set_pinned(uuid,uuid,uuid,boolean)',
   'messaging_set_group_admin(uuid,uuid,boolean)','messaging_remove_general_member(uuid,uuid)',
   'messaging_set_poll_votes(uuid,uuid,uuid,integer[])','messaging_close_poll(uuid,uuid,uuid)'] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION drivy.%s FROM PUBLIC',fn);
  EXECUTE format('GRANT EXECUTE ON FUNCTION drivy.%s TO drivy_app',fn);
 END LOOP;
END $$;

-- RLS : les nouvelles tables suivent la fondation (FORCE, propriétaire explicitement autorisé pour ses fonctions).
DO $$ DECLARE table_name text; BEGIN
 FOREACH table_name IN ARRAY ARRAY['messaging_member_link','messaging_general_removal','messaging_general_admin','messaging_general_audit',
   'messaging_hidden_message','messaging_reaction','messaging_poll','messaging_poll_vote','messaging_report','messaging_report_item'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',table_name);
  EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',table_name);
  EXECUTE format('CREATE POLICY messaging_owner_all ON drivy.%I FOR ALL TO %I USING(true) WITH CHECK(true)',table_name,current_user);
 END LOOP;
 EXECUTE format('CREATE POLICY messaging_owner_conversation_update ON drivy.messaging_conversation FOR UPDATE TO %I USING(true) WITH CHECK(true)',current_user);
 EXECUTE format('CREATE POLICY messaging_owner_message_all ON drivy.messaging_message FOR ALL TO %I USING(true) WITH CHECK(true)',current_user);
 EXECUTE format('CREATE POLICY messaging_owner_read_state ON drivy.messaging_read_state FOR SELECT TO %I USING(true)',current_user);
END $$;

-- Un ancien membre garde la conversation dans sa liste et sa plage lisible ; l'écriture exige un lien ouvert.
DROP POLICY messaging_conversation_read ON drivy.messaging_conversation;
CREATE POLICY messaging_conversation_read ON drivy.messaging_conversation FOR SELECT TO drivy_app
 USING(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,id));
DROP POLICY messaging_conversation_update ON drivy.messaging_conversation;
CREATE POLICY messaging_conversation_update ON drivy.messaging_conversation FOR UPDATE TO drivy_app
 USING(drivy.messaging_can_write(school_id,nullif(current_setting('app.person_id',true),'')::uuid,id))
 WITH CHECK(drivy.messaging_can_write(school_id,nullif(current_setting('app.person_id',true),'')::uuid,id));
DROP POLICY messaging_message_read ON drivy.messaging_message;
CREATE POLICY messaging_message_read ON drivy.messaging_message FOR SELECT TO drivy_app
 USING(drivy.messaging_readable_sequence(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id,sequence));
DROP POLICY messaging_message_insert ON drivy.messaging_message;
CREATE POLICY messaging_message_insert ON drivy.messaging_message FOR INSERT TO drivy_app
 WITH CHECK(sender_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND deleted_at IS NULL AND pinned_at IS NULL
   AND drivy.messaging_mentions_allowed(school_id,sender_person_id,conversation_id,mention_person_ids)
   AND (reply_to_message_id IS NULL OR drivy.messaging_message_open(school_id,sender_person_id,conversation_id,reply_to_message_id)));

CREATE POLICY messaging_link_own ON drivy.messaging_member_link FOR SELECT TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_hidden_own ON drivy.messaging_hidden_message FOR SELECT TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND school_id=nullif(current_setting('app.school_id',true),'')::uuid);
CREATE POLICY messaging_hidden_insert ON drivy.messaging_hidden_message FOR INSERT TO drivy_app
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND EXISTS(SELECT 1 FROM drivy.messaging_message m WHERE m.school_id=messaging_hidden_message.school_id
     AND m.conversation_id=messaging_hidden_message.conversation_id AND m.id=messaging_hidden_message.message_id));
CREATE POLICY messaging_reaction_read ON drivy.messaging_reaction FOR SELECT TO drivy_app
 USING(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id));
CREATE POLICY messaging_reaction_insert ON drivy.messaging_reaction FOR INSERT TO drivy_app
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_can_write(school_id,person_id,conversation_id)
   AND drivy.messaging_message_open(school_id,person_id,conversation_id,message_id));
CREATE POLICY messaging_reaction_delete ON drivy.messaging_reaction FOR DELETE TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_can_write(school_id,person_id,conversation_id));
CREATE POLICY messaging_poll_read ON drivy.messaging_poll FOR SELECT TO drivy_app
 USING(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id));
CREATE POLICY messaging_poll_insert ON drivy.messaging_poll FOR INSERT TO drivy_app
 WITH CHECK(creator_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND closed_at IS NULL
   AND EXISTS(SELECT 1 FROM drivy.messaging_message m WHERE m.school_id=messaging_poll.school_id AND m.conversation_id=messaging_poll.conversation_id
     AND m.id=messaging_poll.message_id AND m.sender_person_id=messaging_poll.creator_person_id));
CREATE POLICY messaging_poll_close ON drivy.messaging_poll FOR UPDATE TO drivy_app
 USING(creator_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_can_write(school_id,creator_person_id,conversation_id))
 WITH CHECK(creator_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND closed_at IS NOT NULL);
CREATE POLICY messaging_vote_read ON drivy.messaging_poll_vote FOR SELECT TO drivy_app
 USING(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id));
CREATE POLICY messaging_vote_insert ON drivy.messaging_poll_vote FOR INSERT TO drivy_app
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_can_write(school_id,person_id,conversation_id)
   AND drivy.messaging_message_open(school_id,person_id,conversation_id,message_id)
   AND EXISTS(SELECT 1 FROM drivy.messaging_poll p WHERE p.message_id=messaging_poll_vote.message_id AND p.closed_at IS NULL
     AND messaging_poll_vote.option_index<p.option_count));
CREATE POLICY messaging_vote_delete ON drivy.messaging_poll_vote FOR DELETE TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_can_write(school_id,person_id,conversation_id)
   AND EXISTS(SELECT 1 FROM drivy.messaging_poll p WHERE p.message_id=messaging_poll_vote.message_id AND p.closed_at IS NULL));
CREATE POLICY messaging_report_read ON drivy.messaging_report FOR SELECT TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND (reporter_person_id=nullif(current_setting('app.person_id',true),'')::uuid
   OR drivy.messaging_school_admin(school_id,nullif(current_setting('app.person_id',true),'')::uuid)));
CREATE POLICY messaging_report_insert ON drivy.messaging_report FOR INSERT TO drivy_app
 WITH CHECK(reporter_person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_conversation_allowed(school_id,reporter_person_id,conversation_id));
CREATE POLICY messaging_report_item_read ON drivy.messaging_report_item FOR SELECT TO drivy_app
 USING(EXISTS(SELECT 1 FROM drivy.messaging_report r WHERE r.school_id=messaging_report_item.school_id AND r.id=messaging_report_item.report_id));
CREATE POLICY messaging_report_item_insert ON drivy.messaging_report_item FOR INSERT TO drivy_app
 WITH CHECK(EXISTS(SELECT 1 FROM drivy.messaging_report r JOIN drivy.messaging_message m ON m.school_id=r.school_id AND m.conversation_id=r.conversation_id
   WHERE r.school_id=messaging_report_item.school_id AND r.id=messaging_report_item.report_id
     AND r.reporter_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.id=messaging_report_item.message_id
     AND drivy.messaging_readable_sequence(r.school_id,r.reporter_person_id,r.conversation_id,m.sequence)));

GRANT SELECT ON drivy.messaging_member_link,drivy.messaging_hidden_message,drivy.messaging_reaction,drivy.messaging_poll,
  drivy.messaging_poll_vote,drivy.messaging_report,drivy.messaging_report_item TO drivy_app;
GRANT INSERT ON drivy.messaging_hidden_message,drivy.messaging_reaction,drivy.messaging_poll,drivy.messaging_poll_vote,
  drivy.messaging_report,drivy.messaging_report_item TO drivy_app;
GRANT DELETE ON drivy.messaging_reaction,drivy.messaging_poll_vote TO drivy_app;
GRANT UPDATE(closed_at) ON drivy.messaging_poll TO drivy_app;
