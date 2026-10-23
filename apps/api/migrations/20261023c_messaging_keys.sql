-- Relais de clés Matrix (Olm/Megolm) sans homeserver. Le serveur ne stocke que des objets JSON publics ou chiffrés
-- produits par matrix-sdk-crypto : clés publiques d'appareil, clés à usage unique, messages to-device chiffrés,
-- sauvegarde chiffrée. Aucune clé privée, aucun texte.
CREATE TABLE drivy.messaging_device (
  school_id uuid NOT NULL REFERENCES drivy.school(id), person_id uuid NOT NULL REFERENCES drivy.person(id),
  device_id text NOT NULL CHECK(device_id ~ '^[A-Z0-9]{10,32}$'),
  device_keys jsonb CHECK(device_keys IS NULL OR (jsonb_typeof(device_keys)='object' AND octet_length(device_keys::text)<=8192)),
  -- Personnes dont cet appareil suit les appareils au dernier sync, pour calculer device_lists.left.
  tracked_person_ids uuid[] NOT NULL DEFAULT '{}'::uuid[] CHECK(cardinality(tracked_person_ids)<=10000),
  created_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz,
  PRIMARY KEY(school_id,person_id,device_id)
);
CREATE TABLE drivy.messaging_one_time_key (
  school_id uuid NOT NULL, person_id uuid NOT NULL, device_id text NOT NULL,
  key_id text NOT NULL CHECK(key_id ~ '^[A-Za-z0-9_.-]{1,64}:[A-Za-z0-9+/=_-]{1,64}$'),
  algorithm text GENERATED ALWAYS AS (split_part(key_id,':',1)) STORED,
  key jsonb NOT NULL CHECK(jsonb_typeof(key) IN('object','string') AND octet_length(key::text)<=2048),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,person_id,device_id,key_id),
  FOREIGN KEY(school_id,person_id,device_id) REFERENCES drivy.messaging_device(school_id,person_id,device_id) ON DELETE CASCADE
);
CREATE INDEX messaging_one_time_key_claim ON drivy.messaging_one_time_key(school_id,person_id,device_id,algorithm,key_id);
CREATE TABLE drivy.messaging_fallback_key (
  school_id uuid NOT NULL, person_id uuid NOT NULL, device_id text NOT NULL,
  algorithm text NOT NULL CHECK(algorithm ~ '^[A-Za-z0-9_.-]{1,64}$'),
  key_id text NOT NULL CHECK(key_id ~ '^[A-Za-z0-9_.-]{1,64}:[A-Za-z0-9+/=_-]{1,64}$'),
  key jsonb NOT NULL CHECK(jsonb_typeof(key)='object' AND octet_length(key::text)<=2048),
  used boolean NOT NULL DEFAULT false, updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,person_id,device_id,algorithm),
  FOREIGN KEY(school_id,person_id,device_id) REFERENCES drivy.messaging_device(school_id,person_id,device_id) ON DELETE CASCADE
);
CREATE TABLE drivy.messaging_cross_signing (
  school_id uuid NOT NULL REFERENCES drivy.school(id), person_id uuid NOT NULL REFERENCES drivy.person(id),
  key_usage text NOT NULL CHECK(key_usage IN('master','self_signing','user_signing')),
  key jsonb NOT NULL CHECK(jsonb_typeof(key)='object' AND octet_length(key::text)<=8192),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,person_id,key_usage)
);
CREATE TABLE drivy.messaging_device_list_change (
  id bigserial PRIMARY KEY, school_id uuid NOT NULL REFERENCES drivy.school(id),
  person_id uuid NOT NULL REFERENCES drivy.person(id), created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX messaging_device_list_change_scan ON drivy.messaging_device_list_change(school_id,id);
CREATE TABLE drivy.messaging_to_device (
  id bigserial PRIMARY KEY, school_id uuid NOT NULL,
  recipient_person_id uuid NOT NULL, recipient_device_id text NOT NULL,
  sender_person_id uuid NOT NULL REFERENCES drivy.person(id), sender_device_id text NOT NULL,
  event_type text NOT NULL CHECK(event_type ~ '^[A-Za-z0-9._-]{1,64}$'),
  content jsonb NOT NULL CHECK(jsonb_typeof(content)='object' AND octet_length(content::text)<=16384),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(school_id,recipient_person_id,recipient_device_id) REFERENCES drivy.messaging_device(school_id,person_id,device_id) ON DELETE CASCADE
);
CREATE INDEX messaging_to_device_queue ON drivy.messaging_to_device(school_id,recipient_person_id,recipient_device_id,id);
CREATE TABLE drivy.messaging_to_device_txn (
  school_id uuid NOT NULL, person_id uuid NOT NULL, device_id text NOT NULL,
  txn_id text NOT NULL CHECK(txn_id ~ '^[A-Za-z0-9._~-]{1,64}$'),
  fingerprint text NOT NULL CHECK(fingerprint ~ '^[0-9a-f]{64}$'), created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,person_id,device_id,txn_id),
  FOREIGN KEY(school_id,person_id,device_id) REFERENCES drivy.messaging_device(school_id,person_id,device_id) ON DELETE CASCADE
);
CREATE TABLE drivy.messaging_key_backup (
  school_id uuid NOT NULL REFERENCES drivy.school(id), person_id uuid NOT NULL REFERENCES drivy.person(id),
  version bigint NOT NULL CHECK(version>0),
  algorithm text NOT NULL CHECK(algorithm ~ '^[A-Za-z0-9._-]{1,128}$'),
  auth_data jsonb NOT NULL CHECK(jsonb_typeof(auth_data)='object' AND octet_length(auth_data::text)<=4096),
  etag bigint NOT NULL DEFAULT 0 CHECK(etag>=0), current boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,person_id,version)
);
CREATE UNIQUE INDEX messaging_key_backup_current ON drivy.messaging_key_backup(school_id,person_id) WHERE current;
CREATE TABLE drivy.messaging_key_backup_session (
  school_id uuid NOT NULL, person_id uuid NOT NULL, version bigint NOT NULL,
  room_id text NOT NULL CHECK(room_id ~ '^![0-9a-f-]{36}:drivy$'),
  session_id text NOT NULL CHECK(session_id ~ '^[A-Za-z0-9+/=_-]{1,128}$'),
  data jsonb NOT NULL CHECK(jsonb_typeof(data)='object' AND octet_length(data::text)<=8192),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,person_id,version,room_id,session_id),
  FOREIGN KEY(school_id,person_id,version) REFERENCES drivy.messaging_key_backup(school_id,person_id,version) ON DELETE CASCADE
);

