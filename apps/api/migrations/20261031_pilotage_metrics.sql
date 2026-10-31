-- #375 / T02 : lectures de pilotage de l'école (activité, cours, valeurs des leçons, règlements de cours).
-- Fonctions de lecture et index SEULEMENT : aucune table, aucune donnée, aucun backfill, aucune écriture.
-- Décision D1 de docs/implementation/pilotage-373-indicateurs.md : sous RLS, un moniteur dont l'affectation est terminée perd la lecture
-- de ses anciennes leçons et un agrégat sous-compterait en silence. Ces fonctions appliquent donc le périmètre elles-mêmes.
--
-- Condition attachée à D1. Chaque fonction SECURITY DEFINER ci-dessous :
--  1. revérifie elle-même l'identité (app.person_id), l'adhésion active à l'école de la requête (current_school_member), le rôle
--     ADMIN ou INSTRUCTOR et le grant propre à la mesure (VIEW_SCHOOL_METRICS, VIEW_FINANCIAL_METRICS, EXPORT_MANAGEMENT), dans
--     metrics_gate, appelée avant toute lecture de donnée ;
--  2. fixe search_path ;
--  3. n'est exécutable que par le rôle applicatif (REVOKE ... FROM PUBLIC puis GRANT ... TO drivy_app) ;
--  4. est STABLE et ne modifie rien.
-- Les tests apps/api/test/school-metrics.integration.test.ts prouvent le refus d'une autre école, d'un autre moniteur et d'un élève.

-- Erreurs métier : SQLSTATE P0001, message = code stable lu par l'API (même convention que course_fail). Réservée aux fonctions ci-dessous.
CREATE FUNCTION drivy.metrics_fail(code text) RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE=code; END $$;

