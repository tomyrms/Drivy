-- Médias chiffrés de la messagerie (#97, tâche T1) : octets opaques, machine d'état durable, journal d'audit.
-- Migration additive : aucune migration appliquée n'est réécrite, aucune colonne existante n'est modifiée.
-- Le serveur ne connaît que l'identifiant, l'école, la conversation, le déposant, la taille, le SHA-256 du chiffré,
-- les octets chiffrés, les horodatages, l'état et le message porteur. Rien de cela ne permet de lire le fichier.
CREATE TABLE drivy.messaging_media (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL,
  conversation_id uuid NOT NULL,
  uploader_person_id uuid NOT NULL REFERENCES drivy.person(id),
  byte_size bigint NOT NULL CHECK (byte_size BETWEEN 1 AND 4194304),
  ciphertext_sha256 text NOT NULL CHECK (ciphertext_sha256 ~ '^[0-9a-f]{64}$'),
  ciphertext bytea,
  message_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  attached_at timestamptz,
  purged_at timestamptz,
  purge_reason text CHECK (purge_reason IN ('MESSAGE_DELETED','ORPHAN','CANCELLED')),
  FOREIGN KEY (school_id, conversation_id) REFERENCES drivy.messaging_conversation(school_id, id),
  FOREIGN KEY (message_id) REFERENCES drivy.messaging_message(id),
  CHECK (ciphertext IS NULL OR octet_length(ciphertext) = byte_size),
  -- États dérivés de colonnes, jamais d'un booléen libre : UPLOADED (octets, sans message), ATTACHED (octets et
  -- message), PURGED (sans octets, marque de suppression conservée). La purge est terminale : aucun octet n'est réécrit.
  CHECK ((ciphertext IS NULL) = (purged_at IS NOT NULL)),
  CHECK ((ciphertext IS NULL) = (purge_reason IS NOT NULL)),
  CHECK ((message_id IS NULL) = (attached_at IS NULL))
);
-- Des octets aléatoires ne se compressent pas : EXTERNAL évite de payer une tentative de compression par dépôt.
ALTER TABLE drivy.messaging_media ALTER COLUMN ciphertext SET STORAGE EXTERNAL;
CREATE UNIQUE INDEX messaging_media_one_per_message
  ON drivy.messaging_media(school_id, message_id) WHERE message_id IS NOT NULL;
CREATE INDEX messaging_media_orphans
  ON drivy.messaging_media(school_id, created_at) WHERE message_id IS NULL AND ciphertext IS NOT NULL;

