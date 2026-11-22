-- R01-T08 (#460) : espace abonnement, factures et demandes de l'école.
-- L'école lit une projection dédiée, sans note interne, motif d'exception, nom d'opérateur ni référence bancaire. Elle dépose des demandes ; seul un
-- opérateur les décide. Rien ici ne change une offre, un module, une facture ou une date de résiliation au moment de la demande.
-- Le droit commercial (`current_school_commercial`) ne dépend pas de l'état de l'école : facture, contact et régularisation restent ouverts
-- pendant un essai expiré, une suspension ou après une résiliation. Aucune donnée n'est créée par cette migration.

-- --- Droit commercial de l'école ------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.current_school_commercial(p_school uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT p_school = nullif(current_setting('app.school_id', true), '')::uuid AND EXISTS(
    SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id = m.person_id
    WHERE m.school_id = p_school AND m.person_id = nullif(current_setting('app.person_id', true), '')::uuid
      AND m.status = 'ACTIVE' AND p.status = 'ACTIVE' AND 'ADMIN' = ANY(m.roles))
$$;
REVOKE ALL ON FUNCTION drivy.current_school_commercial(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.current_school_commercial(uuid) TO drivy_app;

CREATE POLICY school_commercial_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_school_commercial(school_id)
  AND command_type IN ('CREATE_SUBSCRIPTION_REQUEST', 'WITHDRAW_SUBSCRIPTION_REQUEST', 'ACKNOWLEDGE_SUBSCRIPTION_NOTICES'));
CREATE POLICY school_commercial_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_school_commercial(school_id)
  AND action IN ('CREATE_SUBSCRIPTION_REQUEST', 'WITHDRAW_SUBSCRIPTION_REQUEST', 'ACKNOWLEDGE_SUBSCRIPTION_NOTICES'));

-- --- Demandes : auteur école, régularisation, révision d'une résiliation ------------------------------------------------------------------------
ALTER TABLE drivy.platform_commercial_request
  ADD COLUMN source text NOT NULL DEFAULT 'OPERATOR' CHECK (source IN ('OPERATOR', 'SCHOOL')),
  ADD COLUMN requested_by_person uuid REFERENCES drivy.person(id),
  ADD COLUMN withdrawn_by_person uuid REFERENCES drivy.person(id),
  ADD COLUMN requested_modules text[] NOT NULL DEFAULT '{}',
  ALTER COLUMN created_by DROP NOT NULL;

DO $$ DECLARE item record; dropped integer := 0; BEGIN
  FOR item IN SELECT c.conname FROM pg_constraint c
    WHERE c.conrelid = 'drivy.platform_commercial_request'::regclass AND c.contype = 'c'
      AND (c.conname IN ('platform_commercial_request_kind_check', 'platform_commercial_request_status_check')
        OR pg_get_constraintdef(c.oid) LIKE '%effective_on IS NOT NULL%'
        OR pg_get_constraintdef(c.oid) LIKE '%decided_at IS NOT NULL%')
  LOOP
    EXECUTE format('ALTER TABLE drivy.platform_commercial_request DROP CONSTRAINT %I', item.conname);
    dropped := dropped + 1;
  END LOOP;
  IF dropped <> 4 THEN RAISE EXCEPTION 'platform_request_constraints_unexpected: %', dropped; END IF;
END $$;

ALTER TABLE drivy.platform_commercial_request
  ADD CONSTRAINT platform_request_kind CHECK (kind IN ('OFFER_CHANGE', 'TERMINATION', 'REGULARIZATION')),
  ADD CONSTRAINT platform_request_status CHECK (status IN ('RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN', 'REVOKED')),
  ADD CONSTRAINT platform_request_effective CHECK ((status IN ('ACCEPTED', 'REVOKED')) = (effective_on IS NOT NULL)),
  ADD CONSTRAINT platform_request_decided_at CHECK ((status IN ('ACCEPTED', 'REFUSED', 'WITHDRAWN', 'REVOKED')) = (decided_at IS NOT NULL)),
  ADD CONSTRAINT platform_request_decider CHECK (CASE
    WHEN status IN ('ACCEPTED', 'REFUSED', 'REVOKED') THEN decided_by IS NOT NULL AND withdrawn_by_person IS NULL
    WHEN status = 'WITHDRAWN' THEN (decided_by IS NULL) <> (withdrawn_by_person IS NULL)
    ELSE decided_by IS NULL AND withdrawn_by_person IS NULL END),
  ADD CONSTRAINT platform_request_author CHECK (
    (source = 'OPERATOR' AND created_by IS NOT NULL AND requested_by_person IS NULL)
    OR (source = 'SCHOOL' AND created_by IS NULL AND requested_by_person IS NOT NULL)),
  ADD CONSTRAINT platform_request_modules CHECK (kind = 'OFFER_CHANGE' OR cardinality(requested_modules) = 0);