-- Personnes dont l'acteur courant peut lire les clés : lui-même, ses contacts privés autorisés,
-- et les membres actifs de l'école si la conversation Général existe. Acteur et école relus du contexte.
CREATE FUNCTION drivy.messaging_key_peer(school uuid, target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT school=nullif(current_setting('app.school_id',true),'')::uuid
  AND drivy.messaging_member(school,nullif(current_setting('app.person_id',true),'')::uuid)
  AND drivy.messaging_member(school,target)
  AND (target=nullif(current_setting('app.person_id',true),'')::uuid
    OR drivy.messaging_private_allowed(school,nullif(current_setting('app.person_id',true),'')::uuid,target)
    OR (EXISTS(SELECT 1 FROM drivy.messaging_conversation c WHERE c.school_id=school AND c.kind='GENERAL')
      AND drivy.messaging_general_participant(school,nullif(current_setting('app.person_id',true),'')::uuid)
      AND drivy.messaging_general_participant(school,target)))
$$;
CREATE FUNCTION drivy.messaging_key_peers(school uuid) RETURNS TABLE(person_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.person_id FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE m.school_id=school AND m.status='ACTIVE' AND p.status='ACTIVE' AND drivy.messaging_key_peer(school,m.person_id)
$$;
REVOKE ALL ON FUNCTION drivy.messaging_key_peer(uuid,uuid),drivy.messaging_key_peers(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_key_peer(uuid,uuid),drivy.messaging_key_peers(uuid) TO drivy_app;

DO $$ DECLARE table_name text; BEGIN
 FOREACH table_name IN ARRAY ARRAY['messaging_device','messaging_one_time_key','messaging_fallback_key','messaging_cross_signing',
   'messaging_device_list_change','messaging_to_device','messaging_to_device_txn','messaging_key_backup','messaging_key_backup_session'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',table_name);
  EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',table_name);
 END LOOP;
END $$;
-- Propres lignes : appareil, file to-device, transactions, sauvegarde.
CREATE POLICY messaging_device_own ON drivy.messaging_device FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_device_peer_read ON drivy.messaging_device FOR SELECT TO drivy_app
 USING(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_otk_own ON drivy.messaging_one_time_key FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
-- Claim : lecture et suppression des clés d'un pair autorisé, jamais insertion.
CREATE POLICY messaging_otk_peer_read ON drivy.messaging_one_time_key FOR SELECT TO drivy_app USING(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_otk_peer_claim ON drivy.messaging_one_time_key FOR DELETE TO drivy_app USING(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_fallback_own ON drivy.messaging_fallback_key FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_fallback_peer_read ON drivy.messaging_fallback_key FOR SELECT TO drivy_app USING(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_fallback_peer_use ON drivy.messaging_fallback_key FOR UPDATE TO drivy_app
 USING(drivy.messaging_key_peer(school_id,person_id)) WITH CHECK(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_cross_signing_own ON drivy.messaging_cross_signing FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_cross_signing_peer_read ON drivy.messaging_cross_signing FOR SELECT TO drivy_app USING(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_device_list_read ON drivy.messaging_device_list_change FOR SELECT TO drivy_app USING(drivy.messaging_key_peer(school_id,person_id));
CREATE POLICY messaging_device_list_insert ON drivy.messaging_device_list_change FOR INSERT TO drivy_app
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_to_device_recipient ON drivy.messaging_to_device FOR SELECT TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND recipient_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_to_device_ack ON drivy.messaging_to_device FOR DELETE TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND recipient_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_to_device_send ON drivy.messaging_to_device FOR INSERT TO drivy_app
 WITH CHECK(sender_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_key_peer(school_id,recipient_person_id));
CREATE POLICY messaging_to_device_txn_own ON drivy.messaging_to_device_txn FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_key_backup_own ON drivy.messaging_key_backup FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY messaging_key_backup_session_own ON drivy.messaging_key_backup_session FOR ALL TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(school_id=nullif(current_setting('app.school_id',true),'')::uuid AND person_id=nullif(current_setting('app.person_id',true),'')::uuid);

GRANT SELECT,INSERT ON drivy.messaging_device TO drivy_app;
GRANT UPDATE(device_keys,tracked_person_ids,revoked_at) ON drivy.messaging_device TO drivy_app;
GRANT SELECT,INSERT,DELETE ON drivy.messaging_one_time_key TO drivy_app;
GRANT SELECT,INSERT,DELETE ON drivy.messaging_fallback_key TO drivy_app;
GRANT UPDATE(key_id,key,used,updated_at) ON drivy.messaging_fallback_key TO drivy_app;
GRANT SELECT,INSERT ON drivy.messaging_cross_signing TO drivy_app;
GRANT UPDATE(key,updated_at) ON drivy.messaging_cross_signing TO drivy_app;
GRANT SELECT,INSERT ON drivy.messaging_device_list_change TO drivy_app;
GRANT SELECT,INSERT,DELETE ON drivy.messaging_to_device TO drivy_app;
GRANT SELECT,INSERT,DELETE ON drivy.messaging_to_device_txn TO drivy_app;
GRANT SELECT,INSERT ON drivy.messaging_key_backup TO drivy_app;
GRANT UPDATE(etag,current) ON drivy.messaging_key_backup TO drivy_app;
GRANT SELECT,INSERT ON drivy.messaging_key_backup_session TO drivy_app;
GRANT UPDATE(data,updated_at) ON drivy.messaging_key_backup_session TO drivy_app;
GRANT USAGE ON SEQUENCE drivy.messaging_device_list_change_id_seq,drivy.messaging_to_device_id_seq TO drivy_app;
