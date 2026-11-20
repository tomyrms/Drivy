-- R01-T05 (#457) : factures initiales et mensuelles, avoirs, échéancier et préparation planifiée.
-- Aucune donnée n'est créée : aucune facture, aucun paramètre d'émetteur, aucune activation. Une école pilote ou reprise n'a rien de facturé
-- tant qu'un opérateur n'a pas confirmé un début payant (R01-T04, jamais rétroactif) ; la préparation planifiée exige en plus une activation
-- explicite, datée d'aujourd'hui ou plus tard, et ne remonte jamais avant elle.
--
-- Rien n'est inventé : la TVA, le numéro d'entreprise, l'IBAN et l'identité de l'émetteur sont des paramètres saisis par l'équipe. Sans eux,
-- une facture reste en brouillon. Montants : entiers en centimes de CHF. Jours : jours civils Europe/Zurich.
--
-- Toute écriture passe par les fonctions ci-dessous (SECURITY DEFINER) : le rôle applicatif ne fait que lire. Une facture émise est figée
-- (numéro, émetteur, destinataire, lignes, taxes, total, dates) ; seul son état d'envoi bouge. Elle se corrige par un avoir, jamais par une
-- suppression ni une renumérotation.

-- --- Calendrier : mêmes règles que `periodStart` et `periodIndexOf` (src/platform-commercial-model.ts) ------------------------------------
CREATE FUNCTION drivy.billing_period_start(p_anchor date, p_index integer) RETURNS date LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT (date_trunc('month', p_anchor::timestamp) + make_interval(months => p_index))::date
    + (least(extract(day FROM p_anchor)::integer,
        extract(day FROM (date_trunc('month', p_anchor::timestamp) + make_interval(months => p_index + 1) - interval '1 day'))::integer) - 1)
$$;
CREATE FUNCTION drivy.billing_period_index(p_anchor date, p_day date) RETURNS integer LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE WHEN p_day < p_anchor THEN -1
    WHEN drivy.billing_period_start(p_anchor, x.m) <= p_day THEN x.m ELSE x.m - 1 END
  FROM (SELECT ((extract(year FROM p_day) - extract(year FROM p_anchor)) * 12 + extract(month FROM p_day) - extract(month FROM p_anchor))::integer AS m) x
$$;

-- --- Émetteur : paramètres versionnés de l'entité qui facture --------------------------------------------------------------------------
CREATE TABLE drivy.platform_billing_issuer (
  id uuid PRIMARY KEY,
  sequence integer NOT NULL UNIQUE CHECK (sequence > 0),
  legal_name text NOT NULL CHECK (length(btrim(legal_name)) BETWEEN 1 AND 150),
  street text NOT NULL CHECK (length(btrim(street)) BETWEEN 1 AND 200),
  postal_code text NOT NULL CHECK (length(btrim(postal_code)) BETWEEN 1 AND 20),
  city text NOT NULL CHECK (length(btrim(city)) BETWEEN 1 AND 100),
  -- Code pays ISO 3166-1 alpha-2 (exigé par la facture QR, #459).
  country text NOT NULL CHECK (country ~ '^[A-Z]{2}$'),
  email text CHECK (email IS NULL OR (email = lower(email) AND length(email) BETWEEN 3 AND 254 AND position('@' IN email) > 1)),
  -- Compte de paiement : facultatif ici (il sera exigé par #459). Forme seulement ; la clé de contrôle est vérifiée par l'API.
  iban text CHECK (iban IS NULL OR iban ~ '^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$'),
  -- NONE : aucune taxe n'est calculée (la mention éventuelle est `tax_note`). VAT : numéro IDE TVA, taux et sens des prix obligatoires.
  tax_mode text NOT NULL CHECK (tax_mode IN ('NONE', 'VAT')),
  vat_number text CHECK (vat_number IS NULL OR vat_number ~ '^CHE-[0-9]{3}\.[0-9]{3}\.[0-9]{3} (TVA|MWST|IVA)$'),
  -- Taux en centièmes de pour cent (810 = 8,1 %).
  tax_rate_bp integer CHECK (tax_rate_bp IS NULL OR tax_rate_bp BETWEEN 1 AND 5000),
  -- Les montants des conditions incluent-ils la taxe ? Aucun défaut : c'est un choix de l'équipe.
  prices_include_tax boolean,
  tax_note text CHECK (tax_note IS NULL OR length(btrim(tax_note)) BETWEEN 3 AND 200),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  CHECK ((tax_mode = 'VAT') = (vat_number IS NOT NULL AND tax_rate_bp IS NOT NULL AND prices_include_tax IS NOT NULL)),
  CHECK (tax_mode = 'VAT' OR (vat_number IS NULL AND tax_rate_bp IS NULL AND prices_include_tax IS NULL))
);

-- --- Activation explicite de la facturation planifiée d'une école ----------------------------------------------------------------------
-- Un essai, un début payant ou des conditions ne suffisent jamais : seule une activation ouvre la préparation planifiée, et seulement pour
-- les périodes qui commencent à sa date ou après (aucun passé facturé à une école reprise).
CREATE TABLE drivy.platform_billing_activation (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  starts_on date NOT NULL,
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'STOPPED')),
  activated_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  activated_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  stopped_by uuid REFERENCES drivy.platform_operator(id),
  stopped_at timestamptz,
  stop_reason text CHECK (stop_reason IS NULL OR length(btrim(stop_reason)) BETWEEN 3 AND 500),
  CHECK ((status = 'STOPPED') = (stopped_by IS NOT NULL AND stopped_at IS NOT NULL AND stop_reason IS NOT NULL))
);
CREATE UNIQUE INDEX platform_billing_activation_active ON drivy.platform_billing_activation (client_id) WHERE status = 'ACTIVE';
CREATE INDEX platform_billing_activation_client ON drivy.platform_billing_activation (client_id, activated_at DESC);

-- --- Numérotation : une série par genre et par année d'émission (Zurich), sans trou --------------------------------------------------------
-- Le numéro est pris dans la transaction qui émet : un échec annule aussi le numéro, un rejeu rend le reçu sans en consommer un autre.
CREATE TABLE drivy.platform_invoice_counter (
  series text NOT NULL CHECK (series IN ('F', 'AV')),
  year integer NOT NULL CHECK (year BETWEEN 2026 AND 2200),
  last integer NOT NULL CHECK (last > 0),
  PRIMARY KEY (series, year)
);

-- --- Factures et avoirs ------------------------------------------------------------------------------------------------------------
-- État documentaire (status), état d'envoi (send_status) et solde (calculé : total moins avoirs émis ; règlements : #458) restent distincts.
-- Montants positifs ; un avoir (CREDIT_NOTE) annule entièrement la facture qu'il désigne. Une facture créditée peut être remplacée par une
-- nouvelle génération de la même période.
CREATE TABLE drivy.platform_invoice (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  kind text NOT NULL CHECK (kind IN ('INITIAL', 'PERIOD', 'CREDIT_NOTE')),
  generation smallint NOT NULL DEFAULT 1 CHECK (generation BETWEEN 1 AND 50),
  status text NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'ISSUED', 'CANCELLED')),
  origin text NOT NULL CHECK (origin IN ('MANUAL', 'SCHEDULED')),
  paid_start_id uuid NOT NULL REFERENCES drivy.platform_paid_start(id),
  period_index integer CHECK (period_index >= 0),
  period_start date,
  period_end date,
  credits_invoice_id uuid REFERENCES drivy.platform_invoice(id),
  terms_id uuid REFERENCES drivy.platform_commercial_terms(id),
  terms_sequence integer,
  currency text NOT NULL DEFAULT 'CHF' CHECK (currency = 'CHF'),
  lines jsonb NOT NULL CHECK (jsonb_typeof(lines) = 'array' AND jsonb_array_length(lines) BETWEEN 1 AND 10),
  subtotal integer NOT NULL CHECK (subtotal BETWEEN 0 AND 100000000),
  discount_total integer NOT NULL CHECK (discount_total >= 0 AND discount_total <= subtotal),
  net_total integer NOT NULL CHECK (net_total = subtotal - discount_total),
  -- Figé à l'émission.
  number text UNIQUE CHECK (number IS NULL OR number ~ '^(F|AV)-[0-9]{4}-[0-9]{5,}$'),
  issued_on date,
  due_on date,
  issued_at timestamptz,
  issued_by uuid REFERENCES drivy.platform_operator(id),
  issuer_settings_id uuid REFERENCES drivy.platform_billing_issuer(id),
  issuer jsonb CHECK (issuer IS NULL OR jsonb_typeof(issuer) = 'object'),
  recipient jsonb CHECK (recipient IS NULL OR jsonb_typeof(recipient) = 'object'),
  payment_term_days smallint CHECK (payment_term_days IS NULL OR payment_term_days BETWEEN 0 AND 120),
  tax_mode text CHECK (tax_mode IS NULL OR tax_mode IN ('NONE', 'VAT')),
  tax_rate_bp integer,
  prices_include_tax boolean,
  tax_amount integer CHECK (tax_amount IS NULL OR tax_amount >= 0),
  total integer CHECK (total IS NULL OR total >= 0),
  -- Envoi : enregistré à la main tant qu'aucun courriel n'existe (#459).
  send_status text NOT NULL DEFAULT 'NOT_SENT' CHECK (send_status IN ('NOT_SENT', 'SENT')),
  sent_on date,
  sent_recorded_by uuid REFERENCES drivy.platform_operator(id),
  sent_recorded_at timestamptz,
  -- Préparation (NULL = préparation planifiée), annulation d'un brouillon, motif d'un avoir ou d'une annulation.
  prepared_by uuid REFERENCES drivy.platform_operator(id),
  prepared_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  cancelled_by uuid REFERENCES drivy.platform_operator(id),
  cancelled_at timestamptz,
  reason text CHECK (reason IS NULL OR length(btrim(reason)) BETWEEN 3 AND 500),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  UNIQUE (client_id, id),
  CHECK ((kind = 'PERIOD') = (period_index IS NOT NULL AND period_start IS NOT NULL AND period_end IS NOT NULL)),
  CHECK (period_end IS NULL OR period_end >= period_start),
  CHECK ((kind = 'CREDIT_NOTE') = (credits_invoice_id IS NOT NULL)),
  CHECK (kind = 'CREDIT_NOTE' OR (terms_id IS NOT NULL AND terms_sequence IS NOT NULL)),
  CHECK ((status = 'ISSUED') = (number IS NOT NULL)),
  CHECK (status <> 'ISSUED' OR (issued_on IS NOT NULL AND due_on IS NOT NULL AND issued_at IS NOT NULL AND issuer IS NOT NULL
    AND recipient IS NOT NULL AND tax_mode IS NOT NULL AND tax_amount IS NOT NULL AND total IS NOT NULL AND payment_term_days IS NOT NULL)),
  CHECK (due_on IS NULL OR due_on >= issued_on),
  CHECK ((status = 'CANCELLED') = (cancelled_at IS NOT NULL)),
  CHECK (status <> 'CANCELLED' OR reason IS NOT NULL),
  CHECK (kind <> 'CREDIT_NOTE' OR status = 'ISSUED'),
  CHECK ((send_status = 'SENT') = (sent_on IS NOT NULL AND sent_recorded_at IS NOT NULL)),
  CHECK (send_status = 'NOT_SENT' OR status = 'ISSUED')
);
-- Unicité par école, période et genre : une seule facture vivante par génération ; le montant initial n'est facturé qu'une fois.
CREATE UNIQUE INDEX platform_invoice_initial_once ON drivy.platform_invoice (client_id, generation) WHERE kind = 'INITIAL' AND status <> 'CANCELLED';
CREATE UNIQUE INDEX platform_invoice_period_once ON drivy.platform_invoice (client_id, period_start, generation) WHERE kind = 'PERIOD' AND status <> 'CANCELLED';
CREATE UNIQUE INDEX platform_invoice_credit_once ON drivy.platform_invoice (credits_invoice_id) WHERE kind = 'CREDIT_NOTE';
CREATE INDEX platform_invoice_client ON drivy.platform_invoice (client_id, prepared_at DESC, id DESC);
CREATE INDEX platform_invoice_due ON drivy.platform_invoice (due_on, id) WHERE status = 'ISSUED';

