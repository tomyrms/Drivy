-- R01-T02 (#454) : fiches des écoles clientes, codes d'ouverture rattachés à une fiche, liaison école -> fiche -> premier ADMIN.
-- Aucune donnée n'est créée ni modifiée par cette migration : les écoles pilotes existantes gardent leurs données et leur accès,
-- et ne reçoivent une fiche que par un rattachement explicite d'un opérateur (ou lorsqu'un de leurs codes encore distribué est utilisé).

CREATE TABLE drivy.platform_client (
  id uuid PRIMARY KEY,
  -- Nom commercial de la fiche, saisi par l'opérateur. Facultatif : une fiche de suivi légère naît avec un seul libellé, voire aucun.
  display_name text CHECK (display_name IS NULL OR length(btrim(display_name)) BETWEEN 1 AND 150),
  -- L'école et son premier ADMIN ne sont reliés qu'une fois, à l'utilisation d'un code ou par un rattachement explicite.
  school_id uuid UNIQUE REFERENCES drivy.school(id),
  link_source text CHECK (link_source IN ('OPENING_CODE','EXISTING_SCHOOL')),
  opened_via_link_id uuid UNIQUE REFERENCES drivy.school_opening_link(id),
  first_admin_membership_id uuid UNIQUE REFERENCES drivy.membership(id),
  school_linked_at timestamptz,
  school_linked_by uuid REFERENCES drivy.platform_operator(id),
  issued_by_operator_id uuid REFERENCES drivy.platform_operator(id),
  contact_name text CHECK (contact_name IS NULL OR length(btrim(contact_name)) BETWEEN 1 AND 200),
  contact_email text CHECK (contact_email IS NULL OR (contact_email = lower(contact_email) AND length(contact_email) BETWEEN 3 AND 254)),
  contact_phone text CHECK (contact_phone IS NULL OR length(btrim(contact_phone)) BETWEEN 1 AND 32),
  billing_street text CHECK (billing_street IS NULL OR length(btrim(billing_street)) BETWEEN 1 AND 200),
  billing_postal_code text CHECK (billing_postal_code IS NULL OR length(btrim(billing_postal_code)) BETWEEN 1 AND 20),
  billing_city text CHECK (billing_city IS NULL OR length(btrim(billing_city)) BETWEEN 1 AND 100),
  billing_country text CHECK (billing_country IS NULL OR length(btrim(billing_country)) BETWEEN 1 AND 100),
  internal_notes text CHECK (internal_notes IS NULL OR length(btrim(internal_notes)) BETWEEN 1 AND 4000),
  -- Emplacement du futur état commercial (offre, essai, impayé, suspension : #455 et #456). Seule valeur admise ici : aucune
  -- restriction ne s'applique tant qu'un opérateur n'a pas configuré explicitement l'offre de l'école.
  commercial_state text NOT NULL DEFAULT 'NOT_CONFIGURED' CHECK (commercial_state = 'NOT_CONFIGURED'),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  updated_by uuid REFERENCES drivy.platform_operator(id),
  updated_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  CHECK ((school_id IS NULL) = (link_source IS NULL)),
  CHECK ((school_id IS NULL) = (school_linked_at IS NULL)),
  CHECK (coalesce(link_source = 'OPENING_CODE', false) = (opened_via_link_id IS NOT NULL)),
  CHECK (coalesce(link_source = 'OPENING_CODE', false) = (first_admin_membership_id IS NOT NULL)),
  CHECK (coalesce(link_source = 'EXISTING_SCHOOL', false) = (school_linked_by IS NOT NULL))
);
CREATE INDEX platform_client_recent ON drivy.platform_client(created_at DESC, id DESC);

-- Le code d'ouverture se rattache à une fiche et garde l'opérateur émetteur. Les codes déjà distribués n'ont ni l'un ni l'autre :
-- ils restent valables tels quels, et la fiche est créée au moment où l'école est ouverte.
ALTER TABLE drivy.school_opening_link
  ADD COLUMN client_id uuid REFERENCES drivy.platform_client(id),
  ADD COLUMN issued_by_operator_id uuid REFERENCES drivy.platform_operator(id);
CREATE INDEX school_opening_client ON drivy.school_opening_link(client_id, created_at DESC, id) WHERE client_id IS NOT NULL;

ALTER TABLE drivy.platform_client ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_client FORCE ROW LEVEL SECURITY;

-- Le propriétaire reste soumis à FORCE RLS : il n'a que ce que les fonctions ci-dessous exigent (lecture, fiche créée à l'ouverture
-- d'un code déjà distribué, liaison de l'école), et rien d'autre.
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_client_owner_read ON drivy.platform_client FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_client_owner_create ON drivy.platform_client FOR INSERT TO %I WITH CHECK(
    school_id IS NULL AND version=1 AND commercial_state=''NOT_CONFIGURED'')', current_user);
  EXECUTE format('CREATE POLICY platform_client_owner_link ON drivy.platform_client FOR UPDATE TO %I USING(school_id IS NULL)
    WITH CHECK(link_source=''OPENING_CODE'' AND school_id IS NOT NULL)', current_user);
  EXECUTE format('CREATE POLICY opening_owner_read ON drivy.school_opening_link FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY opening_owner_attach ON drivy.school_opening_link FOR UPDATE TO %I USING(client_id IS NULL AND status=''USED'')
    WITH CHECK(client_id IS NOT NULL AND status=''USED'')', current_user);
END $$;

-- Opérateurs : lecture, création et modification de la fiche. Ni suppression, ni changement de l'école une fois reliée (déclencheur ci-dessous).
CREATE POLICY platform_client_read ON drivy.platform_client FOR SELECT TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_client_create ON drivy.platform_client FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by=drivy.current_platform_operator() AND updated_by IS NULL
  AND version=1 AND commercial_state='NOT_CONFIGURED' AND school_id IS NULL AND link_source IS NULL AND opened_via_link_id IS NULL
  AND first_admin_membership_id IS NULL AND school_linked_at IS NULL AND school_linked_by IS NULL AND issued_by_operator_id IS NULL);
CREATE POLICY platform_client_update ON drivy.platform_client FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL)
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND updated_by=drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_client TO drivy_app;
GRANT UPDATE(display_name, contact_name, contact_email, contact_phone, billing_street, billing_postal_code, billing_city, billing_country,
  internal_notes, school_id, link_source, school_linked_at, school_linked_by, updated_by) ON drivy.platform_client TO drivy_app;