-- Une seule demande ouverte par type et par fiche : une reprise ou un double envoi ne crée pas deux demandes contradictoires.
CREATE UNIQUE INDEX platform_request_open ON drivy.platform_commercial_request (client_id, kind) WHERE status IN ('RECEIVED', 'IN_PROGRESS');

-- Après confirmation, un changement de date ou une reprise est une nouvelle décision opérateur, conservée telle quelle.
CREATE TABLE drivy.platform_termination_decision (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  request_id uuid NOT NULL REFERENCES drivy.platform_commercial_request(id),
  request_version integer NOT NULL CHECK (request_version >= 2),
  action text NOT NULL CHECK (action IN ('CHANGE_DATE', 'RESUME')),
  previous_effective_on date NOT NULL,
  new_effective_on date,
  response text NOT NULL CHECK (length(btrim(response)) BETWEEN 3 AND 1000),
  decided_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  decided_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (request_id, request_version),
  CHECK ((action = 'CHANGE_DATE') = (new_effective_on IS NOT NULL))
);
ALTER TABLE drivy.platform_termination_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_termination_decision FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_termination_decision_owner_read ON drivy.platform_termination_decision FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_request_owner_school_create ON drivy.platform_commercial_request FOR INSERT TO %I WITH CHECK(
    source = ''SCHOOL'' AND status = ''RECEIVED'' AND version = 1 AND created_by IS NULL AND requested_by_person IS NOT NULL
    AND updated_by IS NULL AND decided_at IS NULL AND decided_by IS NULL AND effective_on IS NULL AND assignment_id IS NULL AND response IS NULL)', current_user);
  EXECUTE format('CREATE POLICY platform_request_owner_school_withdraw ON drivy.platform_commercial_request FOR UPDATE TO %I
    USING(status IN (''RECEIVED'', ''IN_PROGRESS'')) WITH CHECK(status = ''WITHDRAWN'' AND withdrawn_by_person IS NOT NULL AND decided_by IS NULL)', current_user);
END $$;
CREATE POLICY platform_termination_decision_read ON drivy.platform_termination_decision FOR SELECT TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_termination_decision_create ON drivy.platform_termination_decision FOR INSERT TO drivy_app
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND decided_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_termination_decision TO drivy_app;

DROP POLICY platform_request_decide ON drivy.platform_commercial_request;
CREATE POLICY platform_request_decide ON drivy.platform_commercial_request FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND (status IN ('RECEIVED', 'IN_PROGRESS') OR (kind = 'TERMINATION' AND status = 'ACCEPTED')))
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND updated_by = drivy.current_platform_operator()
    AND (decided_by IS NULL OR decided_by = drivy.current_platform_operator()));

CREATE FUNCTION drivy.platform_termination_decision_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE r drivy.platform_commercial_request; today date := drivy.zurich_today();
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'platform_termination_decision_fixed' USING ERRCODE='23514'; END IF;
  SELECT * INTO r FROM drivy.platform_commercial_request WHERE id = NEW.request_id;
  IF NOT FOUND OR r.client_id <> NEW.client_id OR r.kind <> 'TERMINATION' OR r.status <> 'ACCEPTED'
     OR NEW.request_version <> r.version + 1 OR NEW.previous_effective_on <> r.effective_on THEN
    RAISE EXCEPTION 'platform_termination_undecided' USING ERRCODE='23514';
  END IF;
  IF r.effective_on <= today THEN RAISE EXCEPTION 'platform_termination_effective' USING ERRCODE='23514'; END IF;
  IF NEW.action = 'CHANGE_DATE' AND (NEW.new_effective_on < today OR NEW.new_effective_on = r.effective_on) THEN
    RAISE EXCEPTION 'platform_request_backdated' USING ERRCODE='23514';
  END IF;
  NEW.decided_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_termination_decision_guard() FROM PUBLIC;
CREATE TRIGGER platform_termination_decision_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_termination_decision
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_termination_decision_guard();