ALTER TABLE drivy.platform_billing_issuer ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_billing_issuer FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_billing_activation ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_billing_activation FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice_counter ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice_counter FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice FORCE ROW LEVEL SECURITY;

-- Propriétaire (fonctions SECURITY DEFINER) : seul auteur des factures et des numéros ; lecture des paramètres et des activations.
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_issuer_owner_read ON drivy.platform_billing_issuer FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_activation_owner_read ON drivy.platform_billing_activation FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_counter_owner ON drivy.platform_invoice_counter FOR ALL TO %I USING(true) WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_owner_read ON drivy.platform_invoice FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_owner_insert ON drivy.platform_invoice FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_owner_update ON drivy.platform_invoice FOR UPDATE TO %I USING(true) WITH CHECK(true)', current_user);
END $$;

-- Équipe : lecture ; ajout des paramètres et des activations, arrêt d'une activation. Les factures ne s'écrivent que par les fonctions.
-- Une école (ou tout compte non opérateur) ne lit aucune ligne, y compris les siennes : la facture vue par l'école relève de #460.
CREATE POLICY platform_issuer_read ON drivy.platform_billing_issuer FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_issuer_create ON drivy.platform_billing_issuer FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND created_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_billing_issuer TO drivy_app;

CREATE POLICY platform_activation_read ON drivy.platform_billing_activation FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_activation_create ON drivy.platform_billing_activation FOR INSERT TO drivy_app WITH CHECK(
  drivy.current_platform_operator() IS NOT NULL AND activated_by = drivy.current_platform_operator() AND status = 'ACTIVE'
  AND stopped_by IS NULL AND stopped_at IS NULL AND stop_reason IS NULL);
