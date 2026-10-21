-- #64 : modification du compte global depuis l'app, sans toucher aux dossiers des écoles.
-- Conserver les GRANT existants (notamment UPDATE(version) pour les verrous métiers) :
-- la RLS n'autorise une mutation que sous la portée validée d'une commande PATCH /v1/me.
-- Le contexte est créé par l'API uniquement après validation du jeton et de la version.
CREATE POLICY personal_profile_self_update ON drivy.person FOR UPDATE TO drivy_app
  USING(
    id = nullif(current_setting('app.person_id', true), '')::uuid
    AND status = 'ACTIVE'
    AND current_setting('app.personal_profile_command', true) = 'authorized'
  )
  WITH CHECK(
    id = nullif(current_setting('app.person_id', true), '')::uuid
    AND status = 'ACTIVE'
    AND current_setting('app.personal_profile_command', true) = 'authorized'
  );

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
