-- R01-T09 (#461) : relances des impayés, alertes commerciales, suspension et réactivation d'une école.
-- La règle V1 : deux mois calendaires depuis l'échéance de la plus ancienne somme encore due, réglables globalement et par exception d'école.
-- La politique est créée DÉSACTIVÉE : ni rappel, ni avertissement, ni suspension automatique tant qu'un opérateur ne l'a pas activée.
-- Aucune donnée n'est inventée ici : ni dette, ni facture, ni suspension. `school.status` n'est jamais modifié : suspension et archivage restent distincts.

-- --- Avis : une relance n'a pas de demande d'origine ---------------------------------------------------------------------------------------------
ALTER TABLE drivy.platform_commercial_notice ALTER COLUMN request_id DROP NOT NULL, ALTER COLUMN request_version DROP NOT NULL;
ALTER TABLE drivy.platform_commercial_notice ADD COLUMN dunning_key text CHECK (dunning_key IS NULL OR length(dunning_key) BETWEEN 3 AND 200);
ALTER TABLE drivy.platform_commercial_notice DROP CONSTRAINT platform_commercial_notice_event_check;
ALTER TABLE drivy.platform_commercial_notice ADD CONSTRAINT platform_commercial_notice_event_check CHECK (event IN
  ('RECEIVED', 'IN_PROGRESS', 'ACCEPTED', 'REFUSED', 'WITHDRAWN', 'DATE_CHANGED', 'RESUMED',
   'PAYMENT_REMINDER', 'SUSPENSION_WARNING', 'SUSPENDED', 'REACTIVATED'));
ALTER TABLE drivy.platform_commercial_notice ADD CONSTRAINT platform_commercial_notice_origin CHECK (
  (request_id IS NOT NULL AND request_version IS NOT NULL AND dunning_key IS NULL)
  OR (request_id IS NULL AND request_version IS NULL AND dunning_key IS NOT NULL AND audience = 'SCHOOL'));
CREATE UNIQUE INDEX platform_commercial_notice_dunning ON drivy.platform_commercial_notice (dunning_key) WHERE dunning_key IS NOT NULL;

-- --- Politique, exceptions, étapes, suspensions, alertes ------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_dunning_days_valid(p_days integer[]) RETURNS boolean
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$
  SELECT coalesce(array_ndims(p_days) = 1 AND cardinality(p_days) BETWEEN 1 AND 6
    AND NOT EXISTS(SELECT 1 FROM unnest(p_days) AS d(v) WHERE d.v IS NULL OR d.v NOT BETWEEN 1 AND 365)
    AND (SELECT count(DISTINCT d.v) FROM unnest(p_days) AS d(v)) = cardinality(p_days)
    AND p_days = (SELECT array_agg(d.v ORDER BY d.v) FROM unnest(p_days) AS d(v)), false)
$$;

CREATE TABLE drivy.platform_dunning_policy (
  singleton boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  reminders_enabled boolean NOT NULL DEFAULT false,
  auto_suspend boolean NOT NULL DEFAULT false,
  reminder_days integer[] NOT NULL DEFAULT '{3,15,30}' CHECK (drivy.platform_dunning_days_valid(reminder_days)),
  suspension_months integer NOT NULL DEFAULT 2 CHECK (suspension_months BETWEEN 1 AND 12),
  warning_days integer NOT NULL DEFAULT 14 CHECK (warning_days BETWEEN 3 AND 28),
  trial_alert_days integer NOT NULL DEFAULT 7 CHECK (trial_alert_days BETWEEN 1 AND 30),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  updated_by uuid REFERENCES drivy.platform_operator(id),
  updated_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  CHECK (NOT auto_suspend OR reminders_enabled)
);

-- Exception temporaire et motivée d'une école : autre délai (DELAY) ou arrêt des relances et de la suspension (HOLD, par exemple un litige).
CREATE TABLE drivy.platform_dunning_exception (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  kind text NOT NULL CHECK (kind IN ('DELAY', 'HOLD')),
  suspension_months integer CHECK (suspension_months BETWEEN 1 AND 24),
  ends_on date NOT NULL,
  reason text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 500),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'REVOKED', 'EXPIRED')),
  created_by uuid NOT NULL REFERENCES drivy.platform_operator(id),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  revoked_by uuid REFERENCES drivy.platform_operator(id),
  revoked_at timestamptz,
  revoke_reason text CHECK (revoke_reason IS NULL OR length(btrim(revoke_reason)) BETWEEN 3 AND 500),
  CHECK ((kind = 'DELAY') = (suspension_months IS NOT NULL)),
  CHECK ((status = 'REVOKED') = (revoked_at IS NOT NULL)),
  CHECK ((status = 'REVOKED') = (revoked_by IS NOT NULL))
);
CREATE UNIQUE INDEX platform_dunning_exception_active ON drivy.platform_dunning_exception (client_id) WHERE status = 'ACTIVE';

-- Une étape par facture, cycle et palier : c'est l'unicité qui rend un passage relancé sans double effet.
-- `cycle` compte les suspensions pour impayé déjà levées sur cette facture : une nouvelle suspension exige un nouvel avertissement.
CREATE TABLE drivy.platform_dunning_step (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  invoice_id uuid NOT NULL REFERENCES drivy.platform_invoice(id),
  due_on date NOT NULL,
  cycle integer NOT NULL DEFAULT 0 CHECK (cycle >= 0),
  kind text NOT NULL CHECK (kind IN ('REMINDER', 'WARNING')),
  offset_days integer NOT NULL CHECK (offset_days >= 0),
  planned_on date NOT NULL,
  done_on date NOT NULL,
  status text NOT NULL CHECK (status IN ('RECORDED', 'SKIPPED')),
  suspension_on date,
  recipient_count integer NOT NULL DEFAULT 0 CHECK (recipient_count >= 0),
  notice_id uuid REFERENCES drivy.platform_commercial_notice(id),
  confirmed_by uuid REFERENCES drivy.platform_operator(id),
  confirmed_at timestamptz,
  confirm_reason text CHECK (confirm_reason IS NULL OR length(btrim(confirm_reason)) BETWEEN 3 AND 500),
  created_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  UNIQUE (client_id, invoice_id, cycle, kind, offset_days),
  CHECK ((kind = 'WARNING') = (suspension_on IS NOT NULL)),
  CHECK ((status = 'RECORDED') = (notice_id IS NOT NULL)),
  CHECK (kind <> 'WARNING' OR (offset_days = 0 AND status = 'RECORDED')),
  CHECK ((confirmed_at IS NULL) = (confirmed_by IS NULL)),
  CHECK (confirmed_at IS NULL OR kind = 'WARNING')
);
CREATE INDEX platform_dunning_step_client ON drivy.platform_dunning_step (client_id, created_at DESC);

CREATE TABLE drivy.platform_commercial_suspension (
  id uuid PRIMARY KEY,
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  cause text NOT NULL CHECK (cause IN ('PAYMENT', 'MANUAL')),
  origin text NOT NULL CHECK (origin IN ('AUTOMATIC', 'OPERATOR')),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'LIFTED')),
  starts_on date NOT NULL,
  started_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  invoice_id uuid REFERENCES drivy.platform_invoice(id),
  due_on date,
  months integer CHECK (months BETWEEN 1 AND 24),
  reason text CHECK (reason IS NULL OR length(btrim(reason)) BETWEEN 3 AND 500),
  created_by uuid REFERENCES drivy.platform_operator(id),
  lifted_on date,
  lifted_at timestamptz,
  lifted_by uuid REFERENCES drivy.platform_operator(id),
  lift_cause text CHECK (lift_cause IN ('PAYMENT_CONFIRMED', 'OPERATOR')),
  lift_reason text CHECK (lift_reason IS NULL OR length(btrim(lift_reason)) BETWEEN 3 AND 500),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  CHECK (cause <> 'PAYMENT' OR (invoice_id IS NOT NULL AND due_on IS NOT NULL AND months IS NOT NULL)),
  CHECK (cause <> 'MANUAL' OR origin = 'OPERATOR'),
  CHECK ((origin = 'OPERATOR') = (created_by IS NOT NULL)),
  CHECK (origin <> 'OPERATOR' OR reason IS NOT NULL),
  CHECK ((status = 'LIFTED') = (lifted_at IS NOT NULL)),
  CHECK ((status = 'LIFTED') = (lifted_on IS NOT NULL)),
  CHECK ((status = 'LIFTED') = (lift_cause IS NOT NULL)),
  CHECK (lifted_on IS NULL OR lifted_on >= starts_on),
  CHECK (lift_cause IS DISTINCT FROM 'OPERATOR' OR (lifted_by IS NOT NULL AND lift_reason IS NOT NULL))
);
CREATE UNIQUE INDEX platform_commercial_suspension_active ON drivy.platform_commercial_suspension (client_id, cause) WHERE status = 'ACTIVE';
CREATE INDEX platform_commercial_suspension_client ON drivy.platform_commercial_suspension (client_id, started_at DESC);