-- Journal d'audit dans la même base : il ne protège pas d'une restauration (aucune archive indépendante, #68).
CREATE SEQUENCE drivy.messaging_media_purge_sequence;
CREATE TABLE drivy.messaging_media_purge (
  sequence bigint PRIMARY KEY DEFAULT nextval('drivy.messaging_media_purge_sequence'),
  school_id uuid NOT NULL,
  media_id uuid NOT NULL,
  purged_at timestamptz NOT NULL DEFAULT now(),
  reason text NOT NULL CHECK (reason IN ('MESSAGE_DELETED','ORPHAN','CANCELLED')),
  UNIQUE (school_id, media_id)
);

-- Verrou de la ligne média pour le dépôt : le rôle applicatif n'a aucun privilège UPDATE sur la table, donc le
-- verrou passe par cette fonction SECURITY DEFINER, bornée aux lignes du déposant (aucune révélation étrangère).
CREATE FUNCTION drivy.messaging_lock_media(p_school uuid, p_media uuid)
RETURNS TABLE(sha256 text, byte_size bigint, message_id uuid, conversation_id uuid, purged boolean)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT md.ciphertext_sha256,md.byte_size,md.message_id,md.conversation_id,(md.ciphertext IS NULL)
  FROM drivy.messaging_media md
  WHERE md.school_id=p_school AND md.id=p_media
    AND md.uploader_person_id=nullif(current_setting('app.person_id',true),'')::uuid
  FOR UPDATE
$$;

-- Attache : verrouille la ligne média, vérifie déposant, conversation, état UPLOADED, octets et taille déclarée.
-- Ordre de verrouillage : conversation (tenue par l'appelant) → message (inséré) → média.
CREATE FUNCTION drivy.messaging_attach_media(p_school uuid, p_conversation uuid, p_media uuid, p_message uuid, p_size bigint)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; row record;
BEGIN
  IF p_school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN
    RAISE EXCEPTION 'denied' USING ERRCODE='DV403';
  END IF;
  IF p_size IS NULL OR p_size < 1 OR p_size > 4194304 THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
  SELECT md.uploader_person_id,md.conversation_id,md.message_id,md.byte_size,(md.ciphertext IS NULL) AS purged
    INTO row FROM drivy.messaging_media md
    WHERE md.school_id=p_school AND md.id=p_media FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01'; END IF;
  -- Un média d'une autre conversation, d'un autre déposant ou purgé est indistinguable d'un identifiant inconnu.
  IF row.conversation_id IS DISTINCT FROM p_conversation OR row.uploader_person_id IS DISTINCT FROM actor THEN
    RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01';
  END IF;
  IF row.purged THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01'; END IF;
  IF row.message_id IS NOT NULL THEN
    IF row.message_id = p_message THEN RETURN; END IF;
    RAISE EXCEPTION 'media_attached' USING ERRCODE='DVM03';
  END IF;
  IF row.byte_size <> p_size THEN RAISE EXCEPTION 'media_size' USING ERRCODE='DVM04'; END IF;
  -- Le message porteur doit exister dans la même conversation et avoir été écrit par le déposant.
  IF NOT EXISTS(SELECT 1 FROM drivy.messaging_message m WHERE m.school_id=p_school AND m.conversation_id=p_conversation
      AND m.id=p_message AND m.sender_person_id=actor) THEN
    RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01';
  END IF;
  UPDATE drivy.messaging_media SET message_id=p_message, attached_at=now() WHERE school_id=p_school AND id=p_media;
END $$;

-- Purge : transition terminale vers PURGED, journalisée avec un numéro de séquence ; idempotente sur une marque de suppression.
-- L'annulation (CANCELLED) n'accepte que le déposant ; la suppression du message (MESSAGE_DELETED) relit les droits
-- de suppression du message. La purge des orphelins est réservée à la fonction de maintenance, jamais à drivy_app.
CREATE FUNCTION drivy.messaging_purge_media(p_school uuid, p_media uuid, p_reason text)
RETURNS void LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := nullif(current_setting('app.person_id',true),'')::uuid; row record; sender uuid; kind text;
BEGIN
  IF p_school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid THEN
    RAISE EXCEPTION 'denied' USING ERRCODE='DV403';
  END IF;
  IF p_reason NOT IN ('CANCELLED','MESSAGE_DELETED') THEN RAISE EXCEPTION 'denied' USING ERRCODE='DV403'; END IF;
  SELECT md.uploader_person_id,md.conversation_id,md.message_id,(md.ciphertext IS NULL) AS purged INTO row
    FROM drivy.messaging_media md WHERE md.school_id=p_school AND md.id=p_media FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01'; END IF;
  IF p_reason='CANCELLED' THEN
    IF row.uploader_person_id IS DISTINCT FROM actor THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01'; END IF;
    IF row.purged THEN RETURN; END IF;
    IF row.message_id IS NOT NULL THEN RAISE EXCEPTION 'media_attached' USING ERRCODE='DVM03'; END IF;
    IF NOT drivy.messaging_can_write(p_school,actor,row.conversation_id) THEN
      RAISE EXCEPTION 'denied' USING ERRCODE='DV403';
    END IF;
  ELSE
    IF row.message_id IS NULL THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01'; END IF;
    SELECT m.sender_person_id,c.kind INTO sender,kind FROM drivy.messaging_message m
      JOIN drivy.messaging_conversation c ON c.school_id=m.school_id AND c.id=m.conversation_id
      WHERE m.school_id=p_school AND m.conversation_id=row.conversation_id AND m.id=row.message_id;
    IF sender IS NULL THEN RAISE EXCEPTION 'media_not_found' USING ERRCODE='DVM01'; END IF;
    IF NOT drivy.messaging_can_write(p_school,actor,row.conversation_id)
      OR NOT (sender=actor OR (kind='GENERAL' AND drivy.messaging_is_group_admin(p_school,actor))) THEN
      RAISE EXCEPTION 'denied' USING ERRCODE='DV403';
    END IF;
    IF row.purged THEN RETURN; END IF;
  END IF;
  UPDATE drivy.messaging_media SET ciphertext=NULL,purged_at=now(),purge_reason=p_reason
    WHERE school_id=p_school AND id=p_media;
  INSERT INTO drivy.messaging_media_purge(school_id,media_id,reason) VALUES(p_school,p_media,p_reason)
    ON CONFLICT(school_id,media_id) DO NOTHING;
END $$;

-- Maintenance manuelle : purge les dépôts orphelins antérieurs au cutoff, sans planification par défaut.
-- Ne prend que le verrou des lignes média ; une attache concurrente qui a gagné laisse la ligne ATTACHED et l'exclut.
CREATE FUNCTION drivy.messaging_purge_orphan_media(p_cutoff timestamptz) RETURNS integer
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE purged_count integer;
BEGIN
  IF p_cutoff IS NULL THEN RAISE EXCEPTION 'invalid' USING ERRCODE='22023'; END IF;
  WITH purged AS (
    UPDATE drivy.messaging_media SET ciphertext=NULL,purged_at=now(),purge_reason='ORPHAN'
      WHERE message_id IS NULL AND ciphertext IS NOT NULL AND created_at < p_cutoff
      RETURNING school_id,id
  ), journal AS (
    INSERT INTO drivy.messaging_media_purge(school_id,media_id,reason)
      SELECT school_id,id,'ORPHAN' FROM purged ON CONFLICT(school_id,media_id) DO NOTHING RETURNING 1
  )
  SELECT count(*)::integer INTO purged_count FROM purged;
  RETURN purged_count;
END $$;

-- La suppression pour tout le monde efface l'enveloppe et les octets du média dans la même transaction.
CREATE OR REPLACE FUNCTION drivy.messaging_delete_for_everyone(school uuid, target uuid, message uuid) RETURNS void
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
 -- Verrou du message tenu : le média passe ensuite à PURGED, sans octets servis après cette transaction.
 PERFORM drivy.messaging_purge_media(school,md.id,'MESSAGE_DELETED')
   FROM drivy.messaging_media md WHERE md.school_id=school AND md.message_id=message;
END $$;

-- Privilèges : les fonctions SECURITY DEFINER sont le seul chemin d'écriture ; la purge des orphelins reste
-- réservée au rôle propriétaire (script de maintenance), jamais au rôle applicatif.
REVOKE ALL ON FUNCTION drivy.messaging_attach_media(uuid,uuid,uuid,uuid,bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION drivy.messaging_lock_media(uuid,uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION drivy.messaging_purge_media(uuid,uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION drivy.messaging_purge_orphan_media(timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION drivy.messaging_delete_for_everyone(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_attach_media(uuid,uuid,uuid,uuid,bigint) TO drivy_app;
GRANT EXECUTE ON FUNCTION drivy.messaging_lock_media(uuid,uuid) TO drivy_app;
GRANT EXECUTE ON FUNCTION drivy.messaging_purge_media(uuid,uuid,text) TO drivy_app;
GRANT EXECUTE ON FUNCTION drivy.messaging_delete_for_everyone(uuid,uuid,uuid) TO drivy_app;

-- RLS forcée, propriétaire explicitement autorisé comme les autres tables de messagerie.
ALTER TABLE drivy.messaging_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.messaging_media FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.messaging_media_purge ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.messaging_media_purge FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  EXECUTE format('CREATE POLICY messaging_owner_media ON drivy.messaging_media FOR ALL TO %I USING(true) WITH CHECK(true)',current_user);
  EXECUTE format('CREATE POLICY messaging_owner_media_purge ON drivy.messaging_media_purge FOR ALL TO %I USING(true) WITH CHECK(true)',current_user);
END $$;
-- Lecture : ses propres dépôts tant que le lien est ouvert, ou un média rattaché dans la plage lisible.
-- La suppression du message n'est pas filtrée ici : la projection du message garde la marque de suppression
-- (identifiant et taille), tandis que la route de téléchargement exige elle-même un message non supprimé et des octets.
CREATE POLICY messaging_media_read ON drivy.messaging_media FOR SELECT TO drivy_app
 USING((message_id IS NULL
     AND uploader_person_id=nullif(current_setting('app.person_id',true),'')::uuid
     AND drivy.messaging_can_write(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id))
   OR (message_id IS NOT NULL
     AND drivy.messaging_message_readable(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id,message_id)));
-- Dépôt direct : déposant = acteur, lien ouvert, jamais un média déjà rattaché. Aucun UPDATE ni DELETE accordé.
CREATE POLICY messaging_media_insert ON drivy.messaging_media FOR INSERT TO drivy_app
 WITH CHECK(uploader_person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND message_id IS NULL AND ciphertext IS NOT NULL
   AND drivy.messaging_can_write(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id));

GRANT SELECT,INSERT ON drivy.messaging_media TO drivy_app;
