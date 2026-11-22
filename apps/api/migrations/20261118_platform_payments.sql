-- R01-T06 (#458) : règlements manuels, affectations aux factures, soldes et retards par école.
-- Un règlement est un fait confirmé à la main par l'équipe Drivy (virement vérifié, espèces reçues) : aucun prestataire d'encaissement, aucun
-- prélèvement, aucune synchronisation bancaire. Une facture n'est réglée que par des affectations de règlements confirmés ou par un avoir ;
-- ni un téléchargement, ni un QR scanné, ni une déclaration de l'école ne la règlent. Aucun booléen « payée » n'est stocké : l'état de règlement
-- se calcule à chaque lecture depuis les écritures valides (`platform_invoice_settlement`), et le même calcul sert l'équipe, l'espace école (#460)
-- et la suspension (#461, `platform_client_debt`).
--
-- Rien ne s'efface : un règlement erroné est annulé ou corrigé par une opération motivée qui garde l'original, son auteur et ses affectations
-- libérées. Un trop-perçu reste visible comme reste non affecté ; il n'est jamais présenté comme remboursé. Seule une régularisation explicite,
-- saisie par un opérateur, consomme ce reste.
--
-- Toute écriture passe par les fonctions ci-dessous (SECURITY DEFINER), sous le verrou de la fiche : le rôle applicatif ne fait que lire.

CREATE TABLE drivy.platform_payment (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  amount integer NOT NULL CHECK (amount BETWEEN 1 AND 100000000),
  currency text NOT NULL DEFAULT 'CHF' CHECK (currency = 'CHF'),
  received_on date NOT NULL,
  method text NOT NULL CHECK (method IN ('BANK_TRANSFER', 'CASH', 'OTHER')),
  reference text CHECK (reference IS NULL OR length(btrim(reference)) BETWEEN 1 AND 140),
  note text CHECK (note IS NULL OR length(btrim(note)) BETWEEN 3 AND 500),
  status text NOT NULL DEFAULT 'RECORDED' CHECK (status IN ('RECORDED', 'VOIDED')),
  -- Règlement remplacé par celui-ci (correction d'une erreur de saisie) : l'original reste, annulé avec la cause CORRECTED.
  corrects_payment_id uuid,
  recorded_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  recorded_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  voided_by uuid REFERENCES drivy.platform_operator(id),
  voided_at timestamptz,
  void_cause text CHECK (void_cause IS NULL OR void_cause IN ('VOIDED', 'CORRECTED')),
  void_reason text CHECK (void_reason IS NULL OR length(btrim(void_reason)) BETWEEN 3 AND 500),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  UNIQUE (client_id, id),
  FOREIGN KEY (client_id, corrects_payment_id) REFERENCES drivy.platform_payment(client_id, id),
  CHECK ((status = 'VOIDED') = (voided_by IS NOT NULL AND voided_at IS NOT NULL AND void_cause IS NOT NULL AND void_reason IS NOT NULL)),
  CHECK (corrects_payment_id IS DISTINCT FROM id)
);
CREATE UNIQUE INDEX platform_payment_corrected_once ON drivy.platform_payment (corrects_payment_id) WHERE corrects_payment_id IS NOT NULL;
CREATE INDEX platform_payment_client ON drivy.platform_payment (client_id, received_on DESC, recorded_at DESC);

-- Affectation d'une part d'un règlement à une facture de la même école (clés composites : aucune affectation croisée entre écoles).
CREATE TABLE drivy.platform_payment_allocation (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  amount integer NOT NULL CHECK (amount BETWEEN 1 AND 100000000),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'RELEASED')),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  released_by uuid REFERENCES drivy.platform_operator(id),
  released_at timestamptz,
  release_cause text CHECK (release_cause IS NULL OR release_cause IN ('MANUAL', 'PAYMENT_VOIDED', 'PAYMENT_CORRECTED')),
  release_reason text CHECK (release_reason IS NULL OR length(btrim(release_reason)) BETWEEN 3 AND 500),
  FOREIGN KEY (client_id, payment_id) REFERENCES drivy.platform_payment(client_id, id),
  FOREIGN KEY (client_id, invoice_id) REFERENCES drivy.platform_invoice(client_id, id),
  CHECK ((status = 'RELEASED') = (released_by IS NOT NULL AND released_at IS NOT NULL AND release_cause IS NOT NULL)),
  CHECK (release_cause IS DISTINCT FROM 'MANUAL' OR release_reason IS NOT NULL)
);
CREATE INDEX platform_payment_allocation_payment ON drivy.platform_payment_allocation (payment_id, created_at);
CREATE INDEX platform_payment_allocation_invoice ON drivy.platform_payment_allocation (invoice_id) WHERE status = 'ACTIVE';

-- Régularisation explicite du reste non affecté d'un règlement : remboursement effectué par l'équipe, ou autre motif. Jamais déduite d'un avoir
-- ni d'une correction de saisie.
CREATE TABLE drivy.platform_payment_regularization (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL,
  payment_id uuid NOT NULL,
  amount integer NOT NULL CHECK (amount BETWEEN 1 AND 100000000),
  kind text NOT NULL CHECK (kind IN ('REFUND_RECORDED', 'OTHER')),
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'CANCELLED')),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  cancelled_by uuid REFERENCES drivy.platform_operator(id),
  cancelled_at timestamptz,
  cancel_reason text CHECK (cancel_reason IS NULL OR length(btrim(cancel_reason)) BETWEEN 3 AND 500),
  FOREIGN KEY (client_id, payment_id) REFERENCES drivy.platform_payment(client_id, id),
  CHECK ((status = 'CANCELLED') = (cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL AND cancel_reason IS NOT NULL))
);
CREATE INDEX platform_payment_regularization_payment ON drivy.platform_payment_regularization (payment_id, created_at);

