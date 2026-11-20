-- R01-T04 (#456) : conditions commerciales versionnées par école, essai, début payant confirmé, demandes de changement d'offre ou de résiliation.
-- Aucune donnée n'est créée ni modifiée : une école pilote sans essai ni début payant garde son périmètre (cycle NONE, aucune restriction,
-- rien de facturable). Aucune facture n'existe à ce stade (#457) : ce lot décrit ce qui sera dû, il n'émet rien.
--
-- Dates : une date commerciale (début payant, date d'effet de conditions, résiliation) est un jour civil Europe/Zurich ; elle commence à minuit
-- à Zurich. Montants : entiers en centimes de CHF, seule devise admise. La colonne platform_client.commercial_state reste inchangée : le cycle
-- de vie est dérivé, dans la base, des lignes ci-dessous (jamais d'un état saisi à la main).

CREATE FUNCTION drivy.zurich_today() RETURNS date LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT (statement_timestamp() AT TIME ZONE 'Europe/Zurich')::date
$$;
CREATE FUNCTION drivy.zurich_day_start(p_day date) RETURNS timestamptz LANGUAGE sql STABLE SET search_path=pg_catalog AS $$
  SELECT (p_day::timestamp AT TIME ZONE 'Europe/Zurich')
$$;
-- Début de période mensuelle à ancre stable : le jour d'ancre (jour du début payant) ou, s'il n'existe pas dans le mois, son dernier jour.
-- Ancre au 31 : 31 janvier, 28 ou 29 février, 31 mars, 30 avril. Ancre au 29 : 29 février les années bissextiles, 28 sinon.
CREATE FUNCTION drivy.is_billing_period_start(p_anchor date, p_day date) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT p_day >= p_anchor AND extract(day FROM p_day)::int = least(extract(day FROM p_anchor)::int,
    extract(day FROM (date_trunc('month', p_day) + interval '1 month - 1 day'))::int)
$$;

-- Conditions : chaque modification est une nouvelle version, jamais une réécriture. La version applicable un jour donné est celle de plus
-- grand numéro dont la date d'effet est atteinte : une version plus récente remplace une version encore programmée.
CREATE TABLE drivy.platform_commercial_terms (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  sequence integer NOT NULL CHECK (sequence > 0),
  currency text NOT NULL DEFAULT 'CHF' CHECK (currency = 'CHF'),
  -- Montant initial unique (centimes). NULL = à compléter ; 0 = convenu sans montant initial.
  initial_amount integer CHECK (initial_amount BETWEEN 0 AND 100000000),
  initial_discount integer NOT NULL DEFAULT 0 CHECK (initial_discount >= 0),
  -- Échéance du montant initial ; NULL = le jour du début payant.
  initial_due_on date,
  monthly_amount integer CHECK (monthly_amount BETWEEN 0 AND 10000000),
  recurring_discount integer NOT NULL DEFAULT 0 CHECK (recurring_discount >= 0),
  -- Durée de la remise récurrente en périodes, comptée depuis la première période de cette version ; NULL = permanente.
  recurring_discount_months smallint CHECK (recurring_discount_months BETWEEN 1 AND 120),
  payment_term_days smallint CHECK (payment_term_days BETWEEN 0 AND 120),
  -- Sort des nouvelles périodes pendant une suspension (#461). Aucun défaut : NULL = à compléter.
  suspension_billing text CHECK (suspension_billing IN ('CONTINUE', 'PAUSE')),
  effective_from date NOT NULL,
  -- Motif d'une date d'effet hors début de période (sans prorata automatique : la régularisation relève des documents).
  exception_reason text CHECK (exception_reason IS NULL OR length(btrim(exception_reason)) BETWEEN 3 AND 500),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (client_id, sequence),
  UNIQUE (client_id, id),
  CHECK (initial_amount IS NULL OR initial_discount <= initial_amount),
  CHECK (monthly_amount IS NULL OR recurring_discount <= monthly_amount),
  CHECK (recurring_discount > 0 OR recurring_discount_months IS NULL)
);

-- Essai : chaque changement (début, prolongation, fin anticipée) est une ligne ; l'essai en cours est la dernière. Un seul essai par école.
CREATE TABLE drivy.platform_trial_change (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  sequence integer NOT NULL CHECK (sequence > 0),
  kind text NOT NULL CHECK (kind IN ('START', 'EXTEND', 'END_EARLY')),
  starts_at timestamptz NOT NULL,
  ends_at timestamptz NOT NULL,
  reason text CHECK (reason IS NULL OR length(btrim(reason)) BETWEEN 3 AND 500),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (client_id, sequence),
  CHECK (ends_at > starts_at AND ends_at <= starts_at + interval '400 days'),
  CHECK (kind = 'START' OR reason IS NOT NULL)
);

-- Début payant : confirmé explicitement par un opérateur, à une date choisie, sur des conditions complètes. Jamais créé par l'expiration
-- d'un essai. Annulable tant que la date n'est pas atteinte ; ensuite, il ne se réécrit plus (la fin passe par une résiliation).
CREATE TABLE drivy.platform_paid_start (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  starts_on date NOT NULL,
  terms_id uuid NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CANCELLED')),
  confirmed_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  confirmed_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  cancelled_by uuid REFERENCES drivy.platform_operator(id),
  cancelled_at timestamptz,
  cancel_reason text CHECK (cancel_reason IS NULL OR length(btrim(cancel_reason)) BETWEEN 3 AND 500),
  FOREIGN KEY (client_id, terms_id) REFERENCES drivy.platform_commercial_terms(client_id, id),
  CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL AND cancelled_by IS NOT NULL AND cancel_reason IS NOT NULL))
);
CREATE UNIQUE INDEX platform_paid_start_active ON drivy.platform_paid_start (client_id) WHERE status = 'ACTIVE';

-- Demande de changement d'offre ou de résiliation et décision de l'équipe. La date de demande (déclarée) et la date de confirmation
-- (horodatage serveur de la décision) restent distinctes ; la réponse est celle que l'école verra (#460).
CREATE TABLE drivy.platform_commercial_request (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  kind text NOT NULL CHECK (kind IN ('OFFER_CHANGE', 'TERMINATION')),
  status text NOT NULL DEFAULT 'RECEIVED' CHECK (status IN ('RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN')),
  requested_on date NOT NULL,
  requested_offer_id uuid REFERENCES drivy.platform_offer(id),
  requested_offer_name text,
  desired_on date,
  details text CHECK (details IS NULL OR length(btrim(details)) BETWEEN 3 AND 1000),
  response text CHECK (response IS NULL OR length(btrim(response)) BETWEEN 3 AND 1000),
  effective_on date,
  assignment_id uuid,
  decided_at timestamptz,
  decided_by uuid REFERENCES drivy.platform_operator(id),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  updated_by uuid REFERENCES drivy.platform_operator(id),
  updated_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  FOREIGN KEY (client_id, assignment_id) REFERENCES drivy.platform_offer_assignment(client_id, id),
  CHECK (kind = 'OFFER_CHANGE' OR (requested_offer_id IS NULL AND assignment_id IS NULL)),
  CHECK ((requested_offer_id IS NULL) = (requested_offer_name IS NULL)),
  CHECK ((status = 'ACCEPTED') = (effective_on IS NOT NULL)),
  CHECK ((status IN ('ACCEPTED', 'REFUSED', 'WITHDRAWN')) = (decided_at IS NOT NULL AND decided_by IS NOT NULL)),
  CHECK (status <> 'REFUSED' OR response IS NOT NULL),
  CHECK (kind <> 'OFFER_CHANGE' OR status <> 'ACCEPTED' OR assignment_id IS NOT NULL)
);
CREATE UNIQUE INDEX platform_termination_accepted ON drivy.platform_commercial_request (client_id) WHERE kind = 'TERMINATION' AND status = 'ACCEPTED';
CREATE INDEX platform_request_client ON drivy.platform_commercial_request (client_id, created_at DESC, id DESC);

ALTER TABLE drivy.platform_commercial_terms ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_commercial_terms FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_trial_change ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_trial_change FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_paid_start ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_paid_start FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_commercial_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_commercial_request FORCE ROW LEVEL SECURITY;

DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_terms_owner_read ON drivy.platform_commercial_terms FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_trial_owner_read ON drivy.platform_trial_change FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_paid_start_owner_read ON drivy.platform_paid_start FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_request_owner_read ON drivy.platform_commercial_request FOR SELECT TO %I USING(true)', current_user);
END $$;

-- Équipe : lecture, ajout ; seules l'annulation d'un début payant et la décision sur une demande modifient une ligne. Jamais de suppression.
CREATE POLICY platform_terms_read ON drivy.platform_commercial_terms FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_terms_create ON drivy.platform_commercial_terms FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_commercial_terms TO drivy_app;

CREATE POLICY platform_trial_read ON drivy.platform_trial_change FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_trial_create ON drivy.platform_trial_change FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_trial_change TO drivy_app;

CREATE POLICY platform_paid_start_read ON drivy.platform_paid_start FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_paid_start_create ON drivy.platform_paid_start FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND confirmed_by = drivy.current_platform_operator() AND status = 'ACTIVE'
  AND cancelled_by IS NULL AND cancelled_at IS NULL AND cancel_reason IS NULL);
