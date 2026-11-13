-- R01-T01 (#453) : équipe d'opérateurs de la plateforme, invitations, reçus durables et journal commercial.
-- Un opérateur n'est ni un membre d'école ni un ADMIN scolaire : aucune politique d'école n'est modifiée ici,
-- et aucune ligne n'est créée par cette migration (les premiers comptes entrent par l'amorçage privé documenté).

CREATE TABLE drivy.platform_operator (
  id uuid PRIMARY KEY,
  issuer text NOT NULL CHECK (length(issuer) BETWEEN 1 AND 2048),
  subject text NOT NULL CHECK (length(subject) BETWEEN 1 AND 512),
  display_name text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 200),
  contact_email text CHECK (contact_email IS NULL OR (contact_email = lower(contact_email) AND length(contact_email) BETWEEN 3 AND 254)),
  -- Un seul niveau de droits commerciaux ; la colonne existe pour qu'un futur niveau soit un choix explicite.
  level text NOT NULL DEFAULT 'COMMERCIAL' CHECK (level = 'COMMERCIAL'),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED')),
  added_via text NOT NULL CHECK (added_via IN ('BOOTSTRAP','INVITATION')),
  invitation_id uuid,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  revoked_at timestamptz,
  revoked_by uuid REFERENCES drivy.platform_operator(id),
  CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL)),
  CHECK ((added_via = 'INVITATION') = (invitation_id IS NOT NULL))
);
-- Une identité n'a qu'une appartenance active ; les anciennes restent comme historique et ne donnent aucun accès.
CREATE UNIQUE INDEX platform_operator_active_identity ON drivy.platform_operator(issuer, subject) WHERE status = 'ACTIVE';
CREATE UNIQUE INDEX platform_operator_active_email ON drivy.platform_operator(contact_email) WHERE status = 'ACTIVE' AND contact_email IS NOT NULL;
CREATE INDEX platform_operator_team ON drivy.platform_operator(created_at, id) WHERE status = 'ACTIVE';

-- Code d'accès à la plateforme : table, format (XXXXX-XXXXX) et clé d'empreinte distincts des droits d'ouverture d'école.
CREATE TABLE drivy.platform_operator_invitation (
  id uuid PRIMARY KEY,
  code_hash text NOT NULL UNIQUE CHECK (code_hash ~ '^[a-f0-9]{64}$'),
  invitee_email text NOT NULL CHECK (invitee_email = lower(invitee_email) AND length(invitee_email) BETWEEN 3 AND 254),
  level text NOT NULL DEFAULT 'COMMERCIAL' CHECK (level = 'COMMERCIAL'),
  status text NOT NULL DEFAULT 'AVAILABLE' CHECK (status IN ('AVAILABLE','USED','REVOKED')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  revoked_by uuid REFERENCES drivy.platform_operator(id),
  used_at timestamptz,
  used_by uuid REFERENCES drivy.platform_operator(id),
  CHECK (expires_at > created_at AND expires_at <= created_at + interval '30 days'),
  CHECK ((status = 'USED') = (used_at IS NOT NULL AND used_by IS NOT NULL)),
  CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL AND revoked_by IS NOT NULL))
);
CREATE INDEX platform_invitation_recent ON drivy.platform_operator_invitation(created_at DESC, id);
CREATE INDEX platform_invitation_open_email ON drivy.platform_operator_invitation(invitee_email) WHERE status = 'AVAILABLE';
ALTER TABLE drivy.platform_operator ADD CONSTRAINT platform_operator_invitation_fk
  FOREIGN KEY (invitation_id) REFERENCES drivy.platform_operator_invitation(id);
CREATE UNIQUE INDEX platform_operator_one_per_invitation ON drivy.platform_operator(invitation_id) WHERE invitation_id IS NOT NULL;

