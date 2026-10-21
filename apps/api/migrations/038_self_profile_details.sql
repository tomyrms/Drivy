-- Profil personnel complet (21 octobre 2026, issue #64, suite de 037) : prénom, nom, téléphone et photo de la personne connectée.
-- Ces informations appartiennent au compte Drivy, pas à un dossier d'école ; le dossier d'élève garde ses propres champs.
-- La photo est chiffrée (AES-256-GCM, même clé que les trajets) et nettoyée par l'API avant écriture : JPEG seulement, métadonnées retirées.
ALTER TABLE drivy.person ADD COLUMN first_name text CHECK(first_name IS NULL OR char_length(first_name) BETWEEN 1 AND 150);
ALTER TABLE drivy.person ADD COLUMN last_name text CHECK(last_name IS NULL OR char_length(last_name) BETWEEN 1 AND 150);
ALTER TABLE drivy.person ADD COLUMN contact_phone text CHECK(contact_phone IS NULL OR char_length(contact_phone) BETWEEN 1 AND 32);
ALTER TABLE drivy.person ADD COLUMN photo_version integer NOT NULL DEFAULT 0 CHECK(photo_version>=0);
GRANT UPDATE(first_name,last_name,contact_phone,photo_version) ON drivy.person TO drivy_app;

CREATE TABLE drivy.person_photo (
  person_id uuid PRIMARY KEY REFERENCES drivy.person(id),
  photo_version integer NOT NULL CHECK(photo_version>0),
  key_id text NOT NULL CHECK(char_length(key_id) BETWEEN 1 AND 100),
  encrypted_image bytea NOT NULL CHECK(octet_length(encrypted_image) BETWEEN 29 AND 300000),
  byte_size integer NOT NULL CHECK(byte_size BETWEEN 1 AND 262144),
  width integer NOT NULL CHECK(width BETWEEN 64 AND 1024),
  height integer NOT NULL CHECK(height BETWEEN 64 AND 1024),
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE drivy.person_photo ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.person_photo FORCE ROW LEVEL SECURITY;

-- Lecture : la personne elle-même, ou un membre actif d'une école où cette personne a aussi une adhésion active.
CREATE FUNCTION drivy.person_photo_visible(target uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT target=nullif(current_setting('app.person_id',true),'')::uuid OR EXISTS(
  SELECT 1 FROM drivy.membership viewer JOIN drivy.membership owner ON owner.school_id=viewer.school_id
  WHERE viewer.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND viewer.status='ACTIVE'
    AND owner.person_id=target AND owner.status='ACTIVE')
$$;
REVOKE ALL ON FUNCTION drivy.person_photo_visible(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.person_photo_visible(uuid) TO drivy_app;

CREATE POLICY person_photo_read ON drivy.person_photo FOR SELECT TO drivy_app USING(drivy.person_photo_visible(person_id));
-- Écriture : uniquement sa propre photo, depuis la route du profil personnel (app.self_profile, comme 037).
CREATE POLICY person_photo_insert ON drivy.person_photo FOR INSERT TO drivy_app WITH CHECK(
 person_id=nullif(current_setting('app.person_id',true),'')::uuid AND current_setting('app.self_profile',true)='true');
CREATE POLICY person_photo_update ON drivy.person_photo FOR UPDATE TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND current_setting('app.self_profile',true)='true')
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND current_setting('app.self_profile',true)='true');
CREATE POLICY person_photo_delete ON drivy.person_photo FOR DELETE TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid AND current_setting('app.self_profile',true)='true');
GRANT SELECT,INSERT,UPDATE,DELETE ON drivy.person_photo TO drivy_app;
