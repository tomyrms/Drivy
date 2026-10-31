-- #77 : traitement des signalements d'abus par les administrateurs de l'école, destinataires de clés, contexte minimal.
-- Migration additive : aucune migration existante n'est modifiée. Décisions et limites : docs/implementation/messaging-reports-77.md.
-- Le serveur ne reçoit toujours que des enveloppes chiffrées pour les appareils des administrateurs. Aucune purge n'est définie
-- ici : la conservation des preuves dépend de #68 (décision non prise).

-- 1. Statut de traitement : ouvert, traité, classé. Le changement passe par drivy.messaging_set_report_status uniquement.
ALTER TABLE drivy.messaging_report
 ADD COLUMN status text NOT NULL DEFAULT 'OPEN' CHECK(status IN('OPEN','HANDLED','DISMISSED')),
 ADD COLUMN status_updated_at timestamptz NOT NULL DEFAULT now(),
 ADD COLUMN conversation_kind text CHECK(conversation_kind IS NULL OR conversation_kind IN('PRIVATE','GENERAL'));
CREATE INDEX messaging_report_status_inbox ON drivy.messaging_report(school_id,status,created_at DESC,id DESC);

-- 2. Contexte minimal de chaque message choisi : auteur, rang et date. Jamais le contenu (il reste chiffré dans envelope).
-- Colonnes nulles pour d'éventuelles lignes antérieures : le signalement chiffré n'a jamais pu partir avant ce lot.
ALTER TABLE drivy.messaging_report_item
 ADD COLUMN sender_person_id uuid REFERENCES drivy.person(id),
 ADD COLUMN message_sequence bigint CHECK(message_sequence IS NULL OR message_sequence>0),
 ADD COLUMN message_accepted_at timestamptz;

-- 3. Historique des changements de statut : qui, de quel statut vers lequel, quand. Conservé sans purge.
CREATE TABLE drivy.messaging_report_status_event (
  id bigserial PRIMARY KEY, school_id uuid NOT NULL, report_id uuid NOT NULL,
  actor_person_id uuid NOT NULL REFERENCES drivy.person(id),
  from_status text NOT NULL CHECK(from_status IN('OPEN','HANDLED','DISMISSED')),
  to_status text NOT NULL CHECK(to_status IN('OPEN','HANDLED','DISMISSED')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK(from_status<>to_status),
  FOREIGN KEY(school_id,report_id) REFERENCES drivy.messaging_report(school_id,id)
);
CREATE INDEX messaging_report_status_event_report ON drivy.messaging_report_status_event(school_id,report_id,id);
ALTER TABLE drivy.messaging_report_status_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.messaging_report_status_event FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
 EXECUTE format('CREATE POLICY messaging_owner_all ON drivy.messaging_report_status_event FOR ALL TO %I USING(true) WITH CHECK(true)',current_user);
END $$;
-- Lecture réservée aux administrateurs de l'école ; aucune écriture directe accordée à drivy_app.
CREATE POLICY messaging_report_status_event_read ON drivy.messaging_report_status_event FOR SELECT TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND drivy.messaging_actor_school_admin(school_id));
GRANT SELECT ON drivy.messaging_report_status_event TO drivy_app;

-- 4. Destinataires des signalements : administrateurs actifs de l'école, pour tout membre actif qui signale.
-- Identifiants seulement : aucun nom, aucun contact.
CREATE FUNCTION drivy.messaging_report_recipients(school uuid) RETURNS TABLE(person_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT DISTINCT m.person_id FROM drivy.membership m
 WHERE school=nullif(current_setting('app.school_id',true),'')::uuid
   AND drivy.messaging_member(school,nullif(current_setting('app.person_id',true),'')::uuid)
   AND m.school_id=school AND drivy.messaging_school_admin(school,m.person_id)
$$;

-- 5. Pairs de clés : un administrateur actif de l'école est un pair de tout membre actif, afin que celui-ci puisse lui
-- partager la clé d'un signalement (clés publiques et to-device Olm seulement). Les autres règles sont inchangées.
CREATE OR REPLACE FUNCTION drivy.messaging_key_peer(school uuid, target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT school=nullif(current_setting('app.school_id',true),'')::uuid
  AND drivy.messaging_member(school,nullif(current_setting('app.person_id',true),'')::uuid)
  AND drivy.messaging_member(school,target)
  AND (target=nullif(current_setting('app.person_id',true),'')::uuid
    OR drivy.messaging_private_allowed(school,nullif(current_setting('app.person_id',true),'')::uuid,target)
    OR drivy.messaging_school_admin(school,target)
    OR (EXISTS(SELECT 1 FROM drivy.messaging_conversation c WHERE c.school_id=school AND c.kind='GENERAL')
      AND drivy.messaging_general_participant(school,nullif(current_setting('app.person_id',true),'')::uuid)
      AND drivy.messaging_general_participant(school,target)))
$$;

-- 6. Noms affichables pour la boîte : seulement les personnes présentes dans un signalement de l'école
-- (signalant, auteurs des messages choisis, personnes qui ont changé un statut), et seulement pour un administrateur.
CREATE FUNCTION drivy.messaging_report_people(school uuid) RETURNS TABLE(person_id uuid, display_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.id,p.display_name FROM drivy.person p
 WHERE school=nullif(current_setting('app.school_id',true),'')::uuid
   AND drivy.messaging_actor_school_admin(school)
   AND p.id IN(
     SELECT r.reporter_person_id FROM drivy.messaging_report r WHERE r.school_id=school
     UNION SELECT i.sender_person_id FROM drivy.messaging_report_item i WHERE i.school_id=school AND i.sender_person_id IS NOT NULL
     UNION SELECT e.actor_person_id FROM drivy.messaging_report_status_event e WHERE e.school_id=school)
$$;

-- 7. Changement de statut : droit relu et verrouillé, signalement verrouillé, statut attendu comparé (course entre deux
-- administrateurs), événement écrit dans la même transaction. Rejouer le statut déjà posé ne crée pas d'événement.
CREATE FUNCTION drivy.messaging_set_report_status(school uuid, report uuid, new_status text, expected_status text) RETURNS text
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; held text;
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 PERFORM 1 FROM drivy.membership m WHERE m.school_id=school AND m.person_id=actor AND m.status='ACTIVE' FOR SHARE;
 IF NOT drivy.messaging_actor_school_admin(school) THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
 IF new_status NOT IN('OPEN','HANDLED','DISMISSED') OR expected_status NOT IN('OPEN','HANDLED','DISMISSED') THEN
  RAISE EXCEPTION 'invalid' USING ERRCODE='22023';
 END IF;
 SELECT r.status INTO held FROM drivy.messaging_report r WHERE r.school_id=school AND r.id=report FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'missing' USING ERRCODE='DV404'; END IF;
 IF held=new_status THEN RETURN held; END IF;
 IF held<>expected_status THEN RAISE EXCEPTION 'stale' USING ERRCODE='DV410'; END IF;
 UPDATE drivy.messaging_report SET status=new_status,status_updated_at=now() WHERE school_id=school AND id=report;
 INSERT INTO drivy.messaging_report_status_event(school_id,report_id,actor_person_id,from_status,to_status)
  VALUES(school,report,actor,held,new_status);
 RETURN new_status;
END $$;

REVOKE ALL ON FUNCTION drivy.messaging_report_recipients(uuid),drivy.messaging_report_people(uuid),
 drivy.messaging_set_report_status(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_report_recipients(uuid),drivy.messaging_report_people(uuid),
 drivy.messaging_set_report_status(uuid,uuid,text,text) TO drivy_app;