CREATE OR REPLACE FUNCTION drivy.platform_request_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_request_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.requested_on > drivy.zurich_today() THEN RAISE EXCEPTION 'platform_request_future' USING ERRCODE='23514'; END IF;
    IF NEW.requested_offer_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM drivy.platform_offer o WHERE o.id = NEW.requested_offer_id
       AND o.name = NEW.requested_offer_name) THEN
      RAISE EXCEPTION 'platform_request_offer' USING ERRCODE='23514';
    END IF;
    IF cardinality(NEW.requested_modules) <> (SELECT count(DISTINCT c) FROM unnest(NEW.requested_modules) c)
       OR EXISTS(SELECT 1 FROM unnest(NEW.requested_modules) c WHERE NOT EXISTS(SELECT 1 FROM drivy.platform_module m WHERE m.code = c)) THEN
      RAISE EXCEPTION 'platform_request_modules' USING ERRCODE='23514';
    END IF;
    NEW.created_at := date_trunc('milliseconds', clock_timestamp()); NEW.updated_at := NEW.created_at;
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.kind <> OLD.kind OR NEW.requested_on <> OLD.requested_on
     OR NEW.requested_offer_id IS DISTINCT FROM OLD.requested_offer_id OR NEW.requested_offer_name IS DISTINCT FROM OLD.requested_offer_name
     OR NEW.desired_on IS DISTINCT FROM OLD.desired_on OR NEW.details IS DISTINCT FROM OLD.details
     OR NEW.created_by IS DISTINCT FROM OLD.created_by OR NEW.created_at <> OLD.created_at OR NEW.source <> OLD.source
     OR NEW.requested_by_person IS DISTINCT FROM OLD.requested_by_person OR NEW.requested_modules <> OLD.requested_modules THEN
    RAISE EXCEPTION 'platform_request_fixed' USING ERRCODE='23514';
  END IF;
  -- Résiliation confirmée : seule une décision déjà enregistrée, avant la date d'effet, peut déplacer la date ou reprendre le service.
  IF OLD.kind = 'TERMINATION' AND OLD.status = 'ACCEPTED' THEN
    IF NEW.status NOT IN ('ACCEPTED', 'REVOKED') OR NEW.assignment_id IS DISTINCT FROM OLD.assignment_id OR NEW.response IS DISTINCT FROM OLD.response THEN
      RAISE EXCEPTION 'platform_request_transition' USING ERRCODE='23514';
    END IF;
    IF OLD.effective_on <= drivy.zurich_today() THEN RAISE EXCEPTION 'platform_termination_effective' USING ERRCODE='23514'; END IF;
    IF NEW.status = 'REVOKED' AND NEW.effective_on <> OLD.effective_on THEN RAISE EXCEPTION 'platform_request_transition' USING ERRCODE='23514'; END IF;
    IF NOT EXISTS(SELECT 1 FROM drivy.platform_termination_decision d WHERE d.request_id = OLD.id AND d.request_version = OLD.version + 1
        AND d.previous_effective_on = OLD.effective_on AND d.decided_by = NEW.decided_by
        AND d.action = CASE WHEN NEW.status = 'REVOKED' THEN 'RESUME' ELSE 'CHANGE_DATE' END
        AND d.new_effective_on IS NOT DISTINCT FROM CASE WHEN NEW.status = 'ACCEPTED' THEN NEW.effective_on END) THEN
      RAISE EXCEPTION 'platform_termination_undecided' USING ERRCODE='23514';
    END IF;
    NEW.decided_at := date_trunc('milliseconds', clock_timestamp());
    NEW.version := OLD.version + 1;
    NEW.updated_at := NEW.decided_at;
    RETURN NEW;
  END IF;
  IF OLD.status NOT IN ('RECEIVED', 'IN_PROGRESS') OR NEW.status IN ('RECEIVED', 'REVOKED') OR (OLD.status = 'IN_PROGRESS' AND NEW.status = 'IN_PROGRESS') THEN
    RAISE EXCEPTION 'platform_request_transition' USING ERRCODE='23514';
  END IF;
  IF NEW.status = 'ACCEPTED' AND NEW.effective_on < drivy.zurich_today() THEN RAISE EXCEPTION 'platform_request_backdated' USING ERRCODE='23514'; END IF;
  IF NEW.status IN ('ACCEPTED', 'REFUSED', 'WITHDRAWN') THEN NEW.decided_at := date_trunc('milliseconds', clock_timestamp());
  ELSE NEW.decided_at := NULL; NEW.decided_by := NULL; END IF;
  NEW.version := OLD.version + 1;
  NEW.updated_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;

