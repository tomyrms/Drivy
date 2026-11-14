-- R01-T03 (#455) : catalogue de modules, offres, attribution à une école avec date d'effet, ajustements par école et droits résultants.
-- Aucune donnée d'école n'est créée ni modifiée : tant qu'aucune offre n'est attribuée à la fiche d'une école, son périmètre reste
-- exactement celui d'aujourd'hui (état NOT_CONFIGURED = aucune restriction). Les montants, essais et états commerciaux détaillés
-- relèvent de #456 : la colonne platform_client.commercial_state n'est pas touchée, l'état est dérivé ici des attributions.

-- Catalogue stable : seuls les modules réellement livrés par le code y figurent. Ajouter un module = une migration, jamais l'application.
CREATE TABLE drivy.platform_module (
  code text PRIMARY KEY CHECK (code ~ '^[A-Z][A-Z0-9_]{2,63}$'),
  sort_order smallint NOT NULL UNIQUE CHECK (sort_order > 0),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp())
);
-- Amorçage avant FORCE RLS : MESSAGING = messagerie par école ; COLLECTIVE_COURSES = cours collectifs (séries, inscriptions, présences).
INSERT INTO drivy.platform_module(code, sort_order) VALUES ('MESSAGING', 1), ('COLLECTIVE_COURSES', 2);

-- Offre : un ensemble nommé de modules. Modifier une offre ne change jamais une école déjà attribuée (l'attribution en garde l'instantané).
CREATE TABLE drivy.platform_offer (
  id uuid PRIMARY KEY,
  name text NOT NULL CHECK (length(btrim(name)) BETWEEN 1 AND 100),
  modules text[] NOT NULL DEFAULT '{}',
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'ARCHIVED')),
  archived_at timestamptz,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  updated_by uuid REFERENCES drivy.platform_operator(id),
  updated_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  CHECK ((status = 'ARCHIVED') = (archived_at IS NOT NULL))
);
CREATE UNIQUE INDEX platform_offer_name ON drivy.platform_offer (lower(btrim(name)));
CREATE INDEX platform_offer_listing ON drivy.platform_offer (status, lower(btrim(name)), id);

-- Attribution d'une offre à la fiche d'une école, avec date d'effet. L'offre et ses modules sont copiés : l'historique ne se réécrit pas.
-- La ligne en vigueur est la dernière attribution active dont la date d'effet est atteinte ; une attribution future reste annulable.
CREATE TABLE drivy.platform_offer_assignment (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  offer_id uuid NOT NULL REFERENCES drivy.platform_offer(id),
  offer_name text NOT NULL CHECK (length(btrim(offer_name)) BETWEEN 1 AND 100),
  modules text[] NOT NULL,
  effective_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CANCELLED')),
  cancelled_at timestamptz,
  cancelled_by uuid REFERENCES drivy.platform_operator(id),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (client_id, id),
  CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL))
);
CREATE INDEX platform_assignment_client ON drivy.platform_offer_assignment (client_id, effective_at DESC, created_at DESC, id DESC);
CREATE INDEX platform_assignment_offer ON drivy.platform_offer_assignment (offer_id);