CREATE POLICY platform_activation_stop ON drivy.platform_billing_activation FOR UPDATE TO drivy_app
  USING(drivy.current_platform_operator() IS NOT NULL AND status = 'ACTIVE')
  WITH CHECK(drivy.current_platform_operator() IS NOT NULL AND status = 'STOPPED' AND stopped_by = drivy.current_platform_operator());
GRANT SELECT, INSERT ON drivy.platform_billing_activation TO drivy_app;
GRANT UPDATE (status, stopped_by, stop_reason) ON drivy.platform_billing_activation TO drivy_app;

CREATE POLICY platform_invoice_read ON drivy.platform_invoice FOR SELECT TO drivy_app USING(drivy.current_platform_operator() IS NOT NULL);
GRANT SELECT ON drivy.platform_invoice TO drivy_app;

-- --- Gardes -----------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_issuer_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF TG_OP <> 'INSERT' THEN RAISE EXCEPTION 'platform_issuer_fixed' USING ERRCODE='23514'; END IF;
  IF NEW.sequence <> 1 + coalesce((SELECT max(i.sequence) FROM drivy.platform_billing_issuer i), 0) THEN
    RAISE EXCEPTION 'platform_issuer_sequence' USING ERRCODE='23514';
  END IF;
  NEW.created_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_issuer_guard() FROM PUBLIC;
CREATE TRIGGER platform_issuer_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_billing_issuer FOR EACH ROW EXECUTE FUNCTION drivy.platform_issuer_guard();

