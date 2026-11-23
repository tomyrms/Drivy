-- R01-T10 (#462) : tableau de bord commercial de l'équipe Drivy. Aucune table : une seule lecture, calculée sur les sources déjà utilisées par les
-- fiches, la facturation, les règlements et les relances (droits, règlement d'une facture, dette, conditions, état de relance).
-- Aucune donnée d'élève, de trajet ni de message n'est lue.
--
-- Définitions :
-- * situation : état commercial exclusif (résiliée, archivée, suspendue, essai terminé, essai, active, préparation) ; `preparation` reste l'état
--   métier de l'école et n'est jamais fusionné avec lui.
-- * facturé / avoirs : documents émis dont la date d'émission tombe dans la période. Encaissé : règlements enregistrés reçus dans la période.
--   Régularisé : régularisations actives créées dans la période (jour de Zurich).
-- * restant dû / en retard : photographie du jour, indépendante de la période.
-- * revenu mensuel contractuel : mensualité moins remise récurrente de la période en cours, pour une école payante. Hors montant initial et
--   encaissements. `MISSING` (condition absente) et `PAUSED` (facturation en pause) ne comptent pas comme zéro : ils sont dénombrés à part.
CREATE FUNCTION drivy.platform_commercial_dashboard(p_from date, p_to date) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE
  v_today date := drivy.zurich_today();
  v_horizon date := drivy.zurich_today() + 30;
  v_auto boolean;
  v_result jsonb;
BEGIN
  PERFORM drivy.platform_current_operator_required();
  IF p_from IS NULL OR p_to IS NULL OR p_from > p_to OR p_to - p_from > 366 THEN
    RAISE EXCEPTION 'platform_dashboard_period_invalid' USING ERRCODE='22023';
  END IF;
  SELECT p.auto_suspend INTO v_auto FROM drivy.platform_dunning_policy p;

  WITH base AS (
    SELECT c.id, coalesce(s.name, c.display_name) AS name, c.created_at,
      CASE WHEN c.school_id IS NULL THEN 'AWAITING_SCHOOL' WHEN s.status = 'ACTIVE' THEN 'ACTIVE' WHEN s.status = 'ARCHIVED' THEN 'ARCHIVED'
        ELSE 'IN_PREPARATION' END AS preparation,
      drivy.platform_client_entitlement_core(c.id) AS ent,
      drivy.platform_client_debt(c.id, v_today) AS debt
    FROM drivy.platform_client c LEFT JOIN drivy.school s ON s.id = c.school_id
  ), shaped AS (
    SELECT b.*, b.ent->>'lifecycle' AS lifecycle, (b.ent->>'paidStartsOn')::date AS paid_on, (b.ent->>'terminationOn')::date AS termination_on,
      CASE WHEN b.ent->>'lifecycle' = 'TERMINATED' THEN 'TERMINATED'
        WHEN b.preparation = 'ARCHIVED' THEN 'ARCHIVED'
        WHEN b.ent->'restriction'->>'reason' = 'SUSPENDED' THEN 'SUSPENDED'
        WHEN b.ent->>'lifecycle' = 'TRIAL_EXPIRED' THEN 'TRIAL_EXPIRED'
        WHEN b.ent->>'lifecycle' = 'TRIAL' THEN 'TRIAL'
        WHEN b.ent->>'lifecycle' = 'PAID' THEN 'ACTIVE'
        ELSE 'PREPARATION' END AS situation,
      -- Dernier jour d'essai à Zurich : la fin enregistrée est exclue.
      CASE WHEN b.ent->>'lifecycle' = 'TRIAL'
        THEN (((b.ent->'trial'->>'endsAt')::timestamptz - interval '1 millisecond') AT TIME ZONE 'Europe/Zurich')::date END AS trial_last_day
    FROM base b
  ), priced AS (
    SELECT x.*, p.period_start, t.id AS terms_id, t.monthly_amount,
      CASE WHEN x.lifecycle <> 'PAID' THEN 'NONE'
        WHEN t.id IS NULL OR t.monthly_amount IS NULL THEN 'MISSING'
        WHEN drivy.platform_period_paused(x.id, p.period_start) THEN 'PAUSED'
        ELSE 'DEFINED' END AS monthly_state,
      CASE WHEN x.lifecycle = 'PAID' AND t.monthly_amount IS NOT NULL AND NOT drivy.platform_period_paused(x.id, p.period_start) THEN
        t.monthly_amount - CASE WHEN t.recurring_discount > 0 AND (t.recurring_discount_months IS NULL
            OR p.idx - CASE WHEN t.effective_from <= x.paid_on THEN 0 ELSE drivy.billing_period_index(x.paid_on, t.effective_from - 1) + 1 END
              < t.recurring_discount_months)
          THEN least(t.recurring_discount, t.monthly_amount) ELSE 0 END END AS monthly,
      CASE WHEN x.paid_on IS NULL OR x.lifecycle = 'TERMINATED' THEN NULL
        WHEN x.termination_on IS NOT NULL AND x.termination_on <= drivy.billing_period_start(x.paid_on, drivy.billing_period_index(x.paid_on, v_today) + 1) THEN NULL
        ELSE drivy.billing_period_start(x.paid_on, drivy.billing_period_index(x.paid_on, v_today) + 1) END AS next_renewal
    FROM shaped x
    LEFT JOIN LATERAL (SELECT drivy.billing_period_index(x.paid_on, v_today) AS idx,
      drivy.billing_period_start(x.paid_on, greatest(drivy.billing_period_index(x.paid_on, v_today), 0)) AS period_start) p ON x.paid_on IS NOT NULL
    LEFT JOIN LATERAL drivy.platform_terms_at(x.id, p.period_start) t ON x.lifecycle = 'PAID'
  ), flows AS (
    SELECT r.*, i.invoiced, i.invoice_count, i.credited, i.credit_count, c.collected, c.payment_count, g.regularized
    FROM priced r
    CROSS JOIN LATERAL (SELECT
        coalesce(sum(n.total) FILTER (WHERE n.kind <> 'CREDIT_NOTE'), 0)::bigint AS invoiced, count(*) FILTER (WHERE n.kind <> 'CREDIT_NOTE') AS invoice_count,
        coalesce(sum(n.total) FILTER (WHERE n.kind = 'CREDIT_NOTE'), 0)::bigint AS credited, count(*) FILTER (WHERE n.kind = 'CREDIT_NOTE') AS credit_count
      FROM drivy.platform_invoice n WHERE n.client_id = r.id AND n.status = 'ISSUED' AND n.issued_on BETWEEN p_from AND p_to) i
    CROSS JOIN LATERAL (SELECT coalesce(sum(p.amount), 0)::bigint AS collected, count(*) AS payment_count FROM drivy.platform_payment p
      WHERE p.client_id = r.id AND p.status = 'RECORDED' AND p.received_on BETWEEN p_from AND p_to) c
    CROSS JOIN LATERAL (SELECT coalesce(sum(a.amount), 0)::bigint AS regularized FROM drivy.platform_payment_regularization a
      WHERE a.client_id = r.id AND a.status = 'ACTIVE' AND (a.created_at AT TIME ZONE 'Europe/Zurich')::date BETWEEN p_from AND p_to) g
  ), acted AS (
    SELECT f.*, coalesce(a.items, '[]'::jsonb) AS actions
    FROM flows f
    CROSS JOIN LATERAL (
      SELECT jsonb_agg(jsonb_build_object('kind', q.kind, 'onDate', q.on_date, 'amount', q.amount, 'count', q.n, 'codes', to_jsonb(q.codes))
        ORDER BY q.rank, q.on_date NULLS LAST, q.codes) AS items
      FROM (
        SELECT 1 AS rank, 'SUSPENSION_UPCOMING' AS kind, (d.st->>'suspensionOn')::date AS on_date, (d.st->>'balance')::bigint AS amount, 1::bigint AS n, ARRAY[]::text[] AS codes
        FROM (SELECT drivy.platform_dunning_state(f.id, v_today) AS st) d
        WHERE v_auto AND f.situation NOT IN ('SUSPENDED', 'TERMINATED', 'ARCHIVED') AND (d.st->>'overdue')::boolean AND NOT (d.st->>'hold')::boolean
          AND (d.st->>'suspensionOn')::date <= v_horizon
        UNION ALL
        SELECT 2, 'OVERDUE', (f.debt->>'oldestOverdueDueOn')::date, (f.debt->>'overdueAmount')::bigint, (f.debt->>'overdueCount')::bigint, ARRAY[]::text[]
        WHERE (f.debt->>'overdueCount')::integer > 0
        UNION ALL
        SELECT 3, 'DELIVERY_FAILED', max((l.finished_at AT TIME ZONE 'Europe/Zurich')::date), NULL, count(*), ARRAY[]::text[]
        FROM (SELECT DISTINCT ON (v.invoice_id) v.status, v.finished_at FROM drivy.platform_invoice_delivery v
          WHERE v.client_id = f.id ORDER BY v.invoice_id, v.requested_at DESC, v.id DESC) l
        WHERE l.status IN ('FAILED', 'UNCERTAIN') HAVING count(*) > 0
        UNION ALL
        SELECT 4, 'REQUEST_OPEN', coalesce(q.desired_on, q.requested_on), NULL, 1, ARRAY[q.kind]
        FROM drivy.platform_commercial_request q WHERE q.client_id = f.id AND q.status IN ('RECEIVED', 'IN_PROGRESS')
        UNION ALL
        SELECT 5, 'TERMS_MISSING', f.paid_on, NULL, 1, m.codes
        FROM (SELECT drivy.platform_terms_missing(f.id, drivy.platform_terms_at(f.id, greatest(v_today, f.paid_on))) AS codes) m
        WHERE f.paid_on IS NOT NULL AND f.situation NOT IN ('TERMINATED', 'ARCHIVED') AND cardinality(m.codes) > 0
        UNION ALL
        SELECT 6, 'OPENING_INCOMPLETE', NULL, NULL, 1, ARRAY[f.preparation]
        WHERE f.preparation IN ('AWAITING_SCHOOL', 'IN_PREPARATION') AND f.situation <> 'TERMINATED'
      ) q
    ) a
  ), listed AS (
    SELECT * FROM acted ORDER BY jsonb_array_length(actions) = 0, name, id LIMIT 500
  )
  SELECT jsonb_build_object(
    'today', v_today, 'from', p_from, 'to', p_to, 'horizonOn', v_horizon, 'autoSuspend', coalesce(v_auto, false),
    'totals', (SELECT jsonb_build_object(
      'clients', count(*),
      'invoiced', coalesce(sum(invoiced), 0), 'invoiceCount', coalesce(sum(invoice_count), 0),
      'credited', coalesce(sum(credited), 0), 'creditCount', coalesce(sum(credit_count), 0),
      'collected', coalesce(sum(collected), 0), 'paymentCount', coalesce(sum(payment_count), 0),
      'regularized', coalesce(sum(regularized), 0),
      'outstanding', coalesce(sum((debt->>'outstanding')::bigint), 0),
      'overdue', coalesce(sum((debt->>'overdueAmount')::bigint), 0), 'overdueInvoices', coalesce(sum((debt->>'overdueCount')::bigint), 0),
      'monthly', coalesce(sum(monthly), 0), 'monthlyClients', count(*) FILTER (WHERE monthly_state = 'DEFINED'),
      'monthlyMissing', count(*) FILTER (WHERE monthly_state = 'MISSING'), 'monthlyPaused', count(*) FILTER (WHERE monthly_state = 'PAUSED'),
      'renewalsSoon', count(*) FILTER (WHERE next_renewal <= v_horizon), 'trialsEndingSoon', count(*) FILTER (WHERE trial_last_day <= v_horizon),
      'withActions', count(*) FILTER (WHERE jsonb_array_length(actions) > 0)) FROM acted),
    'situations', (SELECT jsonb_object_agg(k.key, (SELECT count(*) FROM acted a WHERE a.situation = k.key))
      FROM unnest(ARRAY['PREPARATION', 'TRIAL', 'TRIAL_EXPIRED', 'ACTIVE', 'SUSPENDED', 'TERMINATED', 'ARCHIVED']) AS k(key)),
    'preparations', (SELECT jsonb_object_agg(k.key, (SELECT count(*) FROM acted a WHERE a.preparation = k.key))
      FROM unnest(ARRAY['AWAITING_SCHOOL', 'IN_PREPARATION', 'ACTIVE', 'ARCHIVED']) AS k(key)),
    'truncated', (SELECT count(*) > 500 FROM acted),
    'clients', coalesce((SELECT jsonb_agg(jsonb_build_object(
        'id', l.id, 'name', l.name, 'situation', l.situation, 'preparation', l.preparation,
        'invoiced', l.invoiced, 'credited', l.credited, 'collected', l.collected, 'regularized', l.regularized,
        'outstanding', (l.debt->>'outstanding')::bigint, 'overdue', (l.debt->>'overdueAmount')::bigint,
        'monthly', l.monthly, 'monthlyState', l.monthly_state, 'nextRenewalOn', l.next_renewal, 'trialLastDay', l.trial_last_day,
        'terminationOn', l.termination_on, 'actions', l.actions) ORDER BY jsonb_array_length(l.actions) = 0, l.name, l.id) FROM listed l), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END $$;
REVOKE ALL ON FUNCTION drivy.platform_commercial_dashboard(date, date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.platform_commercial_dashboard(date, date) TO drivy_app;