-- Une révision porte la version : un If-Match périmé ne passe pas, y compris après une reprise avant effet.
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
      + (SELECT coalesce(sum(1 + (SELECT count(*)::integer FROM drivy.platform_termination_decision d WHERE d.request_id = r.id)
           + CASE WHEN r.status = 'ACCEPTED' AND drivy.zurich_day_start(r.effective_on) <= clock.t THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_commercial_request r, clock WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status IN ('ACCEPTED', 'REVOKED')),
    'nextChangeAt', (SELECT least(
        (SELECT nxt.effective_at FROM nxt),
        (SELECT trial.starts_at FROM trial WHERE trial.starts_at > clock.t),
        (SELECT trial.ends_at FROM trial WHERE trial.ends_at > clock.t),
        (SELECT paid.at FROM paid WHERE paid.at > clock.t),
        (SELECT term.at FROM term WHERE term.at > clock.t)) FROM clock))
$$;

-- La vue opérateur expose en plus l'origine, les modules souhaités et l'historique des révisions.
CREATE OR REPLACE FUNCTION drivy.platform_client_commercial(p_client uuid) RETURNS jsonb
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
        'decidedByName', d.display_name, 'version', r.version, 'createdAt', r.created_at, 'createdByName', coalesce(o.display_name, rp.display_name),
        'updatedAt', r.updated_at, 'source', r.source, 'requestedModules', to_jsonb(r.requested_modules), 'withdrawnBySchool', r.withdrawn_by_person IS NOT NULL,
        'revisions', (SELECT coalesce(jsonb_agg(jsonb_build_object('action', x.action, 'previousEffectiveOn', x.previous_effective_on,
            'newEffectiveOn', x.new_effective_on, 'response', x.response, 'decidedAt', x.decided_at, 'decidedByName', xo.display_name)
            ORDER BY x.request_version), '[]'::jsonb)
          FROM drivy.platform_termination_decision x LEFT JOIN drivy.platform_operator xo ON xo.id = x.decided_by WHERE x.request_id = r.id))
        ORDER BY r.created_at DESC, r.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_commercial_request WHERE client_id = p_client ORDER BY created_at DESC, id DESC LIMIT 100) r
      LEFT JOIN drivy.platform_operator o ON o.id = r.created_by LEFT JOIN drivy.person rp ON rp.id = r.requested_by_person
      LEFT JOIN drivy.platform_operator d ON d.id = r.decided_by),
    'version', (core->>'version')::integer
      + (SELECT count(*)::integer FROM drivy.platform_commercial_terms t WHERE t.client_id = p_client)
      + (SELECT coalesce(sum(r.version), 0)::integer FROM drivy.platform_commercial_request r WHERE r.client_id = p_client));
END $$;

-- --- Avis durables ---------------------------------------------------------------------------------------------------------------------------
-- Écrits dans la transaction de la demande : pas d'événement perdu, pas de doublon par rafraîchissement ou reprise.
CREATE TABLE drivy.platform_commercial_notice (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  request_id uuid NOT NULL REFERENCES drivy.platform_commercial_request(id),
  request_version integer NOT NULL CHECK (request_version >= 1),
  event text NOT NULL CHECK (event IN ('RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN', 'DATE_CHANGED', 'RESUMED')),
  audience text NOT NULL CHECK (audience IN ('SCHOOL', 'OPERATOR')),
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (request_id, request_version, event, audience)
);
CREATE INDEX platform_commercial_notice_inbox ON drivy.platform_commercial_notice (audience, client_id, created_at DESC) WHERE read_at IS NULL;
ALTER TABLE drivy.platform_commercial_notice ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_commercial_notice FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_commercial_notice_owner ON drivy.platform_commercial_notice TO %I USING(true) WITH CHECK(true)', current_user);
END $$;

ALTER TABLE drivy.push_notification DROP CONSTRAINT push_notification_category_check;
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_category_check
 CHECK(category IN('OFFER','REMINDER','CHANGE','STAFF','NEW_SESSION','MESSAGE_MENTION','MESSAGE_PRIVATE','MESSAGE_GENERAL',
  'LESSON_REQUEST','LESSON_REQUEST_ANSWER','EXAM','COMMERCIAL'));
ALTER TABLE drivy.push_notification ADD COLUMN commercial_notice_id uuid REFERENCES drivy.platform_commercial_notice(id);
ALTER TABLE drivy.push_notification ADD CONSTRAINT push_notification_commercial_ref
 CHECK((commercial_notice_id IS NOT NULL)=(category='COMMERCIAL'));

