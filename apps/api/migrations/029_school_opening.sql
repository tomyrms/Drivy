-- Un droit d'ouverture n'est ni une invitation scolaire, ni une autorisation issue d'un rôle ADMIN.
CREATE TABLE drivy.school_opening_link (
  id uuid PRIMARY KEY,
  token_hash text NOT NULL UNIQUE CHECK(token_hash ~ '^[a-f0-9]{64}$'),
  reserved_school_id uuid NOT NULL UNIQUE,
  reserved_membership_id uuid NOT NULL UNIQUE,
  created_by_issuer text NOT NULL,
  created_by_subject text NOT NULL,
  create_operation_id uuid NOT NULL,
  create_hash text NOT NULL CHECK(create_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'AVAILABLE' CHECK(status IN('AVAILABLE','USED','REVOKED')),
  revoked_at timestamptz,
  revoke_operation_id uuid,
  revoked_by_issuer text,
  revoked_by_subject text,
  used_at timestamptz,
  used_by_issuer text,
  used_by_subject text,
  used_by_person_id uuid REFERENCES drivy.person(id),
  consume_operation_id uuid,
  consume_hash text CHECK(consume_hash ~ '^[a-f0-9]{64}$'),
  UNIQUE(created_by_issuer,created_by_subject,create_operation_id),
  UNIQUE(used_by_issuer,used_by_subject,consume_operation_id),
  CHECK(expires_at>created_at),
  CHECK((status='USED')=(used_at IS NOT NULL AND used_by_issuer IS NOT NULL AND used_by_subject IS NOT NULL
    AND used_by_person_id IS NOT NULL AND consume_operation_id IS NOT NULL AND consume_hash IS NOT NULL)),
  CHECK((status='REVOKED')=(revoked_at IS NOT NULL AND revoke_operation_id IS NOT NULL AND revoked_by_issuer IS NOT NULL AND revoked_by_subject IS NOT NULL))
);
CREATE INDEX school_opening_created ON drivy.school_opening_link(created_at DESC,id);
ALTER TABLE drivy.school_opening_link ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.school_opening_link FORCE ROW LEVEL SECURITY;
-- Le service vérifie l'identité OIDC contre la liste d'exploitation avant de poser ce contexte transactionnel.
CREATE POLICY opening_operator_read ON drivy.school_opening_link FOR SELECT TO drivy_app
  USING(current_setting('app.school_opening_operator',true)='true');
CREATE POLICY opening_operator_insert ON drivy.school_opening_link FOR INSERT TO drivy_app WITH CHECK(
  current_setting('app.school_opening_operator',true)='true' AND status='AVAILABLE'
  AND created_by_issuer=current_setting('app.issuer',true) AND created_by_subject=current_setting('app.subject',true));
CREATE POLICY opening_operator_revoke ON drivy.school_opening_link FOR UPDATE TO drivy_app
  USING(current_setting('app.school_opening_operator',true)='true' AND status IN('AVAILABLE','REVOKED'))
  WITH CHECK(current_setting('app.school_opening_operator',true)='true' AND status='REVOKED'
    AND revoked_by_issuer=current_setting('app.issuer',true) AND revoked_by_subject=current_setting('app.subject',true));
CREATE POLICY opening_target_read ON drivy.school_opening_link FOR SELECT TO drivy_app USING(
  token_hash=current_setting('app.school_opening_hash',true)
  OR (used_by_issuer=current_setting('app.issuer',true) AND used_by_subject=current_setting('app.subject',true)));
CREATE POLICY opening_target_consume ON drivy.school_opening_link FOR UPDATE TO drivy_app
  USING(token_hash=current_setting('app.school_opening_hash',true))
  WITH CHECK(token_hash=current_setting('app.school_opening_hash',true) AND status='USED' AND expires_at>now()
    AND used_by_issuer=current_setting('app.issuer',true) AND used_by_subject=current_setting('app.subject',true)
    AND used_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
GRANT SELECT,INSERT ON drivy.school_opening_link TO drivy_app;
GRANT UPDATE(status,revoked_at,revoke_operation_id,revoked_by_issuer,revoked_by_subject,used_at,used_by_issuer,used_by_subject,used_by_person_id,consume_operation_id,consume_hash)
  ON drivy.school_opening_link TO drivy_app;
-- Un lien réserve les identifiants : il ne permet jamais d'insérer deux écoles ou plusieurs premiers membres.
CREATE POLICY opening_school_insert ON drivy.school FOR INSERT TO drivy_app WITH CHECK(
  status='DRAFT' AND version=1 AND configuration_version=1
  AND modules='{"gpsEnabled":false,"packsEnabled":false,"collectiveCoursesEnabled":false,"courseOffersVisibleByDefault":false}'::jsonb
  AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.token_hash=current_setting('app.school_opening_hash',true)
    AND l.status='AVAILABLE' AND l.expires_at>now() AND l.reserved_school_id=school.id));
GRANT INSERT ON drivy.school TO drivy_app;
CREATE POLICY opening_person_insert ON drivy.person FOR INSERT TO drivy_app WITH CHECK(
  id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE' AND version=1
  AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.token_hash=current_setting('app.school_opening_hash',true)
    AND l.status='AVAILABLE' AND l.expires_at>now()));
CREATE POLICY opening_identity_insert ON drivy.identity_link FOR INSERT TO drivy_app WITH CHECK(
  issuer=current_setting('app.issuer',true) AND subject=current_setting('app.subject',true)
  AND person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.token_hash=current_setting('app.school_opening_hash',true)
    AND l.status='AVAILABLE' AND l.expires_at>now()));
-- Le nom explicitement confirmé concerne uniquement la personne du compte, sans modifier ses autres droits.
CREATE POLICY opening_person_update ON drivy.person FOR UPDATE TO drivy_app
  USING(id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE'
    AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.token_hash=current_setting('app.school_opening_hash',true)
      AND l.status='AVAILABLE' AND l.expires_at>now()))
  WITH CHECK(id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE'
    AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.token_hash=current_setting('app.school_opening_hash',true)
      AND l.status='AVAILABLE' AND l.expires_at>now()));
GRANT UPDATE(display_name) ON drivy.person TO drivy_app;
CREATE POLICY opening_membership_insert ON drivy.membership FOR INSERT TO drivy_app WITH CHECK(
  person_id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE' AND version=1 AND access_epoch=1
  AND (roles=ARRAY['ADMIN']::text[] OR roles=ARRAY['ADMIN','INSTRUCTOR']::text[]) AND grants=ARRAY['CONFIGURE_CATALOG']::text[]
  AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.token_hash=current_setting('app.school_opening_hash',true)
    AND l.status='AVAILABLE' AND l.expires_at>now() AND l.reserved_school_id=membership.school_id AND l.reserved_membership_id=membership.id));

-- Les états terminaux sont immuables, même si un SELECT FOR UPDATE doit pouvoir les verrouiller pour un rejeu.
CREATE FUNCTION drivy.school_opening_terminal() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF OLD.status<>'AVAILABLE' THEN RAISE EXCEPTION 'opening_link_terminal' USING ERRCODE='23514'; END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.school_opening_terminal() FROM PUBLIC;
CREATE TRIGGER school_opening_terminal BEFORE UPDATE ON drivy.school_opening_link
  FOR EACH ROW EXECUTE FUNCTION drivy.school_opening_terminal();