-- Ajustement d'une école : un module accordé ou retiré en plus de l'offre en vigueur, avec motif, auteur et historique.
-- Il se rattache à l'attribution qu'il ajuste : quand une autre attribution prend effet, il cesse de s'appliquer (il reste dans l'historique).
CREATE TABLE drivy.platform_module_adjustment (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL,
  assignment_id uuid NOT NULL,
  module_code text NOT NULL REFERENCES drivy.platform_module(code),
  effect text NOT NULL CHECK (effect IN ('GRANT', 'REVOKE')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  lifted_at timestamptz,
  lifted_by uuid REFERENCES drivy.platform_operator(id),
  lift_reason text CHECK (lift_reason IS NULL OR length(btrim(lift_reason)) BETWEEN 3 AND 500),
  FOREIGN KEY (client_id, assignment_id) REFERENCES drivy.platform_offer_assignment(client_id, id),
  CHECK ((lifted_at IS NULL) = (lifted_by IS NULL)),
  CHECK (lift_reason IS NULL OR lifted_at IS NOT NULL)
);
CREATE UNIQUE INDEX platform_adjustment_active ON drivy.platform_module_adjustment (assignment_id, module_code) WHERE lifted_at IS NULL;
CREATE INDEX platform_adjustment_client ON drivy.platform_module_adjustment (client_id, created_at DESC, id DESC);

ALTER TABLE drivy.platform_module ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_module FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_offer ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_offer FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_offer_assignment ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_offer_assignment FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_module_adjustment ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_module_adjustment FORCE ROW LEVEL SECURITY;

-- Le propriétaire reste soumis à FORCE RLS : il ne lit que ce que les fonctions ci-dessous exigent, et n'écrit que le catalogue (migrations).
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_module_owner_read ON drivy.platform_module FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_module_owner_add ON drivy.platform_module FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_offer_owner_read ON drivy.platform_offer FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_assignment_owner_read ON drivy.platform_offer_assignment FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_adjustment_owner_read ON drivy.platform_module_adjustment FOR SELECT TO %I USING(true)', current_user);
END $$;

-- Opérateurs : lecture du catalogue, création et modification des offres, attributions et ajustements. Jamais de suppression.
CREATE POLICY platform_module_read ON drivy.platform_module FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
GRANT SELECT ON drivy.platform_module TO drivy_app;

CREATE POLICY platform_offer_read ON drivy.platform_offer FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_offer_create ON drivy.platform_offer FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator() AND updated_by IS NULL
  AND version = 1 AND status = 'ACTIVE' AND archived_at IS NULL);
CREATE POLICY platform_offer_update ON drivy.platform_offer FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL)
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND updated_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_offer TO drivy_app;
GRANT UPDATE (name, modules, status, updated_by) ON drivy.platform_offer TO drivy_app;

CREATE POLICY platform_assignment_read ON drivy.platform_offer_assignment FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_assignment_create ON drivy.platform_offer_assignment FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator() AND status = 'ACTIVE'
  AND cancelled_at IS NULL AND cancelled_by IS NULL);
CREATE POLICY platform_assignment_cancel ON drivy.platform_offer_assignment FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND status = 'ACTIVE')
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND status = 'CANCELLED' AND cancelled_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_offer_assignment TO drivy_app;
GRANT UPDATE (status, cancelled_by) ON drivy.platform_offer_assignment TO drivy_app;

CREATE POLICY platform_adjustment_read ON drivy.platform_module_adjustment FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_adjustment_create ON drivy.platform_module_adjustment FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator()
  AND lifted_at IS NULL AND lifted_by IS NULL AND lift_reason IS NULL);
CREATE POLICY platform_adjustment_lift ON drivy.platform_module_adjustment FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND lifted_at IS NULL)
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND lifted_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_module_adjustment TO drivy_app;
GRANT UPDATE (lifted_by, lift_reason) ON drivy.platform_module_adjustment TO drivy_app;

-- Le catalogue ne perd ni ne change jamais un module : une école ou une offre qui le référence resterait sans sens.
CREATE FUNCTION drivy.platform_module_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  RAISE EXCEPTION 'platform_module_fixed' USING ERRCODE='23514';
END $$;
CREATE TRIGGER platform_module_guard BEFORE UPDATE OR DELETE ON drivy.platform_module
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_module_guard();