ALTER TABLE drivy.platform_payment ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_payment FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_payment_allocation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_payment_allocation FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_payment_regularization ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_payment_regularization FORCE ROW LEVEL SECURITY;

-- Le propriétaire (fonctions SECURITY DEFINER) lit, insère et met à jour ; aucune politique de suppression.
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_payment_owner_read ON drivy.platform_payment FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_payment_owner_insert ON drivy.platform_payment FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_payment_owner_update ON drivy.platform_payment FOR UPDATE TO %I USING(true) WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_allocation_owner_read ON drivy.platform_payment_allocation FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_allocation_owner_insert ON drivy.platform_payment_allocation FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_allocation_owner_update ON drivy.platform_payment_allocation FOR UPDATE TO %I USING(true) WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_regularization_owner_read ON drivy.platform_payment_regularization FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_regularization_owner_insert ON drivy.platform_payment_regularization FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_regularization_owner_update ON drivy.platform_payment_regularization FOR UPDATE TO %I USING(true) WITH CHECK(true)', current_user);
END $$;

-- L'équipe lit ; une école ne lit rien (sa vue relève de #460).
CREATE POLICY platform_payment_read ON drivy.platform_payment FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_allocation_read ON drivy.platform_payment_allocation FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_regularization_read ON drivy.platform_payment_regularization FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
GRANT SELECT ON drivy.platform_payment, drivy.platform_payment_allocation, drivy.platform_payment_regularization TO drivy_app;