CREATE TABLE drivy.platform_commercial_alert (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES drivy.platform_client(id),
  kind text NOT NULL CHECK (kind IN ('TRIAL_ENDING', 'TRIAL_ENDED', 'NEW_OVERDUE', 'DELIVERY_FAILED', 'SUSPENSION_UPCOMING', 'SUSPENDED')),
  dedupe_key text NOT NULL UNIQUE CHECK (length(dedupe_key) BETWEEN 3 AND 200),
  invoice_id uuid REFERENCES drivy.platform_invoice(id),
  on_date date,
  status text NOT NULL DEFAULT 'OPEN' CHECK (status IN ('OPEN', 'RESOLVED')),
  opened_at timestamptz NOT NULL DEFAULT date_trunc('milliseconds', clock_timestamp()),
  resolved_at timestamptz,
  resolved_cause text CHECK (resolved_cause IN ('OBSOLETE', 'OPERATOR')),
  acknowledged_by uuid REFERENCES drivy.platform_operator(id),
  acknowledged_at timestamptz,
  CHECK ((status = 'RESOLVED') = (resolved_at IS NOT NULL)),
  CHECK ((status = 'RESOLVED') = (resolved_cause IS NOT NULL)),
  CHECK (resolved_cause IS DISTINCT FROM 'OPERATOR' OR acknowledged_by IS NOT NULL)
);
CREATE INDEX platform_commercial_alert_open ON drivy.platform_commercial_alert (opened_at DESC, id DESC) WHERE status = 'OPEN';
CREATE INDEX platform_commercial_alert_client ON drivy.platform_commercial_alert (client_id, status);

-- Aucun droit direct pour l'application : tout passe par les fonctions ci-dessous, qui relisent l'opérateur.
DO $$ DECLARE t text; BEGIN
  FOREACH t IN ARRAY ARRAY['platform_dunning_policy', 'platform_dunning_exception', 'platform_dunning_step', 'platform_commercial_suspension', 'platform_commercial_alert'] LOOP
    EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format('CREATE POLICY %I ON drivy.%I TO %I USING(true) WITH CHECK(true)', t || '_owner', t, current_user);
  END LOOP;
END $$;
INSERT INTO drivy.platform_dunning_policy DEFAULT VALUES;

-- Une suspension ne se supprime ni ne se réécrit : seul le passage ACTIVE -> LIFTED existe.
CREATE FUNCTION drivy.platform_suspension_guard() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN RAISE EXCEPTION 'platform_suspension_fixed' USING ERRCODE='23514'; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'ACTIVE' OR NEW.version <> 1 THEN RAISE EXCEPTION 'platform_suspension_fixed' USING ERRCODE='23514'; END IF;
    RETURN NEW;
  END IF;
  IF OLD.status = 'ACTIVE' AND NEW.status = 'LIFTED' AND NEW.version = OLD.version + 1
    AND (to_jsonb(NEW) - ARRAY['status', 'lifted_on', 'lifted_at', 'lifted_by', 'lift_cause', 'lift_reason', 'version'])
      = (to_jsonb(OLD) - ARRAY['status', 'lifted_on', 'lifted_at', 'lifted_by', 'lift_cause', 'lift_reason', 'version']) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'platform_suspension_fixed' USING ERRCODE='23514';
END $$;
REVOKE ALL ON FUNCTION drivy.platform_suspension_guard() FROM PUBLIC;
CREATE TRIGGER platform_suspension_guard BEFORE INSERT OR UPDATE OR DELETE ON drivy.platform_commercial_suspension
  FOR EACH ROW EXECUTE FUNCTION drivy.platform_suspension_guard();

-- --- Calcul : une seule définition pour le passage, la console et l'école ------------------------------------------------------------------------
-- N mois calendaires après une date. PostgreSQL borne au dernier jour du mois : 31 décembre + 2 mois = 28 ou 29 février. Aucun fuseau n'intervient.
CREATE FUNCTION drivy.platform_dunning_months_after(p_day date, p_months integer) RETURNS date
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog AS $$ SELECT (p_day + make_interval(months => p_months))::date $$;

-- La plus ancienne facture émise encore en retard à ce jour. Un paiement partiel la laisse en tête : le compteur ne repart pas de zéro.
CREATE FUNCTION drivy.platform_dunning_oldest(p_client uuid, p_today date)
RETURNS TABLE(invoice_id uuid, invoice_number text, due_on date, balance integer)
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT i.id, i.number, i.due_on, (x.st->>'balance')::integer
  FROM drivy.platform_invoice i CROSS JOIN LATERAL (SELECT drivy.platform_invoice_settlement(i.id, p_today) AS st) x
  WHERE i.client_id = p_client AND i.status = 'ISSUED' AND i.kind <> 'CREDIT_NOTE' AND (x.st->>'overdue')::boolean
  ORDER BY i.due_on, i.issued_on, i.number LIMIT 1
$$;

-- Remise d'une étape, du fait le plus fort au plus faible. Seuls READ, SENT et CONFIRMED autorisent une suspension automatique.
CREATE FUNCTION drivy.platform_dunning_delivery(p_step uuid) RETURNS text
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT CASE
    WHEN st.status = 'SKIPPED' THEN 'SKIPPED'
    WHEN st.confirmed_at IS NOT NULL THEN 'CONFIRMED'
    WHEN st.recipient_count = 0 THEN 'NO_RECIPIENT'
    WHEN n.read_at IS NOT NULL THEN 'READ'
    WHEN EXISTS(SELECT 1 FROM drivy.push_notification p WHERE p.commercial_notice_id = st.notice_id AND p.status = 'SENT') THEN 'SENT'
    WHEN EXISTS(SELECT 1 FROM drivy.push_notification p WHERE p.commercial_notice_id = st.notice_id AND p.status = 'PENDING'
      AND (p.valid_until IS NULL OR p.valid_until > statement_timestamp())) THEN 'PENDING'
    ELSE 'FAILED' END
  FROM drivy.platform_dunning_step st LEFT JOIN drivy.platform_commercial_notice n ON n.id = st.notice_id
  WHERE st.id = p_step
$$;

