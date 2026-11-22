-- R01-T07 (#459) : factures PDF avec section de paiement QR suisse, envoi au contact de facturation de l'école.
-- Un document est rendu une fois depuis l'instantané figé de la facture émise, puis conservé tel quel : le télécharger ou le renvoyer redonne les
-- mêmes octets. Une correction passe par un avoir. Rien ici ne règle une facture : ni la génération, ni l'envoi, ni un QR scanné.
--
-- L'envoi est une file durable propre au domaine commercial, distincte des invitations scolaires. Le contenu de l'envoi (adresse, PDF) y est chiffré
-- par l'API et effacé dès que l'envoi est terminé. Le service d'envoi n'a aucun droit de table : il n'appelle que `claim` et `settle`.
-- Un serveur SMTP qui accepte un message ne prouve ni la livraison ni la lecture : aucun état « livré » n'existe. Une tentative dont l'issue est
-- inconnue passe en UNCERTAIN et n'est jamais rejouée sans décision d'un opérateur.

ALTER TABLE drivy.platform_billing_issuer
  ADD COLUMN building_number text CHECK (building_number IS NULL OR char_length(building_number) BETWEEN 1 AND 16),
  ADD COLUMN account_holder text CHECK (account_holder IS NULL OR char_length(account_holder) BETWEEN 1 AND 70);

-- --- Contrôles QR, miroirs de `src/platform-invoice-qr.ts` -----------------------------------------------------------------------------------
-- Directives SIX QR-facture v2.4 : adresse structurée, longueurs par champ, jeu de caractères restreint. Le jeu retenu est l'intersection de celui
-- des directives et de WinAnsi, seul codage de la police PDF standard : tout ce qui est accepté s'imprime tel quel.
CREATE FUNCTION drivy.platform_qr_text(p text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT btrim(regexp_replace(translate(p, E'\u2019\u2018\u201C\u201D\u2013\u2014\u00A0', $q$''""-- $q$), '\s+', ' ', 'g'))
$$;

CREATE FUNCTION drivy.platform_qr_field_ok(p text, p_max integer) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT p IS NOT NULL AND char_length(p) BETWEEN 1 AND p_max
    AND p ~ '^[\u0020-\u007E\u00A0-\u00FF\u0152\u0153\u0160\u0161\u0178\u017D\u017E\u20AC]*$'
$$;

-- Pays d'une adresse de facturation (texte libre sur la fiche) : code ISO à deux lettres, ou nom courant. Sinon NULL : jamais deviné.
CREATE FUNCTION drivy.platform_billing_country(p text) RETURNS text LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT CASE
    WHEN upper(v) = ANY(string_to_array('AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW', ' ')) THEN upper(v)
    WHEN lower(v) IN ('suisse', 'schweiz', 'svizzera', 'svizra', 'switzerland') THEN 'CH'
    WHEN lower(v) = 'liechtenstein' THEN 'LI'
    WHEN lower(v) = 'france' THEN 'FR'
    WHEN lower(v) IN ('allemagne', 'deutschland', 'germany') THEN 'DE'
    WHEN lower(v) IN ('italie', 'italia', 'italy') THEN 'IT'
    WHEN lower(v) IN ('autriche', 'österreich', 'austria') THEN 'AT'
  END FROM (SELECT btrim(p) AS v) AS input
$$;

CREATE FUNCTION drivy.platform_qr_postal_ok(p text) RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,drivy AS $$
  -- Le NPA s'écrit sans préfixe de pays (« 1200 », pas « CH-1200 »).
  SELECT drivy.platform_qr_field_ok(drivy.platform_qr_text(p), 16) AND drivy.platform_qr_text(p) !~ '^[A-Za-z]{1,2}-'
$$;

-- Ce qui empêche l'émetteur de demander un paiement : NULL, ou le marqueur du refus guidé.
CREATE FUNCTION drivy.platform_billing_issuer_problem(p drivy.platform_billing_issuer) RETURNS text
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT CASE
    WHEN p.iban IS NULL OR p.iban !~ '^(CH|LI)[0-9]{7}[A-Z0-9]{12}$' THEN 'platform_invoice_payment_account'
    WHEN NOT (drivy.platform_qr_field_ok(drivy.platform_qr_text(coalesce(p.account_holder, p.legal_name)), 70)
      AND drivy.platform_qr_field_ok(drivy.platform_qr_text(p.street), 70)
      AND (p.building_number IS NULL OR drivy.platform_qr_field_ok(drivy.platform_qr_text(p.building_number), 16))
      AND drivy.platform_qr_postal_ok(p.postal_code)
      AND drivy.platform_qr_field_ok(drivy.platform_qr_text(p.city), 35)
      AND drivy.platform_billing_country(p.country) IS NOT NULL) THEN 'platform_invoice_issuer_address'
  END
$$;

CREATE FUNCTION drivy.platform_invoice_recipient_problem(p_name text, p_street text, p_postal text, p_city text, p_country text) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,drivy AS $$
  SELECT CASE WHEN NOT (drivy.platform_qr_field_ok(drivy.platform_qr_text(p_name), 70)
      AND drivy.platform_qr_field_ok(drivy.platform_qr_text(p_street), 70)
      AND drivy.platform_qr_postal_ok(p_postal)
      AND drivy.platform_qr_field_ok(drivy.platform_qr_text(p_city), 35)
      AND drivy.platform_billing_country(p_country) IS NOT NULL) THEN 'platform_invoice_recipient_address' END
$$;

-- --- Émission : même corps que R01-T05, plus le refus d'un document à payer incohérent ------------------------------------------------------
-- Le passage planifié capture ce refus (check_violation) : le brouillon attend une correction, sans échec ni facture à moitié émise.
CREATE OR REPLACE FUNCTION drivy.platform_invoice_issue_as(p_invoice uuid, p_actor uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE inv drivy.platform_invoice; doc jsonb; iss drivy.platform_billing_issuer; cli drivy.platform_client; today date := drivy.zurich_today();
  v_client uuid; v_name text; v_tax integer; v_total integer; v_problem text;
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
  v_name := cli.display_name;
  IF v_name IS NULL OR cli.billing_street IS NULL OR cli.billing_postal_code IS NULL OR cli.billing_city IS NULL OR cli.billing_country IS NULL THEN
    RAISE EXCEPTION 'platform_invoice_recipient_incomplete' USING ERRCODE='23514';
  END IF;
  v_tax := drivy.platform_invoice_tax(inv.net_total, iss.tax_mode, iss.tax_rate_bp, iss.prices_include_tax);
  v_total := CASE WHEN iss.tax_mode = 'VAT' AND NOT iss.prices_include_tax THEN inv.net_total + v_tax ELSE inv.net_total END;
  IF v_total > 0 THEN
    v_problem := coalesce(drivy.platform_billing_issuer_problem(iss),
      drivy.platform_invoice_recipient_problem(v_name, cli.billing_street, cli.billing_postal_code, cli.billing_city, cli.billing_country));
    IF v_problem IS NOT NULL THEN RAISE EXCEPTION '%', v_problem USING ERRCODE='23514'; END IF;
  END IF;
  UPDATE drivy.platform_invoice SET status = 'ISSUED', number = drivy.platform_invoice_next_number('F', today), issued_on = today,
      due_on = greatest(today, (doc->>'dueBase')::date) + (doc->>'paymentTermDays')::integer, issued_by = p_actor, issuer_settings_id = iss.id,
      issuer = jsonb_build_object('legalName', iss.legal_name, 'street', iss.street, 'buildingNumber', iss.building_number, 'postalCode', iss.postal_code,
        'city', iss.city, 'country', iss.country, 'email', iss.email, 'iban', iss.iban, 'accountHolder', coalesce(iss.account_holder, iss.legal_name),
        'vatNumber', iss.vat_number, 'taxNote', iss.tax_note),
      recipient = jsonb_build_object('name', v_name, 'contactName', cli.contact_name, 'street', cli.billing_street,
        'postalCode', cli.billing_postal_code, 'city', cli.billing_city, 'country', cli.billing_country),
      payment_term_days = (doc->>'paymentTermDays')::smallint, tax_mode = iss.tax_mode, tax_rate_bp = iss.tax_rate_bp,
      prices_include_tax = iss.prices_include_tax, tax_amount = v_tax, total = v_total, version = inv.version + 1
    WHERE id = p_invoice;
  RETURN p_invoice;
END $$;

-- --- Documents PDF ---------------------------------------------------------------------------------------------------------------------------
-- Un document par mode de paiement et par facture : QR (montant total, référence) ou NONE (aucun ordre de paiement). Jamais réécrit.
CREATE TABLE drivy.platform_invoice_document (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  revision smallint NOT NULL CHECK (revision BETWEEN 1 AND 20),
  payment_mode text NOT NULL CHECK (payment_mode IN ('QR', 'NONE')),
  reference_type text CHECK (reference_type IN ('QRR', 'SCOR')),
  reference text CHECK (reference IS NULL OR reference ~ '^[A-Z0-9]{5,27}$'),
  amount integer NOT NULL CHECK (amount >= 0),
  content bytea NOT NULL CHECK (octet_length(content) BETWEEN 1 AND 2097152),
  byte_size integer NOT NULL,
  sha256 text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  generator text NOT NULL CHECK (char_length(generator) BETWEEN 1 AND 60),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  FOREIGN KEY (client_id, invoice_id) REFERENCES drivy.platform_invoice(client_id, id),
  UNIQUE (invoice_id, revision),
  UNIQUE (invoice_id, payment_mode),
  CHECK (byte_size = octet_length(content)),
  CHECK ((payment_mode = 'QR' AND amount > 0 AND reference_type IS NOT NULL AND reference IS NOT NULL)
    OR (payment_mode = 'NONE' AND amount = 0 AND reference_type IS NULL AND reference IS NULL))
);

CREATE FUNCTION drivy.platform_invoice_document_guard() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog AS $$
BEGIN RAISE EXCEPTION 'platform_invoice_document_fixed' USING ERRCODE='23514'; END $$;
REVOKE ALL ON FUNCTION drivy.platform_invoice_document_guard() FROM PUBLIC;
CREATE TRIGGER platform_invoice_document_guard BEFORE UPDATE OR DELETE ON drivy.platform_invoice_document
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_invoice_document_guard();

-- --- File d'envoi ----------------------------------------------------------------------------------------------------------------------------
CREATE TABLE drivy.platform_invoice_delivery (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL,
  invoice_id uuid NOT NULL,
  document_id uuid NOT NULL REFERENCES drivy.platform_invoice_document(id),
  status text NOT NULL DEFAULT 'QUEUED' CHECK (status IN ('QUEUED', 'PROCESSING', 'ACCEPTED', 'FAILED', 'UNCERTAIN', 'CANCELLED')),
  payload bytea CHECK (payload IS NULL OR octet_length(payload) BETWEEN 29 AND 4194304),
  recipient_masked text NOT NULL CHECK (char_length(recipient_masked) BETWEEN 3 AND 254),
  attempts smallint NOT NULL DEFAULT 0 CHECK (attempts BETWEEN 0 AND 5),
  lease_id uuid,
  lease_until timestamptz,
  available_at timestamptz NOT NULL DEFAULT now(),
  failure_code text CHECK (failure_code IS NULL OR failure_code ~ '^[A-Z_]{3,40}$'),
  resend_of uuid REFERENCES drivy.platform_invoice_delivery(id),
  requested_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  requested_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  accepted_at timestamptz,
  finished_at timestamptz,
  FOREIGN KEY (client_id, invoice_id) REFERENCES drivy.platform_invoice(client_id, id),
  CHECK ((status IN ('QUEUED', 'PROCESSING')) = (payload IS NOT NULL)),
  CHECK ((status = 'PROCESSING') = (lease_id IS NOT NULL AND lease_until IS NOT NULL)),
  CHECK ((status = 'ACCEPTED') = (accepted_at IS NOT NULL)),
  CHECK ((status IN ('QUEUED', 'PROCESSING')) = (finished_at IS NULL))
);
-- Un seul envoi logique en cours par facture : c'est la dernière barrière contre un double envoi.
CREATE UNIQUE INDEX platform_invoice_delivery_active ON drivy.platform_invoice_delivery(invoice_id) WHERE status IN ('QUEUED', 'PROCESSING');
CREATE INDEX platform_invoice_delivery_queue_idx ON drivy.platform_invoice_delivery(available_at, id) WHERE status = 'QUEUED';
CREATE INDEX platform_invoice_delivery_lease_idx ON drivy.platform_invoice_delivery(lease_until) WHERE status = 'PROCESSING';
CREATE INDEX platform_invoice_delivery_invoice_idx ON drivy.platform_invoice_delivery(invoice_id, requested_at DESC, id DESC);

-- --- Droits de lecture ------------------------------------------------------------------------------------------------------------------------
ALTER TABLE drivy.platform_invoice_document ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice_document FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice_delivery ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.platform_invoice_delivery FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
  EXECUTE format('CREATE POLICY platform_invoice_document_owner_read ON drivy.platform_invoice_document FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_document_owner_insert ON drivy.platform_invoice_document FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_delivery_owner_read ON drivy.platform_invoice_delivery FOR SELECT TO %I USING(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_delivery_owner_insert ON drivy.platform_invoice_delivery FOR INSERT TO %I WITH CHECK(true)', current_user);
  EXECUTE format('CREATE POLICY platform_invoice_delivery_owner_update ON drivy.platform_invoice_delivery FOR UPDATE TO %I USING(true) WITH CHECK(true)', current_user);
END $$;
CREATE POLICY platform_invoice_document_team_read ON drivy.platform_invoice_document FOR SELECT TO drivy_app
  USING (drivy.current_platform_operator() IS NOT NULL);
CREATE POLICY platform_invoice_delivery_team_read ON drivy.platform_invoice_delivery FOR SELECT TO drivy_app
  USING (drivy.current_platform_operator() IS NOT NULL);
REVOKE ALL ON drivy.platform_invoice_document, drivy.platform_invoice_delivery FROM PUBLIC;
GRANT SELECT ON drivy.platform_invoice_document TO drivy_app;
-- Le contenu chiffré d'un envoi n'est jamais lisible par l'application.
GRANT SELECT (id, client_id, invoice_id, document_id, status, recipient_masked, attempts, available_at, failure_code, resend_of, requested_by, requested_at,
  accepted_at, finished_at) ON drivy.platform_invoice_delivery TO drivy_app;

-- --- Écritures --------------------------------------------------------------------------------------------------------------------------------
-- Conserve un document rendu par l'API. Le montant, la référence et le couple compte/référence sont relus ici, sous le verrou de la fiche.
-- Un document du même mode existe déjà : il est rendu tel quel, sans en créer un autre.
CREATE FUNCTION drivy.platform_invoice_document_store(p_id uuid, p_invoice uuid, p_mode text, p_reference_type text, p_reference text, p_amount integer,
  p_content bytea, p_sha256 text, p_generator text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); inv drivy.platform_invoice; v_client uuid; existing uuid; next_revision integer; v_iban text; v_qr boolean;
BEGIN
  SELECT i.client_id INTO v_client FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF v_client IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(v_client);
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF inv.status <> 'ISSUED' THEN RAISE EXCEPTION 'platform_invoice_not_issued' USING ERRCODE='23514'; END IF;
  SELECT d.id INTO existing FROM drivy.platform_invoice_document d WHERE d.invoice_id = p_invoice AND d.payment_mode = p_mode;
  IF existing IS NOT NULL THEN RETURN existing; END IF;
  IF p_mode = 'QR' THEN
    -- Aucun ordre de paiement sur un avoir, une facture à zéro, créditée ou déjà réglée en partie.
    IF inv.kind = 'CREDIT_NOTE' OR inv.total IS NULL OR inv.total <= 0 OR p_amount IS DISTINCT FROM inv.total
       OR EXISTS(SELECT 1 FROM drivy.platform_invoice c WHERE c.credits_invoice_id = inv.id)
       OR coalesce((drivy.platform_invoice_settlement(inv.id)->>'allocated')::integer, 0) > 0 THEN
      RAISE EXCEPTION 'platform_invoice_qr_invalid' USING ERRCODE='23514';
    END IF;
    v_iban := inv.issuer->>'iban';
    IF v_iban IS NULL OR v_iban !~ '^(CH|LI)[0-9]{7}[A-Z0-9]{12}$' THEN RAISE EXCEPTION 'platform_invoice_payment_account' USING ERRCODE='23514'; END IF;
    v_qr := substring(v_iban, 5, 5)::integer BETWEEN 30000 AND 31999;
    IF (p_reference_type = 'QRR') IS DISTINCT FROM v_qr OR p_reference_type NOT IN ('QRR', 'SCOR') THEN
      RAISE EXCEPTION 'platform_invoice_qr_invalid' USING ERRCODE='23514';
    END IF;
  END IF;
  SELECT coalesce(max(d.revision), 0) + 1 INTO next_revision FROM drivy.platform_invoice_document d WHERE d.invoice_id = p_invoice;
  INSERT INTO drivy.platform_invoice_document(id, client_id, invoice_id, revision, payment_mode, reference_type, reference, amount, content, byte_size, sha256,
      generator, created_by)
    VALUES(p_id, inv.client_id, p_invoice, next_revision, p_mode, p_reference_type, p_reference, p_amount, p_content, octet_length(p_content), p_sha256, p_generator, actor);
  RETURN p_id;
END $$;

CREATE FUNCTION drivy.platform_invoice_delivery_audit(p_delivery uuid, p_status text, p_code text) RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
  SELECT gen_random_uuid(), 'SYSTEM', 'Envoi des factures', 'INVOICE_DELIVERY_' || p_status, 'SUCCESS', c.school_id, 'PlatformInvoice', d.invoice_id,
    jsonb_build_object('deliveryId', d.id, 'invoiceId', d.invoice_id, 'documentId', d.document_id, 'status', p_status, 'code', p_code, 'attempts', d.attempts)
  FROM drivy.platform_invoice_delivery d JOIN drivy.platform_client c ON c.id = d.client_id WHERE d.id = p_delivery
$$;

-- Met un envoi en file. Refuse un second envoi en cours, un renvoi non demandé, une facture créditée, et un QR dont le montant n'est plus le solde.
CREATE FUNCTION drivy.platform_invoice_delivery_queue(p_id uuid, p_invoice uuid, p_document uuid, p_payload bytea, p_masked text, p_resend boolean) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE actor uuid := drivy.platform_current_operator_required(); inv drivy.platform_invoice; doc drivy.platform_invoice_document;
  latest drivy.platform_invoice_delivery; settlement jsonb; v_client uuid;
BEGIN
  SELECT i.client_id INTO v_client FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF v_client IS NULL THEN RAISE EXCEPTION 'platform_invoice_unknown' USING ERRCODE='23514'; END IF;
  PERFORM drivy.platform_client_lock(v_client);
  SELECT i.* INTO inv FROM drivy.platform_invoice i WHERE i.id = p_invoice;
  IF inv.status <> 'ISSUED' THEN RAISE EXCEPTION 'platform_invoice_not_issued' USING ERRCODE='23514'; END IF;
  SELECT d.* INTO doc FROM drivy.platform_invoice_document d WHERE d.id = p_document AND d.invoice_id = p_invoice;
  IF doc.id IS NULL OR doc.revision <> (SELECT max(x.revision) FROM drivy.platform_invoice_document x WHERE x.invoice_id = p_invoice) THEN
    RAISE EXCEPTION 'platform_invoice_document_stale' USING ERRCODE='23514';
  END IF;
  settlement := drivy.platform_invoice_settlement(p_invoice);
  IF settlement->>'state' = 'CREDITED' THEN RAISE EXCEPTION 'platform_invoice_delivery_credited' USING ERRCODE='23514'; END IF;
  IF doc.payment_mode = 'QR' AND settlement->>'state' <> 'UNPAID' THEN RAISE EXCEPTION 'platform_invoice_delivery_settled' USING ERRCODE='23514'; END IF;
  SELECT x.* INTO latest FROM drivy.platform_invoice_delivery x WHERE x.invoice_id = p_invoice ORDER BY x.requested_at DESC, x.id DESC LIMIT 1;
  IF latest.status IN ('QUEUED', 'PROCESSING') THEN RAISE EXCEPTION 'platform_invoice_delivery_active' USING ERRCODE='23514'; END IF;
  IF (latest.status IN ('ACCEPTED', 'UNCERTAIN') OR inv.send_status = 'SENT') AND NOT p_resend THEN
    RAISE EXCEPTION 'platform_invoice_delivery_resend_required' USING ERRCODE='23514';
  END IF;
  INSERT INTO drivy.platform_invoice_delivery(id, client_id, invoice_id, document_id, payload, recipient_masked, resend_of, requested_by)
    VALUES(p_id, inv.client_id, p_invoice, doc.id, p_payload, p_masked, latest.id, actor);
  RETURN p_id;
END $$;

-- Prend le prochain envoi. Un bail expiré laisse une issue inconnue : UNCERTAIN, jamais rejoué. Un envoi devenu sans objet est annulé.
CREATE FUNCTION drivy.platform_invoice_delivery_claim()
RETURNS TABLE(job_id uuid, job_payload bytea, job_lease uuid, job_attempts smallint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE item drivy.platform_invoice_delivery; v_state text; v_mode text; v_lease uuid;
BEGIN
  FOR item IN SELECT x.* FROM drivy.platform_invoice_delivery x WHERE x.status = 'PROCESSING' AND x.lease_until < now() FOR UPDATE SKIP LOCKED LOOP
    UPDATE drivy.platform_invoice_delivery x SET status = 'UNCERTAIN', payload = NULL, lease_id = NULL, lease_until = NULL, failure_code = 'LEASE_EXPIRED',
      finished_at = now() WHERE x.id = item.id;
    PERFORM drivy.platform_invoice_delivery_audit(item.id, 'UNCERTAIN', 'LEASE_EXPIRED');
  END LOOP;
  LOOP
    SELECT x.* INTO item FROM drivy.platform_invoice_delivery x WHERE x.status = 'QUEUED' AND x.available_at <= now()
      ORDER BY x.available_at, x.id LIMIT 1 FOR UPDATE SKIP LOCKED;
    EXIT WHEN item.id IS NULL;
    v_state := drivy.platform_invoice_settlement(item.invoice_id)->>'state';
    SELECT d.payment_mode INTO v_mode FROM drivy.platform_invoice_document d WHERE d.id = item.document_id;
    IF v_state = 'CREDITED' OR (v_mode = 'QR' AND v_state <> 'UNPAID') THEN
      UPDATE drivy.platform_invoice_delivery x SET status = 'CANCELLED', payload = NULL, failure_code = 'SETTLEMENT_CHANGED', finished_at = now() WHERE x.id = item.id;
      PERFORM drivy.platform_invoice_delivery_audit(item.id, 'CANCELLED', 'SETTLEMENT_CHANGED');
      item := NULL;
      CONTINUE;
    END IF;
    v_lease := gen_random_uuid();
    UPDATE drivy.platform_invoice_delivery x SET status = 'PROCESSING', attempts = x.attempts + 1, lease_id = v_lease, lease_until = now() + interval '180 seconds'
      WHERE x.id = item.id;
    job_id := item.id; job_payload := item.payload; job_lease := v_lease; job_attempts := item.attempts + 1;
    RETURN NEXT;
    RETURN;
  END LOOP;
END $$;

-- Enregistre l'issue d'une tentative sous son bail. Seule une acceptation SMTP marque la facture envoyée. Aucune issue ne touche au paiement ni à l'échéance.
CREATE FUNCTION drivy.platform_invoice_delivery_settle(p_id uuid, p_lease uuid, p_outcome text, p_code text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE item drivy.platform_invoice_delivery; v_client uuid; v_status text;
BEGIN
  IF p_outcome NOT IN ('ACCEPTED', 'RETRY', 'FAILED', 'UNCERTAIN') THEN RAISE EXCEPTION 'platform_invoice_delivery_outcome' USING ERRCODE='23514'; END IF;
  SELECT x.client_id INTO v_client FROM drivy.platform_invoice_delivery x WHERE x.id = p_id;
  IF v_client IS NULL THEN RETURN 'STALE'; END IF;
  PERFORM drivy.platform_client_lock(v_client);
  SELECT x.* INTO item FROM drivy.platform_invoice_delivery x WHERE x.id = p_id FOR UPDATE;
  IF item.status <> 'PROCESSING' OR item.lease_id IS DISTINCT FROM p_lease THEN RETURN 'STALE'; END IF;
  IF p_outcome = 'ACCEPTED' THEN
    UPDATE drivy.platform_invoice_delivery x SET status = 'ACCEPTED', payload = NULL, lease_id = NULL, lease_until = NULL, failure_code = NULL,
      accepted_at = now(), finished_at = now() WHERE x.id = p_id;
    UPDATE drivy.platform_invoice i SET send_status = 'SENT', sent_on = drivy.zurich_today(), sent_recorded_by = item.requested_by, version = i.version + 1
      WHERE i.id = item.invoice_id AND i.send_status = 'NOT_SENT';
    PERFORM drivy.platform_invoice_delivery_audit(p_id, 'ACCEPTED', NULL);
    RETURN 'ACCEPTED';
  END IF;
  IF p_outcome = 'RETRY' AND item.attempts < 5 THEN
    UPDATE drivy.platform_invoice_delivery x SET status = 'QUEUED', lease_id = NULL, lease_until = NULL, failure_code = p_code,
      available_at = now() + item.attempts * interval '60 seconds' WHERE x.id = p_id;
    RETURN 'QUEUED';
  END IF;
  v_status := CASE WHEN p_outcome = 'UNCERTAIN' THEN 'UNCERTAIN' ELSE 'FAILED' END;
  UPDATE drivy.platform_invoice_delivery x SET status = v_status, payload = NULL, lease_id = NULL, lease_until = NULL,
    failure_code = CASE WHEN p_outcome = 'RETRY' THEN 'RETRY_EXHAUSTED' ELSE p_code END, finished_at = now() WHERE x.id = p_id;
  PERFORM drivy.platform_invoice_delivery_audit(p_id, v_status, CASE WHEN p_outcome = 'RETRY' THEN 'RETRY_EXHAUSTED' ELSE p_code END);
  RETURN v_status;
END $$;

REVOKE ALL ON FUNCTION drivy.platform_qr_text(text), drivy.platform_qr_field_ok(text, integer), drivy.platform_billing_country(text),
  drivy.platform_qr_postal_ok(text), drivy.platform_billing_issuer_problem(drivy.platform_billing_issuer),
  drivy.platform_invoice_recipient_problem(text, text, text, text, text),
  drivy.platform_invoice_document_store(uuid, uuid, text, text, text, integer, bytea, text, text),
  drivy.platform_invoice_delivery_audit(uuid, text, text), drivy.platform_invoice_delivery_queue(uuid, uuid, uuid, bytea, text, boolean),
  drivy.platform_invoice_delivery_claim(), drivy.platform_invoice_delivery_settle(uuid, uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.platform_qr_text(text), drivy.platform_qr_field_ok(text, integer), drivy.platform_billing_country(text),
  drivy.platform_qr_postal_ok(text), drivy.platform_billing_issuer_problem(drivy.platform_billing_issuer),
  drivy.platform_invoice_recipient_problem(text, text, text, text, text),
  drivy.platform_invoice_document_store(uuid, uuid, text, text, text, integer, bytea, text, text),
  drivy.platform_invoice_delivery_queue(uuid, uuid, uuid, bytea, text, boolean) TO drivy_app;

-- Service d'envoi : rôle sans connexion, sans droit de table, qui ne peut que prendre un envoi et en écrire l'issue. Son rôle de connexion et son
-- service sur le homelab ne sont pas créés ici (aucun déploiement implicite).
DO $$ BEGIN IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname = 'drivy_billing_mailer') THEN
  CREATE ROLE drivy_billing_mailer NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEROLE NOCREATEDB NOINHERIT; END IF; END $$;
GRANT USAGE ON SCHEMA drivy TO drivy_billing_mailer;
GRANT EXECUTE ON FUNCTION drivy.platform_invoice_delivery_claim(), drivy.platform_invoice_delivery_settle(uuid, uuid, text, text) TO drivy_billing_mailer;