-- Offre : modules connus du catalogue, sans doublon, rangés dans l'ordre du catalogue ; jamais supprimée ; archivée = figée.
CREATE FUNCTION drivy.platform_offer_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE normalised text[];
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_offer_not_deletable' USING ERRCODE='23514'; END IF;
  SELECT coalesce(array_agg(m.code ORDER BY m.sort_order), '{}') INTO normalised FROM drivy.platform_module m WHERE m.code = ANY(NEW.modules);
  IF cardinality(normalised) <> cardinality(NEW.modules) THEN RAISE EXCEPTION 'platform_offer_modules_invalid' USING ERRCODE='23514'; END IF;
  NEW.modules := normalised;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.id <> OLD.id OR NEW.created_at <> OLD.created_at OR NEW.created_by <> OLD.created_by THEN
      RAISE EXCEPTION 'platform_offer_identity_fixed' USING ERRCODE='23514';
    END IF;
    IF OLD.status = 'ARCHIVED' AND (NEW.name <> OLD.name OR NEW.modules <> OLD.modules) THEN
      RAISE EXCEPTION 'platform_offer_archived' USING ERRCODE='23514';
    END IF;
    IF OLD.status = 'ACTIVE' AND NEW.status = 'ARCHIVED' THEN NEW.archived_at := date_trunc('milliseconds', clock_timestamp());
    ELSIF OLD.status = 'ARCHIVED' AND NEW.status = 'ACTIVE' THEN NEW.archived_at := NULL;
    ELSE NEW.archived_at := OLD.archived_at; END IF;
    NEW.version := OLD.version + 1;
    NEW.updated_at := date_trunc('milliseconds', clock_timestamp());
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_offer_guard() FROM PUBLIC;
CREATE TRIGGER platform_offer_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_offer
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_offer_guard();

-- Attribution : jamais supprimée ni réécrite. À la création, l'instantané doit être celui d'une offre active et la date d'effet ne remonte pas
-- dans le passé ; ensuite, seule une attribution encore future peut être annulée.
CREATE FUNCTION drivy.platform_assignment_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE offer drivy.platform_offer;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_assignment_not_deletable' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO offer FROM drivy.platform_offer WHERE id = NEW.offer_id;
    IF NOT FOUND OR offer.status <> 'ACTIVE' THEN RAISE EXCEPTION 'platform_offer_archived' USING ERRCODE='23514'; END IF;
    IF NEW.offer_name <> offer.name OR NEW.modules <> offer.modules THEN RAISE EXCEPTION 'platform_assignment_snapshot' USING ERRCODE='23514'; END IF;
    IF NEW.effective_at < statement_timestamp() - interval '1 second' THEN RAISE EXCEPTION 'platform_assignment_backdated' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.offer_id <> OLD.offer_id OR NEW.offer_name <> OLD.offer_name
     OR NEW.modules <> OLD.modules OR NEW.effective_at <> OLD.effective_at OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'platform_assignment_fixed' USING ERRCODE='23514';
  END IF;
  IF OLD.status <> 'ACTIVE' OR NEW.status <> 'CANCELLED' THEN RAISE EXCEPTION 'platform_assignment_fixed' USING ERRCODE='23514'; END IF;
  IF OLD.effective_at <= statement_timestamp() THEN RAISE EXCEPTION 'platform_assignment_in_force' USING ERRCODE='23514'; END IF;
  NEW.cancelled_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_assignment_guard() FROM PUBLIC;
CREATE TRIGGER platform_assignment_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_offer_assignment
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_assignment_guard();

-- Ajustement : jamais supprimé ni réécrit. Il ne se crée que sur l'attribution actuellement en vigueur ; ensuite, seule sa levée (une fois) est permise.
CREATE FUNCTION drivy.platform_adjustment_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_adjustment_not_deletable' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF coalesce(drivy.platform_client_entitlement_core(NEW.client_id)->'assignment'->>'id', '') <> NEW.assignment_id::text THEN
      RAISE EXCEPTION 'platform_adjustment_assignment_ended' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.assignment_id <> OLD.assignment_id OR NEW.module_code <> OLD.module_code
     OR NEW.effect <> OLD.effect OR NEW.reason <> OLD.reason OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at
     OR OLD.lifted_at IS NOT NULL OR NEW.lifted_by IS NULL THEN
    RAISE EXCEPTION 'platform_adjustment_fixed' USING ERRCODE='23514';
  END IF;
  NEW.lifted_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_adjustment_guard() FROM PUBLIC;
CREATE TRIGGER platform_adjustment_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_module_adjustment
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_adjustment_guard();