-- État recalculé d'une fiche : la facture et l'échéance qui l'expliquent, le délai applicable et la date de suspension. Une date annoncée n'est jamais avancée.
CREATE FUNCTION drivy.platform_dunning_state(p_client uuid, p_today date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog,drivy AS $$
DECLARE v_pol drivy.platform_dunning_policy; v_exc drivy.platform_dunning_exception; v_oldest record; v_months integer; v_base date; v_cycle integer;
  v_warn drivy.platform_dunning_step; v_suspension_on date; v_warning_on date; v_hold boolean;
BEGIN
  SELECT p.* INTO v_pol FROM drivy.platform_dunning_policy p;
  SELECT e.* INTO v_exc FROM drivy.platform_dunning_exception e WHERE e.client_id = p_client AND e.status = 'ACTIVE' AND e.ends_on >= p_today;
  v_hold := coalesce(v_exc.kind = 'HOLD', false);
  SELECT o.* INTO v_oldest FROM drivy.platform_dunning_oldest(p_client, p_today) o;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('overdue', false, 'hold', v_hold, 'exceptionId', v_exc.id, 'invoiceId', NULL, 'invoiceNumber', NULL, 'dueOn', NULL, 'balance', NULL,
      'months', NULL, 'baseOn', NULL, 'cycle', 0, 'warningStepId', NULL, 'warningDelivery', NULL, 'warningOn', NULL, 'suspensionOn', NULL, 'suspensionDue', false,
      'daysLate', 0, 'nextReminderOn', NULL);
  END IF;
  v_months := CASE WHEN v_exc.kind = 'DELAY' THEN v_exc.suspension_months ELSE v_pol.suspension_months END;
  v_base := drivy.platform_dunning_months_after(v_oldest.due_on, v_months);
  SELECT count(*)::integer INTO v_cycle FROM drivy.platform_commercial_suspension s
    WHERE s.client_id = p_client AND s.invoice_id = v_oldest.invoice_id AND s.cause = 'PAYMENT' AND s.status = 'LIFTED';
  SELECT st.* INTO v_warn FROM drivy.platform_dunning_step st
    WHERE st.client_id = p_client AND st.invoice_id = v_oldest.invoice_id AND st.cycle = v_cycle AND st.kind = 'WARNING';
  IF v_warn.id IS NOT NULL THEN
    v_warning_on := v_warn.done_on;
    v_suspension_on := greatest(v_base, v_warn.suspension_on);
  ELSE
    v_warning_on := greatest(v_base - v_pol.warning_days, p_today);
    v_suspension_on := greatest(v_base, v_warning_on + v_pol.warning_days);
  END IF;
  RETURN jsonb_build_object('overdue', true, 'hold', v_hold, 'exceptionId', v_exc.id, 'invoiceId', v_oldest.invoice_id, 'invoiceNumber', v_oldest.invoice_number,
    'dueOn', v_oldest.due_on, 'balance', v_oldest.balance, 'months', v_months, 'baseOn', v_base, 'cycle', v_cycle, 'warningStepId', v_warn.id,
    'warningDelivery', CASE WHEN v_warn.id IS NOT NULL THEN drivy.platform_dunning_delivery(v_warn.id) END,
    'warningOn', v_warning_on, 'suspensionOn', v_suspension_on, 'suspensionDue', NOT v_hold AND p_today >= v_suspension_on,
    'daysLate', p_today - v_oldest.due_on,
    'nextReminderOn', CASE WHEN v_pol.reminders_enabled AND NOT v_hold THEN
      (SELECT min(v_oldest.due_on + d.v) FROM unnest(v_pol.reminder_days) AS d(v) WHERE v_oldest.due_on + d.v > p_today) END);
END $$;

-- Période en pause : les conditions disent PAUSE à cette date et une suspension couvre le début de la période. Sans prorata, factures émises intactes.
CREATE FUNCTION drivy.platform_period_paused(p_client uuid, p_day date) RETURNS boolean
LANGUAGE sql STABLE SET search_path=pg_catalog,drivy AS $$
  SELECT coalesce((drivy.platform_terms_at(p_client, p_day)).suspension_billing = 'PAUSE', false) AND EXISTS(
    SELECT 1 FROM drivy.platform_commercial_suspension s
    WHERE s.client_id = p_client AND s.starts_on <= p_day AND (s.lifted_on IS NULL OR s.lifted_on > p_day))
$$;

-- --- Écritures communes -----------------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_dunning_audit(p_action text, p_school uuid, p_type text, p_subject uuid, p_changes jsonb) RETURNS void
LANGUAGE sql SET search_path=pg_catalog,drivy AS $$
  INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
  VALUES(gen_random_uuid(), 'SYSTEM', 'Relances planifiées', p_action, 'SUCCESS', p_school, p_type, p_subject, p_changes)
$$;

CREATE FUNCTION drivy.platform_dunning_alert(p_client uuid, p_kind text, p_key text, p_invoice uuid, p_on date) RETURNS void
LANGUAGE sql SET search_path=pg_catalog,drivy AS $$
  INSERT INTO drivy.platform_commercial_alert AS a(client_id, kind, dedupe_key, invoice_id, on_date)
  VALUES(p_client, p_kind, p_key, p_invoice, p_on)
  ON CONFLICT (dedupe_key) DO UPDATE SET status = 'OPEN', on_date = EXCLUDED.on_date, resolved_at = NULL, resolved_cause = NULL,
    opened_at = CASE WHEN a.status = 'OPEN' THEN a.opened_at ELSE date_trunc('milliseconds', clock_timestamp()) END
  WHERE a.status = 'OPEN' OR a.resolved_cause = 'OBSOLETE'
$$;

-- Avis durable et notification générique (ni montant, ni motif sur l'écran verrouillé) aux responsables actifs. Rejoué : même avis, aucun nouvel envoi.
CREATE FUNCTION drivy.platform_dunning_notify(p_client uuid, p_school uuid, p_event text, p_key text, OUT o_notice uuid, OUT o_recipients integer)
LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$
DECLARE v_message text;
BEGIN
  INSERT INTO drivy.platform_commercial_notice(client_id, event, audience, dunning_key) VALUES (p_client, p_event, 'SCHOOL', p_key)
  ON CONFLICT (dunning_key) WHERE dunning_key IS NOT NULL DO NOTHING RETURNING id INTO o_notice;
  IF o_notice IS NULL THEN
    SELECT n.id INTO o_notice FROM drivy.platform_commercial_notice n WHERE n.dunning_key = p_key;
  ELSIF p_school IS NOT NULL THEN
    v_message := CASE p_event WHEN 'PAYMENT_REMINDER' THEN 'Un règlement est attendu pour votre école.'
      WHEN 'SUSPENSION_WARNING' THEN 'Une suspension est prévue pour votre école.'
      WHEN 'SUSPENDED' THEN 'Votre école est suspendue.' ELSE 'La suspension de votre école est levée.' END;
    INSERT INTO drivy.push_notification(person_id, school_id, category, dedupe_key, title, body, valid_until, commercial_notice_id)
    SELECT m.person_id, p_school, 'COMMERCIAL', 'commercial:dunning:' || p_key, 'Abonnement', v_message, statement_timestamp() + interval '24 hours', o_notice
    FROM drivy.membership m JOIN drivy.person pe ON pe.id = m.person_id
    WHERE m.school_id = p_school AND m.status = 'ACTIVE' AND pe.status = 'ACTIVE' AND 'ADMIN' = ANY(m.roles)
    ON CONFLICT (person_id, dedupe_key) DO NOTHING;
  END IF;
  SELECT count(*)::integer INTO o_recipients FROM drivy.push_notification p WHERE p.commercial_notice_id = o_notice;
END $$;

-- Lève la seule cause PAYMENT quand plus aucune facture en retard n'atteint le délai retenu à la suspension. Sous le verrou de la fiche.
-- Une exception accordée ne compte pas : seule une écriture confirmée (règlement affecté, avoir) lève ici. Ni la cause MANUAL, ni une résiliation, ni un archivage.
CREATE FUNCTION drivy.platform_dunning_lift_if_settled(p_client uuid, p_today date) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_susp drivy.platform_commercial_suspension; v_oldest record; v_school uuid; v_done integer := 0; v_notified record; v_on date;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.cause = 'PAYMENT' AND s.status = 'ACTIVE') THEN RETURN 0; END IF;
  PERFORM drivy.platform_client_lock(p_client);
  SELECT s.* INTO v_susp FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.cause = 'PAYMENT' AND s.status = 'ACTIVE' FOR UPDATE;
  IF NOT FOUND THEN RETURN 0; END IF;
  SELECT o.* INTO v_oldest FROM drivy.platform_dunning_oldest(p_client, p_today) o;
  IF FOUND AND drivy.platform_dunning_months_after(v_oldest.due_on, v_susp.months) <= p_today THEN RETURN 0; END IF;
  v_on := greatest(p_today, v_susp.starts_on);
  UPDATE drivy.platform_commercial_suspension s SET status = 'LIFTED', lifted_on = v_on, lifted_at = date_trunc('milliseconds', clock_timestamp()),
    lift_cause = 'PAYMENT_CONFIRMED', version = v_susp.version + 1 WHERE s.id = v_susp.id;
  v_done := 1;
  SELECT c.school_id INTO v_school FROM drivy.platform_client c WHERE c.id = p_client;
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.status = 'ACTIVE') THEN
    SELECT * INTO v_notified FROM drivy.platform_dunning_notify(p_client, v_school, 'REACTIVATED', 'reactivated:' || v_susp.id);
  END IF;
  UPDATE drivy.platform_commercial_alert a SET status = 'RESOLVED', resolved_at = date_trunc('milliseconds', clock_timestamp()), resolved_cause = 'OBSOLETE'
    WHERE a.client_id = p_client AND a.status = 'OPEN' AND a.dedupe_key = 'suspended:' || v_susp.id;
  PERFORM drivy.platform_dunning_audit('LIFT_SCHOOL_SUSPENSION', v_school, 'PlatformSuspension', v_susp.id,
    jsonb_build_object('suspensionId', v_susp.id, 'cause', 'PAYMENT', 'liftCause', 'PAYMENT_CONFIRMED', 'invoiceId', v_susp.invoice_id, 'liftedOn', v_on));
  RETURN v_done;
