-- #440 : preuve durable de consommation d'une clé à usage unique.
-- Avant : la réclamation SUPPRIMAIT la ligne ; un renvoi identique du lot (réponse perdue, redémarrage du client)
-- réinsérait la clé, qui pouvait alors être distribuée une seconde fois. Désormais la ligne reste, marquée consommée,
-- avec la seule empreinte SHA-256 du contenu (la clé publique elle-même est effacée). Aucune table nouvelle.
--
-- Transition : les clés déjà consommées avant cette migration ont été supprimées sans trace ; aucune empreinte
-- ne peut en être inventée. Seules les clés présentes reçoivent une empreinte.
--
-- Retour arrière (API arrêtée) : voir docs/implementation/audit-messagerie-serveur-20261110.md. Rétablir la suppression
-- ressuscite le risque #440.
ALTER TABLE drivy.messaging_one_time_key
  ADD COLUMN consumed_at timestamptz,
  ADD COLUMN key_digest bytea;
-- Rattrapage sous la politique propriétaire (RLS forcée) : empreinte du texte jsonb normalisé, en UTF-8.
UPDATE drivy.messaging_one_time_key SET key_digest=sha256(convert_to(key::text,'UTF8'));
ALTER TABLE drivy.messaging_one_time_key
  ALTER COLUMN key_digest SET NOT NULL,
  ADD CONSTRAINT messaging_otk_digest_size CHECK(octet_length(key_digest)=32),
  ADD CONSTRAINT messaging_otk_consumed_wiped CHECK(consumed_at IS NULL OR key='""'::jsonb);
CREATE INDEX messaging_one_time_key_available ON drivy.messaging_one_time_key(school_id,person_id,device_id,algorithm,key_id)
  WHERE consumed_at IS NULL;
-- Un pair ne lit que les clés encore disponibles.
DROP POLICY messaging_otk_peer_read ON drivy.messaging_one_time_key;
CREATE POLICY messaging_otk_peer_read ON drivy.messaging_one_time_key FOR SELECT TO drivy_app
  USING(consumed_at IS NULL AND drivy.messaging_key_peer(school_id,person_id));

CREATE OR REPLACE FUNCTION drivy.messaging_claim_one_time_key(school uuid, target uuid, device text, algo text)
RETURNS TABLE(key_id text, key jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 WITH picked AS (
   SELECT o.school_id,o.person_id,o.device_id,o.key_id,o.key AS public_key
   FROM drivy.messaging_one_time_key o JOIN drivy.messaging_device d
     ON d.school_id=o.school_id AND d.person_id=o.person_id AND d.device_id=o.device_id AND d.revoked_at IS NULL
   WHERE drivy.messaging_key_peer(school,target)
     AND o.school_id=school AND o.person_id=target AND o.device_id=device AND o.algorithm=algo AND o.consumed_at IS NULL
   ORDER BY o.key_id LIMIT 1 FOR UPDATE OF o SKIP LOCKED)
 UPDATE drivy.messaging_one_time_key k SET consumed_at=now(), key='""'::jsonb
 FROM picked p
 WHERE (k.school_id,k.person_id,k.device_id,k.key_id)=(p.school_id,p.person_id,p.device_id,p.key_id)
 RETURNING k.key_id,p.public_key
$$;