CREATE FUNCTION drivy.platform_request_notice() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE ev text; target text; notice uuid; school uuid; message text;
BEGIN
  IF TG_OP = 'INSERT' THEN
    ev := 'RECEIVED';
    target := CASE WHEN NEW.source = 'SCHOOL' THEN 'OPERATOR' ELSE 'SCHOOL' END;
  ELSE
    ev := CASE WHEN NEW.status = 'REVOKED' THEN 'RESUMED' WHEN OLD.status = 'ACCEPTED' THEN 'DATE_CHANGED' ELSE NEW.status END;
    target := CASE WHEN NEW.status = 'WITHDRAWN' AND NEW.withdrawn_by_person IS NOT NULL THEN 'OPERATOR' ELSE 'SCHOOL' END;
  END IF;
  INSERT INTO drivy.platform_commercial_notice(client_id, request_id, request_version, event, audience)
  VALUES (NEW.client_id, NEW.id, NEW.version, ev, target)
  ON CONFLICT (request_id, request_version, event, audience) DO NOTHING RETURNING id INTO notice;
  IF notice IS NULL OR target <> 'SCHOOL' THEN RETURN NULL; END IF;
  SELECT c.school_id INTO school FROM drivy.platform_client c WHERE c.id = NEW.client_id;
  IF school IS NULL THEN RETURN NULL; END IF;
  -- Texte générique : ni montant, ni offre, ni motif sur l'écran verrouillé.
  message := CASE ev WHEN 'RECEIVED' THEN 'Une demande a été enregistrée pour votre école.'
    WHEN 'IN_PROGRESS' THEN 'Votre demande est en cours de traitement.' ELSE 'Drivy a répondu à votre demande.' END;
  INSERT INTO drivy.push_notification(person_id, school_id, category, dedupe_key, title, body, valid_until, commercial_notice_id)
  SELECT m.person_id, school, 'COMMERCIAL', 'commercial:' || NEW.id || ':' || NEW.version || ':' || ev, 'Abonnement', message,
    statement_timestamp() + interval '24 hours', notice
  FROM drivy.membership m JOIN drivy.person p ON p.id = m.person_id
  WHERE m.school_id = school AND m.status = 'ACTIVE' AND p.status = 'ACTIVE' AND 'ADMIN' = ANY(m.roles)
  ON CONFLICT (person_id, dedupe_key) DO NOTHING;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_request_notice() FROM PUBLIC;
CREATE TRIGGER platform_request_notice AFTER INSERT OR UPDATE ON drivy.platform_commercial_request
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_request_notice();

CREATE OR REPLACE FUNCTION drivy.push_revalidate(notification uuid) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE n drivy.push_notification; reason text;
BEGIN
 SELECT * INTO n FROM drivy.push_notification WHERE id=notification FOR UPDATE;
 IF NOT FOUND OR n.status<>'PENDING' THEN RETURN false; END IF;
 IF n.category='COMMERCIAL' THEN
  IF n.valid_until<=statement_timestamp() THEN
   UPDATE drivy.push_notification SET status='EXPIRED' WHERE id=n.id;
   RETURN false;
  END IF;
  -- Une école suspendue ou archivée garde son responsable : seul le droit commercial compte.
  IF NOT EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
    WHERE m.school_id=n.school_id AND m.person_id=n.person_id AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'ADMIN'=ANY(m.roles)) THEN
   reason:='RECIPIENT_INELIGIBLE';
  ELSIF NOT EXISTS(SELECT 1 FROM drivy.platform_commercial_notice c WHERE c.id=n.commercial_notice_id AND c.audience='SCHOOL' AND c.read_at IS NULL) THEN
   reason:='EVENT_OBSOLETE';
  END IF;
  IF reason IS NOT NULL THEN
   UPDATE drivy.push_notification SET status='SKIPPED',failure_code=reason WHERE id=n.id;
   RETURN false;
  END IF;
  RETURN true;
 END IF;
 IF n.category<>'MESSAGE_MENTION' THEN RETURN drivy.course_push_revalidate(notification); END IF;
 IF NOT coalesce((SELECT p.messaging_mentions FROM drivy.notification_preference p WHERE p.person_id=n.person_id),true) THEN
  reason:='PREFERENCE_DISABLED';
 ELSIF NOT EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id JOIN drivy.school s ON s.id=m.school_id
   WHERE m.school_id=n.school_id AND m.person_id=n.person_id AND m.status='ACTIVE' AND p.status='ACTIVE' AND s.status='ACTIVE')
  OR EXISTS(SELECT 1 FROM drivy.messaging_general_removal r JOIN drivy.membership m ON m.school_id=r.school_id AND m.id=r.membership_id AND m.status='ACTIVE'
   WHERE r.school_id=n.school_id AND r.person_id=n.person_id) THEN
  reason:='RECIPIENT_INELIGIBLE';
 ELSIF NOT EXISTS(SELECT 1 FROM drivy.messaging_message msg JOIN drivy.messaging_member_link l
   ON l.school_id=msg.school_id AND l.conversation_id=msg.conversation_id AND l.person_id=n.person_id AND l.cut_sequence IS NULL
   WHERE msg.school_id=n.school_id AND msg.conversation_id=n.conversation_id AND msg.id=n.message_id
    AND msg.deleted_at IS NULL AND msg.sequence>l.readable_after AND n.person_id=ANY(msg.mention_person_ids)) THEN
  reason:='EVENT_OBSOLETE';
 ELSIF EXISTS(SELECT 1 FROM drivy.messaging_read_state rs WHERE rs.school_id=n.school_id AND rs.conversation_id=n.conversation_id
   AND rs.person_id=n.person_id AND rs.muted_until>statement_timestamp()) THEN
  reason:='SILENCED';
 END IF;
 IF reason IS NOT NULL THEN
  UPDATE drivy.push_notification SET status='SKIPPED',failure_code=reason WHERE id=n.id;
  RETURN false;
 END IF;
 RETURN true;