-- --- Calculs : une seule définition, relue par l'API, l'espace école et la suspension ----------------------------------------------------
-- Reste disponible d'un règlement : montant moins affectations actives et régularisations actives. Zéro pour un règlement annulé.
CREATE FUNCTION drivy.platform_payment_available(p_payment uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT CASE WHEN p.status <> 'RECORDED' THEN 0 ELSE (p.amount
    - coalesce((SELECT sum(a.amount) FROM drivy.platform_payment_allocation a WHERE a.payment_id = p.id AND a.status = 'ACTIVE'), 0)
    - coalesce((SELECT sum(r.amount) FROM drivy.platform_payment_regularization r WHERE r.payment_id = p.id AND r.status = 'ACTIVE'), 0))::integer END
  FROM drivy.platform_payment p WHERE p.id = p_payment
$$;

-- Règlement d'une facture émise (pas d'un avoir) : montant affecté, montant crédité, solde, état (PAID, PARTIAL, UNPAID, CREDITED) et retard.
-- NULL pour un brouillon, une facture annulée ou un avoir.
CREATE FUNCTION drivy.platform_invoice_settlement(p_invoice uuid, p_today date DEFAULT drivy.zurich_today()) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT CASE WHEN i.status <> 'ISSUED' OR i.kind = 'CREDIT_NOTE' THEN NULL ELSE jsonb_build_object(
      'allocated', a.allocated, 'credited', c.credited, 'balance', b.balance,
      'state', CASE WHEN c.credited > 0 THEN 'CREDITED' WHEN b.balance = 0 THEN 'PAID' WHEN a.allocated > 0 THEN 'PARTIAL' ELSE 'UNPAID' END,
      'overdue', b.balance > 0 AND i.due_on < p_today) END
  FROM drivy.platform_invoice i
  CROSS JOIN LATERAL (SELECT coalesce(sum(x.amount), 0)::integer AS allocated FROM drivy.platform_payment_allocation x
    WHERE x.invoice_id = i.id AND x.status = 'ACTIVE') a
  CROSS JOIN LATERAL (SELECT coalesce(sum(n.total), 0)::integer AS credited FROM drivy.platform_invoice n
    WHERE n.credits_invoice_id = i.id AND n.kind = 'CREDIT_NOTE' AND n.status = 'ISSUED') c
  CROSS JOIN LATERAL (SELECT CASE WHEN c.credited > 0 THEN 0 ELSE greatest(coalesce(i.total, 0) - a.allocated, 0) END AS balance) b
  WHERE i.id = p_invoice
$$;

