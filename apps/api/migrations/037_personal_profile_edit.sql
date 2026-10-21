-- #64 : données globales du compte, indépendantes des dossiers scolaires et de l'OIDC.
-- Seul le titulaire du jeton lié peut modifier le nom public ; les rôles et l'identité de connexion restent intacts.
CREATE POLICY personal_profile_self_update ON drivy.person FOR UPDATE TO drivy_app
  USING (id = nullif(current_setting('app.person_id', true), '')::uuid AND status = 'ACTIVE')
  WITH CHECK (id = nullif(current_setting('app.person_id', true), '')::uuid AND status = 'ACTIVE');
GRANT UPDATE(display_name, version) ON drivy.person TO drivy_app;

-- Le reçu durable rend un retry réseau sûr, même si la réponse d'origine s'est perdue.
CREATE TABLE drivy.personal_profile_operation (
  person_id uuid NOT NULL REFERENCES drivy.person(id),
  operation_id uuid NOT NULL,
  payload_hash text NOT NULL CHECK(length(payload_hash) = 64),
  response_version integer NOT NULL CHECK(response_version > 0),
  response_display_name text NOT NULL,
  response_locale text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(person_id, operation_id)
);
ALTER TABLE drivy.personal_profile_operation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.personal_profile_operation FORCE ROW LEVEL SECURITY;
CREATE POLICY personal_profile_operation_self_read ON drivy.personal_profile_operation FOR SELECT TO drivy_app
  USING (person_id = nullif(current_setting('app.person_id', true), '')::uuid);
CREATE POLICY personal_profile_operation_self_insert ON drivy.personal_profile_operation FOR INSERT TO drivy_app
  WITH CHECK (person_id = nullif(current_setting('app.person_id', true), '')::uuid);
GRANT SELECT, INSERT ON drivy.personal_profile_operation TO drivy_app;