END $$;

-- --- Projection de l'école --------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.school_commercial_terms_json(t drivy.platform_commercial_terms) RETURNS jsonb
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE WHEN t.id IS NULL THEN NULL ELSE jsonb_build_object('currency', t.currency, 'initialAmount', t.initial_amount,
    'initialDiscount', t.initial_discount, 'initialDueOn', t.initial_due_on, 'monthlyAmount', t.monthly_amount,
    'recurringDiscount', t.recurring_discount, 'recurringDiscountMonths', t.recurring_discount_months,
    'paymentTermDays', t.payment_term_days, 'effectiveFrom', t.effective_from) END
$$;
REVOKE ALL ON FUNCTION drivy.school_commercial_terms_json(drivy.platform_commercial_terms) FROM PUBLIC;

CREATE FUNCTION drivy.school_commercial_view(p_school uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE c drivy.platform_client; core jsonb; today date := drivy.zurich_today(); next_terms date; contact jsonb;
BEGIN
  IF NOT drivy.current_school_commercial(p_school) THEN RAISE EXCEPTION 'school_commercial_denied' USING ERRCODE='42501'; END IF;
  SELECT jsonb_build_object('name', i.legal_name, 'email', i.email) INTO contact FROM drivy.platform_billing_issuer i ORDER BY i.sequence DESC LIMIT 1;
  SELECT * INTO c FROM drivy.platform_client WHERE school_id = p_school;
  IF NOT FOUND THEN RETURN jsonb_build_object('hasClient', false, 'today', today, 'contact', contact, 'version', 0); END IF;
  core := drivy.platform_client_entitlement_core(c.id);
  SELECT min(t.effective_from) INTO next_terms FROM drivy.platform_commercial_terms t WHERE t.client_id = c.id AND t.effective_from > today;
  RETURN jsonb_build_object(
    'hasClient', true, 'today', today, 'contact', contact,
    'lifecycle', core->'lifecycle', 'state', core->'state', 'restriction', core->'restriction', 'trial', core->'trial',
    'paidStartsOn', core->'paidStartsOn', 'terminationOn', core->'terminationOn',
    'offer', CASE WHEN core->'assignment' <> 'null'::jsonb THEN jsonb_build_object('name', core->'assignment'->'offerName', 'effectiveAt', core->'assignment'->'effectiveAt') END,
    'scheduledOffer', CASE WHEN core->'scheduled' <> 'null'::jsonb THEN jsonb_build_object('name', core->'scheduled'->'offerName', 'effectiveAt', core->'scheduled'->'effectiveAt') END,
    'modules', (SELECT coalesce(jsonb_agg(jsonb_build_object('code', e->'code', 'inOffer', e->'inOffer', 'entitled', e->'entitled')), '[]'::jsonb)
      FROM jsonb_array_elements(core->'modules') e),
    'terms', drivy.school_commercial_terms_json(drivy.platform_terms_at(c.id, today)),
    'scheduledTerms', CASE WHEN next_terms IS NOT NULL THEN drivy.school_commercial_terms_json(drivy.platform_terms_at(c.id, next_terms)) END,
    'debt', drivy.platform_client_debt(c.id, today),
    'invoices', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'kind', i.kind, 'number', i.number, 'periodStart', i.period_start,
        'periodEnd', i.period_end, 'issuedOn', i.issued_on, 'dueOn', i.due_on, 'taxAmount', i.tax_amount, 'total', i.total,
        'creditsInvoiceNumber', (SELECT o.number FROM drivy.platform_invoice o WHERE o.id = i.credits_invoice_id),
        'settlement', drivy.platform_invoice_settlement(i.id, today),
        'hasDocument', EXISTS(SELECT 1 FROM drivy.platform_invoice_document d WHERE d.invoice_id = i.id))
        ORDER BY i.issued_on DESC, i.number DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_invoice x WHERE x.client_id = c.id AND x.status = 'ISSUED' ORDER BY x.issued_on DESC, x.number DESC LIMIT 200) i),
    'payments', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'amount', p.amount, 'receivedOn', p.received_on, 'method', p.method)
        ORDER BY p.received_on DESC, p.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_payment x WHERE x.client_id = c.id AND x.status = 'RECORDED' ORDER BY x.received_on DESC, x.id DESC LIMIT 200) p),
    'requests', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'status', r.status, 'source', r.source,
        'requestedOn', r.requested_on, 'requestedOfferId', r.requested_offer_id, 'requestedOfferName', r.requested_offer_name,
        'requestedModules', to_jsonb(r.requested_modules), 'desiredOn', r.desired_on,
        'details', CASE WHEN r.source = 'SCHOOL' THEN r.details END, 'response', r.response, 'effectiveOn', r.effective_on,
        'decidedAt', r.decided_at, 'version', r.version, 'createdAt', r.created_at,
        'revisions', (SELECT coalesce(jsonb_agg(jsonb_build_object('action', d.action, 'previousEffectiveOn', d.previous_effective_on,
            'newEffectiveOn', d.new_effective_on, 'response', d.response, 'decidedAt', d.decided_at) ORDER BY d.request_version), '[]'::jsonb)
          FROM drivy.platform_termination_decision d WHERE d.request_id = r.id))
        ORDER BY r.created_at DESC, r.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_commercial_request x WHERE x.client_id = c.id ORDER BY x.created_at DESC, x.id DESC LIMIT 50) r),
    'availableOffers', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'modules', to_jsonb(o.modules)) ORDER BY o.name), '[]'::jsonb)
      FROM drivy.platform_offer o WHERE o.status = 'ACTIVE'),
    'notices', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'requestId', n.request_id, 'event', n.event, 'createdAt', n.created_at)
        ORDER BY n.created_at DESC, n.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_commercial_notice x WHERE x.client_id = c.id AND x.audience = 'SCHOOL' AND x.read_at IS NULL
        ORDER BY x.created_at DESC, x.id DESC LIMIT 20) n),
    'version', (core->>'version')::integer
      + (SELECT count(*)::integer FROM drivy.platform_commercial_terms t WHERE t.client_id = c.id)
      + (SELECT coalesce(sum(r.version), 0)::integer FROM drivy.platform_commercial_request r WHERE r.client_id = c.id));