CREATE POLICY platform_paid_start_cancel ON drivy.platform_paid_start FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND status = 'ACTIVE')
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND status = 'CANCELLED' AND cancelled_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_paid_start TO drivy_app;
GRANT UPDATE (status, cancelled_by, cancel_reason) ON drivy.platform_paid_start TO drivy_app;

CREATE POLICY platform_request_read ON drivy.platform_commercial_request FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_request_create ON drivy.platform_commercial_request FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator() AND status = 'RECEIVED' AND version = 1
  AND updated_by IS NULL AND decided_at IS NULL AND decided_by IS NULL AND effective_on IS NULL AND assignment_id IS NULL AND response IS NULL);
CREATE POLICY platform_request_decide ON drivy.platform_commercial_request FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND status IN ('RECEIVED', 'IN_PROGRESS'))
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND updated_by = drivy.current_platform_operator()
    AND (decided_by IS NULL OR decided_by = drivy.current_platform_operator()));
GRANT SELECT, INSERT ON drivy.platform_commercial_request TO drivy_app;
GRANT UPDATE (status, response, effective_on, assignment_id, decided_by, updated_by) ON drivy.platform_commercial_request TO drivy_app;

-- Version de conditions applicable à un jour donné (NULL s'il n'y en a pas encore).
CREATE FUNCTION drivy.platform_terms_at(p_client uuid, p_day date) RETURNS drivy.platform_commercial_terms
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT t.* FROM drivy.platform_commercial_terms t WHERE t.client_id = p_client AND t.effective_from <= p_day ORDER BY t.sequence DESC LIMIT 1
$$;
-- Ce qui manque pour que des conditions soient facturables. Une offre attribuée (en vigueur ou programmée) en fait partie.
CREATE FUNCTION drivy.platform_terms_missing(p_client uuid, p_terms drivy.platform_commercial_terms) RETURNS text[]
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN NOT EXISTS(SELECT 1 FROM drivy.platform_offer_assignment a WHERE a.client_id = p_client AND a.status = 'ACTIVE') THEN 'OFFER' END,
    CASE WHEN p_terms.id IS NULL THEN 'TERMS' END,
    CASE WHEN p_terms.id IS NOT NULL AND p_terms.initial_amount IS NULL THEN 'INITIAL_AMOUNT' END,
    CASE WHEN p_terms.id IS NOT NULL AND p_terms.monthly_amount IS NULL THEN 'MONTHLY_AMOUNT' END,
    CASE WHEN p_terms.id IS NOT NULL AND p_terms.payment_term_days IS NULL THEN 'PAYMENT_TERM' END,
    CASE WHEN p_terms.id IS NOT NULL AND p_terms.suspension_billing IS NULL THEN 'SUSPENSION_BILLING' END], NULL)