-- Droits en vigueur d'une fiche : calculés dans la base, à l'instant de l'instruction, depuis les seules attributions et ajustements.
-- Sans attribution en vigueur : NOT_CONFIGURED et tous les modules du catalogue (périmètre inchangé). Avec : l'offre, plus les ajustements
-- non levés de cette attribution. `version` (au moins 1, pour servir d'If-Match) ne décroît jamais : chaque création, annulation, levée et prise d'effet l'augmente ;
-- `nextChangeAt` est la prochaine prise d'effet connue, pour qu'un client relise avant qu'elle n'arrive.
-- Non exposée : les fonctions ci-dessous y ajoutent l'autorisation (équipe ou membre de l'école) et la projection.
CREATE FUNCTION drivy.platform_client_entitlement_core(p_client uuid) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  WITH clock AS (SELECT statement_timestamp() AS t),
  cur AS (
    SELECT a.* FROM drivy.platform_offer_assignment a, clock
    WHERE a.client_id = p_client AND a.status = 'ACTIVE' AND a.effective_at <= clock.t
    ORDER BY a.effective_at DESC, a.created_at DESC, a.id DESC LIMIT 1),
  nxt AS (
    SELECT a.* FROM drivy.platform_offer_assignment a, clock
    WHERE a.client_id = p_client AND a.status = 'ACTIVE' AND a.effective_at > clock.t
    ORDER BY a.effective_at ASC, a.created_at ASC, a.id ASC LIMIT 1),
  adj AS (
    SELECT j.*, o.display_name AS author_name FROM drivy.platform_module_adjustment j
    JOIN cur ON cur.id = j.assignment_id LEFT JOIN drivy.platform_operator o ON o.id = j.created_by
    WHERE j.lifted_at IS NULL),
  per_module AS (
    SELECT m.code, m.sort_order,
      EXISTS(SELECT 1 FROM cur WHERE m.code = ANY(cur.modules)) AS in_offer,
      (SELECT jsonb_build_object('id', adj.id, 'effect', adj.effect, 'reason', adj.reason, 'createdAt', adj.created_at, 'createdByName', adj.author_name)
       FROM adj WHERE adj.module_code = m.code) AS adjustment,
      (SELECT adj.effect FROM adj WHERE adj.module_code = m.code) AS effect
    FROM drivy.platform_module m)
  SELECT jsonb_build_object(
    'state', CASE WHEN EXISTS(SELECT 1 FROM cur) THEN 'OFFER_ACTIVE' ELSE 'NOT_CONFIGURED' END,
    'assignment', (SELECT jsonb_build_object('id', cur.id, 'offerId', cur.offer_id, 'offerName', cur.offer_name, 'effectiveAt', cur.effective_at,
       'modules', to_jsonb(cur.modules)) FROM cur),
    'scheduled', (SELECT jsonb_build_object('id', nxt.id, 'offerId', nxt.offer_id, 'offerName', nxt.offer_name, 'effectiveAt', nxt.effective_at,
       'modules', to_jsonb(nxt.modules)) FROM nxt),
    'modules', (SELECT jsonb_agg(jsonb_build_object('code', p.code, 'inOffer', p.in_offer, 'adjustment', p.adjustment,
       'entitled', CASE WHEN NOT EXISTS(SELECT 1 FROM cur) THEN true WHEN p.effect = 'GRANT' THEN true WHEN p.effect = 'REVOKE' THEN false ELSE p.in_offer END)
       ORDER BY p.sort_order) FROM per_module p),
    'version', 1 + (SELECT coalesce(sum(1 + CASE WHEN a.status = 'CANCELLED' THEN 1 ELSE 0 END
         + CASE WHEN a.status = 'ACTIVE' AND a.effective_at <= clock.t THEN 1 ELSE 0 END), 0)::integer
       FROM drivy.platform_offer_assignment a, clock WHERE a.client_id = p_client)
      + (SELECT coalesce(sum(1 + CASE WHEN j.lifted_at IS NOT NULL THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_module_adjustment j WHERE j.client_id = p_client),
    'nextChangeAt', (SELECT nxt.effective_at FROM nxt))
$$;
REVOKE ALL ON FUNCTION drivy.platform_client_entitlement_core(uuid) FROM PUBLIC;

-- Vue d'une école sur ses propres droits : état, modules (accordés ou non), version, prochaine échéance. Ni offre, ni motif, ni auteur.
-- Réservée à l'équipe et aux membres actifs de l'école courante ; toute autre session reçoit un refus.
CREATE FUNCTION drivy.school_entitlements(p_school uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE core jsonb;
BEGIN
  IF NOT (drivy.current_platform_operator() IS NOT NULL OR drivy.current_school_member(p_school)) THEN
    RAISE EXCEPTION 'school_entitlements_denied' USING ERRCODE='42501';
  END IF;
  core := drivy.platform_client_entitlement_core((SELECT c.id FROM drivy.platform_client c WHERE c.school_id = p_school));
  RETURN jsonb_build_object('state', core->'state',
    'modules', (SELECT jsonb_agg(jsonb_build_object('code', e->'code', 'entitled', e->'entitled')) FROM jsonb_array_elements(core->'modules') e),
    'version', core->'version', 'nextChangeAt', core->'nextChangeAt');
END $$;

-- Contrôle d'un module, utilisé par les routes de messagerie et de cours : faux si l'appelant n'est ni l'équipe ni membre de l'école,
-- et faux pour un module inconnu (échec fermé). Vrai pour tout module du catalogue d'une école sans offre en vigueur.
CREATE FUNCTION drivy.school_module_entitled(p_school uuid, p_module text) RETURNS boolean
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE core jsonb;
BEGIN
  IF NOT (drivy.current_platform_operator() IS NOT NULL OR drivy.current_school_member(p_school)) THEN RETURN false; END IF;
  core := drivy.platform_client_entitlement_core((SELECT c.id FROM drivy.platform_client c WHERE c.school_id = p_school));
  RETURN EXISTS(SELECT 1 FROM jsonb_array_elements(core->'modules') e WHERE e->>'code' = p_module AND (e->>'entitled')::boolean);
END $$;

-- Droits d'une fiche, vus par l'équipe : détail et historique complet (attributions et ajustements, jamais supprimés).
CREATE FUNCTION drivy.platform_client_entitlements(p_client uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE core jsonb;
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_client c WHERE c.id = p_client) THEN RETURN NULL; END IF;
  core := drivy.platform_client_entitlement_core(p_client);
  RETURN core || jsonb_build_object(
    'assignments', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'offerId', a.offer_id, 'offerName', a.offer_name, 'modules', to_jsonb(a.modules),
        'effectiveAt', a.effective_at, 'status', a.status, 'createdAt', a.created_at, 'createdByName', o.display_name, 'cancelledAt', a.cancelled_at)
        ORDER BY a.effective_at DESC, a.created_at DESC, a.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_offer_assignment WHERE client_id = p_client ORDER BY effective_at DESC, created_at DESC, id DESC LIMIT 50) a
      LEFT JOIN drivy.platform_operator o ON o.id = a.created_by),
    'adjustments', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'assignmentId', j.assignment_id, 'moduleCode', j.module_code,
        'effect', j.effect, 'reason', j.reason, 'createdAt', j.created_at, 'createdByName', o.display_name, 'liftedAt', j.lifted_at,
        'liftedByName', l.display_name, 'liftReason', j.lift_reason)
        ORDER BY j.created_at DESC, j.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_module_adjustment WHERE client_id = p_client ORDER BY created_at DESC, id DESC LIMIT 100) j
      LEFT JOIN drivy.platform_operator o ON o.id = j.created_by LEFT JOIN drivy.platform_operator l ON l.id = j.lifted_by));
