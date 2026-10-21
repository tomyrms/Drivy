-- Le compte se modifie uniquement par une fonction bornée : le rôle API
-- n'obtient PAS UPDATE(version), ce qui protège les autres écritures et les tests RLS.
-- La fonction s'exécute sous l'identité du propriétaire des migrations, avec
-- vérification explicite des trois preuves issues du jeton OIDC et du lien serveur.
CREATE FUNCTION drivy.update_personal_display_name(target_person uuid, expected_version integer, new_display_name text)
RETURNS TABLE("personId" uuid, "version" integer, "displayName" text, "locale" text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF target_person IS DISTINCT FROM nullif(current_setting('app.person_id', true), '')::uuid
     OR NOT EXISTS(
        SELECT 1 FROM drivy.identity_link l
        WHERE l.person_id=target_person
          AND l.issuer=current_setting('app.issuer',true)
          AND l.subject=current_setting('app.subject',true)
     )
  THEN RAISE EXCEPTION 'personal_account_forbidden' USING ERRCODE='42501'; END IF;
  IF new_display_name IS NULL OR length(new_display_name) NOT BETWEEN 1 AND 200
     OR new_display_name ~ '[[:cntrl:]]'
  THEN RAISE EXCEPTION 'personal_account_name_invalid' USING ERRCODE='22023'; END IF;

  RETURN QUERY UPDATE drivy.person p
    SET display_name=new_display_name, version=p.version+1
    WHERE p.id=target_person AND p.version=expected_version AND p.status='ACTIVE'
    RETURNING p.id,p.version,p.display_name,p.locale;
END $$;
REVOKE ALL ON FUNCTION drivy.update_personal_display_name(uuid,integer,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.update_personal_display_name(uuid,integer,text) TO drivy_app;

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