$$;
REVOKE ALL ON FUNCTION drivy.platform_terms_at(uuid, date), drivy.platform_terms_missing(uuid, drivy.platform_commercial_terms) FROM PUBLIC;

-- Conditions : jamais réécrites ni supprimées ; numérotées sans trou ; jamais rétroactives. Une fois le payant confirmé, une date d'effet
-- hors début de période exige un motif (aucun prorata automatique).
CREATE FUNCTION drivy.platform_terms_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE anchor date;
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'platform_terms_fixed' USING ERRCODE='23514'; END IF;
  IF NEW.sequence <> 1 + coalesce((SELECT max(t.sequence) FROM drivy.platform_commercial_terms t WHERE t.client_id = NEW.client_id), 0) THEN
    RAISE EXCEPTION 'platform_terms_sequence' USING ERRCODE='23514';
  END IF;
  IF NEW.effective_from < drivy.zurich_today() THEN RAISE EXCEPTION 'platform_terms_backdated' USING ERRCODE='23514'; END IF;
  SELECT p.starts_on INTO anchor FROM drivy.platform_paid_start p WHERE p.client_id = NEW.client_id AND p.status = 'ACTIVE';
  IF anchor IS NOT NULL AND NEW.effective_from > anchor AND NOT drivy.is_billing_period_start(anchor, NEW.effective_from) AND NEW.exception_reason IS NULL THEN
    RAISE EXCEPTION 'platform_terms_exception_reason' USING ERRCODE='23514';
  END IF;
  NEW.created_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_terms_guard() FROM PUBLIC;