-- Un code ne désigne jamais un autre émetteur que l'opérateur qui l'écrit.
CREATE POLICY opening_issuer_integrity ON drivy.school_opening_link AS RESTRICTIVE FOR INSERT TO drivy_app
  WITH CHECK(issued_by_operator_id IS NULL OR issued_by_operator_id=drivy.current_platform_operator());

-- La fiche est la preuve de la relation : l'école et son premier ADMIN n'y sont reliés qu'une fois, et la fiche ne disparaît jamais.
CREATE FUNCTION drivy.platform_client_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_client_not_deletable' USING ERRCODE='23514'; END IF;
  IF NEW.id <> OLD.id OR NEW.created_at <> OLD.created_at OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'platform_client_identity_fixed' USING ERRCODE='23514';
  END IF;
  IF OLD.school_id IS NOT NULL AND (NEW.school_id IS DISTINCT FROM OLD.school_id OR NEW.link_source IS DISTINCT FROM OLD.link_source
     OR NEW.opened_via_link_id IS DISTINCT FROM OLD.opened_via_link_id OR NEW.first_admin_membership_id IS DISTINCT FROM OLD.first_admin_membership_id
     OR NEW.school_linked_at IS DISTINCT FROM OLD.school_linked_at OR NEW.school_linked_by IS DISTINCT FROM OLD.school_linked_by
     OR NEW.issued_by_operator_id IS DISTINCT FROM OLD.issued_by_operator_id) THEN
    RAISE EXCEPTION 'platform_client_school_linked' USING ERRCODE='23514';
  END IF;
  -- Le rattachement d'une école existante est toujours écrit par l'opérateur qui le fait (jamais au nom d'un autre).
  IF OLD.school_id IS NULL AND NEW.school_id IS NOT NULL AND NEW.link_source = 'EXISTING_SCHOOL'
     AND NEW.school_linked_by IS DISTINCT FROM drivy.current_platform_operator() THEN
    RAISE EXCEPTION 'platform_client_identity_fixed' USING ERRCODE='23514';
  END IF;
  -- Un code encore utilisable réserve déjà l'école à créer : y rattacher en plus une école existante la ferait exister deux fois.
  IF OLD.school_id IS NULL AND NEW.school_id IS NOT NULL AND NEW.link_source = 'EXISTING_SCHOOL'
     AND EXISTS(SELECT 1 FROM drivy.school_opening_link l WHERE l.client_id = OLD.id AND l.status = 'AVAILABLE' AND l.expires_at > now()) THEN
    RAISE EXCEPTION 'platform_client_code_pending' USING ERRCODE='23514';
  END IF;
  NEW.version := OLD.version + 1;
  NEW.updated_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_client_guard() FROM PUBLIC;
CREATE TRIGGER platform_client_guard BEFORE UPDATE OR DELETE ON drivy.platform_client
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_client_guard();

-- Un code utilisé peut recevoir sa fiche (code déjà distribué avant ce lot) ; rien d'autre ne change sur une ligne terminale.
CREATE OR REPLACE FUNCTION drivy.school_opening_terminal() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF OLD.status<>'AVAILABLE' AND NOT (OLD.status='USED' AND OLD.client_id IS NULL AND NEW.client_id IS NOT NULL
     AND to_jsonb(NEW) - 'client_id' = to_jsonb(OLD) - 'client_id') THEN
    RAISE EXCEPTION 'opening_link_terminal' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;

-- Liaison unique, dans la transaction même qui crée l'école : quand un code passe à « utilisé », l'école et le premier ADMIN
-- créés par ce code sont reliés à la fiche du code (créée à l'instant pour un code antérieur à ce lot), et le journal commercial
-- retient l'événement. Le déclencheur ne s'exécute qu'à cette transition : un rejeu ne relie, ne crée et n'écrit rien de plus.
CREATE FUNCTION drivy.platform_client_opened() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE target uuid := NEW.client_id;
BEGIN
  IF target IS NULL THEN
    target := gen_random_uuid();
    INSERT INTO drivy.platform_client(id, created_by, issued_by_operator_id) VALUES(target, NEW.issued_by_operator_id, NEW.issued_by_operator_id);
    UPDATE drivy.school_opening_link SET client_id = target WHERE id = NEW.id;
  END IF;
  UPDATE drivy.platform_client SET school_id = NEW.reserved_school_id, link_source = 'OPENING_CODE', opened_via_link_id = NEW.id,
    first_admin_membership_id = NEW.reserved_membership_id, school_linked_at = NEW.used_at,
    issued_by_operator_id = coalesce(issued_by_operator_id, NEW.issued_by_operator_id)
  WHERE id = target AND school_id IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'platform_client_already_linked' USING ERRCODE='23514'; END IF;
  INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
  VALUES(gen_random_uuid(), 'SYSTEM', 'Système', 'SCHOOL_OPENED_FROM_CODE', 'SUCCESS', NEW.reserved_school_id, 'PlatformClient', target,
    jsonb_build_object('linkId', NEW.id, 'issuedByOperatorId', NEW.issued_by_operator_id));
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_client_opened() FROM PUBLIC;
CREATE TRIGGER platform_client_opened AFTER UPDATE OF status ON drivy.school_opening_link
  FOR EACH ROW WHEN (OLD.status = 'AVAILABLE' AND NEW.status = 'USED') EXECUTE FUNCTION drivy.platform_client_opened();

-- Faits d'école lisibles par l'équipe : projection fixe (nom, contact, état, progression de la mise en place), jamais un dossier,
-- un trajet ni un message. La fonction exige un opérateur actif relu dans la base ; aucune politique d'école n'est élargie.
CREATE FUNCTION drivy.platform_client_overview(only_id uuid, search_pattern text, preparation_filter text,
  after_created timestamptz, after_id uuid, page_size integer)
RETURNS TABLE(result_total bigint, item jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  WITH base AS (
    SELECT c.*, s.name AS school_name, s.contact_email AS school_contact_email, s.contact_phone AS school_contact_phone, s.status AS school_status,
      ss.current_step AS setup_step, coalesce(cardinality(ss.completed_steps), 0) AS setup_done, ss.completed_at AS setup_completed_at,
      ss.last_saved_at AS setup_saved_at,
      (SELECT jsonb_build_object('id', l.id, 'status', CASE WHEN l.status = 'AVAILABLE' AND l.expires_at <= now() THEN 'EXPIRED' ELSE l.status END,
         'expires_at', l.expires_at, 'created_at', l.created_at)
       FROM drivy.school_opening_link l WHERE l.client_id = c.id ORDER BY l.created_at DESC, l.id DESC LIMIT 1) AS latest_code,
      (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = c.issued_by_operator_id) AS issued_by_name,
      CASE WHEN c.school_id IS NULL THEN 'AWAITING_SCHOOL' WHEN s.status = 'ACTIVE' THEN 'ACTIVE' WHEN s.status = 'ARCHIVED' THEN 'ARCHIVED'
        ELSE 'IN_PREPARATION' END AS preparation
    FROM drivy.platform_client c
    LEFT JOIN drivy.school s ON s.id = c.school_id
    LEFT JOIN drivy.school_setup ss ON ss.school_id = c.school_id
    WHERE only_id IS NULL OR c.id = only_id
  ), matching AS (
    SELECT b.*, count(*) OVER () AS matches FROM base b
    WHERE (preparation_filter IS NULL OR b.preparation = preparation_filter)
      AND (search_pattern IS NULL OR b.display_name ILIKE search_pattern ESCAPE '\' OR b.contact_name ILIKE search_pattern ESCAPE '\'
        OR b.contact_email ILIKE search_pattern ESCAPE '\' OR b.school_name ILIKE search_pattern ESCAPE '\'
        OR b.school_contact_email ILIKE search_pattern ESCAPE '\')
  )
  SELECT m.matches, jsonb_build_object(
    'id', m.id, 'display_name', m.display_name, 'school_id', m.school_id, 'link_source', m.link_source, 'opened_via_link_id', m.opened_via_link_id,
    'school_linked_at', m.school_linked_at, 'issued_by_name', m.issued_by_name,
    'contact_name', m.contact_name, 'contact_email', m.contact_email, 'contact_phone', m.contact_phone,
    'billing_street', m.billing_street, 'billing_postal_code', m.billing_postal_code, 'billing_city', m.billing_city, 'billing_country', m.billing_country,
    'internal_notes', m.internal_notes, 'commercial_state', m.commercial_state, 'version', m.version, 'created_at', m.created_at, 'updated_at', m.updated_at,
    'preparation', m.preparation, 'latest_code', m.latest_code,
    'school', CASE WHEN m.school_id IS NULL THEN NULL ELSE jsonb_build_object('name', m.school_name, 'status', m.school_status,
      'contact_email', m.school_contact_email, 'contact_phone', m.school_contact_phone, 'setup_step', m.setup_step, 'setup_done', m.setup_done,
      'setup_completed_at', m.setup_completed_at, 'setup_saved_at', m.setup_saved_at) END)
  FROM matching m
  WHERE after_created IS NULL OR (m.created_at, m.id) < (after_created, after_id)
  ORDER BY m.created_at DESC, m.id DESC LIMIT page_size;
END $$;

-- Suivi des codes d'ouverture : état, émetteur, fiche rattachée et, une fois utilisé, école créée et progression.
CREATE FUNCTION drivy.platform_code_overview(only_client uuid, only_code uuid, state_filter text, after_created timestamptz, after_id uuid, page_size integer)
RETURNS TABLE(result_total bigint, item jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  WITH base AS (
    SELECT l.id, l.client_id, l.created_at, date_trunc('milliseconds', l.created_at) AS created_ms, l.expires_at, l.used_at, l.revoked_at,
      CASE WHEN l.status = 'AVAILABLE' AND l.expires_at <= now() THEN 'EXPIRED' ELSE l.status END AS state,
      c.display_name AS client_name, c.school_id AS school_id, s.name AS school_name, s.status AS school_status,
      s.contact_email AS school_contact_email, s.contact_phone AS school_contact_phone,
      ss.current_step AS setup_step, coalesce(cardinality(ss.completed_steps), 0) AS setup_done, ss.completed_at AS setup_completed_at,
      (SELECT o.display_name FROM drivy.platform_operator o WHERE o.id = l.issued_by_operator_id) AS issued_by_name
    FROM drivy.school_opening_link l
    LEFT JOIN drivy.platform_client c ON c.id = l.client_id
    LEFT JOIN drivy.school s ON s.id = l.reserved_school_id
    LEFT JOIN drivy.school_setup ss ON ss.school_id = s.id
    WHERE (only_client IS NULL OR l.client_id = only_client) AND (only_code IS NULL OR l.id = only_code)
  ), matching AS (
    SELECT b.*, count(*) OVER () AS matches FROM base b WHERE state_filter IS NULL OR b.state = state_filter
  )
  SELECT m.matches, jsonb_build_object(
    'id', m.id, 'client_id', m.client_id, 'client_name', m.client_name, 'state', m.state, 'created_at', m.created_ms, 'expires_at', m.expires_at,
    'used_at', m.used_at, 'revoked_at', m.revoked_at, 'issued_by_name', m.issued_by_name,
    'school', CASE WHEN m.state <> 'USED' THEN NULL ELSE jsonb_build_object('id', m.school_id, 'name', m.school_name, 'status', m.school_status,
      'contact_email', m.school_contact_email, 'contact_phone', m.school_contact_phone, 'setup_step', m.setup_step, 'setup_done', m.setup_done,
      'setup_completed_at', m.setup_completed_at) END)
  FROM matching m
  WHERE after_created IS NULL OR (m.created_ms, m.id) < (after_created, after_id)
  ORDER BY m.created_ms DESC, m.id DESC LIMIT page_size;
END $$;

-- Écoles déjà ouvertes que personne n'a encore reliées à une fiche : les écoles pilotes, proposées au rattachement explicite.
CREATE FUNCTION drivy.platform_unattached_schools(search_pattern text, page_size integer)
RETURNS TABLE(item jsonb) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT jsonb_build_object('id', s.id, 'name', s.name, 'status', s.status, 'contact_email', s.contact_email, 'contact_phone', s.contact_phone,
    'setup_step', ss.current_step, 'setup_done', coalesce(cardinality(ss.completed_steps), 0), 'setup_completed_at', ss.completed_at)
  FROM drivy.school s LEFT JOIN drivy.school_setup ss ON ss.school_id = s.id
  WHERE NOT EXISTS(SELECT 1 FROM drivy.platform_client c WHERE c.school_id = s.id)
    AND (search_pattern IS NULL OR s.name ILIKE search_pattern ESCAPE '\' OR s.contact_email ILIKE search_pattern ESCAPE '\')
  ORDER BY lower(s.name), s.id LIMIT page_size;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_client_overview(uuid, text, text, timestamptz, uuid, integer),
  drivy.platform_code_overview(uuid, uuid, text, timestamptz, uuid, integer), drivy.platform_unattached_schools(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.platform_client_overview(uuid, text, text, timestamptz, uuid, integer),
  drivy.platform_code_overview(uuid, uuid, text, timestamptz, uuid, integer), drivy.platform_unattached_schools(text, integer) TO drivy_app;