END $$;

-- Aperçu des conséquences d'un retrait : volumes seulement (conversations, séries, inscriptions, séances à venir), jamais un contenu.
CREATE FUNCTION drivy.platform_module_usage(p_client uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE s uuid;
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  SELECT c.school_id INTO s FROM drivy.platform_client c WHERE c.id = p_client;
  IF s IS NULL THEN RETURN jsonb_build_object('MESSAGING', jsonb_build_object('conversations', 0),
    'COLLECTIVE_COURSES', jsonb_build_object('publishedSeries', 0, 'activeEnrollments', 0, 'upcomingSessions', 0)); END IF;
  RETURN jsonb_build_object(
    'MESSAGING', jsonb_build_object('conversations', (SELECT count(*) FROM drivy.messaging_conversation WHERE school_id = s)),
    'COLLECTIVE_COURSES', jsonb_build_object(
      'publishedSeries', (SELECT count(*) FROM drivy.course_series WHERE school_id = s AND status = 'PUBLISHED'),
      'activeEnrollments', (SELECT count(*) FROM drivy.course_enrollment e JOIN drivy.course_series cs ON cs.id = e.series_id
        WHERE e.school_id = s AND e.status = 'ACTIVE' AND cs.status = 'PUBLISHED'),
      'upcomingSessions', (SELECT count(*) FROM drivy.course_occurrence o JOIN drivy.course_series cs ON cs.id = o.series_id
        WHERE o.school_id = s AND o.starts_at > statement_timestamp() AND cs.status = 'PUBLISHED')));
END $$;

-- Offres vues par l'équipe, avec le nombre d'écoles pour lesquelles chacune est en vigueur (un compte, jamais la liste des écoles).
-- L'attribution en vigueur de chaque fiche est calculée une fois, pas une fois par offre.
CREATE FUNCTION drivy.platform_offer_overview(p_only uuid, p_status text) RETURNS TABLE(item jsonb)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  WITH inforce AS (
    SELECT DISTINCT ON (a.client_id) a.client_id, a.offer_id FROM drivy.platform_offer_assignment a
    WHERE a.status = 'ACTIVE' AND a.effective_at <= statement_timestamp()
    ORDER BY a.client_id, a.effective_at DESC, a.created_at DESC, a.id DESC)
  SELECT jsonb_build_object('id', o.id, 'name', o.name, 'modules', to_jsonb(o.modules), 'status', o.status, 'version', o.version,
    'created_at', o.created_at, 'updated_at', o.updated_at, 'archived_at', o.archived_at,
    'schools_in_force', (SELECT count(*) FROM inforce i WHERE i.offer_id = o.id))
  FROM drivy.platform_offer o
  WHERE (p_only IS NULL OR o.id = p_only) AND (p_status IS NULL OR o.status = p_status)
  ORDER BY o.status, lower(btrim(o.name)), o.id
  LIMIT 200;
END $$;

REVOKE ALL ON FUNCTION drivy.school_entitlements(uuid), drivy.school_module_entitled(uuid, text), drivy.platform_client_entitlements(uuid),
  drivy.platform_module_usage(uuid), drivy.platform_offer_overview(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.school_entitlements(uuid), drivy.school_module_entitled(uuid, text), drivy.platform_client_entitlements(uuid),
  drivy.platform_module_usage(uuid), drivy.platform_offer_overview(uuid, text) TO drivy_app;

-- Fiche : l'état commercial affiché est dérivé des attributions (NOT_CONFIGURED tant qu'aucune n'est en vigueur), avec l'offre en vigueur
-- et l'offre programmée. La colonne platform_client.commercial_state reste inchangée : #456 y ajoutera ses propres états.
CREATE OR REPLACE FUNCTION drivy.platform_client_overview(only_id uuid, search_pattern text, preparation_filter text,
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
        ELSE 'IN_PREPARATION' END AS preparation,
      drivy.platform_client_entitlement_core(c.id) AS ent
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
    'internal_notes', m.internal_notes, 'commercial_state', m.ent->>'state', 'offer', m.ent->'assignment', 'scheduled_offer', m.ent->'scheduled',
    'entitlement_version', m.ent->'version', 'version', m.version, 'created_at', m.created_at, 'updated_at', m.updated_at,
    'preparation', m.preparation, 'latest_code', m.latest_code,
    'school', CASE WHEN m.school_id IS NULL THEN NULL ELSE jsonb_build_object('name', m.school_name, 'status', m.school_status,
      'contact_email', m.school_contact_email, 'contact_phone', m.school_contact_phone, 'setup_step', m.setup_step, 'setup_done', m.setup_done,
      'setup_completed_at', m.setup_completed_at, 'setup_saved_at', m.setup_saved_at) END)
  FROM matching m
  WHERE after_created IS NULL OR (m.created_at, m.id) < (after_created, after_id)
  ORDER BY m.created_at DESC, m.id DESC LIMIT page_size;
END $$;