END $$;

-- --- Commandes de l'école ---------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.school_commercial_request_create(p_school uuid, p_id uuid, p_kind text, p_offer uuid, p_modules text[], p_desired date, p_details text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE client uuid; core jsonb; offer_name text; today date := drivy.zurich_today(); actor uuid := nullif(current_setting('app.person_id', true), '')::uuid;
BEGIN
  IF NOT drivy.current_school_commercial(p_school) THEN RAISE EXCEPTION 'school_commercial_denied' USING ERRCODE='42501'; END IF;
  SELECT c.id INTO client FROM drivy.platform_client c WHERE c.school_id = p_school;
  IF client IS NULL THEN RAISE EXCEPTION 'school_commercial_no_client' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(client);
  core := drivy.platform_client_entitlement_core(client);
  IF p_kind = 'OFFER_CHANGE' AND core->>'terminationOn' IS NOT NULL THEN RAISE EXCEPTION 'platform_client_terminated' USING ERRCODE='23514'; END IF;
  IF p_kind = 'TERMINATION' AND core->>'terminationOn' IS NOT NULL THEN RAISE EXCEPTION 'school_termination_confirmed' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_commercial_request r WHERE r.client_id = client AND r.kind = p_kind AND r.status IN ('RECEIVED', 'IN_PROGRESS')) THEN
    RAISE EXCEPTION 'school_request_open' USING ERRCODE='23514';
  END IF;
  IF p_desired IS NOT NULL AND p_desired < today THEN RAISE EXCEPTION 'platform_request_backdated' USING ERRCODE='23514'; END IF;
  IF p_kind <> 'OFFER_CHANGE' AND (p_offer IS NOT NULL OR cardinality(p_modules) > 0) THEN RAISE EXCEPTION 'platform_request_modules' USING ERRCODE='23514'; END IF;
  IF p_kind = 'OFFER_CHANGE' AND p_offer IS NULL AND cardinality(p_modules) = 0 THEN RAISE EXCEPTION 'platform_request_modules' USING ERRCODE='23514'; END IF;
  IF p_offer IS NOT NULL THEN
    SELECT o.name INTO offer_name FROM drivy.platform_offer o WHERE o.id = p_offer AND o.status = 'ACTIVE';
    IF offer_name IS NULL THEN RAISE EXCEPTION 'platform_offer_archived' USING ERRCODE='23514'; END IF;
  END IF;
  INSERT INTO drivy.platform_commercial_request(id, client_id, kind, requested_on, requested_offer_id, requested_offer_name, requested_modules,
    desired_on, details, source, requested_by_person)
  VALUES (p_id, client, p_kind, today, p_offer, offer_name, p_modules, p_desired, p_details, 'SCHOOL', actor);
  RETURN 1;
END $$;