END $$;

-- Un règlement affecté ou un avoir émis lève la suspension dans la même transaction : l'école qui vient de solder n'attend pas le passage suivant.
CREATE FUNCTION drivy.platform_dunning_on_settlement() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  PERFORM drivy.platform_dunning_lift_if_settled(NEW.client_id, drivy.zurich_today());
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_dunning_on_settlement() FROM PUBLIC;
CREATE TRIGGER platform_dunning_allocation AFTER INSERT ON drivy.platform_payment_allocation
  FOR EACH ROW WHEN (NEW.status = 'ACTIVE') EXECUTE FUNCTION drivy.platform_dunning_on_settlement();
CREATE TRIGGER platform_dunning_credit AFTER INSERT OR UPDATE OF status ON drivy.platform_invoice
  FOR EACH ROW WHEN (NEW.kind = 'CREDIT_NOTE' AND NEW.status = 'ISSUED') EXECUTE FUNCTION drivy.platform_dunning_on_settlement();

-- --- Passage planifié ---------------------------------------------------------------------------------------------------------------------------------
-- Une fiche, sous son verrou : tout est recalculé ici, jamais repris d'un passage précédent. Après une panne, seul le dernier rappel dû part ; les précédents sont notés sautés.
CREATE FUNCTION drivy.platform_dunning_client_pass(p_client uuid, p_today date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE
  v_pol drivy.platform_dunning_policy; v_school uuid; v_school_status text; v_state jsonb; v_trial drivy.platform_trial_change; v_trial_end date;
  v_keep text[] := ARRAY[]::text[]; v_key text; v_row record; v_late integer; v_latest integer; v_d integer; v_step drivy.platform_dunning_step; v_delivery text;
  v_sent record; v_invoice uuid; v_due date; v_cycle integer; v_hold boolean; v_paused boolean; v_terminated boolean; v_base date; v_on date; v_id uuid;
  v_reminders integer := 0; v_warnings integer := 0; v_suspended integer := 0; v_lifted integer;
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  SELECT p.* INTO v_pol FROM drivy.platform_dunning_policy p;
  SELECT c.school_id, sc.status INTO v_school, v_school_status FROM drivy.platform_client c LEFT JOIN drivy.school sc ON sc.id = c.school_id WHERE c.id = p_client;
  UPDATE drivy.platform_dunning_exception e SET status = 'EXPIRED' WHERE e.client_id = p_client AND e.status = 'ACTIVE' AND e.ends_on < p_today;
  v_lifted := drivy.platform_dunning_lift_if_settled(p_client, p_today);
  v_terminated := EXISTS(SELECT 1 FROM drivy.platform_commercial_request r
    WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED' AND r.effective_on <= p_today);

  -- Essai : le dernier jour au fuseau de Zurich, relu à chaque passage. Une prolongation change la clé : l'ancienne alerte se ferme, une autre s'ouvre.
  SELECT t.* INTO v_trial FROM drivy.platform_trial_change t WHERE t.client_id = p_client ORDER BY t.sequence DESC LIMIT 1;
  IF v_trial.id IS NOT NULL AND NOT v_terminated
    AND NOT EXISTS(SELECT 1 FROM drivy.platform_paid_start ps WHERE ps.client_id = p_client AND ps.status = 'ACTIVE' AND ps.starts_on <= p_today) THEN
    v_trial_end := ((v_trial.ends_at - interval '1 millisecond') AT TIME ZONE 'Europe/Zurich')::date;
    IF v_trial_end < p_today THEN
      v_key := 'trial-ended:' || p_client || ':' || v_trial_end;
      PERFORM drivy.platform_dunning_alert(p_client, 'TRIAL_ENDED', v_key, NULL, v_trial_end);
      v_keep := v_keep || v_key;
    ELSIF v_trial_end - p_today <= v_pol.trial_alert_days THEN
      v_key := 'trial-ending:' || p_client || ':' || v_trial_end;
      PERFORM drivy.platform_dunning_alert(p_client, 'TRIAL_ENDING', v_key, NULL, v_trial_end);
      v_keep := v_keep || v_key;
    END IF;
  END IF;

  FOR v_row IN SELECT i.id, i.due_on FROM drivy.platform_invoice i
    WHERE i.client_id = p_client AND i.status = 'ISSUED' AND i.kind <> 'CREDIT_NOTE'
      AND (drivy.platform_invoice_settlement(i.id, p_today)->>'overdue')::boolean LOOP
    v_key := 'overdue:' || v_row.id;
    PERFORM drivy.platform_dunning_alert(p_client, 'NEW_OVERDUE', v_key, v_row.id, v_row.due_on);
    v_keep := v_keep || v_key;
  END LOOP;

  v_state := drivy.platform_dunning_state(p_client, p_today);
  IF (v_state->>'overdue')::boolean THEN
    v_invoice := (v_state->>'invoiceId')::uuid; v_due := (v_state->>'dueOn')::date; v_cycle := (v_state->>'cycle')::integer;
    v_hold := (v_state->>'hold')::boolean; v_base := (v_state->>'baseOn')::date; v_late := p_today - v_due;
    v_paused := EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.cause = 'PAYMENT' AND s.status = 'ACTIVE');

    -- Rappels : le palier le plus récent atteint, une seule fois. Rien pendant une exception d'arrêt ou une suspension pour impayé déjà effective.
    IF v_pol.reminders_enabled AND NOT v_hold AND NOT v_paused THEN
      SELECT max(d.v) INTO v_latest FROM unnest(v_pol.reminder_days) AS d(v) WHERE d.v <= v_late;
      IF v_latest IS NOT NULL AND NOT EXISTS(SELECT 1 FROM drivy.platform_dunning_step st WHERE st.client_id = p_client AND st.invoice_id = v_invoice
          AND st.cycle = v_cycle AND st.kind = 'REMINDER' AND st.offset_days = v_latest) THEN
        FOREACH v_d IN ARRAY v_pol.reminder_days LOOP
          CONTINUE WHEN v_d > v_latest;
          CONTINUE WHEN EXISTS(SELECT 1 FROM drivy.platform_dunning_step st WHERE st.client_id = p_client AND st.invoice_id = v_invoice
            AND st.cycle = v_cycle AND st.kind = 'REMINDER' AND st.offset_days = v_d);
          IF v_d < v_latest THEN
            INSERT INTO drivy.platform_dunning_step(client_id, invoice_id, due_on, cycle, kind, offset_days, planned_on, done_on, status)
            VALUES (p_client, v_invoice, v_due, v_cycle, 'REMINDER', v_d, v_due + v_d, p_today, 'SKIPPED');
          ELSE
            SELECT * INTO v_sent FROM drivy.platform_dunning_notify(p_client, v_school, 'PAYMENT_REMINDER', 'reminder:' || v_invoice || ':' || v_cycle || ':' || v_d);
            INSERT INTO drivy.platform_dunning_step(client_id, invoice_id, due_on, cycle, kind, offset_days, planned_on, done_on, status, recipient_count, notice_id)
            VALUES (p_client, v_invoice, v_due, v_cycle, 'REMINDER', v_d, v_due + v_d, p_today, 'RECORDED', v_sent.o_recipients, v_sent.o_notice)
            RETURNING id INTO v_id;
            PERFORM drivy.platform_dunning_audit('SEND_PAYMENT_REMINDER', v_school, 'PlatformInvoice', v_invoice,
              jsonb_build_object('stepId', v_id, 'invoiceId', v_invoice, 'dueOn', v_due, 'offsetDays', v_d, 'recipients', v_sent.o_recipients));
            v_reminders := v_reminders + 1;
          END IF;
        END LOOP;
      END IF;
    END IF;

    -- Avertissement puis suspension : jamais sans remise connue, jamais pendant une exception d'arrêt, une résiliation effective ou un archivage.
    IF v_pol.auto_suspend AND NOT v_hold AND NOT v_paused AND NOT v_terminated AND v_school IS NOT NULL AND v_school_status <> 'ARCHIVED' THEN
      SELECT st.* INTO v_step FROM drivy.platform_dunning_step st
        WHERE st.client_id = p_client AND st.invoice_id = v_invoice AND st.cycle = v_cycle AND st.kind = 'WARNING';
      IF v_step.id IS NULL AND p_today >= v_base - v_pol.warning_days THEN
        v_on := greatest(v_base, p_today + v_pol.warning_days);
        SELECT * INTO v_sent FROM drivy.platform_dunning_notify(p_client, v_school, 'SUSPENSION_WARNING', 'warning:' || v_invoice || ':' || v_cycle);
        INSERT INTO drivy.platform_dunning_step(client_id, invoice_id, due_on, cycle, kind, offset_days, planned_on, done_on, status, suspension_on, recipient_count, notice_id)
        VALUES (p_client, v_invoice, v_due, v_cycle, 'WARNING', 0, v_base - v_pol.warning_days, p_today, 'RECORDED', v_on, v_sent.o_recipients, v_sent.o_notice)
        RETURNING * INTO v_step;
        PERFORM drivy.platform_dunning_audit('SEND_SUSPENSION_WARNING', v_school, 'PlatformInvoice', v_invoice,
          jsonb_build_object('stepId', v_step.id, 'invoiceId', v_invoice, 'dueOn', v_due, 'suspensionOn', v_on, 'recipients', v_sent.o_recipients));
        v_warnings := v_warnings + 1;
      END IF;
      IF v_step.id IS NOT NULL THEN
        v_on := greatest(v_base, v_step.suspension_on);
        IF p_today < v_on THEN
          v_key := 'upcoming:' || v_invoice || ':' || v_cycle;
          PERFORM drivy.platform_dunning_alert(p_client, 'SUSPENSION_UPCOMING', v_key, v_invoice, v_on);
          v_keep := v_keep || v_key;
        ELSE
          v_delivery := drivy.platform_dunning_delivery(v_step.id);
          IF v_delivery IN ('READ', 'SENT', 'CONFIRMED') THEN
            v_id := gen_random_uuid();
            INSERT INTO drivy.platform_commercial_suspension(id, client_id, cause, origin, starts_on, invoice_id, due_on, months)
            VALUES (v_id, p_client, 'PAYMENT', 'AUTOMATIC', p_today, v_invoice, v_due, (v_state->>'months')::integer);
            SELECT * INTO v_sent FROM drivy.platform_dunning_notify(p_client, v_school, 'SUSPENDED', 'suspended:' || v_id);
            PERFORM drivy.platform_dunning_audit('SUSPEND_SCHOOL', v_school, 'PlatformSuspension', v_id,
              jsonb_build_object('suspensionId', v_id, 'cause', 'PAYMENT', 'invoiceId', v_invoice, 'dueOn', v_due, 'months', (v_state->>'months')::integer, 'startsOn', p_today));
            v_suspended := v_suspended + 1;
          ELSE
            -- Remise inconnue ou en échec à la date prévue : pas de suspension surprise, une action de l'opérateur.
            v_key := 'delivery:' || v_step.id;
            PERFORM drivy.platform_dunning_alert(p_client, 'DELIVERY_FAILED', v_key, v_invoice, p_today);
            v_keep := v_keep || v_key;
          END IF;
        END IF;
      END IF;
    END IF;

    FOR v_step IN SELECT st.* FROM drivy.platform_dunning_step st
      WHERE st.client_id = p_client AND st.invoice_id = v_invoice AND st.cycle = v_cycle AND st.status = 'RECORDED' LOOP
      IF drivy.platform_dunning_delivery(v_step.id) IN ('FAILED', 'NO_RECIPIENT') THEN
        v_key := 'delivery:' || v_step.id;
        PERFORM drivy.platform_dunning_alert(p_client, 'DELIVERY_FAILED', v_key, v_invoice, v_step.done_on);
        v_keep := v_keep || v_key;
      END IF;
    END LOOP;
  END IF;

  FOR v_row IN SELECT s.id, s.invoice_id, s.starts_on FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.status = 'ACTIVE' LOOP
    v_key := 'suspended:' || v_row.id;
    PERFORM drivy.platform_dunning_alert(p_client, 'SUSPENDED', v_key, v_row.invoice_id, v_row.starts_on);
    v_keep := v_keep || v_key;
  END LOOP;

  -- Ce qui n'est plus vrai se ferme de soi-même ; une alerte déjà traitée par un opérateur reste close.
  UPDATE drivy.platform_commercial_alert a SET status = 'RESOLVED', resolved_at = date_trunc('milliseconds', clock_timestamp()), resolved_cause = 'OBSOLETE'
    WHERE a.client_id = p_client AND a.status = 'OPEN' AND NOT a.dedupe_key = ANY(v_keep);
  RETURN jsonb_build_object('reminders', v_reminders, 'warnings', v_warnings, 'suspended', v_suspended, 'lifted', v_lifted);
END $$;

-- Chaque fiche dans sa sous-transaction : un échec n'arrête pas les autres et reprend au passage suivant. Le verrou évite deux passages simultanés.
CREATE FUNCTION drivy.platform_dunning_run_at(p_today date) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_id uuid; v_res jsonb; v_clients integer := 0; v_failed integer := 0; v_reminders integer := 0; v_warnings integer := 0; v_suspended integer := 0; v_lifted integer := 0;
BEGIN
  IF NOT pg_try_advisory_xact_lock(hashtextextended('platform-dunning-run', 0)) THEN RETURN jsonb_build_object('skipped', true); END IF;
  FOR v_id IN SELECT c.id FROM drivy.platform_client c WHERE
      EXISTS(SELECT 1 FROM drivy.platform_invoice i WHERE i.client_id = c.id AND i.status = 'ISSUED')
      OR EXISTS(SELECT 1 FROM drivy.platform_trial_change t WHERE t.client_id = c.id)
      OR EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s WHERE s.client_id = c.id AND s.status = 'ACTIVE')
      OR EXISTS(SELECT 1 FROM drivy.platform_dunning_exception e WHERE e.client_id = c.id AND e.status = 'ACTIVE')
      OR EXISTS(SELECT 1 FROM drivy.platform_commercial_alert a WHERE a.client_id = c.id AND a.status = 'OPEN')
    ORDER BY c.id LOOP
    v_clients := v_clients + 1;
    BEGIN
      v_res := drivy.platform_dunning_client_pass(v_id, p_today);
      v_reminders := v_reminders + (v_res->>'reminders')::integer; v_warnings := v_warnings + (v_res->>'warnings')::integer;
      v_suspended := v_suspended + (v_res->>'suspended')::integer; v_lifted := v_lifted + (v_res->>'lifted')::integer;
    EXCEPTION WHEN OTHERS THEN v_failed := v_failed + 1;
    END;
  END LOOP;
  RETURN jsonb_build_object('skipped', false, 'today', p_today, 'clients', v_clients, 'reminders', v_reminders, 'warnings', v_warnings,
    'suspended', v_suspended, 'lifted', v_lifted, 'failed', v_failed);