-- Dette d'une école à un jour donné : solde ouvert, montant et nombre de factures en retard, plus ancienne échéance encore due, reste non affecté.
-- La suspension (#461) l'appellera sous `platform_client_lock` : un règlement enregistré sous le même verrou est vu, ou attend, jamais à moitié.
CREATE FUNCTION drivy.platform_client_debt(p_client uuid, p_today date DEFAULT drivy.zurich_today()) RETURNS jsonb
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  WITH s AS (
    SELECT i.due_on, drivy.platform_invoice_settlement(i.id, p_today) AS st FROM drivy.platform_invoice i
    WHERE i.client_id = p_client AND i.status = 'ISSUED' AND i.kind <> 'CREDIT_NOTE'
  ), v AS (SELECT due_on, (st->>'balance')::integer AS balance, (st->>'overdue')::boolean AS overdue FROM s)
  SELECT jsonb_build_object(
    'outstanding', coalesce(sum(v.balance), 0),
    'overdueAmount', coalesce(sum(v.balance) FILTER (WHERE v.overdue), 0),
    'overdueCount', count(*) FILTER (WHERE v.overdue),
    'oldestOverdueDueOn', min(v.due_on) FILTER (WHERE v.overdue),
    'unallocated', (SELECT coalesce(sum(drivy.platform_payment_available(p.id)), 0) FROM drivy.platform_payment p
      WHERE p.client_id = p_client AND p.status = 'RECORDED'))
  FROM v
$$;

-- --- Gardes : aucune suppression, aucune réécriture ; seuls les passages prévus sont permis ------------------------------------------------
CREATE FUNCTION drivy.platform_payment_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_payment_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'RECORDED' OR NEW.version <> 1 THEN RAISE EXCEPTION 'platform_payment_fixed' USING ERRCODE='23514'; END IF;
    IF NEW.received_on > drivy.zurich_today() THEN RAISE EXCEPTION 'platform_payment_future' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'RECORDED' AND NEW.status = 'VOIDED' AND NEW.version = OLD.version + 1
    AND (to_jsonb(NEW) - ARRAY['status', 'voided_by', 'voided_at', 'void_cause', 'void_reason', 'version'])
      = (to_jsonb(OLD) - ARRAY['status', 'voided_by', 'voided_at', 'void_cause', 'void_reason', 'version']) THEN
    IF EXISTS(SELECT 1 FROM drivy.platform_payment_allocation a WHERE a.payment_id = OLD.id AND a.status = 'ACTIVE') THEN
      RAISE EXCEPTION 'platform_payment_allocated' USING ERRCODE='23514';
    END IF;
    IF EXISTS(SELECT 1 FROM drivy.platform_payment_regularization r WHERE r.payment_id = OLD.id AND r.status = 'ACTIVE') THEN
      RAISE EXCEPTION 'platform_payment_regularized' USING ERRCODE='23514';
    END IF;
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'platform_payment_fixed' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION drivy.platform_payment_guard() FROM PUBLIC;
CREATE TRIGGER platform_payment_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_payment FOR EACH ROW EXECUTE FUNCTION drivy.platform_payment_guard();

-- Une affectation ne dépasse ni le reste du règlement ni le solde de la facture ; elle vise une facture émise, ni avoir ni créditée.
CREATE FUNCTION drivy.platform_payment_allocation_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE pay drivy.platform_payment; inv drivy.platform_invoice; settlement jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_allocation_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'ACTIVE' OR NEW.released_at IS NOT NULL THEN RAISE EXCEPTION 'platform_allocation_fixed' USING ERRCODE='23514'; END IF;
    SELECT p.* INTO pay FROM drivy.platform_payment p WHERE p.id = NEW.payment_id;
    IF pay.status IS DISTINCT FROM 'RECORDED' THEN RAISE EXCEPTION 'platform_payment_voided' USING ERRCODE='23514'; END IF;
    SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = NEW.invoice_id;
    IF inv.id IS NULL OR inv.client_id <> pay.client_id THEN RAISE EXCEPTION 'platform_payment_other_client' USING ERRCODE='23514'; END IF;
    IF inv.status <> 'ISSUED' OR inv.kind = 'CREDIT_NOTE' THEN RAISE EXCEPTION 'platform_payment_invoice_invalid' USING ERRCODE='23514'; END IF;
    settlement := drivy.platform_invoice_settlement(inv.id);
    IF settlement->>'state' = 'CREDITED' THEN RAISE EXCEPTION 'platform_invoice_credited' USING ERRCODE='23514'; END IF;
    IF NEW.amount > drivy.platform_payment_available(pay.id) THEN RAISE EXCEPTION 'platform_payment_exceeds_available' USING ERRCODE='23514'; END IF;
    IF NEW.amount > (settlement->>'balance')::integer THEN RAISE EXCEPTION 'platform_payment_exceeds_balance' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'ACTIVE' AND NEW.status = 'RELEASED'
    AND (to_jsonb(NEW) - ARRAY['status', 'released_by', 'released_at', 'release_cause', 'release_reason'])
      = (to_jsonb(OLD) - ARRAY['status', 'released_by', 'released_at', 'release_cause', 'release_reason']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'platform_allocation_fixed' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION drivy.platform_payment_allocation_guard() FROM PUBLIC;
CREATE TRIGGER platform_payment_allocation_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_payment_allocation
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_payment_allocation_guard();

CREATE FUNCTION drivy.platform_payment_regularization_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE pay drivy.platform_payment;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_regularization_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'ACTIVE' OR NEW.cancelled_at IS NOT NULL THEN RAISE EXCEPTION 'platform_regularization_fixed' USING ERRCODE='23514'; END IF;
    SELECT p.* INTO pay FROM drivy.platform_payment p WHERE p.id = NEW.payment_id;
    IF pay.status IS DISTINCT FROM 'RECORDED' THEN RAISE EXCEPTION 'platform_payment_voided' USING ERRCODE='23514'; END IF;
    IF NEW.amount > drivy.platform_payment_available(pay.id) THEN RAISE EXCEPTION 'platform_payment_exceeds_available' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'ACTIVE' AND NEW.status = 'CANCELLED'
    AND (to_jsonb(NEW) - ARRAY['status', 'cancelled_by', 'cancelled_at', 'cancel_reason'])
      = (to_jsonb(OLD) - ARRAY['status', 'cancelled_by', 'cancelled_at', 'cancel_reason']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'platform_regularization_fixed' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION drivy.platform_payment_regularization_guard() FROM PUBLIC;
CREATE TRIGGER platform_payment_regularization_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_payment_regularization
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_payment_regularization_guard();

-- Un avoir ne s'émet pas sur une facture qui porte des règlements : ils doivent d'abord être libérés, sinon l'argent reçu disparaîtrait du solde
-- sans réapparaître comme reste non affecté.
CREATE FUNCTION drivy.platform_invoice_paid_credit_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF NEW.kind = 'CREDIT_NOTE' AND EXISTS(SELECT 1 FROM drivy.platform_payment_allocation a
      WHERE a.invoice_id = NEW.credits_invoice_id AND a.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'platform_invoice_paid' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_invoice_paid_credit_guard() FROM PUBLIC;
CREATE TRIGGER platform_invoice_paid_credit_guard BEFORE INSERT ON drivy.platform_invoice
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_invoice_paid_credit_guard();

-- --- Écritures internes (sans droit pour le rôle applicatif) -----------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_payment_allocate_as(p_payment uuid, p_invoice uuid, p_amount integer, p_actor uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_client uuid; v_invoice_client uuid; v_id uuid := gen_random_uuid();
BEGIN
  SELECT p.client_id INTO v_client FROM drivy.platform_payment p WHERE p.id = p_payment;
  SELECT i.client_id INTO v_invoice_client FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF v_invoice_client IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  IF v_invoice_client <> v_client THEN RAISE EXCEPTION 'platform_payment_other_client' USING ERRCODE='23514'; END IF;
  INSERT INTO drivy.platform_payment_allocation(id, client_id, payment_id, invoice_id, amount, created_by)
    VALUES(v_id, v_client, p_payment, p_invoice, p_amount, p_actor);
  RETURN v_id;
END $$;

-- Affecte le reste d'un règlement aux factures ouvertes de l'école, de la plus ancienne échéance à la plus récente, ou seulement aux factures
-- données, dans leur ordre. Chaque part vaut le plus petit du reste et du solde : rien n'est affecté au-delà.
CREATE FUNCTION drivy.platform_payment_spread_as(p_payment uuid, p_actor uuid, p_invoices uuid[]) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_client uuid; target record; share integer; remaining integer; n integer := 0;
BEGIN
  SELECT p.client_id INTO v_client FROM drivy.platform_payment p WHERE p.id = p_payment;
  FOR target IN
    SELECT i.id, (drivy.platform_invoice_settlement(i.id)->>'balance')::integer AS balance
    FROM drivy.platform_invoice i
    LEFT JOIN LATERAL (SELECT array_position(p_invoices, i.id) AS position) o ON true
    WHERE i.client_id = v_client AND i.status = 'ISSUED' AND i.kind <> 'CREDIT_NOTE'
      AND (p_invoices IS NULL OR i.id = ANY(p_invoices))
    ORDER BY o.position NULLS LAST, i.due_on, i.issued_on, i.number
  LOOP
    remaining := drivy.platform_payment_available(p_payment);
    EXIT WHEN remaining <= 0;
    share := least(remaining, coalesce(target.balance, 0));
    IF share > 0 THEN
      PERFORM drivy.platform_payment_allocate_as(p_payment, target.id, share, p_actor);
      n := n + 1;
    END IF;
  END LOOP;
  RETURN n;
END $$;

-- --- Commandes de l'équipe : l'acteur est toujours l'opérateur relu en base -------------------------------------------------------------
-- Saisie : refuse une autre devise, une réception future et un doublon probable (même école, même montant, et même référence ou réception à
-- trois jours près) sauf confirmation explicite. Deux virements réellement distincts restent possibles ; l'idempotence d'un double clic repose
-- sur l'identifiant d'opération de la commande, pas sur ce contrôle. Les affectations sont données, ou réparties d'office (`p_spread`).
CREATE FUNCTION drivy.platform_payment_record(p_id uuid, p_client uuid, p_amount integer, p_currency text, p_received_on date, p_method text,
  p_reference text, p_note text, p_allocations jsonb, p_spread boolean, p_confirm_duplicate boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); v_reference text := nullif(btrim(p_reference), ''); item jsonb;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_client c WHERE c.id = p_client) THEN RAISE EXCEPTION 'platform_payment_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(p_client);
  IF p_currency IS DISTINCT FROM 'CHF' THEN RAISE EXCEPTION 'platform_payment_currency' USING ERRCODE='23514'; END IF;
  IF p_received_on > drivy.zurich_today() THEN RAISE EXCEPTION 'platform_payment_future' USING ERRCODE='23514'; END IF;
  IF p_spread AND jsonb_array_length(coalesce(p_allocations, '[]'::jsonb)) > 0 THEN
    RAISE EXCEPTION 'platform_payment_allocation_mode' USING ERRCODE='23514';
  END IF;
  IF NOT coalesce(p_confirm_duplicate, false) AND EXISTS(SELECT 1 FROM drivy.platform_payment q
      WHERE q.client_id = p_client AND q.status = 'RECORDED' AND q.amount = p_amount
        AND ((v_reference IS NOT NULL AND lower(q.reference) = lower(v_reference)) OR abs(q.received_on - p_received_on) <= 3)) THEN
    RAISE EXCEPTION 'platform_payment_possible_duplicate' USING ERRCODE='23514';
  END IF;
  INSERT INTO drivy.platform_payment(id, client_id, amount, received_on, method, reference, note, recorded_by)
    VALUES(p_id, p_client, p_amount, p_received_on, p_method, v_reference, nullif(btrim(p_note), ''), actor);
  IF p_spread THEN
    PERFORM drivy.platform_payment_spread_as(p_id, actor, NULL);
  ELSE
    FOR item IN SELECT value FROM jsonb_array_elements(coalesce(p_allocations, '[]'::jsonb)) LOOP
      PERFORM drivy.platform_payment_allocate_as(p_id, (item->>'invoiceId')::uuid, (item->>'amount')::integer, actor);
    END LOOP;
  END IF;
  RETURN p_id;
END $$;

-- Lit un règlement, prend le verrou de sa fiche, puis le relit verrouillé.
CREATE FUNCTION drivy.platform_payment_locked(p_payment uuid) RETURNS drivy.platform_payment
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE pay drivy.platform_payment;
BEGIN
  SELECT p.* INTO pay FROM drivy.platform_payment p WHERE p.id = p_payment;
  IF pay.id IS NULL THEN RAISE EXCEPTION 'platform_payment_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(pay.client_id);
  SELECT p.* INTO pay FROM drivy.platform_payment p WHERE p.id = p_payment FOR UPDATE;
  RETURN pay;
END $$;

-- Affecte une part d'un règlement enregistré à une facture de la même école.
CREATE FUNCTION drivy.platform_payment_allocate(p_payment uuid, p_invoice uuid, p_amount integer) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); pay drivy.platform_payment := drivy.platform_payment_locked(p_payment);
BEGIN
  IF pay.status <> 'RECORDED' THEN RAISE EXCEPTION 'platform_payment_voided' USING ERRCODE='23514'; END IF;
  RETURN drivy.platform_payment_allocate_as(pay.id, p_invoice, p_amount, actor);
END $$;

-- Libère une affectation (motif requis) : la part revient au reste du règlement, le solde de la facture remonte. L'affectation reste lisible.
CREATE FUNCTION drivy.platform_payment_release(p_allocation uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); alloc drivy.platform_payment_allocation;
BEGIN
  SELECT a.* INTO alloc FROM drivy.platform_payment_allocation a WHERE a.id = p_allocation;
  IF alloc.id IS NULL THEN RAISE EXCEPTION 'platform_allocation_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(alloc.client_id);
  SELECT a.* INTO alloc FROM drivy.platform_payment_allocation a WHERE a.id = p_allocation FOR UPDATE;
  IF alloc.status <> 'ACTIVE' THEN RAISE EXCEPTION 'platform_allocation_released' USING ERRCODE='23514'; END IF;
  UPDATE drivy.platform_payment_allocation SET status = 'RELEASED', released_by = actor, released_at = date_trunc('milliseconds', clock_timestamp()),
    release_cause = 'MANUAL', release_reason = p_reason WHERE id = p_allocation;
  RETURN p_allocation;
END $$;

CREATE FUNCTION drivy.platform_payment_release_all_as(p_payment uuid, p_actor uuid, p_cause text) RETURNS uuid[]
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE released uuid[];
BEGIN
  SELECT coalesce(array_agg(a.invoice_id ORDER BY a.created_at, a.id), '{}') INTO released FROM drivy.platform_payment_allocation a
    WHERE a.payment_id = p_payment AND a.status = 'ACTIVE';
  UPDATE drivy.platform_payment_allocation SET status = 'RELEASED', released_by = p_actor,
    released_at = date_trunc('milliseconds', clock_timestamp()), release_cause = p_cause
    WHERE payment_id = p_payment AND status = 'ACTIVE';
  RETURN released;
END $$;

-- Annulation d'une erreur de saisie (motif requis) : les affectations sont libérées, le règlement reste lisible avec son auteur. Une régularisation
-- active doit d'abord être annulée.
CREATE FUNCTION drivy.platform_payment_void(p_payment uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); pay drivy.platform_payment := drivy.platform_payment_locked(p_payment);
BEGIN
  IF pay.status <> 'RECORDED' THEN RAISE EXCEPTION 'platform_payment_voided' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_payment_regularization r WHERE r.payment_id = pay.id AND r.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'platform_payment_regularized' USING ERRCODE='23514';
  END IF;
  PERFORM drivy.platform_payment_release_all_as(pay.id, actor, 'PAYMENT_VOIDED');
  UPDATE drivy.platform_payment SET status = 'VOIDED', voided_by = actor, voided_at = date_trunc('milliseconds', clock_timestamp()),
    void_cause = 'VOIDED', void_reason = p_reason, version = pay.version + 1 WHERE id = pay.id;
  RETURN pay.id;
END $$;

-- Correction d'une erreur de saisie : l'original est annulé (cause CORRECTED) et garde son auteur ; un nouveau règlement le remplace, puis
-- reprend les factures de l'original dans le même ordre, jusqu'à son nouveau montant et au solde de chacune.
CREATE FUNCTION drivy.platform_payment_correct(p_payment uuid, p_id uuid, p_amount integer, p_currency text, p_received_on date, p_method text,
  p_reference text, p_note text, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); pay drivy.platform_payment := drivy.platform_payment_locked(p_payment);
  v_reference text := nullif(btrim(p_reference), ''); v_note text := nullif(btrim(p_note), ''); invoices uuid[];
BEGIN
  IF pay.status <> 'RECORDED' THEN RAISE EXCEPTION 'platform_payment_voided' USING ERRCODE='23514'; END IF;
  IF p_currency IS DISTINCT FROM 'CHF' THEN RAISE EXCEPTION 'platform_payment_currency' USING ERRCODE='23514'; END IF;
  IF p_received_on > drivy.zurich_today() THEN RAISE EXCEPTION 'platform_payment_future' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_payment_regularization r WHERE r.payment_id = pay.id AND r.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'platform_payment_regularized' USING ERRCODE='23514';
  END IF;
  IF pay.amount = p_amount AND pay.received_on = p_received_on AND pay.method = p_method AND pay.reference IS NOT DISTINCT FROM v_reference
    AND pay.note IS NOT DISTINCT FROM v_note THEN
    RAISE EXCEPTION 'platform_payment_unchanged' USING ERRCODE='23514';
  END IF;
  invoices := drivy.platform_payment_release_all_as(pay.id, actor, 'PAYMENT_CORRECTED');
  UPDATE drivy.platform_payment SET status = 'VOIDED', voided_by = actor, voided_at = date_trunc('milliseconds', clock_timestamp()),
    void_cause = 'CORRECTED', void_reason = p_reason, version = pay.version + 1 WHERE id = pay.id;
  INSERT INTO drivy.platform_payment(id, client_id, amount, received_on, method, reference, note, corrects_payment_id, recorded_by)
    VALUES(p_id, pay.client_id, p_amount, p_received_on, p_method, v_reference, v_note, pay.id, actor);
  IF cardinality(invoices) > 0 THEN PERFORM drivy.platform_payment_spread_as(p_id, actor, invoices); END IF;
  RETURN p_id;
END $$;

-- Régularisation explicite d'une part du reste non affecté (remboursement effectué par l'équipe, ou autre motif).
CREATE FUNCTION drivy.platform_payment_regularize(p_payment uuid, p_id uuid, p_amount integer, p_kind text, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); pay drivy.platform_payment := drivy.platform_payment_locked(p_payment);
BEGIN
  IF pay.status <> 'RECORDED' THEN RAISE EXCEPTION 'platform_payment_voided' USING ERRCODE='23514'; END IF;
  INSERT INTO drivy.platform_payment_regularization(id, client_id, payment_id, amount, kind, reason, created_by)
    VALUES(p_id, pay.client_id, pay.id, p_amount, p_kind, p_reason, actor);
  RETURN p_id;
END $$;

CREATE FUNCTION drivy.platform_payment_regularization_cancel(p_regularization uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); reg drivy.platform_payment_regularization;
BEGIN
  SELECT r.* INTO reg FROM drivy.platform_payment_regularization r WHERE r.id = p_regularization;
  IF reg.id IS NULL THEN RAISE EXCEPTION 'platform_regularization_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(reg.client_id);
  SELECT r.* INTO reg FROM drivy.platform_payment_regularization r WHERE r.id = p_regularization FOR UPDATE;
  IF reg.status <> 'ACTIVE' THEN RAISE EXCEPTION 'platform_regularization_cancelled' USING ERRCODE='23514'; END IF;
  UPDATE drivy.platform_payment_regularization SET status = 'CANCELLED', cancelled_by = actor,
    cancelled_at = date_trunc('milliseconds', clock_timestamp()), cancel_reason = p_reason WHERE id = p_regularization;
  RETURN p_regularization;
END $$;

-- Version de la facturation d'une fiche : elle croît aussi à chaque règlement, affectation, libération et régularisation.
CREATE OR REPLACE FUNCTION drivy.platform_client_billing_version(p_client uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT (1 + coalesce((SELECT sum(i.version) FROM drivy.platform_invoice i WHERE i.client_id = p_client), 0)
    + (SELECT count(*) + count(*) FILTER (WHERE a.status = 'STOPPED') FROM drivy.platform_billing_activation a WHERE a.client_id = p_client)
    + coalesce((SELECT sum(p.version) FROM drivy.platform_payment p WHERE p.client_id = p_client), 0)
    + (SELECT count(*) + count(*) FILTER (WHERE x.status = 'RELEASED') FROM drivy.platform_payment_allocation x WHERE x.client_id = p_client)
    + (SELECT count(*) + count(*) FILTER (WHERE r.status = 'CANCELLED') FROM drivy.platform_payment_regularization r WHERE r.client_id = p_client))::integer
$$;

REVOKE ALL ON FUNCTION drivy.platform_payment_available(uuid), drivy.platform_invoice_settlement(uuid, date), drivy.platform_client_debt(uuid, date),
  drivy.platform_payment_allocate_as(uuid, uuid, integer, uuid), drivy.platform_payment_spread_as(uuid, uuid, uuid[]),
  drivy.platform_payment_record(uuid, uuid, integer, text, date, text, text, text, jsonb, boolean, boolean), drivy.platform_payment_locked(uuid),
  drivy.platform_payment_allocate(uuid, uuid, integer), drivy.platform_payment_release(uuid, text), drivy.platform_payment_release_all_as(uuid, uuid, text),
  drivy.platform_payment_void(uuid, text), drivy.platform_payment_correct(uuid, uuid, integer, text, date, text, text, text, text),
  drivy.platform_payment_regularize(uuid, uuid, integer, text, text), drivy.platform_payment_regularization_cancel(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION drivy.platform_client_billing_version(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.platform_payment_available(uuid), drivy.platform_invoice_settlement(uuid, date), drivy.platform_client_debt(uuid, date),
  drivy.platform_payment_record(uuid, uuid, integer, text, date, text, text, text, jsonb, boolean, boolean),
  drivy.platform_payment_allocate(uuid, uuid, integer), drivy.platform_payment_release(uuid, text), drivy.platform_payment_void(uuid, text),
  drivy.platform_payment_correct(uuid, uuid, integer, text, date, text, text, text, text), drivy.platform_payment_regularize(uuid, uuid, integer, text, text),
  drivy.platform_payment_regularization_cancel(uuid, text), drivy.platform_client_billing_version(uuid) TO drivy_app;