-- Reçu durable d'une commande de la plateforme, propre à l'identité qui l'a envoyée. Jamais de secret dans la réponse conservée.
CREATE TABLE drivy.platform_operation (
  issuer text NOT NULL,
  subject text NOT NULL,
  operation_id uuid NOT NULL,
  kind text NOT NULL CHECK (kind ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  request_hash text NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  status_code smallint NOT NULL CHECK (status_code BETWEEN 200 AND 299),
  response jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (issuer, subject, operation_id)
);

-- Journal commercial : acteur de plateforme, date, école éventuelle, action, résultat, modification utile. Ajout seul.
CREATE TABLE drivy.platform_audit_event (
  id uuid PRIMARY KEY,
  occurred_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  actor_kind text NOT NULL CHECK (actor_kind IN ('OPERATOR','SYSTEM')),
  actor_operator_id uuid REFERENCES drivy.platform_operator(id),
  actor_name text NOT NULL CHECK (length(actor_name) BETWEEN 1 AND 200),
  action text NOT NULL CHECK (action ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  result text NOT NULL CHECK (result IN ('SUCCESS','REFUSED')),
  reason_code text CHECK (reason_code IS NULL OR reason_code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  school_id uuid REFERENCES drivy.school(id),
  subject_type text CHECK (subject_type IS NULL OR subject_type ~ '^[A-Za-z][A-Za-z0-9_]{1,63}$'),
  subject_id uuid,
  operation_id uuid,
  changes jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(changes) = 'object' AND length(changes::text) <= 4000),
  CHECK ((actor_kind = 'OPERATOR') = (actor_operator_id IS NOT NULL)),
  CHECK ((result = 'REFUSED') = (reason_code IS NOT NULL))
);
CREATE INDEX platform_audit_recent ON drivy.platform_audit_event(occurred_at DESC, id DESC);
CREATE INDEX platform_audit_school ON drivy.platform_audit_event(school_id, occurred_at DESC, id DESC) WHERE school_id IS NOT NULL;

ALTER TABLE drivy.platform_operator ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_operator FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_operator_invitation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_operator_invitation FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_operation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_operation FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_audit_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_audit_event FORCE ROW LEVEL SECURITY;

-- Les fonctions scalaires lisent l'équipe sans récursion de politique. Le propriétaire DDL reste soumis à FORCE RLS :
-- il n'a que les politiques explicites ci-dessous (lecture pour les fonctions, amorçage pour la mise en service).
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_operator_owner_read ON drivy.platform_operator FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_operator_bootstrap ON drivy.platform_operator FOR INSERT TO %I WITH CHECK(
    status=''ACTIVE'' AND added_via=''BOOTSTRAP'' AND version=1 AND level=''COMMERCIAL'' AND invitation_id IS NULL)', current_user);
  EXECUTE format('CREATE POLICY platform_invitation_owner_read ON drivy.platform_operator_invitation FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_audit_bootstrap ON drivy.platform_audit_event FOR INSERT TO %I WITH CHECK(
    actor_kind=''SYSTEM'' AND result=''SUCCESS'' AND actor_operator_id IS NULL)', current_user);
END $$;

-- Autorisation relue dans la base à chaque instruction : l'opérateur courant est celui de l'identité OIDC vérifiée
-- par le service, tant que son appartenance est ACTIVE. Une révocation validée prend effet à l'instruction suivante.
CREATE FUNCTION drivy.current_platform_operator() RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT o.id FROM drivy.platform_operator o
  WHERE o.issuer = current_setting('app.issuer', true) AND o.subject = current_setting('app.subject', true) AND o.status = 'ACTIVE'
$$;
-- Un code est acceptable par l'identité courante seulement s'il est disponible, non expiré et destiné à son adresse vérifiée.
CREATE FUNCTION drivy.platform_invitation_acceptable(invitation uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT EXISTS(SELECT 1 FROM drivy.platform_operator_invitation i
    WHERE i.id = invitation AND i.code_hash = current_setting('app.platform_invitation_hash', true)
      AND i.status = 'AVAILABLE' AND i.expires_at > now() AND i.invitee_email = current_setting('app.verified_email', true))
$$;
REVOKE ALL ON FUNCTION drivy.current_platform_operator(), drivy.platform_invitation_acceptable(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.current_platform_operator(), drivy.platform_invitation_acceptable(uuid) TO drivy_app;

-- Équipe : visible aux seuls opérateurs ; on n'y entre que par acceptation authentifiée d'un code ; on n'en sort que par révocation.
CREATE POLICY platform_operator_read ON drivy.platform_operator FOR SELECT TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_operator_accept ON drivy.platform_operator FOR INSERT TO drivy_app WITH CHECK(
  status='ACTIVE' AND version=1 AND level='COMMERCIAL' AND added_via='INVITATION' AND revoked_at IS NULL AND revoked_by IS NULL
  AND issuer=current_setting('app.issuer',true) AND subject=current_setting('app.subject',true)
  AND contact_email=current_setting('app.verified_email',true)
  AND drivy.platform_invitation_acceptable(invitation_id));
CREATE POLICY platform_operator_revoke ON drivy.platform_operator FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND status='ACTIVE')
  WITH CHECK(status='REVOKED' AND revoked_by=drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_operator TO drivy_app;
GRANT UPDATE(status, revoked_at, revoked_by) ON drivy.platform_operator TO drivy_app;

CREATE POLICY platform_invitation_read ON drivy.platform_operator_invitation FOR SELECT TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL OR code_hash=current_setting('app.platform_invitation_hash',true));
CREATE POLICY platform_invitation_create ON drivy.platform_operator_invitation FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by=drivy.current_platform_operator()
  AND status='AVAILABLE' AND version=1 AND level='COMMERCIAL' AND revoked_at IS NULL AND used_at IS NULL);
CREATE POLICY platform_invitation_revoke ON drivy.platform_operator_invitation FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND status='AVAILABLE')
  WITH CHECK(status='REVOKED' AND revoked_by=drivy.current_platform_operator());
CREATE POLICY platform_invitation_consume ON drivy.platform_operator_invitation FOR UPDATE TO drivy_app
  USING(code_hash=current_setting('app.platform_invitation_hash',true) AND status='AVAILABLE')
  WITH CHECK(code_hash=current_setting('app.platform_invitation_hash',true) AND status='USED'
    AND used_by=drivy.current_platform_operator() AND invitee_email=current_setting('app.verified_email',true));
GRANT SELECT, INSERT ON drivy.platform_operator_invitation TO drivy_app;
GRANT UPDATE(status, revoked_at, revoked_by, used_at, used_by) ON drivy.platform_operator_invitation TO drivy_app;

-- Un reçu n'est lisible et écrit que par l'identité qui l'a produit ; hors acceptation, il faut être opérateur.
CREATE POLICY platform_operation_own_read ON drivy.platform_operation FOR SELECT TO drivy_app
  USING(issuer=current_setting('app.issuer',true) AND subject=current_setting('app.subject',true));
CREATE POLICY platform_operation_own_insert ON drivy.platform_operation FOR INSERT TO drivy_app WITH CHECK(
  issuer=current_setting('app.issuer',true) AND subject=current_setting('app.subject',true)
  AND (kind='ACCEPT_PLATFORM_INVITATION' OR drivy.current_platform_operator() IS NOT NULL));
GRANT SELECT, INSERT ON drivy.platform_operation TO drivy_app;

CREATE POLICY platform_audit_read ON drivy.platform_audit_event FOR SELECT TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_audit_insert ON drivy.platform_audit_event FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND actor_kind='OPERATOR' AND actor_operator_id=drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_audit_event TO drivy_app;

-- Le droit d'ouvrir des écoles suit désormais l'équipe en base, relue ici, et non plus un indicateur posé par le service seul.
DROP POLICY opening_operator_read ON drivy.school_opening_link;
DROP POLICY opening_operator_insert ON drivy.school_opening_link;
DROP POLICY opening_operator_revoke ON drivy.school_opening_link;
CREATE POLICY opening_operator_read ON drivy.school_opening_link FOR SELECT TO drivy_app
  USING(current_setting('app.school_opening_operator',true)='true' AND drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY opening_operator_insert ON drivy.school_opening_link FOR INSERT TO drivy_app WITH CHECK(
  current_setting('app.school_opening_operator',true)='true' AND drivy.current_platform_operator() IS NOT NULL AND status='AVAILABLE'
  AND created_by_issuer=current_setting('app.issuer',true) AND created_by_subject=current_setting('app.subject',true));
CREATE POLICY opening_operator_revoke ON drivy.school_opening_link FOR UPDATE TO drivy_app
  USING(current_setting('app.school_opening_operator',true)='true' AND drivy.current_platform_operator() IS NOT NULL AND status IN('AVAILABLE','REVOKED'))
  WITH CHECK(current_setting('app.school_opening_operator',true)='true' AND drivy.current_platform_operator() IS NOT NULL AND status='REVOKED'
    AND revoked_by_issuer=current_setting('app.issuer',true) AND revoked_by_subject=current_setting('app.subject',true));

-- Garde-fous portés par la base, quel que soit l'appelant.
-- 1. Version : toute modification d'une ligne la fait avancer ; deux opérateurs ne s'écrasent pas en silence.
CREATE FUNCTION drivy.platform_bump_version() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  NEW.version := OLD.version + 1;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_bump_version() FROM PUBLIC;
-- 2. Équipe : identité immuable, appartenance révoquée définitive, jamais de suppression, et jamais zéro opérateur actif.
--    Le verrou consultatif sérialise toutes les révocations : la seconde voit la première validée et refuse.
CREATE FUNCTION drivy.platform_operator_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_operator_not_deletable' USING ERRCODE='23514'; END IF;
  IF OLD.status <> 'ACTIVE' THEN RAISE EXCEPTION 'platform_operator_terminal' USING ERRCODE='23514'; END IF;
  IF NEW.id <> OLD.id OR NEW.issuer <> OLD.issuer OR NEW.subject <> OLD.subject OR NEW.level <> OLD.level
     OR NEW.display_name <> OLD.display_name OR NEW.contact_email IS DISTINCT FROM OLD.contact_email
     OR NEW.added_via <> OLD.added_via OR NEW.invitation_id IS DISTINCT FROM OLD.invitation_id OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'platform_operator_identity_fixed' USING ERRCODE='23514';
  END IF;
  IF NEW.status = 'REVOKED' THEN
    PERFORM pg_advisory_xact_lock(hashtextextended('drivy.platform_operator.team', 0));
    IF NOT EXISTS(SELECT 1 FROM drivy.platform_operator o WHERE o.status = 'ACTIVE' AND o.id <> OLD.id) THEN
      RAISE EXCEPTION 'last_platform_operator' USING ERRCODE='23514';
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_operator_guard() FROM PUBLIC;
CREATE TRIGGER platform_operator_guard BEFORE UPDATE OR DELETE ON drivy.platform_operator
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_operator_guard();
CREATE TRIGGER platform_operator_version BEFORE UPDATE ON drivy.platform_operator
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_bump_version();
-- Une équipe vide ne peut pas non plus naître d'une troncature hors migration : la table n'a aucun DELETE accordé.
-- 3. Invitation : un état terminal ne change plus ; l'identité et l'adresse visées restent celles de l'émission.
CREATE FUNCTION drivy.platform_invitation_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_invitation_not_deletable' USING ERRCODE='23514'; END IF;
  IF OLD.status <> 'AVAILABLE' THEN RAISE EXCEPTION 'platform_invitation_terminal' USING ERRCODE='23514'; END IF;
  IF NEW.id <> OLD.id OR NEW.code_hash <> OLD.code_hash OR NEW.invitee_email <> OLD.invitee_email OR NEW.level <> OLD.level
     OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at OR NEW.expires_at <> OLD.expires_at THEN
    RAISE EXCEPTION 'platform_invitation_fixed' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_invitation_guard() FROM PUBLIC;
CREATE TRIGGER platform_invitation_guard BEFORE UPDATE OR DELETE ON drivy.platform_operator_invitation
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_invitation_guard();
CREATE TRIGGER platform_invitation_version BEFORE UPDATE ON drivy.platform_operator_invitation
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_bump_version();
-- 4. Journal et reçus : jamais modifiés ni supprimés.
CREATE FUNCTION drivy.platform_append_only() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  RAISE EXCEPTION 'platform_append_only' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION drivy.platform_append_only() FROM PUBLIC;
CREATE TRIGGER platform_audit_append_only BEFORE UPDATE OR DELETE ON drivy.platform_audit_event
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_append_only();
CREATE TRIGGER platform_operation_append_only BEFORE UPDATE OR DELETE ON drivy.platform_operation
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_append_only();