CREATE TRIGGER platform_terms_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_commercial_terms
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_terms_guard();

-- Essai : un début unique, puis des prolongations ou une fin anticipée motivées. Fermé une fois le payant commencé ou la résiliation effective.
CREATE FUNCTION drivy.platform_trial_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE prev drivy.platform_trial_change; now_at timestamptz := statement_timestamp();
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'platform_trial_fixed' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_paid_start p WHERE p.client_id = NEW.client_id AND p.status = 'ACTIVE' AND drivy.zurich_day_start(p.starts_on) <= now_at)
     OR EXISTS(SELECT 1 FROM drivy.platform_commercial_request r WHERE r.client_id = NEW.client_id AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED'
       AND drivy.zurich_day_start(r.effective_on) <= now_at) THEN
    RAISE EXCEPTION 'platform_trial_closed' USING ERRCODE='23514';
  END IF;
  SELECT * INTO prev FROM drivy.platform_trial_change t WHERE t.client_id = NEW.client_id ORDER BY t.sequence DESC LIMIT 1;
  IF NEW.sequence <> coalesce(prev.sequence, 0) + 1 THEN RAISE EXCEPTION 'platform_trial_sequence' USING ERRCODE='23514'; END IF;
  IF prev.id IS NULL THEN
    IF NEW.kind <> 'START' OR NEW.ends_at <= now_at THEN RAISE EXCEPTION 'platform_trial_start' USING ERRCODE='23514'; END IF;
  ELSIF NEW.kind = 'EXTEND' THEN
    IF NEW.starts_at <> prev.starts_at OR NEW.ends_at <= prev.ends_at OR NEW.ends_at <= now_at THEN RAISE EXCEPTION 'platform_trial_extend' USING ERRCODE='23514'; END IF;
  ELSIF NEW.kind = 'END_EARLY' THEN
    IF NEW.starts_at <> prev.starts_at OR prev.ends_at <= now_at OR NEW.ends_at >= prev.ends_at OR NEW.ends_at < now_at - interval '1 second' THEN
      RAISE EXCEPTION 'platform_trial_end' USING ERRCODE='23514';
    END IF;
  ELSE RAISE EXCEPTION 'platform_trial_start' USING ERRCODE='23514';
  END IF;
  NEW.created_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_trial_guard() FROM PUBLIC;
CREATE TRIGGER platform_trial_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_trial_change
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_trial_guard();