CREATE FUNCTION drivy.school_commercial_request_withdraw(p_school uuid, p_request uuid, p_expected integer) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE client uuid; r drivy.platform_commercial_request; result integer; actor uuid := nullif(current_setting('app.person_id', true), '')::uuid;
BEGIN
  IF NOT drivy.current_school_commercial(p_school) THEN RAISE EXCEPTION 'school_commercial_denied' USING ERRCODE='42501'; END IF;
  SELECT c.id INTO client FROM drivy.platform_client c WHERE c.school_id = p_school;
  IF client IS NULL THEN RETURN NULL; END IF;
  -- Le verrou de fiche sérialise cette lecture avec toute décision opérateur.
  PERFORM drivy.platform_client_lock(client);
  SELECT * INTO r FROM drivy.platform_commercial_request x WHERE x.id = p_request AND x.client_id = client;
  IF NOT FOUND THEN RETURN NULL; END IF;
  IF r.status NOT IN ('RECEIVED', 'IN_PROGRESS') THEN RAISE EXCEPTION 'platform_request_transition' USING ERRCODE='23514'; END IF;
  IF r.version <> p_expected THEN RAISE EXCEPTION 'school_request_stale' USING ERRCODE='23514'; END IF;
  UPDATE drivy.platform_commercial_request SET status = 'WITHDRAWN', withdrawn_by_person = actor, updated_by = NULL WHERE id = r.id
  RETURNING version INTO result;
  RETURN result;
END $$;

CREATE FUNCTION drivy.school_commercial_notice_read(p_school uuid) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE client uuid; changed integer;
BEGIN
  IF NOT drivy.current_school_commercial(p_school) THEN RAISE EXCEPTION 'school_commercial_denied' USING ERRCODE='42501'; END IF;
  SELECT c.id INTO client FROM drivy.platform_client c WHERE c.school_id = p_school;
  IF client IS NULL THEN RETURN 0; END IF;
  UPDATE drivy.platform_commercial_notice SET read_at = date_trunc('milliseconds', clock_timestamp())
  WHERE client_id = client AND audience = 'SCHOOL' AND read_at IS NULL;
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed;
END $$;

-- Le document conservé d'une facture émise de cette école, sans jamais en générer. Aucune ligne : la facture n'existe pas ici.
CREATE FUNCTION drivy.school_invoice_document(p_school uuid, p_invoice uuid)
RETURNS TABLE(invoice_kind text, invoice_number text, content bytea)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF NOT drivy.current_school_commercial(p_school) THEN RAISE EXCEPTION 'school_commercial_denied' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT i.kind, i.number, (SELECT d.content FROM drivy.platform_invoice_document d WHERE d.invoice_id = i.id ORDER BY d.revision DESC LIMIT 1)
  FROM drivy.platform_invoice i JOIN drivy.platform_client c ON c.id = i.client_id
  WHERE i.id = p_invoice AND c.school_id = p_school AND i.status = 'ISSUED';
END $$;

-- --- Boîte des opérateurs ----------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_commercial_notices() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'clientId', n.client_id, 'clientName', c.display_name, 'requestId', n.request_id,
      'kind', r.kind, 'event', n.event, 'createdAt', n.created_at) ORDER BY n.created_at DESC, n.id DESC), '[]'::jsonb)
    FROM (SELECT * FROM drivy.platform_commercial_notice x WHERE x.audience = 'OPERATOR' AND x.read_at IS NULL ORDER BY x.created_at DESC, x.id DESC LIMIT 50) n
    JOIN drivy.platform_client c ON c.id = n.client_id JOIN drivy.platform_commercial_request r ON r.id = n.request_id);
END $$;

CREATE FUNCTION drivy.platform_commercial_notices_read(p_ids uuid[]) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE changed integer;
BEGIN
  IF drivy.current_platform_operator() IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  UPDATE drivy.platform_commercial_notice SET read_at = date_trunc('milliseconds', clock_timestamp())
  WHERE id = ANY(p_ids) AND audience = 'OPERATOR' AND read_at IS NULL;
  GET DIAGNOSTICS changed = ROW_COUNT;
  RETURN changed;
END $$;

REVOKE ALL ON FUNCTION drivy.school_commercial_view(uuid), drivy.school_commercial_request_create(uuid, uuid, text, uuid, text[], date, text),
  drivy.school_commercial_request_withdraw(uuid, uuid, integer), drivy.school_commercial_notice_read(uuid), drivy.school_invoice_document(uuid, uuid),
  drivy.platform_commercial_notices(), drivy.platform_commercial_notices_read(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.school_commercial_view(uuid), drivy.school_commercial_request_create(uuid, uuid, text, uuid, text[], date, text),
  drivy.school_commercial_request_withdraw(uuid, uuid, integer), drivy.school_commercial_notice_read(uuid), drivy.school_invoice_document(uuid, uuid),
  drivy.platform_commercial_notices(), drivy.platform_commercial_notices_read(uuid[]) TO drivy_app;