-- Porte unique. p_right : ACTIVITY (leçons et cours sans montant), FINANCE (montants), ANY (simple lecture de contexte).
-- p_scope : 'school' (toute l'école) ou 'self' (le moniteur connecté, jamais un paramètre). Renvoie le moniteur à filtrer et le fuseau de l'école.
-- Les montants exigent ADMIN ou VIEW_FINANCIAL_METRICS ET la portée école : un moniteur sans ce grant n'obtient jamais de montant, même sur ses leçons.
CREATE FUNCTION drivy.metrics_gate(p_school uuid,p_right text,p_scope text,p_instructor uuid,p_export boolean)
RETURNS TABLE(membership_id uuid,scope_instructor uuid,time_zone text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE r record; is_admin boolean; is_instructor boolean; can_school boolean; can_finance boolean; can_export boolean; target uuid;
BEGIN
 SELECT m.id AS member_id,m.roles AS roles,m.grants AS grants,s.time_zone AS tz,s.status AS school_status INTO r
  FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id JOIN drivy.school s ON s.id=m.school_id
  WHERE m.school_id=p_school AND drivy.current_school_member(p_school)
   AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND p.status='ACTIVE';
 IF NOT FOUND THEN PERFORM drivy.metrics_fail('METRIC_FORBIDDEN'); END IF;
 is_admin:='ADMIN'=ANY(r.roles); is_instructor:='INSTRUCTOR'=ANY(r.roles);
 IF NOT (is_admin OR is_instructor) THEN PERFORM drivy.metrics_fail('METRIC_FORBIDDEN'); END IF;
 IF r.school_status='DRAFT' THEN PERFORM drivy.metrics_fail('SCHOOL_NOT_ACTIVE'); END IF;
 can_school:=is_admin OR 'VIEW_SCHOOL_METRICS'=ANY(r.grants);
 can_finance:=is_admin OR 'VIEW_FINANCIAL_METRICS'=ANY(r.grants);
 can_export:='EXPORT_MANAGEMENT'=ANY(r.grants);
 IF p_export AND NOT can_export THEN PERFORM drivy.metrics_fail('ACCESS_REVOKED'); END IF;
 CASE p_right
  WHEN 'ANY' THEN target:=NULL;
  WHEN 'FINANCE' THEN
   IF NOT can_finance THEN PERFORM drivy.metrics_fail('METRIC_FORBIDDEN'); END IF;
   IF p_scope IS DISTINCT FROM 'school' THEN PERFORM drivy.metrics_fail('METRIC_SCOPE_FORBIDDEN'); END IF;
   target:=p_instructor;
  WHEN 'ACTIVITY' THEN
   IF p_scope='school' THEN
    IF NOT can_school THEN PERFORM drivy.metrics_fail('METRIC_SCOPE_FORBIDDEN'); END IF;
    target:=p_instructor;
   ELSIF p_scope='self' THEN
    IF NOT is_instructor THEN PERFORM drivy.metrics_fail('METRIC_SCOPE_FORBIDDEN'); END IF;
    IF p_instructor IS NOT NULL AND p_instructor<>r.member_id THEN PERFORM drivy.metrics_fail('METRIC_SCOPE_FORBIDDEN'); END IF;
    target:=r.member_id;
   ELSE PERFORM drivy.metrics_fail('METRIC_SCOPE_FORBIDDEN');
   END IF;
  ELSE PERFORM drivy.metrics_fail('METRIC_FORBIDDEN');
 END CASE;
 RETURN QUERY SELECT r.member_id,target,r.tz;
END $$;

-- Début de couverture : date civile (fuseau de l'école) de la plus ancienne leçon ou série de cours enregistrée. Une date, aucune personne.
CREATE FUNCTION drivy.metrics_data_since(p_school uuid) RETURNS date
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE g record; first_at timestamptz;
BEGIN
 SELECT * INTO g FROM drivy.metrics_gate(p_school,'ANY',NULL,NULL,false);
 SELECT min(t.at) INTO first_at FROM (
  SELECT min(l.created_at) AS at FROM drivy.lesson l WHERE l.school_id=p_school
  UNION ALL SELECT min(s.created_at) FROM drivy.course_series s WHERE s.school_id=p_school) t;
 RETURN (first_at AT TIME ZONE g.time_zone)::date;
END $$;

-- Leçons individuelles de la période. Un seul rattachement par leçon (event_at) : début réel si réalisée avec un début réel, sinon début prévu.
-- Période : dates civiles de l'école, [p_from, p_to), 366 jours au plus ; p_from et p_to nuls = sans borne (états « à traiter »).
-- state : COMPLETED, CANCELLED, NO_SHOW, UPCOMING, TO_VERIFY, IN_PROGRESS, TO_FINALIZE (jamais déduit d'un horaire passé seul : voir le dictionnaire).
-- Les montants (price_cents, charge_cents) ne sortent que si p_money, et alors seulement pour ADMIN ou VIEW_FINANCIAL_METRICS.
-- p_status (facultatif) restreint au statut stocké, ce qui permet à l'index partiel lesson_metrics_open de servir les états « à traiter ».
CREATE FUNCTION drivy.metrics_lesson_lines(p_school uuid,p_from date,p_to date,p_now timestamptz,p_scope text,p_instructor uuid,
 p_category text,p_product text,p_money boolean,p_status text DEFAULT NULL)
RETURNS TABLE(lesson_id uuid,training_id uuid,event_at timestamptz,local_day date,state text,status text,
 planned_start timestamptz,planned_end timestamptz,actual_start timestamptz,actual_end timestamptz,
 instructor_membership_id uuid,learner_id uuid,category_code text,product_key text,quantity integer,
 planned_seconds integer,actual_seconds integer,commercial_mode text,price_cents bigint,charge_cents bigint,other_time_zone boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE g record; from_at timestamptz; to_at timestamptz;
BEGIN
 SELECT * INTO g FROM drivy.metrics_gate(p_school,CASE WHEN p_money THEN 'FINANCE' ELSE 'ACTIVITY' END,p_scope,p_instructor,false);
 IF p_from IS NULL AND p_to IS NULL THEN from_at:='-infinity'; to_at:='infinity';
 ELSIF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>366 THEN PERFORM drivy.metrics_fail('INVALID_PERIOD');
 ELSE from_at:=(p_from::timestamp AT TIME ZONE g.time_zone); to_at:=(p_to::timestamp AT TIME ZONE g.time_zone);
 END IF;
 RETURN QUERY
 SELECT l.id,l.training_id,ev.event_at,(ev.event_at AT TIME ZONE g.time_zone)::date,
  CASE l.status
   WHEN 'COMPLETED' THEN 'COMPLETED' WHEN 'CANCELLED' THEN 'CANCELLED' WHEN 'NO_SHOW' THEN 'NO_SHOW'
   ELSE CASE WHEN l.actual_start IS NOT NULL THEN CASE WHEN l.planned_end<=p_now THEN 'TO_FINALIZE' ELSE 'IN_PROGRESS' END
    ELSE CASE WHEN l.planned_start>p_now THEN 'UPCOMING' ELSE 'TO_VERIFY' END END
  END,
  l.status,l.planned_start,l.planned_end,l.actual_start,l.actual_end,l.instructor_membership_id,l.learner_id,
  o.category_code,sp.product_key,(l.commercial_selection->>'quantity')::integer,
  floor(extract(epoch FROM (l.planned_end-l.planned_start)))::integer,
  CASE WHEN l.status='COMPLETED' AND l.actual_start IS NOT NULL AND l.actual_end IS NOT NULL
   THEN floor(extract(epoch FROM (l.actual_end-l.actual_start)))::integer END,
  l.commercial_selection->>'mode',
  CASE WHEN p_money THEN l.price_cents_snapshot END,
  CASE WHEN p_money THEN (SELECT sum(c.amount_signed_cents)::bigint FROM drivy.lesson_account a
   JOIN drivy.charge_entry c ON c.school_id=a.school_id AND c.account_id=a.id WHERE a.school_id=l.school_id AND a.lesson_id=l.id) END,
  l.time_zone<>g.time_zone
 FROM drivy.lesson l
 CROSS JOIN LATERAL (SELECT CASE WHEN l.status='COMPLETED' AND l.actual_start IS NOT NULL THEN l.actual_start ELSE l.planned_start END AS event_at) ev
 JOIN drivy.training t ON t.school_id=l.school_id AND t.id=l.training_id
 JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
 LEFT JOIN drivy.service_product_version sp ON sp.school_id=l.school_id AND sp.id=nullif(l.commercial_selection->>'serviceProductVersionId','')::uuid
 WHERE l.school_id=p_school AND ev.event_at>=from_at AND ev.event_at<to_at
  AND (g.scope_instructor IS NULL OR l.instructor_membership_id=g.scope_instructor)
  AND (p_category IS NULL OR o.category_code=p_category)
  AND (p_product IS NULL OR sp.product_key=p_product)
  AND (p_status IS NULL OR l.status=p_status);
END $$;

-- Séances de cours (séries PUBLISHED ou CLOSED) de la période, une ligne par inscription attendue ; une séance sans inscription donne une ligne
-- aux colonnes d'inscription nulles. Attendue = créée avant la séance et ACTIVE, ou annulée après son début ; une présence saisie est toujours
-- conservée, attendue ou non. attendance_status nul pour une inscription attendue = appel non renseigné (jamais « absent »).
CREATE FUNCTION drivy.metrics_course_session_lines(p_school uuid,p_from date,p_to date,p_scope text,p_instructor uuid)
RETURNS TABLE(occurrence_id uuid,series_id uuid,type_id uuid,series_status text,starts_at timestamptz,ends_at timestamptz,local_day date,
 instructor_membership_id uuid,enrollment_id uuid,learner_id uuid,attendance_status text,expected boolean)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE g record; from_at timestamptz; to_at timestamptz;
BEGIN
 SELECT * INTO g FROM drivy.metrics_gate(p_school,'ACTIVITY',p_scope,p_instructor,false);
 IF p_from IS NULL AND p_to IS NULL THEN from_at:='-infinity'; to_at:='infinity';
 ELSIF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>366 THEN PERFORM drivy.metrics_fail('INVALID_PERIOD');
 ELSE from_at:=(p_from::timestamp AT TIME ZONE g.time_zone); to_at:=(p_to::timestamp AT TIME ZONE g.time_zone);
 END IF;
 RETURN QUERY
 SELECT o.id,o.series_id,s.type_id,s.status,o.starts_at,o.ends_at,(o.starts_at AT TIME ZONE g.time_zone)::date,o.instructor_membership_id,
  x.enrollment_id,x.learner_id,x.attendance_status,coalesce(x.expected,false)
 FROM drivy.course_occurrence o
 JOIN drivy.course_series s ON s.school_id=o.school_id AND s.id=o.series_id
 LEFT JOIN LATERAL (
  SELECT e.id AS enrollment_id,e.learner_id AS learner_id,a.status AS attendance_status,
   (e.created_at<=o.starts_at AND (e.status='ACTIVE' OR e.cancelled_at>o.starts_at)) AS expected
  FROM drivy.course_enrollment e
  LEFT JOIN drivy.course_attendance a ON a.enrollment_id=e.id AND a.occurrence_id=o.id
  WHERE e.school_id=o.school_id AND e.series_id=o.series_id
   AND (a.enrollment_id IS NOT NULL OR (e.created_at<=o.starts_at AND (e.status='ACTIVE' OR e.cancelled_at>o.starts_at)))) x ON true
 WHERE o.school_id=p_school AND s.status IN ('PUBLISHED','CLOSED') AND o.starts_at>=from_at AND o.starts_at<to_at
  AND (g.scope_instructor IS NULL OR o.instructor_membership_id=g.scope_instructor);
END $$;

-- Séries de cours : instantané des séries publiées (inscriptions actives, retenues non échues, capacité) et séries annulées dans la période.
-- Portée soi : séries dont on est responsable. Aucune valeur : une série n'a ni prix ni lien produit.
CREATE FUNCTION drivy.metrics_course_series_lines(p_school uuid,p_from date,p_to date,p_now timestamptz,p_scope text,p_instructor uuid)
RETURNS TABLE(series_id uuid,series_status text,type_id uuid,capacity integer,responsible_membership_id uuid,first_starts_at timestamptz,
 cancelled_at timestamptz,occurrence_count integer,active_enrollments integer,active_offers integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE g record; from_at timestamptz; to_at timestamptz;
BEGIN
 SELECT * INTO g FROM drivy.metrics_gate(p_school,'ACTIVITY',p_scope,p_instructor,false);
 IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>366 THEN PERFORM drivy.metrics_fail('INVALID_PERIOD'); END IF;
 from_at:=(p_from::timestamp AT TIME ZONE g.time_zone); to_at:=(p_to::timestamp AT TIME ZONE g.time_zone);
 RETURN QUERY
 SELECT s.id,s.status,s.type_id,s.capacity,s.responsible_membership_id,
  (SELECT min(o.starts_at) FROM drivy.course_occurrence o WHERE o.school_id=s.school_id AND o.series_id=s.id),
  s.cancelled_at,
  (SELECT count(*)::integer FROM drivy.course_occurrence o WHERE o.school_id=s.school_id AND o.series_id=s.id),
  (SELECT count(*)::integer FROM drivy.course_enrollment e WHERE e.school_id=s.school_id AND e.series_id=s.id AND e.status='ACTIVE'),
  (SELECT count(*)::integer FROM drivy.course_seat_offer f WHERE f.school_id=s.school_id AND f.series_id=s.id AND f.status='ACTIVE' AND f.expires_at>p_now)
 FROM drivy.course_series s
 WHERE s.school_id=p_school
  AND (s.status='PUBLISHED' OR (s.status='CANCELLED' AND s.cancelled_at>=from_at AND s.cancelled_at<to_at))
  AND (g.scope_instructor IS NULL OR s.responsible_membership_id=g.scope_instructor);
END $$;

-- Mouvements d'inscription : créations et annulations datées par created_at et cancelled_at, jamais déduites des places.
CREATE FUNCTION drivy.metrics_course_enrollment_events(p_school uuid,p_from date,p_to date,p_scope text)
RETURNS TABLE(enrollment_id uuid,series_id uuid,created_at timestamptz,cancelled_at timestamptz,cancel_kind text,status text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE g record; from_at timestamptz; to_at timestamptz;
BEGIN
 SELECT * INTO g FROM drivy.metrics_gate(p_school,'ACTIVITY',p_scope,NULL,false);
 IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>366 THEN PERFORM drivy.metrics_fail('INVALID_PERIOD'); END IF;
 from_at:=(p_from::timestamp AT TIME ZONE g.time_zone); to_at:=(p_to::timestamp AT TIME ZONE g.time_zone);
 RETURN QUERY
 SELECT e.id,e.series_id,e.created_at,e.cancelled_at,e.cancel_kind,e.status
 FROM drivy.course_enrollment e JOIN drivy.course_series s ON s.school_id=e.school_id AND s.id=e.series_id
 WHERE e.school_id=p_school
  AND ((e.created_at>=from_at AND e.created_at<to_at) OR (e.cancelled_at>=from_at AND e.cancelled_at<to_at))
  AND (g.scope_instructor IS NULL OR s.responsible_membership_id=g.scope_instructor);
END $$;

-- Règlements de cours saisis sur place : saisies de la période (recorded_at) et saisies annulées dans la période (voided_at).
-- Date de SAISIE, jamais une date bancaire. Réservé à ADMIN ou VIEW_FINANCIAL_METRICS, portée école. Aucune personne n'en sort.
CREATE FUNCTION drivy.metrics_course_payment_lines(p_school uuid,p_from date,p_to date)
RETURNS TABLE(payment_id uuid,enrollment_id uuid,series_id uuid,type_id uuid,recorded_at timestamptz,local_day date,amount_cents bigint,voided_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
#variable_conflict use_column
DECLARE g record; from_at timestamptz; to_at timestamptz;
BEGIN
 SELECT * INTO g FROM drivy.metrics_gate(p_school,'FINANCE','school',NULL,false);
 IF p_from IS NULL OR p_to IS NULL OR p_to<=p_from OR p_to-p_from>366 THEN PERFORM drivy.metrics_fail('INVALID_PERIOD'); END IF;
 from_at:=(p_from::timestamp AT TIME ZONE g.time_zone); to_at:=(p_to::timestamp AT TIME ZONE g.time_zone);
 RETURN QUERY
 SELECT p.id,p.enrollment_id,e.series_id,s.type_id,p.recorded_at,(p.recorded_at AT TIME ZONE g.time_zone)::date,p.amount_cents,p.voided_at
 FROM drivy.course_payment_record p
 JOIN drivy.course_enrollment e ON e.school_id=p.school_id AND e.id=p.enrollment_id
 JOIN drivy.course_series s ON s.school_id=e.school_id AND s.id=e.series_id
 WHERE p.school_id=p_school
  AND ((p.recorded_at>=from_at AND p.recorded_at<to_at) OR (p.voided_at>=from_at AND p.voided_at<to_at));
END $$;

REVOKE ALL ON FUNCTION drivy.metrics_fail(text),
 drivy.metrics_gate(uuid,text,text,uuid,boolean),
 drivy.metrics_data_since(uuid),
 drivy.metrics_lesson_lines(uuid,date,date,timestamptz,text,uuid,text,text,boolean,text),
 drivy.metrics_course_session_lines(uuid,date,date,text,uuid),
 drivy.metrics_course_series_lines(uuid,date,date,timestamptz,text,uuid),
 drivy.metrics_course_enrollment_events(uuid,date,date,text),
 drivy.metrics_course_payment_lines(uuid,date,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.metrics_gate(uuid,text,text,uuid,boolean),
 drivy.metrics_data_since(uuid),
 drivy.metrics_lesson_lines(uuid,date,date,timestamptz,text,uuid,text,text,boolean,text),
 drivy.metrics_course_session_lines(uuid,date,date,text,uuid),
 drivy.metrics_course_series_lines(uuid,date,date,timestamptz,text,uuid),
 drivy.metrics_course_enrollment_events(uuid,date,date,text),
 drivy.metrics_course_payment_lines(uuid,date,date) TO drivy_app;

-- Index candidats, un par mesure. Aucun objectif de performance n'est affirmé : à mesurer sur un volume représentatif.
CREATE INDEX IF NOT EXISTS lesson_metrics_completed ON drivy.lesson(school_id,actual_start) WHERE status='COMPLETED';
CREATE INDEX IF NOT EXISTS lesson_metrics_open ON drivy.lesson(school_id,planned_start) WHERE status='PLANNED';
CREATE INDEX IF NOT EXISTS course_attendance_occurrence ON drivy.course_attendance(occurrence_id);
CREATE INDEX IF NOT EXISTS course_enrollment_metrics_created ON drivy.course_enrollment(school_id,created_at);
CREATE INDEX IF NOT EXISTS course_enrollment_metrics_cancelled ON drivy.course_enrollment(school_id,cancelled_at) WHERE cancelled_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS course_payment_metrics_recorded ON drivy.course_payment_record(school_id,recorded_at);
CREATE INDEX IF NOT EXISTS course_payment_metrics_voided ON drivy.course_payment_record(school_id,voided_at) WHERE voided_at IS NOT NULL;