-- Début payant : jamais rétroactif, sur la version de conditions applicable ce jour-là et complète ; annulable seulement avant sa date.
CREATE FUNCTION drivy.platform_paid_start_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE terms drivy.platform_commercial_terms;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_paid_start_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.starts_on < drivy.zurich_today() THEN RAISE EXCEPTION 'platform_paid_start_backdated' USING ERRCODE='23514'; END IF;
    terms := drivy.platform_terms_at(NEW.client_id, NEW.starts_on);
    IF terms.id IS DISTINCT FROM NEW.terms_id OR cardinality(drivy.platform_terms_missing(NEW.client_id, terms)) > 0 THEN
      RAISE EXCEPTION 'platform_terms_incomplete' USING ERRCODE='23514';
    END IF;
    IF EXISTS(SELECT 1 FROM drivy.platform_commercial_request r WHERE r.client_id = NEW.client_id AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED') THEN
      RAISE EXCEPTION 'platform_client_terminated' USING ERRCODE='23514';
    END IF;
    NEW.confirmed_at := date_trunc('milliseconds', clock_timestamp());
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.starts_on <> OLD.starts_on OR NEW.terms_id <> OLD.terms_id
     OR NEW.confirmed_by <> OLD.confirmed_by OR NEW.confirmed_at <> OLD.confirmed_at OR OLD.status <> 'ACTIVE' OR NEW.status <> 'CANCELLED' THEN
    RAISE EXCEPTION 'platform_paid_start_fixed' USING ERRCODE='23514';
  END IF;
  IF drivy.zurich_day_start(OLD.starts_on) <= statement_timestamp() THEN RAISE EXCEPTION 'platform_paid_start_started' USING ERRCODE='23514'; END IF;
  NEW.cancelled_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_paid_start_guard() FROM PUBLIC;
CREATE TRIGGER platform_paid_start_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_paid_start
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_paid_start_guard();

-- Demande : la demande elle-même ne change plus ; seul son traitement avance (reçue -> en traitement -> acceptée, refusée ou retirée).
-- Une décision est définitive ; sa date de confirmation est posée par la base ; une date d'effet acceptée n'est jamais passée.
CREATE FUNCTION drivy.platform_request_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_request_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.requested_on > drivy.zurich_today() THEN RAISE EXCEPTION 'platform_request_future' USING ERRCODE='23514'; END IF;
    IF NEW.requested_offer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM drivy.platform_offer o WHERE o.id = NEW.requested_offer_id
       AND o.name = NEW.requested_offer_name) THEN
      RAISE EXCEPTION 'platform_request_offer' USING ERRCODE='23514';
    END IF;
    NEW.created_at := date_trunc('milliseconds', clock_timestamp()); NEW.updated_at := NEW.created_at;
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.kind <> OLD.kind OR NEW.requested_on <> OLD.requested_on
     OR NEW.requested_offer_id IS DISTINCT FROM OLD.requested_offer_id OR NEW.requested_offer_name IS DISTINCT FROM OLD.requested_offer_name
     OR NEW.desired_on IS DISTINCT FROM OLD.desired_on OR NEW.details IS DISTINCT FROM OLD.details
     OR NEW.created_by <> OLD.created_by OR NEW.created_at <> OLD.created_at THEN
    RAISE EXCEPTION 'platform_request_fixed' USING ERRCODE='23514';
  END IF;
  IF OLD.status NOT IN ('RECEIVED', 'IN_PROGRESS') OR NEW.status = 'RECEIVED' OR (OLD.status = 'IN_PROGRESS' AND NEW.status = 'IN_PROGRESS') THEN
    RAISE EXCEPTION 'platform_request_transition' USING ERRCODE='23514';
  END IF;
  IF NEW.status = 'ACCEPTED' AND NEW.effective_on < drivy.zurich_today() THEN RAISE EXCEPTION 'platform_request_backdated' USING ERRCODE='23514'; END IF;
  IF NEW.status IN ('ACCEPTED', 'REFUSED', 'WITHDRAWN') THEN NEW.decided_at := date_trunc('milliseconds', clock_timestamp());
  ELSE NEW.decided_at := NULL; NEW.decided_by := NULL; END IF;
  NEW.version := OLD.version + 1;
  NEW.updated_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_request_guard() FROM PUBLIC;
CREATE TRIGGER platform_request_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_commercial_request
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_request_guard();

