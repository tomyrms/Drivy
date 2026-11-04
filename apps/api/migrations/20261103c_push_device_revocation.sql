-- #120/#74 : révocation d'un appareil push sans jeton d'accès.
-- À l'enregistrement, le serveur rend une fois un secret propre à l'appareil ; seule son empreinte SHA-256 est stockée.
-- Une route anonyme compare cette empreinte en temps constant et révoque cette seule ligne, même quand la session iOS
-- s'est terminée sans déconnexion explicite (restauration échouée, renouvellement refusé, Trousseau en échec).
-- Migration additive : aucune migration existante modifiée, aucune donnée relue.
-- Décisions et justification de l'empreinte simple : docs/implementation/messaging-notifications-74.md (§ Révocation sans jeton).

-- Empreinte de 32 octets, jamais le secret. Nulle pour les appareils enregistrés avant cette migration : la révocation
-- anonyme reste alors impossible, seule la route authentifiée agit (aucun repli vers un secret absent).
ALTER TABLE drivy.push_device ADD COLUMN revocation_digest bytea
 CHECK(revocation_digest IS NULL OR octet_length(revocation_digest)=32);

-- Enregistrement avec le secret : un nouvel enregistrement du même jeton — y compris repris par un autre compte — remplace
-- l'empreinte, donc l'ancien secret ne révoque plus rien.
CREATE FUNCTION drivy.push_device_claim_secret(person uuid,device_token text,device_environment text,device_digest bytea)
 RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 INSERT INTO drivy.push_device(person_id,platform,environment,token,revocation_digest) SELECT person,'IOS',device_environment,device_token,device_digest
  WHERE person=nullif(current_setting('app.person_id',true),'')::uuid
 ON CONFLICT(token) DO UPDATE SET person_id=EXCLUDED.person_id,environment=EXCLUDED.environment,revoked_at=NULL,last_seen_at=now(),
  revocation_digest=EXCLUDED.revocation_digest
$$;
REVOKE ALL ON FUNCTION drivy.push_device_claim_secret(uuid,text,text,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_device_claim_secret(uuid,text,text,bytea) TO drivy_app;
-- L'ancien enregistrement sans secret efface l'empreinte : il ne laisse jamais un secret antérieur survivre à une reprise.
CREATE OR REPLACE FUNCTION drivy.push_device_claim(person uuid,device_token text,device_environment text) RETURNS void
 LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.push_device_claim_secret(person,device_token,device_environment,NULL)
$$;

-- Révocation par possession du secret, sans identité : la seule autorité est la correspondance de l'empreinte.
-- Comparaison XOR octet par octet sur une longueur fixe (32 octets), sans sortie anticipée sur le contenu ; un jeton
-- inconnu, sans empreinte ou d'une autre longueur ne correspond jamais. Aucun paramètre de session n'est lu : la fonction
-- est SECURITY DEFINER et n'agit que sur revoked_at, jamais sur person_id, le jeton ni l'empreinte.
CREATE FUNCTION drivy.push_device_revoke_anonymous(device_token text,presented_digest bytea) RETURNS boolean
 LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE stored bytea; diff integer:=0; i integer;
BEGIN
 SELECT d.revocation_digest INTO stored FROM drivy.push_device d WHERE d.token=device_token FOR UPDATE;
 IF NOT FOUND OR stored IS NULL OR octet_length(stored)<>octet_length(presented_digest) THEN RETURN false; END IF;
 FOR i IN 0..octet_length(stored)-1 LOOP
  diff:=diff | (get_byte(stored,i) # get_byte(presented_digest,i));
 END LOOP;
 IF diff<>0 THEN RETURN false; END IF;
 UPDATE drivy.push_device SET revoked_at=now() WHERE token=device_token AND revoked_at IS NULL;
 RETURN true;
END $$;
REVOKE ALL ON FUNCTION drivy.push_device_revoke_anonymous(text,bytea) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.push_device_revoke_anonymous(text,bytea) TO drivy_app;