END $$;
CREATE FUNCTION drivy.platform_dunning_run() RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.platform_dunning_run_at(drivy.zurich_today())
$$;
CREATE FUNCTION drivy.platform_dunning_run_manual() RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  PERFORM drivy.platform_current_operator_required();
  RETURN drivy.platform_dunning_run_at(drivy.zurich_today());
END $$;

-- --- Console : politique ------------------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_dunning_policy_read() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  PERFORM drivy.platform_current_operator_required();
  RETURN (SELECT jsonb_build_object('remindersEnabled', p.reminders_enabled, 'autoSuspend', p.auto_suspend, 'reminderDays', to_jsonb(p.reminder_days),
      'suspensionMonths', p.suspension_months, 'warningDays', p.warning_days, 'trialAlertDays', p.trial_alert_days, 'version', p.version,
      'updatedAt', p.updated_at, 'updatedByName', o.display_name)
    FROM drivy.platform_dunning_policy p LEFT JOIN drivy.platform_operator o ON o.id = p.updated_by);
END $$;

CREATE FUNCTION drivy.platform_dunning_policy_update(p_expected integer, p_reminders boolean, p_auto boolean, p_days integer[], p_months integer, p_warning integer, p_trial integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required(); v_pol drivy.platform_dunning_policy;
BEGIN
  SELECT p.* INTO v_pol FROM drivy.platform_dunning_policy p FOR UPDATE;
  IF v_pol.version <> p_expected THEN RAISE EXCEPTION 'platform_dunning_policy_stale' USING ERRCODE='23514'; END IF;
  IF (p_auto AND NOT p_reminders) OR NOT drivy.platform_dunning_days_valid(p_days) OR p_months NOT BETWEEN 1 AND 12
    OR p_warning NOT BETWEEN 3 AND 28 OR p_trial NOT BETWEEN 1 AND 30 THEN
    RAISE EXCEPTION 'platform_dunning_policy_invalid' USING ERRCODE='23514';
  END IF;
  UPDATE drivy.platform_dunning_policy p SET reminders_enabled = p_reminders, auto_suspend = p_auto, reminder_days = p_days, suspension_months = p_months,
    warning_days = p_warning, trial_alert_days = p_trial, version = v_pol.version + 1, updated_by = v_actor,
    updated_at = date_trunc('milliseconds', clock_timestamp()) WHERE p.singleton;
  RETURN drivy.platform_dunning_policy_read();
END $$;

-- --- Console : dossier d'une école --------------------------------------------------------------------------------------------------------------------
CREATE FUNCTION drivy.platform_dunning_version(p_client uuid) RETURNS integer
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  PERFORM drivy.platform_current_operator_required();
  RETURN (1
    + (SELECT count(*) + count(*) FILTER (WHERE e.status <> 'ACTIVE') FROM drivy.platform_dunning_exception e WHERE e.client_id = p_client)
    + (SELECT coalesce(sum(s.version), 0) FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client)
    + (SELECT count(*) + count(st.confirmed_at) FROM drivy.platform_dunning_step st WHERE st.client_id = p_client))::integer;
END $$;

CREATE FUNCTION drivy.platform_dunning_view(p_client uuid) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_today date := drivy.zurich_today();
BEGIN
  PERFORM drivy.platform_current_operator_required();
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_client c WHERE c.id = p_client) THEN RETURN NULL; END IF;
  RETURN jsonb_build_object(
    'today', v_today,
    'state', drivy.platform_dunning_state(p_client, v_today),
    'recipients', (SELECT count(*)::integer FROM drivy.platform_client c JOIN drivy.membership m ON m.school_id = c.school_id JOIN drivy.person pe ON pe.id = m.person_id
      WHERE c.id = p_client AND m.status = 'ACTIVE' AND pe.status = 'ACTIVE' AND 'ADMIN' = ANY(m.roles)),
    'exceptions', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'kind', e.kind, 'suspensionMonths', e.suspension_months, 'endsOn', e.ends_on,
        'reason', e.reason, 'status', CASE WHEN e.status = 'ACTIVE' AND e.ends_on < v_today THEN 'EXPIRED' ELSE e.status END,
        'createdAt', e.created_at, 'createdByName', o.display_name, 'revokedAt', e.revoked_at, 'revokeReason', e.revoke_reason)
        ORDER BY e.created_at DESC, e.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_dunning_exception x WHERE x.client_id = p_client ORDER BY x.created_at DESC, x.id DESC LIMIT 20) e
      LEFT JOIN drivy.platform_operator o ON o.id = e.created_by),
    'suspensions', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'cause', s.cause, 'origin', s.origin, 'status', s.status, 'startsOn', s.starts_on,
        'invoiceNumber', i.number, 'dueOn', s.due_on, 'months', s.months, 'reason', s.reason, 'createdByName', o.display_name, 'liftedOn', s.lifted_on,
        'liftCause', s.lift_cause, 'liftReason', s.lift_reason, 'liftedByName', l.display_name) ORDER BY s.started_at DESC, s.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_commercial_suspension x WHERE x.client_id = p_client ORDER BY x.started_at DESC, x.id DESC LIMIT 20) s
      LEFT JOIN drivy.platform_invoice i ON i.id = s.invoice_id LEFT JOIN drivy.platform_operator o ON o.id = s.created_by
      LEFT JOIN drivy.platform_operator l ON l.id = s.lifted_by),
    'steps', (SELECT coalesce(jsonb_agg(jsonb_build_object('id', st.id, 'kind', st.kind, 'invoiceNumber', i.number, 'dueOn', st.due_on, 'offsetDays', st.offset_days,
        'plannedOn', st.planned_on, 'doneOn', st.done_on, 'status', st.status, 'suspensionOn', st.suspension_on, 'recipientCount', st.recipient_count,
        'delivery', drivy.platform_dunning_delivery(st.id), 'confirmedAt', st.confirmed_at, 'confirmedByName', o.display_name, 'confirmReason', st.confirm_reason)
        ORDER BY st.created_at DESC, st.id DESC), '[]'::jsonb)
      FROM (SELECT * FROM drivy.platform_dunning_step x WHERE x.client_id = p_client ORDER BY x.created_at DESC, x.id DESC LIMIT 40) st
      JOIN drivy.platform_invoice i ON i.id = st.invoice_id LEFT JOIN drivy.platform_operator o ON o.id = st.confirmed_by),
    'version', drivy.platform_dunning_version(p_client));