-- Calcul unique des droits (remplace celui de R01-T03, même signature). Ajouts :
--  * `lifecycle` : NONE (école pilote ou non configurée), TRIAL, TRIAL_EXPIRED, PAID, TERMINATED ; précédence TERMINATED > PAID > TRIAL > TRIAL_EXPIRED ;
--  * `restriction` : en TRIAL_EXPIRED ou TERMINATED, les modules ne sont plus accordés et seule la classe WRITE_NEW est fermée (la consultation
--    de l'historique et la fin des engagements déjà pris restent possibles, matrice de R01-T03) ;
--  * `version` compte aussi chaque changement d'essai, de début payant, de résiliation, et chaque échéance atteinte ;
--  * `nextChangeAt` inclut début et fin d'essai, début payant et résiliation à venir.
-- `state` garde son sens de R01-T03 (offre en vigueur ou non) : les clients existants ne changent pas d'interprétation.
CREATE OR REPLACE FUNCTION drivy.platform_client_entitlement_core(p_client uuid) RETURNS jsonb
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
  trial AS (SELECT t.* FROM drivy.platform_trial_change t WHERE t.client_id = p_client ORDER BY t.sequence DESC LIMIT 1),
  paid AS (SELECT p.*, drivy.zurich_day_start(p.starts_on) AS at FROM drivy.platform_paid_start p WHERE p.client_id = p_client AND p.status = 'ACTIVE'),
  term AS (SELECT r.*, drivy.zurich_day_start(r.effective_on) AS at FROM drivy.platform_commercial_request r
    WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED'),
  lc AS (SELECT CASE
    WHEN EXISTS(SELECT 1 FROM term, clock WHERE term.at <= clock.t) THEN 'TERMINATED'
    WHEN EXISTS(SELECT 1 FROM paid, clock WHERE paid.at <= clock.t) THEN 'PAID'
    WHEN EXISTS(SELECT 1 FROM trial, clock WHERE trial.starts_at <= clock.t AND trial.ends_at > clock.t) THEN 'TRIAL'
    WHEN EXISTS(SELECT 1 FROM trial, clock WHERE trial.ends_at <= clock.t) THEN 'TRIAL_EXPIRED'
    ELSE 'NONE' END AS lifecycle),
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
    'lifecycle', (SELECT lifecycle FROM lc),
    'restriction', (SELECT CASE WHEN lc.lifecycle IN ('TRIAL_EXPIRED', 'TERMINATED')
       THEN jsonb_build_object('reason', lc.lifecycle, 'closes', jsonb_build_array('WRITE_NEW')) END FROM lc),
    'trial', (SELECT jsonb_build_object('startsAt', trial.starts_at, 'endsAt', trial.ends_at) FROM trial),
    'paidStartsOn', (SELECT paid.starts_on FROM paid),
    'terminationOn', (SELECT term.effective_on FROM term),
    'assignment', (SELECT jsonb_build_object('id', cur.id, 'offerId', cur.offer_id, 'offerName', cur.offer_name, 'effectiveAt', cur.effective_at,
       'modules', to_jsonb(cur.modules)) FROM cur),
    'scheduled', (SELECT jsonb_build_object('id', nxt.id, 'offerId', nxt.offer_id, 'offerName', nxt.offer_name, 'effectiveAt', nxt.effective_at,
       'modules', to_jsonb(nxt.modules)) FROM nxt),
    'modules', (SELECT jsonb_agg(jsonb_build_object('code', p.code, 'inOffer', p.in_offer, 'adjustment', p.adjustment,
       'entitled', CASE WHEN (SELECT lifecycle FROM lc) IN ('TRIAL_EXPIRED', 'TERMINATED') THEN false
         WHEN NOT EXISTS(SELECT 1 FROM cur) THEN true WHEN p.effect = 'GRANT' THEN true WHEN p.effect = 'REVOKE' THEN false ELSE p.in_offer END)
       ORDER BY p.sort_order) FROM per_module p),
    'version', 1 + (SELECT coalesce(sum(1 + CASE WHEN a.status = 'CANCELLED' THEN 1 ELSE 0 END
         + CASE WHEN a.status = 'ACTIVE' AND a.effective_at <= clock.t THEN 1 ELSE 0 END), 0)::integer
       FROM drivy.platform_offer_assignment a, clock WHERE a.client_id = p_client)
      + (SELECT coalesce(sum(1 + CASE WHEN j.lifted_at IS NOT NULL THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_module_adjustment j WHERE j.client_id = p_client)
      + (SELECT coalesce(sum(1 + CASE WHEN t.starts_at <= clock.t THEN 1 ELSE 0 END + CASE WHEN t.ends_at <= clock.t THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_trial_change t, clock WHERE t.client_id = p_client)
      + (SELECT coalesce(sum(1 + CASE WHEN p.status = 'CANCELLED' THEN 1 ELSE 0 END
           + CASE WHEN p.status = 'ACTIVE' AND drivy.zurich_day_start(p.starts_on) <= clock.t THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_paid_start p, clock WHERE p.client_id = p_client)
      + (SELECT coalesce(sum(1 + CASE WHEN drivy.zurich_day_start(r.effective_on) <= clock.t THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_commercial_request r, clock WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED'),
    'nextChangeAt', (SELECT least(
        (SELECT nxt.effective_at FROM nxt),
        (SELECT trial.starts_at FROM trial WHERE trial.starts_at > clock.t),
        (SELECT trial.ends_at FROM trial WHERE trial.ends_at > clock.t),
        (SELECT paid.at FROM paid WHERE paid.at > clock.t),
        (SELECT term.at FROM term WHERE term.at > clock.t)) FROM clock))
$$;

-- Vue d'une école sur ses propres droits : on y ajoute le cycle de vie, la fermeture éventuelle, la fin d'essai et le début payant,
-- exactement comme la console les voit. Jamais un montant, une remise, un motif ni un auteur.
CREATE OR REPLACE FUNCTION drivy.school_entitlements(p_school uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE core jsonb;
BEGIN
  IF NOT (drivy.current_platform_operator() IS NOT NULL OR drivy.current_school_member(p_school)) THEN
    RAISE EXCEPTION 'school_entitlements_denied' USING ERRCODE='42501';
  END IF;
  core := drivy.platform_client_entitlement_core((SELECT c.id FROM drivy.platform_client c WHERE c.school_id = p_school));
  RETURN jsonb_build_object('state', core->'state', 'lifecycle', core->'lifecycle', 'restriction', core->'restriction',
    'trialEndsAt', CASE WHEN core->>'lifecycle' IN ('TRIAL', 'TRIAL_EXPIRED') THEN core->'trial'->'endsAt' END,
    'paidStartsOn', core->'paidStartsOn', 'terminationOn', core->'terminationOn',
    'modules', (SELECT jsonb_agg(jsonb_build_object('code', e->'code', 'entitled', e->'entitled')) FROM jsonb_array_elements(core->'modules') e),
    'version', core->'version', 'nextChangeAt', core->'nextChangeAt');
END $$;

-- Accès d'un usage nouveau à un module, avec sa raison : ENTITLED, NOT_ENTITLED (hors offre), TRIAL_EXPIRED ou TERMINATED. Le refus dit ainsi
-- quoi faire. Échec fermé : NOT_ENTITLED pour un appelant qui n'est ni l'équipe ni membre de l'école, et pour un module inconnu.
CREATE FUNCTION drivy.school_module_access(p_school uuid, p_module text) RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE core jsonb;
BEGIN
  IF NOT (drivy.current_platform_operator() IS NOT NULL OR drivy.current_school_member(p_school)) THEN RETURN 'NOT_ENTITLED'; END IF;
  core := drivy.platform_client_entitlement_core((SELECT c.id FROM drivy.platform_client c WHERE c.school_id = p_school));
  IF EXISTS(SELECT 1 FROM jsonb_array_elements(core->'modules') e WHERE e->>'code' = p_module AND (e->>'entitled')::boolean) THEN RETURN 'ENTITLED'; END IF;
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(core->'modules') e WHERE e->>'code' = p_module) THEN RETURN 'NOT_ENTITLED'; END IF;
  RETURN coalesce(core->'restriction'->>'reason', 'NOT_ENTITLED');
END $$;

-- Dossier commercial d'une fiche, vu par l'équipe : droits et cycle, jalons, conditions, essai, débuts payants, demandes.
-- `version` = version des droits + nombre de versions de conditions + versions des demandes : l'If-Match de toutes les commandes de ce lot.
CREATE FUNCTION drivy.platform_client_commercial(p_client uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE core jsonb; c drivy.platform_client; today date := drivy.zurich_today(); anchor date;
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  SELECT * INTO c FROM drivy.platform_client WHERE id = p_client;
  IF NOT FOUND THEN RETURN NULL; END IF;
  core := drivy.platform_client_entitlement_core(p_client);
  anchor := (core->>'paidStartsOn')::date;
  RETURN jsonb_build_object(
    'core', core,
    'today', today,
    'termsInForce', (SELECT t.id FROM drivy.platform_terms_at(p_client, today) t WHERE t.id IS NOT NULL),
    'missing', to_jsonb(drivy.platform_terms_missing(p_client, drivy.platform_terms_at(p_client, greatest(today, coalesce(anchor, today))))),
    'milestones', jsonb_build_object(
      'codeIssuedAt', (SELECT min(l.created_at) FROM drivy.school_opening_link l WHERE l.client_id = p_client),
      'schoolCreatedAt', (SELECT l.used_at FROM drivy.school_opening_link l WHERE l.id = c.opened_via_link_id),
      'schoolLinkedAt', c.school_linked_at,
      'activatedAt', (SELECT ss.completed_at FROM drivy.school_setup ss WHERE ss.school_id = c.school_id),
      'trialStartsAt', (SELECT t.starts_at FROM drivy.platform_trial_change t WHERE t.client_id = p_client AND t.sequence = 1),
      'paidStartsOn', anchor),
    'terms', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'sequence', t.sequence, 'currency', t.currency,
        'initialAmount', t.initial_amount, 'initialDiscount', t.initial_discount, 'initialDueOn', t.initial_due_on,
        'monthlyAmount', t.monthly_amount, 'recurringDiscount', t.recurring_discount, 'recurringDiscountMonths', t.recurring_discount_months,
        'paymentTermDays', t.payment_term_days, 'suspensionBilling', t.suspension_billing, 'effectiveFrom', t.effective_from,
        'exceptionReason', t.exception_reason, 'createdAt', t.created_at, 'createdByName', o.display_name) ORDER BY t.sequence DESC), '[]'::jsonb)
      FROM drivy.platform_commercial_terms t LEFT JOIN drivy.platform_operator o ON o.id = t.created_by WHERE t.client_id = p_client),
    'trialChanges', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'sequence', t.sequence, 'kind', t.kind, 'startsAt', t.starts_at,
        'endsAt', t.ends_at, 'reason', t.reason, 'createdAt', t.created_at, 'createdByName', o.display_name) ORDER BY t.sequence DESC), '[]'::jsonb)
      FROM drivy.platform_trial_change t LEFT JOIN drivy.platform_operator o ON o.id = t.created_by WHERE t.client_id = p_client),
    'paidStarts', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'startsOn', p.starts_on, 'termsId', p.terms_id, 'status', p.status,
        'confirmedAt', p.confirmed_at, 'confirmedByName', o.display_name, 'cancelledAt', p.cancelled_at, 'cancelledByName', x.display_name,
        'cancelReason', p.cancel_reason) ORDER BY p.confirmed_at DESC, p.id DESC), '[]'::jsonb)
      FROM drivy.platform_paid_start p LEFT JOIN drivy.platform_operator o ON o.id = p.confirmed_by
      LEFT JOIN drivy.platform_operator x ON x.id = p.cancelled_by WHERE p.client_id = p_client),
    'requests', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'status', r.status, 'requestedOn', r.requested_on,
        'requestedOfferId', r.requested_offer_id, 'requestedOfferName', r.requested_offer_name, 'desiredOn', r.desired_on, 'details', r.details,
        'response', r.response, 'effectiveOn', r.effective_on, 'assignmentId', r.assignment_id, 'decidedAt', r.decided_at,
        'decidedByName', d.display_name, 'version', r.version, 'createdAt', r.created_at, 'createdByName', o.display_name, 'updatedAt', r.updated_at)
        ORDER BY r.created_at DESC, r.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_commercial_request WHERE client_id = p_client ORDER BY created_at DESC, id DESC LIMIT 100) r
      LEFT JOIN drivy.platform_operator o ON o.id = r.created_by LEFT JOIN drivy.platform_operator d ON d.id = r.decided_by),
    'version', (core->>'version')::integer
      + (SELECT count(*)::integer FROM drivy.platform_commercial_terms t WHERE t.client_id = p_client)
      + (SELECT coalesce(sum(r.version), 0)::integer FROM drivy.platform_commercial_request r WHERE r.client_id = p_client));