-- Activation : jamais rétroactive ; seulement pour une école facturable (début payant confirmé sur des conditions complètes, sans résiliation).
CREATE FUNCTION drivy.platform_activation_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE paid drivy.platform_paid_start;
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_activation_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.starts_on < drivy.zurich_today() THEN RAISE EXCEPTION 'platform_activation_backdated' USING ERRCODE='23514'; END IF;
    SELECT p.* INTO paid FROM drivy.platform_paid_start p WHERE p.client_id = NEW.client_id AND p.status = 'ACTIVE';
    IF paid.id IS NULL OR cardinality(drivy.platform_terms_missing(NEW.client_id, drivy.platform_terms_at(NEW.client_id, paid.starts_on))) > 0 THEN
      RAISE EXCEPTION 'platform_billing_not_billable' USING ERRCODE='23514';
    END IF;
    IF EXISTS(SELECT 1 FROM drivy.platform_commercial_request r WHERE r.client_id = NEW.client_id AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED') THEN
      RAISE EXCEPTION 'platform_client_terminated' USING ERRCODE='23514';
    END IF;
    NEW.activated_at := date_trunc('milliseconds', clock_timestamp());
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.starts_on <> OLD.starts_on OR NEW.activated_by <> OLD.activated_by
     OR NEW.activated_at <> OLD.activated_at OR OLD.status <> 'ACTIVE' OR NEW.status <> 'STOPPED' THEN
    RAISE EXCEPTION 'platform_activation_fixed' USING ERRCODE='23514';
  END IF;
  NEW.stopped_at := date_trunc('milliseconds', clock_timestamp());
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_activation_guard() FROM PUBLIC;
CREATE TRIGGER platform_activation_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_billing_activation
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_activation_guard();

-- Facture : jamais supprimée ; un brouillon s'émet ou s'annule ; une facture émise ne change plus, sauf son état d'envoi (une fois).
CREATE FUNCTION drivy.platform_invoice_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_invoice_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.version <> 1 THEN RAISE EXCEPTION 'platform_invoice_fixed' USING ERRCODE='23514'; END IF;
    NEW.prepared_at := date_trunc('milliseconds', clock_timestamp());
    RETURN NEW;
  END IF;
  IF NEW.id <> OLD.id OR NEW.client_id <> OLD.client_id OR NEW.kind <> OLD.kind OR NEW.generation <> OLD.generation OR NEW.origin <> OLD.origin
     OR NEW.paid_start_id <> OLD.paid_start_id OR NEW.period_start IS DISTINCT FROM OLD.period_start OR NEW.credits_invoice_id IS DISTINCT FROM OLD.credits_invoice_id
     OR NEW.prepared_by IS DISTINCT FROM OLD.prepared_by OR NEW.prepared_at <> OLD.prepared_at OR NEW.version <> OLD.version + 1 THEN
    RAISE EXCEPTION 'platform_invoice_fixed' USING ERRCODE='23514';
  END IF;
  IF OLD.status = 'CANCELLED' THEN RAISE EXCEPTION 'platform_invoice_fixed' USING ERRCODE='23514'; END IF;
  IF OLD.status = 'ISSUED' THEN
    -- Seul l'envoi s'enregistre, une fois ; tout le document reste tel qu'émis.
    IF NEW.status <> 'ISSUED' OR OLD.send_status <> 'NOT_SENT' OR NEW.send_status <> 'SENT'
       OR (to_jsonb(NEW) - ARRAY['send_status','sent_on','sent_recorded_by','sent_recorded_at','version'])
          <> (to_jsonb(OLD) - ARRAY['send_status','sent_on','sent_recorded_by','sent_recorded_at','version']) THEN
      RAISE EXCEPTION 'platform_invoice_issued_fixed' USING ERRCODE='23514';
    END IF;
    NEW.sent_recorded_at := date_trunc('milliseconds', clock_timestamp());
    RETURN NEW;
  END IF;
  -- Brouillon : émission ou annulation seulement (la préparation suivante crée une nouvelle ligne).
  IF NEW.status = 'CANCELLED' THEN NEW.cancelled_at := date_trunc('milliseconds', clock_timestamp()); RETURN NEW; END IF;
  IF NEW.status = 'ISSUED' THEN NEW.issued_at := date_trunc('milliseconds', clock_timestamp()); RETURN NEW; END IF;
  RAISE EXCEPTION 'platform_invoice_fixed' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION drivy.platform_invoice_guard() FROM PUBLIC;
CREATE TRIGGER platform_invoice_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_invoice FOR EACH ROW EXECUTE FUNCTION drivy.platform_invoice_guard();

-- Un début payant facturé ne s'annule plus : la facture vivante doit d'abord être annulée (brouillon) ou créditée (émise).
CREATE FUNCTION drivy.platform_paid_start_invoiced_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF NEW.status = 'CANCELLED' AND EXISTS(SELECT 1 FROM drivy.platform_invoice i WHERE i.paid_start_id = OLD.id AND i.kind <> 'CREDIT_NOTE'
      AND (i.status = 'DRAFT' OR (i.status = 'ISSUED' AND NOT EXISTS(SELECT 1 FROM drivy.platform_invoice c WHERE c.credits_invoice_id = i.id)))) THEN
    RAISE EXCEPTION 'platform_paid_start_invoiced' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_paid_start_invoiced_guard() FROM PUBLIC;
CREATE TRIGGER platform_paid_start_invoiced_guard BEFORE UPDATE ON drivy.platform_paid_start
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_paid_start_invoiced_guard();

-- --- Calcul d'un document : mêmes règles que `billingSchedule` (src/platform-commercial-model.ts) ------------------------------------
-- Rend le contenu d'une facture INITIAL ou PERIOD à partir du début payant actif et de la version de conditions applicable. Refuse ce qui
-- n'est pas dû : pas de début payant (essai non converti), période hors calendrier, période à partir de la résiliation, montant nul.
-- La suspension en PAUSE (#461) s'ajoutera ici, au seul endroit qui décide qu'une période est due.
CREATE FUNCTION drivy.platform_invoice_compute(p_client uuid, p_kind text, p_period_start date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE
  paid drivy.platform_paid_start; terms drivy.platform_commercial_terms; termination date; idx integer; first_idx integer;
  amount integer; discount integer; period_end date; label text;
BEGIN
  SELECT p.* INTO paid FROM drivy.platform_paid_start p WHERE p.client_id = p_client AND p.status = 'ACTIVE';
  IF paid.id IS NULL THEN RAISE EXCEPTION 'platform_invoice_not_billable' USING ERRCODE='23514'; END IF;
  SELECT r.effective_on INTO termination FROM drivy.platform_commercial_request r
    WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED';
  IF p_kind = 'INITIAL' THEN
    terms := drivy.platform_terms_at(p_client, paid.starts_on);
    IF terms.id IS NULL OR terms.initial_amount IS NULL THEN RAISE EXCEPTION 'platform_terms_incomplete' USING ERRCODE='23514'; END IF;
    IF terms.initial_amount - terms.initial_discount <= 0 THEN RAISE EXCEPTION 'platform_invoice_nothing_due' USING ERRCODE='23514'; END IF;
    IF termination IS NOT NULL AND termination <= paid.starts_on THEN RAISE EXCEPTION 'platform_invoice_period_terminated' USING ERRCODE='23514'; END IF;
    RETURN jsonb_build_object('paidStartId', paid.id, 'anchor', paid.starts_on, 'termsId', terms.id, 'termsSequence', terms.sequence,
      'periodIndex', NULL, 'periodStart', NULL, 'periodEnd', NULL, 'paymentTermDays', terms.payment_term_days,
      'dueBase', coalesce(terms.initial_due_on, paid.starts_on),
      'lines', jsonb_build_array(jsonb_build_object('code', 'INITIAL', 'label', 'Montant initial', 'periodStart', NULL, 'periodEnd', NULL,
        'amount', terms.initial_amount, 'discount', terms.initial_discount, 'net', terms.initial_amount - terms.initial_discount, 'termsSequence', terms.sequence)),
      'subtotal', terms.initial_amount, 'discountTotal', terms.initial_discount, 'netTotal', terms.initial_amount - terms.initial_discount);
  END IF;
  IF p_kind <> 'PERIOD' OR p_period_start IS NULL THEN RAISE EXCEPTION 'platform_invoice_period_invalid' USING ERRCODE='23514'; END IF;
  IF NOT drivy.is_billing_period_start(paid.starts_on, p_period_start) THEN RAISE EXCEPTION 'platform_invoice_period_invalid' USING ERRCODE='23514'; END IF;
  IF termination IS NOT NULL AND p_period_start >= termination THEN RAISE EXCEPTION 'platform_invoice_period_terminated' USING ERRCODE='23514'; END IF;
  idx := drivy.billing_period_index(paid.starts_on, p_period_start);
  period_end := drivy.billing_period_start(paid.starts_on, idx + 1) - 1;
  terms := drivy.platform_terms_at(p_client, p_period_start);
  IF terms.id IS NULL OR terms.monthly_amount IS NULL OR terms.payment_term_days IS NULL THEN RAISE EXCEPTION 'platform_terms_incomplete' USING ERRCODE='23514'; END IF;
  first_idx := CASE WHEN terms.effective_from <= paid.starts_on THEN 0 ELSE drivy.billing_period_index(paid.starts_on, terms.effective_from - 1) + 1 END;
  amount := terms.monthly_amount;
  discount := CASE WHEN terms.recurring_discount > 0 AND (terms.recurring_discount_months IS NULL OR idx - first_idx < terms.recurring_discount_months)
    THEN least(terms.recurring_discount, amount) ELSE 0 END;
  IF amount - discount <= 0 THEN RAISE EXCEPTION 'platform_invoice_nothing_due' USING ERRCODE='23514'; END IF;
  label := 'Abonnement du ' || to_char(p_period_start, 'DD.MM.YYYY') || ' au ' || to_char(period_end, 'DD.MM.YYYY');
  RETURN jsonb_build_object('paidStartId', paid.id, 'anchor', paid.starts_on, 'termsId', terms.id, 'termsSequence', terms.sequence,
    'periodIndex', idx, 'periodStart', p_period_start, 'periodEnd', period_end, 'paymentTermDays', terms.payment_term_days, 'dueBase', p_period_start,
    'lines', jsonb_build_array(jsonb_build_object('code', 'MONTHLY', 'label', label, 'periodStart', p_period_start, 'periodEnd', period_end,
      'amount', amount, 'discount', discount, 'net', amount - discount, 'termsSequence', terms.sequence)),
    'subtotal', amount, 'discountTotal', discount, 'netTotal', amount - discount);
END $$;

-- Taxe d'un montant net selon les paramètres : arrondi au centime le plus proche (moitié vers le haut), entiers seulement.
CREATE FUNCTION drivy.platform_invoice_tax(p_net integer, p_mode text, p_rate integer, p_included boolean) RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE WHEN p_mode <> 'VAT' THEN 0
    WHEN p_included THEN (p_net::bigint - ((p_net::bigint * 10000 * 2 + (10000 + p_rate)) / (2 * (10000 + p_rate))))::integer
    ELSE ((p_net::bigint * p_rate * 2 + 10000) / 20000)::integer END
$$;

-- Prochain numéro d'une série : la ligne du compteur est verrouillée jusqu'au commit ; aucun trou.
CREATE FUNCTION drivy.platform_invoice_next_number(p_series text, p_day date) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE y integer := extract(year FROM p_day)::integer; n integer;
BEGIN
  INSERT INTO drivy.platform_invoice_counter AS c(series, year, last) VALUES(p_series, y, 1)
    ON CONFLICT (series, year) DO UPDATE SET last = c.last + 1 RETURNING c.last INTO n;
  RETURN p_series || '-' || y || '-' || lpad(n::text, 5, '0');
END $$;

-- Verrou de la fiche : le même que celui des commandes commerciales (src/platform-commercial.ts, `lockedClient`).
CREATE FUNCTION drivy.platform_client_lock(p_client uuid) RETURNS void LANGUAGE sql SET search_path=pg_catalog AS $$
  SELECT pg_advisory_xact_lock(hashtextextended('platform-client:' || p_client::text, 0))
$$;

-- Génération suivante d'une période (ou du montant initial) : 1, ou la suivante d'une facture émise puis entièrement créditée.
-- Refuse une seconde facture vivante (brouillon, ou émise sans avoir) : c'est le refus « déjà facturé ».
CREATE FUNCTION drivy.platform_invoice_generation(p_client uuid, p_kind text, p_period_start date) RETURNS smallint
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE live integer; credited integer;
BEGIN
  SELECT count(*) FILTER (WHERE i.status = 'DRAFT' OR NOT EXISTS(SELECT 1 FROM drivy.platform_invoice c WHERE c.credits_invoice_id = i.id)),
         count(*) FILTER (WHERE i.status = 'ISSUED' AND EXISTS(SELECT 1 FROM drivy.platform_invoice c WHERE c.credits_invoice_id = i.id))
    INTO live, credited
    FROM drivy.platform_invoice i
   WHERE i.client_id = p_client AND i.kind = p_kind AND i.status <> 'CANCELLED' AND i.period_start IS NOT DISTINCT FROM p_period_start;
  IF live > 0 THEN RAISE EXCEPTION 'platform_invoice_exists' USING ERRCODE='23514'; END IF;
  RETURN (credited + 1)::smallint;
END $$;

-- Préparation d'un brouillon (acteur NULL = préparation planifiée). Une période se prépare au plus tôt à son début, sauf la prochaine
-- période qu'un opérateur peut préparer d'avance ; la préparation planifiée ne prépare jamais l'avenir.
CREATE FUNCTION drivy.platform_invoice_prepare_as(p_client uuid, p_kind text, p_period_start date, p_actor uuid, p_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE doc jsonb; gen smallint; today date := drivy.zurich_today(); horizon date;
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_client c WHERE c.id = p_client) THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  doc := drivy.platform_invoice_compute(p_client, p_kind, p_period_start);
  IF p_kind = 'PERIOD' THEN
    horizon := CASE WHEN p_actor IS NULL THEN today
      ELSE drivy.billing_period_start((doc->>'anchor')::date, greatest(0, drivy.billing_period_index((doc->>'anchor')::date, today) + 1)) END;
    IF p_period_start > horizon THEN RAISE EXCEPTION 'platform_invoice_period_future' USING ERRCODE='23514'; END IF;
  ELSIF p_actor IS NULL AND (doc->>'anchor')::date > today THEN
    RAISE EXCEPTION 'platform_invoice_period_future' USING ERRCODE='23514';
  END IF;
  gen := drivy.platform_invoice_generation(p_client, p_kind, p_period_start);
  INSERT INTO drivy.platform_invoice(id, client_id, kind, generation, origin, paid_start_id, period_index, period_start, period_end, terms_id, terms_sequence,
      lines, subtotal, discount_total, net_total, payment_term_days, prepared_by)
    VALUES(p_id, p_client, p_kind, gen, CASE WHEN p_actor IS NULL THEN 'SCHEDULED' ELSE 'MANUAL' END, (doc->>'paidStartId')::uuid,
      (doc->>'periodIndex')::integer, (doc->>'periodStart')::date, (doc->>'periodEnd')::date, (doc->>'termsId')::uuid, (doc->>'termsSequence')::integer,
      doc->'lines', (doc->>'subtotal')::integer, (doc->>'discountTotal')::integer, (doc->>'netTotal')::integer, (doc->>'paymentTermDays')::smallint, p_actor);
  RETURN p_id;
END $$;

-- Émission : contenu recalculé et comparé au brouillon (un changement de conditions entre-temps refuse l'émission : personne n'émet un montant
-- qu'il n'a pas vu), émetteur et destinataire complets, numéro pris, tout est figé. Acteur NULL = émission planifiée.
CREATE FUNCTION drivy.platform_invoice_issue_as(p_invoice uuid, p_actor uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE inv drivy.platform_invoice; doc jsonb; iss drivy.platform_billing_issuer; cli drivy.platform_client; today date := drivy.zurich_today();
  v_client uuid; v_name text; v_tax integer; v_total integer;
BEGIN
  SELECT i.client_id INTO v_client FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF v_client IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(v_client);
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice FOR UPDATE;
  IF inv.status <> 'DRAFT' THEN RAISE EXCEPTION 'platform_invoice_not_draft' USING ERRCODE='23514'; END IF;
  doc := drivy.platform_invoice_compute(inv.client_id, inv.kind, inv.period_start);
  IF (doc->>'paidStartId')::uuid <> inv.paid_start_id OR (doc->>'termsId')::uuid <> inv.terms_id OR doc->'lines' <> inv.lines THEN
    RAISE EXCEPTION 'platform_invoice_terms_changed' USING ERRCODE='23514';
  END IF;
  SELECT i.* INTO iss FROM drivy.platform_billing_issuer i ORDER BY i.sequence DESC LIMIT 1;
  IF iss.id IS NULL THEN RAISE EXCEPTION 'platform_billing_issuer_missing' USING ERRCODE='23514'; END IF;
  SELECT c.* INTO cli FROM drivy.platform_client c WHERE c.id = inv.client_id;
  -- Destinataire : raison sociale et adresse de facturation de la fiche, toutes requises. Le nom de l'école n'est pas repris : la facture
  -- s'adresse à la relation commerciale, et le propriétaire des fonctions ne lit pas drivy.school (RLS forcée).
  v_name := cli.display_name;
  IF v_name IS NULL OR cli.billing_street IS NULL OR cli.billing_postal_code IS NULL OR cli.billing_city IS NULL OR cli.billing_country IS NULL THEN
    RAISE EXCEPTION 'platform_invoice_recipient_incomplete' USING ERRCODE='23514';
  END IF;
  v_tax := drivy.platform_invoice_tax(inv.net_total, iss.tax_mode, iss.tax_rate_bp, iss.prices_include_tax);
  v_total := CASE WHEN iss.tax_mode = 'VAT' AND NOT iss.prices_include_tax THEN inv.net_total + v_tax ELSE inv.net_total END;
  UPDATE drivy.platform_invoice SET status = 'ISSUED', number = drivy.platform_invoice_next_number('F', today), issued_on = today,
      due_on = greatest(today, (doc->>'dueBase')::date) + (doc->>'paymentTermDays')::integer, issued_by = p_actor, issuer_settings_id = iss.id,
      issuer = jsonb_build_object('legalName', iss.legal_name, 'street', iss.street, 'postalCode', iss.postal_code, 'city', iss.city, 'country', iss.country,
        'email', iss.email, 'iban', iss.iban, 'vatNumber', iss.vat_number, 'taxNote', iss.tax_note),
      recipient = jsonb_build_object('name', v_name, 'contactName', cli.contact_name, 'street', cli.billing_street,
        'postalCode', cli.billing_postal_code, 'city', cli.billing_city, 'country', cli.billing_country),
      payment_term_days = (doc->>'paymentTermDays')::smallint, tax_mode = iss.tax_mode, tax_rate_bp = iss.tax_rate_bp,
      prices_include_tax = iss.prices_include_tax, tax_amount = v_tax, total = v_total, version = inv.version + 1
    WHERE id = p_invoice;
  RETURN p_invoice;
END $$;

-- --- Fonctions de l'équipe : l'acteur est toujours l'opérateur relu en base, jamais un paramètre -----------------------------------------
CREATE FUNCTION drivy.platform_current_operator_required() RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.current_platform_operator();
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'platform_operator_required' USING ERRCODE='42501'; END IF;
  RETURN actor;
END $$;

CREATE FUNCTION drivy.platform_invoice_prepare(p_client uuid, p_kind text, p_period_start date, p_id uuid) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.platform_invoice_prepare_as(p_client, p_kind, p_period_start, drivy.platform_current_operator_required(), p_id)
$$;
CREATE FUNCTION drivy.platform_invoice_issue(p_invoice uuid) RETURNS uuid
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.platform_invoice_issue_as(p_invoice, drivy.platform_current_operator_required())
$$;

-- Annulation d'un brouillon : motivée ; une facture émise ne s'annule pas, elle se crédite.
CREATE FUNCTION drivy.platform_invoice_cancel(p_invoice uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); inv drivy.platform_invoice;
BEGIN
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF inv.id IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(inv.client_id);
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice FOR UPDATE;
  IF inv.status <> 'DRAFT' THEN RAISE EXCEPTION 'platform_invoice_not_draft' USING ERRCODE='23514'; END IF;
  UPDATE drivy.platform_invoice SET status = 'CANCELLED', cancelled_by = actor, reason = p_reason, version = inv.version + 1 WHERE id = p_invoice;
  RETURN p_invoice;
END $$;

-- Avoir : annule entièrement une facture émise, sans la toucher. Émis aussitôt, dans sa propre série, avec l'émetteur, le destinataire et les
-- taxes de l'original : le solde de l'original tombe à zéro. Une nouvelle génération de la même période devient alors possible.
CREATE FUNCTION drivy.platform_invoice_credit(p_invoice uuid, p_reason text, p_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); inv drivy.platform_invoice; today date := drivy.zurich_today();
BEGIN
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF inv.id IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(inv.client_id);
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice FOR SHARE;
  IF inv.status <> 'ISSUED' OR inv.kind = 'CREDIT_NOTE' THEN RAISE EXCEPTION 'platform_invoice_not_creditable' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_invoice c WHERE c.credits_invoice_id = inv.id) THEN RAISE EXCEPTION 'platform_invoice_credited' USING ERRCODE='23514'; END IF;
  INSERT INTO drivy.platform_invoice(id, client_id, kind, generation, status, origin, paid_start_id, credits_invoice_id, terms_id, terms_sequence, lines,
      subtotal, discount_total, net_total, number, issued_on, due_on, issued_at, issued_by, issuer_settings_id, issuer, recipient, payment_term_days,
      tax_mode, tax_rate_bp, prices_include_tax, tax_amount, total, prepared_by, reason)
    VALUES(p_id, inv.client_id, 'CREDIT_NOTE', inv.generation, 'ISSUED', 'MANUAL', inv.paid_start_id, inv.id, inv.terms_id, inv.terms_sequence,
      jsonb_build_array(jsonb_build_object('code', 'CREDIT', 'label', 'Annulation de la facture ' || inv.number, 'periodStart', inv.period_start,
        'periodEnd', inv.period_end, 'amount', inv.subtotal, 'discount', inv.discount_total, 'net', inv.net_total, 'termsSequence', inv.terms_sequence)),
      inv.subtotal, inv.discount_total, inv.net_total, drivy.platform_invoice_next_number('AV', today), today, today,
      date_trunc('milliseconds', clock_timestamp()), actor, inv.issuer_settings_id, inv.issuer, inv.recipient, 0,
      inv.tax_mode, inv.tax_rate_bp, inv.prices_include_tax, inv.tax_amount, inv.total, actor, p_reason);
  RETURN p_id;
END $$;

-- Envoi enregistré à la main (date déclarée, jamais future) : l'état d'envoi est distinct de l'état du document et du solde.
CREATE FUNCTION drivy.platform_invoice_mark_sent(p_invoice uuid, p_sent_on date) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); inv drivy.platform_invoice;
BEGIN
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF inv.id IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(inv.client_id);
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice FOR UPDATE;
  IF inv.status <> 'ISSUED' THEN RAISE EXCEPTION 'platform_invoice_not_issued' USING ERRCODE='23514'; END IF;
  IF inv.send_status = 'SENT' THEN RAISE EXCEPTION 'platform_invoice_already_sent' USING ERRCODE='23514'; END IF;
  IF p_sent_on < inv.issued_on OR p_sent_on > drivy.zurich_today() THEN RAISE EXCEPTION 'platform_invoice_sent_date' USING ERRCODE='23514'; END IF;
  UPDATE drivy.platform_invoice SET send_status = 'SENT', sent_on = p_sent_on, sent_recorded_by = actor, version = inv.version + 1 WHERE id = p_invoice;
  RETURN p_invoice;
END $$;

-- --- Préparation et émission planifiées -------------------------------------------------------------------------------------------------
-- Pour chaque école à facturation activée : le montant initial (si son début payant est atteint et tombe dans l'activation), puis chaque période
-- commencée depuis l'activation, jusqu'à aujourd'hui. Idempotent : ce qui existe déjà est sauté, l'unicité reste la dernière barrière.
-- Rattrapage : un passage interrompu (arrêt, panne) est repris tel quel au passage suivant ; chaque document est préparé et émis dans sa propre
-- sous-transaction : un échec n'empêche ni les autres documents ni les autres écoles, et il est repris au passage suivant. Un brouillon planifié dont les conditions ont
-- changé est annulé (motif tracé) puis préparé à nouveau ; un brouillon d'opérateur n'est jamais touché. Au plus 24 périodes par école et par passage.
CREATE FUNCTION drivy.platform_billing_run_at(p_today date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE act record; paid drivy.platform_paid_start; termination date; idx integer; first_idx integer; start date; target uuid; done integer;
  prepared integer := 0; issued integer := 0; waiting integer := 0; failed integer := 0; clients integer := 0; school uuid; inv drivy.platform_invoice;
  outcome text;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtextextended('platform-billing-run', 0)) THEN
    RETURN jsonb_build_object('skipped', true);
  END IF;
  FOR act IN SELECT a.client_id, a.starts_on FROM drivy.platform_billing_activation a WHERE a.status = 'ACTIVE' AND a.starts_on <= p_today ORDER BY a.client_id LOOP
    clients := clients + 1; done := 0;
    BEGIN
      PERFORM drivy.platform_client_lock(act.client_id);
      SELECT c.school_id INTO school FROM drivy.platform_client c WHERE c.id = act.client_id;
      SELECT p.* INTO paid FROM drivy.platform_paid_start p WHERE p.client_id = act.client_id AND p.status = 'ACTIVE';
      SELECT r.effective_on INTO termination FROM drivy.platform_commercial_request r WHERE r.client_id = act.client_id AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED';
      CONTINUE WHEN paid.id IS NULL;
      -- Liste des documents dus : (genre, début de période).
      FOR outcome, start IN
        SELECT 'INITIAL', NULL::date WHERE paid.starts_on >= act.starts_on AND paid.starts_on <= p_today
          AND (drivy.platform_terms_at(act.client_id, paid.starts_on)).initial_amount
            - (drivy.platform_terms_at(act.client_id, paid.starts_on)).initial_discount > 0
        UNION ALL
        SELECT 'PERIOD', drivy.billing_period_start(paid.starts_on, g.i)
          FROM generate_series(
            CASE WHEN act.starts_on <= paid.starts_on THEN 0 ELSE drivy.billing_period_index(paid.starts_on, act.starts_on - 1) + 1 END,
            drivy.billing_period_index(paid.starts_on, p_today)) AS g(i)
         WHERE drivy.billing_period_start(paid.starts_on, g.i) <= p_today
           AND (termination IS NULL OR drivy.billing_period_start(paid.starts_on, g.i) < termination)
      LOOP
        EXIT WHEN done >= 24;
        BEGIN
        SELECT i.* INTO inv FROM drivy.platform_invoice i
          WHERE i.client_id = act.client_id AND i.kind = outcome AND i.period_start IS NOT DISTINCT FROM start AND i.status <> 'CANCELLED'
          ORDER BY i.generation DESC LIMIT 1;
        -- Déjà émise (créditée ou non) : une nouvelle génération relève d'un opérateur, jamais du passage planifié.
        CONTINUE WHEN inv.id IS NOT NULL AND inv.status = 'ISSUED';
        -- Brouillon d'opérateur : laissé à son auteur.
        IF inv.id IS NOT NULL AND inv.origin = 'MANUAL' THEN waiting := waiting + 1; CONTINUE; END IF;
        done := done + 1;
        IF inv.id IS NOT NULL THEN
          target := inv.id;
          IF (drivy.platform_invoice_compute(act.client_id, outcome, start))->'lines' <> inv.lines THEN
            UPDATE drivy.platform_invoice SET status = 'CANCELLED', reason = 'Conditions modifiées avant émission', version = inv.version + 1 WHERE id = inv.id;
            INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
              VALUES(gen_random_uuid(), 'SYSTEM', 'Facturation planifiée', 'CANCEL_INVOICE_DRAFT', 'SUCCESS', school, 'PlatformInvoice', inv.id,
                jsonb_build_object('invoiceId', inv.id, 'kind', outcome, 'periodStart', start, 'reason', 'TERMS_CHANGED'));
            target := NULL;
          END IF;
        ELSE
          target := NULL;
        END IF;
        IF target IS NULL THEN
          target := drivy.platform_invoice_prepare_as(act.client_id, outcome, start, NULL, gen_random_uuid());
          prepared := prepared + 1;
          INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
            VALUES(gen_random_uuid(), 'SYSTEM', 'Facturation planifiée', 'PREPARE_INVOICE', 'SUCCESS', school, 'PlatformInvoice', target,
              jsonb_build_object('invoiceId', target, 'kind', outcome, 'periodStart', start));
        END IF;
        BEGIN
          PERFORM drivy.platform_invoice_issue_as(target, NULL);
          issued := issued + 1;
          INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
            SELECT gen_random_uuid(), 'SYSTEM', 'Facturation planifiée', 'ISSUE_INVOICE', 'SUCCESS', school, 'PlatformInvoice', i.id,
              jsonb_build_object('invoiceId', i.id, 'number', i.number, 'kind', i.kind, 'periodStart', i.period_start, 'total', i.total, 'dueOn', i.due_on)
            FROM drivy.platform_invoice i WHERE i.id = target;
        EXCEPTION WHEN check_violation THEN
          -- Émetteur ou destinataire incomplet : le brouillon attend le passage suivant (ou un opérateur).
          waiting := waiting + 1;
        END;
        EXCEPTION WHEN OTHERS THEN
          -- Document en échec : annulé seul (sous-transaction), les documents déjà émis de l'école restent acquis.
          failed := failed + 1;
        END;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      failed := failed + 1;
    END;
  END LOOP;
  RETURN jsonb_build_object('skipped', false, 'today', p_today, 'clients', clients, 'prepared', prepared, 'issued', issued, 'waiting', waiting, 'failed', failed);
END $$;

-- Passage planifié (service de facturation) et passage demandé par un opérateur : toujours au jour de Zurich, jamais à une date choisie.
CREATE FUNCTION drivy.platform_billing_run() RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.platform_billing_run_at(drivy.zurich_today())
$$;
CREATE FUNCTION drivy.platform_billing_run_manual() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  PERFORM drivy.platform_current_operator_required();
  RETURN drivy.platform_billing_run_at(drivy.zurich_today());
END $$;

-- Version de la facturation d'une fiche (If-Match des commandes) : croît à chaque facture, changement de facture ou activation.
-- Sans SECURITY DEFINER : lue par l'équipe sous ses propres politiques.
CREATE FUNCTION drivy.platform_client_billing_version(p_client uuid) RETURNS integer
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT (1 + coalesce((SELECT sum(i.version) FROM drivy.platform_invoice i WHERE i.client_id = p_client), 0)
    + (SELECT count(*) + count(*) FILTER (WHERE a.status = 'STOPPED') FROM drivy.platform_billing_activation a WHERE a.client_id = p_client))::integer
$$;

REVOKE ALL ON FUNCTION drivy.billing_period_start(date, integer), drivy.billing_period_index(date, date), drivy.platform_invoice_compute(uuid, text, date),
  drivy.platform_invoice_tax(integer, text, integer, boolean), drivy.platform_invoice_next_number(text, date), drivy.platform_client_lock(uuid),
  drivy.platform_invoice_generation(uuid, text, date), drivy.platform_invoice_prepare_as(uuid, text, date, uuid, uuid), drivy.platform_invoice_issue_as(uuid, uuid),
  drivy.platform_current_operator_required(), drivy.platform_invoice_prepare(uuid, text, date, uuid), drivy.platform_invoice_issue(uuid),
  drivy.platform_invoice_cancel(uuid, text), drivy.platform_invoice_credit(uuid, text, uuid), drivy.platform_invoice_mark_sent(uuid, date),
  drivy.platform_billing_run_at(date), drivy.platform_billing_run(), drivy.platform_billing_run_manual(), drivy.platform_client_billing_version(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.billing_period_start(date, integer), drivy.billing_period_index(date, date),
  drivy.platform_invoice_prepare(uuid, text, date, uuid), drivy.platform_invoice_issue(uuid), drivy.platform_invoice_cancel(uuid, text),
  drivy.platform_invoice_credit(uuid, text, uuid), drivy.platform_invoice_mark_sent(uuid, date), drivy.platform_billing_run_manual(),
  drivy.platform_client_billing_version(uuid) TO drivy_app;

-- Service de facturation : rôle sans connexion, sans BYPASSRLS, qui ne peut qu'appeler le passage planifié. Son rôle de connexion et son service
-- sur le homelab ne sont pas créés ici (aucun déploiement implicite).
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'drivy_billing_worker') THEN
  CREATE ROLE drivy_billing_worker NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$;
GRANT USAGE ON SCHEMA drivy TO drivy_billing_worker;
GRANT EXECUTE ON FUNCTION drivy.platform_billing_run() TO drivy_billing_worker;