END $$;

CREATE FUNCTION drivy.platform_dunning_exception_create(p_client uuid, p_id uuid, p_kind text, p_months integer, p_ends_on date, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required(); v_today date := drivy.zurich_today();
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  IF p_ends_on < v_today OR p_ends_on > v_today + 366 THEN RAISE EXCEPTION 'platform_dunning_exception_date' USING ERRCODE='23514'; END IF;
  IF p_kind NOT IN ('DELAY', 'HOLD') OR (p_kind = 'DELAY') <> (p_months IS NOT NULL) OR coalesce(p_months NOT BETWEEN 1 AND 24, false) THEN
    RAISE EXCEPTION 'platform_dunning_exception_invalid' USING ERRCODE='23514';
  END IF;
  UPDATE drivy.platform_dunning_exception e SET status = 'EXPIRED' WHERE e.client_id = p_client AND e.status = 'ACTIVE' AND e.ends_on < v_today;
  IF EXISTS(SELECT 1 FROM drivy.platform_dunning_exception e WHERE e.client_id = p_client AND e.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'platform_dunning_exception_active' USING ERRCODE='23514';
  END IF;
  INSERT INTO drivy.platform_dunning_exception(id, client_id, kind, suspension_months, ends_on, reason, created_by)
  VALUES (p_id, p_client, p_kind, p_months, p_ends_on, btrim(p_reason), v_actor);
  RETURN p_id;
END $$;

CREATE FUNCTION drivy.platform_dunning_exception_revoke(p_client uuid, p_id uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required();
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  UPDATE drivy.platform_dunning_exception e SET status = 'REVOKED', revoked_by = v_actor, revoked_at = date_trunc('milliseconds', clock_timestamp()), revoke_reason = btrim(p_reason)
    WHERE e.id = p_id AND e.client_id = p_client AND e.status = 'ACTIVE';
  IF NOT FOUND THEN RAISE EXCEPTION 'platform_dunning_exception_closed' USING ERRCODE='23514'; END IF;
  RETURN p_id;
END $$;

-- Suspension décidée par un opérateur. Pour impayé : seulement si la dette a atteint son délai et hors exception d'arrêt. La cause reste celle qu'il a choisie.
CREATE FUNCTION drivy.platform_suspension_create(p_client uuid, p_id uuid, p_cause text, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required(); v_today date := drivy.zurich_today(); v_school uuid; v_status text; v_state jsonb; v_sent record;
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  SELECT c.school_id, sc.status INTO v_school, v_status FROM drivy.platform_client c LEFT JOIN drivy.school sc ON sc.id = c.school_id WHERE c.id = p_client;
  IF v_school IS NULL THEN RAISE EXCEPTION 'platform_suspension_no_school' USING ERRCODE='23514'; END IF;
  IF v_status = 'ARCHIVED' THEN RAISE EXCEPTION 'platform_suspension_archived' USING ERRCODE='23514'; END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_commercial_request r WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status = 'ACCEPTED' AND r.effective_on <= v_today) THEN
    RAISE EXCEPTION 'platform_client_terminated' USING ERRCODE='23514';
  END IF;
  IF EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.cause = p_cause AND s.status = 'ACTIVE') THEN
    RAISE EXCEPTION 'platform_suspension_active' USING ERRCODE='23514';
  END IF;
  IF p_cause = 'PAYMENT' THEN
    v_state := drivy.platform_dunning_state(p_client, v_today);
    IF NOT (v_state->>'overdue')::boolean OR v_today < (v_state->>'baseOn')::date THEN RAISE EXCEPTION 'platform_suspension_no_debt' USING ERRCODE='23514'; END IF;
    IF (v_state->>'hold')::boolean THEN RAISE EXCEPTION 'platform_suspension_hold' USING ERRCODE='23514'; END IF;
    INSERT INTO drivy.platform_commercial_suspension(id, client_id, cause, origin, starts_on, invoice_id, due_on, months, reason, created_by)
    VALUES (p_id, p_client, 'PAYMENT', 'OPERATOR', v_today, (v_state->>'invoiceId')::uuid, (v_state->>'dueOn')::date, (v_state->>'months')::integer, btrim(p_reason), v_actor);
  ELSE
    INSERT INTO drivy.platform_commercial_suspension(id, client_id, cause, origin, starts_on, reason, created_by)
    VALUES (p_id, p_client, 'MANUAL', 'OPERATOR', v_today, btrim(p_reason), v_actor);
  END IF;
  SELECT * INTO v_sent FROM drivy.platform_dunning_notify(p_client, v_school, 'SUSPENDED', 'suspended:' || p_id);
  PERFORM drivy.platform_dunning_alert(p_client, 'SUSPENDED', 'suspended:' || p_id, (v_state->>'invoiceId')::uuid, v_today);
  RETURN p_id;
END $$;

-- Levée par un opérateur, motivée. Une suspension pour impayé dont la dette reste due ne se lève que sous une exception active.
CREATE FUNCTION drivy.platform_suspension_lift(p_client uuid, p_id uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required(); v_today date := drivy.zurich_today(); v_susp drivy.platform_commercial_suspension;
  v_oldest record; v_school uuid; v_sent record; v_on date;
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  SELECT s.* INTO v_susp FROM drivy.platform_commercial_suspension s WHERE s.id = p_id AND s.client_id = p_client FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'platform_suspension_unknown' USING ERRCODE='23514'; END IF;
  IF v_susp.status <> 'ACTIVE' THEN RAISE EXCEPTION 'platform_suspension_lifted' USING ERRCODE='23514'; END IF;
  IF v_susp.cause = 'PAYMENT' THEN
    SELECT o.* INTO v_oldest FROM drivy.platform_dunning_oldest(p_client, v_today) o;
    IF FOUND AND drivy.platform_dunning_months_after(v_oldest.due_on, v_susp.months) <= v_today
      AND NOT EXISTS(SELECT 1 FROM drivy.platform_dunning_exception e WHERE e.client_id = p_client AND e.status = 'ACTIVE' AND e.ends_on >= v_today) THEN
      RAISE EXCEPTION 'platform_suspension_debt_remaining' USING ERRCODE='23514';
    END IF;
  END IF;
  v_on := greatest(v_today, v_susp.starts_on);
  UPDATE drivy.platform_commercial_suspension s SET status = 'LIFTED', lifted_on = v_on, lifted_at = date_trunc('milliseconds', clock_timestamp()),
    lifted_by = v_actor, lift_cause = 'OPERATOR', lift_reason = btrim(p_reason), version = v_susp.version + 1 WHERE s.id = p_id;
  SELECT c.school_id INTO v_school FROM drivy.platform_client c WHERE c.id = p_client;
  IF NOT EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.status = 'ACTIVE') THEN
    SELECT * INTO v_sent FROM drivy.platform_dunning_notify(p_client, v_school, 'REACTIVATED', 'reactivated:' || p_id);
  END IF;
  UPDATE drivy.platform_commercial_alert a SET status = 'RESOLVED', resolved_at = date_trunc('milliseconds', clock_timestamp()), resolved_cause = 'OBSOLETE'
    WHERE a.client_id = p_client AND a.status = 'OPEN' AND a.dedupe_key = 'suspended:' || p_id;
  RETURN p_id;
END $$;

-- Remise confirmée par un autre canal (appel, courrier) après un échec connu : c'est un fait attesté par un opérateur, avec son motif.
CREATE FUNCTION drivy.platform_dunning_warning_confirm(p_client uuid, p_step uuid, p_reason text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required();
BEGIN
  PERFORM drivy.platform_client_lock(p_client);
  UPDATE drivy.platform_dunning_step st SET confirmed_by = v_actor, confirmed_at = date_trunc('milliseconds', clock_timestamp()), confirm_reason = btrim(p_reason)
    WHERE st.id = p_step AND st.client_id = p_client AND st.kind = 'WARNING' AND st.confirmed_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'platform_dunning_step_closed' USING ERRCODE='23514'; END IF;
  UPDATE drivy.platform_commercial_alert a SET status = 'RESOLVED', resolved_at = date_trunc('milliseconds', clock_timestamp()), resolved_cause = 'OBSOLETE'
    WHERE a.client_id = p_client AND a.status = 'OPEN' AND a.dedupe_key = 'delivery:' || p_step;
  RETURN p_step;
END $$;

CREATE FUNCTION drivy.platform_commercial_alerts() RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
  PERFORM drivy.platform_current_operator_required();
  RETURN (SELECT coalesce(jsonb_agg(jsonb_build_object('id', a.id, 'clientId', a.client_id, 'clientName', c.display_name, 'kind', a.kind,
      'invoiceNumber', i.number, 'onDate', a.on_date, 'openedAt', a.opened_at) ORDER BY a.opened_at DESC, a.id DESC), '[]'::jsonb)
    FROM (SELECT * FROM drivy.platform_commercial_alert x WHERE x.status = 'OPEN' ORDER BY x.opened_at DESC, x.id DESC LIMIT 100) a
    JOIN drivy.platform_client c ON c.id = a.client_id LEFT JOIN drivy.platform_invoice i ON i.id = a.invoice_id);
END $$;

CREATE FUNCTION drivy.platform_commercial_alert_ack(p_alert uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE v_actor uuid := drivy.platform_current_operator_required(); v_client uuid;
BEGIN
  UPDATE drivy.platform_commercial_alert a SET status = 'RESOLVED', resolved_at = date_trunc('milliseconds', clock_timestamp()), resolved_cause = 'OPERATOR',
    acknowledged_by = v_actor, acknowledged_at = date_trunc('milliseconds', clock_timestamp())
    WHERE a.id = p_alert AND a.status = 'OPEN' RETURNING a.client_id INTO v_client;
  IF v_client IS NULL THEN RAISE EXCEPTION 'platform_alert_closed' USING ERRCODE='23514'; END IF;
  RETURN v_client;
END $$;

-- --- École : ce qu'elle voit et ce qui lui est fermé ------------------------------------------------------------------------------------------------
-- Ni motif, ni auteur, ni exception. La date de suspension n'apparaît qu'une fois annoncée par un avertissement.
CREATE FUNCTION drivy.school_dunning_json(p_client uuid, p_today date) RETURNS jsonb
LANGUAGE plpgsql STABLE SET search_path=pg_catalog,drivy AS $$
DECLARE v_state jsonb; v_causes jsonb; v_since date;
BEGIN
  v_state := drivy.platform_dunning_state(p_client, p_today);
  SELECT coalesce(jsonb_agg(s.cause ORDER BY s.cause), '[]'::jsonb), min(s.starts_on) INTO v_causes, v_since
    FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.status = 'ACTIVE';
  IF NOT (v_state->>'overdue')::boolean AND v_since IS NULL THEN RETURN NULL; END IF;
  RETURN jsonb_build_object('suspended', v_since IS NOT NULL, 'causes', v_causes, 'since', v_since,
    'invoiceNumber', v_state->'invoiceNumber', 'dueOn', v_state->'dueOn', 'balance', v_state->'balance',
    'suspensionOn', CASE WHEN v_since IS NULL AND v_state->>'warningStepId' IS NOT NULL AND NOT (v_state->>'hold')::boolean THEN v_state->'suspensionOn' END);
END $$;

-- Porte des commandes métier : relue au serveur à chaque écriture, quel que soit l'âge du client.
CREATE FUNCTION drivy.school_commercially_suspended(p_school uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT coalesce(p_school = nullif(current_setting('app.school_id', true), '')::uuid, false)
    AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.school_id = p_school AND m.status = 'ACTIVE'
      AND m.person_id = nullif(current_setting('app.person_id', true), '')::uuid)
    AND EXISTS(SELECT 1 FROM drivy.platform_commercial_suspension s JOIN drivy.platform_client c ON c.id = s.client_id
      WHERE c.school_id = p_school AND s.status = 'ACTIVE')
$$;

-- --- Fonctions existantes : suspension dans le droit aux modules, pause de facturation, vue de l'école -------------------------------------------------
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
  susp AS (SELECT s.cause FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client AND s.status = 'ACTIVE'),
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
    'restriction', (SELECT CASE
       WHEN lc.lifecycle = 'TERMINATED' THEN jsonb_build_object('reason', 'TERMINATED', 'closes', jsonb_build_array('WRITE_NEW'))
       WHEN EXISTS(SELECT 1 FROM susp) THEN jsonb_build_object('reason', 'SUSPENDED', 'closes', jsonb_build_array('WRITE_NEW'),
         'causes', (SELECT jsonb_agg(susp.cause ORDER BY susp.cause) FROM susp))
       WHEN lc.lifecycle = 'TRIAL_EXPIRED' THEN jsonb_build_object('reason', 'TRIAL_EXPIRED', 'closes', jsonb_build_array('WRITE_NEW')) END FROM lc),
    'trial', (SELECT jsonb_build_object('startsAt', trial.starts_at, 'endsAt', trial.ends_at) FROM trial),
    'paidStartsOn', (SELECT paid.starts_on FROM paid),
    'terminationOn', (SELECT term.effective_on FROM term),
    'assignment', (SELECT jsonb_build_object('id', cur.id, 'offerId', cur.offer_id, 'offerName', cur.offer_name, 'effectiveAt', cur.effective_at,
       'modules', to_jsonb(cur.modules)) FROM cur),
    'scheduled', (SELECT jsonb_build_object('id', nxt.id, 'offerId', nxt.offer_id, 'offerName', nxt.offer_name, 'effectiveAt', nxt.effective_at,
       'modules', to_jsonb(nxt.modules)) FROM nxt),
    'modules', (SELECT jsonb_agg(jsonb_build_object('code', p.code, 'inOffer', p.in_offer, 'adjustment', p.adjustment,
       'entitled', CASE WHEN (SELECT lifecycle FROM lc) IN ('TRIAL_EXPIRED', 'TERMINATED') OR EXISTS(SELECT 1 FROM susp) THEN false
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
         FROM drivy.platform_commercial_request r, clock WHERE r.client_id = p_client AND r.kind = 'TERMINATION' AND r.status IN ('ACCEPTED', 'REVOKED'))
      + (SELECT coalesce(sum(1 + CASE WHEN s.status = 'LIFTED' THEN 1 ELSE 0 END), 0)::integer
         FROM drivy.platform_commercial_suspension s WHERE s.client_id = p_client),
    'nextChangeAt', (SELECT least(
        (SELECT nxt.effective_at FROM nxt),
        (SELECT trial.starts_at FROM trial WHERE trial.starts_at > clock.t),
        (SELECT trial.ends_at FROM trial WHERE trial.ends_at > clock.t),
        (SELECT paid.at FROM paid WHERE paid.at > clock.t),
        (SELECT term.at FROM term WHERE term.at > clock.t)) FROM clock))
$$;

CREATE OR REPLACE FUNCTION drivy.platform_invoice_compute(p_client uuid, p_kind text, p_period_start date) RETURNS jsonb
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
  IF drivy.platform_period_paused(p_client, p_period_start) THEN RAISE EXCEPTION 'platform_invoice_period_paused' USING ERRCODE='23514'; END IF;
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

CREATE OR REPLACE FUNCTION drivy.platform_billing_run_at(p_today date) RETURNS jsonb
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
        -- Contrat en PAUSE et suspension couvrant le début de la période : rien à facturer, un brouillon planifié est annulé avec son motif.
        IF outcome = 'PERIOD' AND drivy.platform_period_paused(act.client_id, start) THEN
          IF inv.id IS NOT NULL THEN
            UPDATE drivy.platform_invoice SET status = 'CANCELLED', reason = 'Facturation en pause pendant la suspension', version = inv.version + 1 WHERE id = inv.id;
            INSERT INTO drivy.platform_audit_event(id, actor_kind, actor_name, action, result, school_id, subject_type, subject_id, changes)
              VALUES(gen_random_uuid(), 'SYSTEM', 'Facturation planifiée', 'CANCEL_INVOICE_DRAFT', 'SUCCESS', school, 'PlatformInvoice', inv.id,
                jsonb_build_object('invoiceId', inv.id, 'kind', outcome, 'periodStart', start, 'reason', 'SUSPENSION_PAUSE'));
          END IF;
          CONTINUE;
        END IF;
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

CREATE OR REPLACE FUNCTION drivy.school_commercial_view(p_school uuid) RETURNS jsonb
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
    'dunning', drivy.school_dunning_json(c.id, today),
    'version', (core->>'version')::integer
      + (SELECT count(*)::integer FROM drivy.platform_commercial_terms t WHERE t.client_id = c.id)
      + (SELECT coalesce(sum(r.version), 0)::integer FROM drivy.platform_commercial_request r WHERE r.client_id = c.id));
END $$;


-- --- Droits ----------------------------------------------------------------------------------------------------------------------------------------------
REVOKE ALL ON FUNCTION drivy.platform_dunning_days_valid(integer[]), drivy.platform_dunning_months_after(date, integer), drivy.platform_dunning_oldest(uuid, date),
  drivy.platform_dunning_delivery(uuid), drivy.platform_dunning_state(uuid, date), drivy.platform_period_paused(uuid, date),
  drivy.platform_dunning_audit(text, uuid, text, uuid, jsonb), drivy.platform_dunning_alert(uuid, text, text, uuid, date),
  drivy.platform_dunning_notify(uuid, uuid, text, text), drivy.platform_dunning_lift_if_settled(uuid, date), drivy.platform_dunning_client_pass(uuid, date),
  drivy.platform_dunning_run_at(date), drivy.platform_dunning_run(), drivy.platform_dunning_run_manual(), drivy.platform_dunning_policy_read(),
  drivy.platform_dunning_policy_update(integer, boolean, boolean, integer[], integer, integer, integer), drivy.platform_dunning_version(uuid),
  drivy.platform_dunning_view(uuid), drivy.platform_dunning_exception_create(uuid, uuid, text, integer, date, text),
  drivy.platform_dunning_exception_revoke(uuid, uuid, text), drivy.platform_suspension_create(uuid, uuid, text, text), drivy.platform_suspension_lift(uuid, uuid, text),
  drivy.platform_dunning_warning_confirm(uuid, uuid, text), drivy.platform_commercial_alerts(), drivy.platform_commercial_alert_ack(uuid),
  drivy.school_dunning_json(uuid, date), drivy.school_commercially_suspended(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.platform_dunning_run_manual(), drivy.platform_dunning_policy_read(),
  drivy.platform_dunning_policy_update(integer, boolean, boolean, integer[], integer, integer, integer), drivy.platform_dunning_version(uuid),
  drivy.platform_dunning_view(uuid), drivy.platform_dunning_exception_create(uuid, uuid, text, integer, date, text),
  drivy.platform_dunning_exception_revoke(uuid, uuid, text), drivy.platform_suspension_create(uuid, uuid, text, text), drivy.platform_suspension_lift(uuid, uuid, text),
  drivy.platform_dunning_warning_confirm(uuid, uuid, text), drivy.platform_commercial_alerts(), drivy.platform_commercial_alert_ack(uuid),
  drivy.school_commercially_suspended(uuid) TO drivy_app;
GRANT EXECUTE ON FUNCTION drivy.platform_dunning_run() TO drivy_billing_worker;