END $$;

REVOKE ALL ON FUNCTION drivy.school_module_access(uuid, text), drivy.platform_client_commercial(uuid),
  drivy.zurich_today(), drivy.zurich_day_start(date), drivy.is_billing_period_start(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.school_module_access(uuid, text), drivy.platform_client_commercial(uuid),
  drivy.zurich_today(), drivy.zurich_day_start(date), drivy.is_billing_period_start(date, date) TO drivy_app;

-- Fiche (liste et détail) : on ajoute le cycle de vie et ce qu'il faut pour annoncer la prochaine échéance (début payant, version de conditions
-- complète ou non, résiliation). Le reste de la projection est celui de R01-T03.
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
    'entitlement_version', m.ent->'version', 'lifecycle', m.ent->>'lifecycle', 'trial_ends_at', m.ent->'trial'->'endsAt',
    'paid_starts_on', m.ent->'paidStartsOn', 'termination_on', m.ent->'terminationOn',
    'billing_ready', CASE WHEN m.ent->>'paidStartsOn' IS NULL THEN false ELSE cardinality(drivy.platform_terms_missing(m.id,
      drivy.platform_terms_at(m.id, greatest(drivy.zurich_today(), (m.ent->>'paidStartsOn')::date)))) = 0 END,
    'version', m.version, 'created_at', m.created_at, 'updated_at', m.updated_at,
    'preparation', m.preparation, 'latest_code', m.latest_code,
    'school', CASE WHEN m.school_id IS NULL THEN NULL ELSE jsonb_build_object('name', m.school_name, 'status', m.school_status,
      'contact_email', m.school_contact_email, 'contact_phone', m.school_contact_phone, 'setup_step', m.setup_step, 'setup_done', m.setup_done,
      'setup_completed_at', m.setup_completed_at, 'setup_saved_at', m.setup_saved_at) END)
  FROM matching m
  WHERE after_created IS NULL OR (m.created_at, m.id) < (after_created, after_id)
  ORDER BY m.created_at DESC, m.id DESC LIMIT page_size;
END $$;
