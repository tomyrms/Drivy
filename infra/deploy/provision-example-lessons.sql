-- Données fictives d'essai pour « Luc auto école », demandées par le porteur le 28 septembre 2026.
-- Opérateur uniquement (psql superutilisateur sur CT113), en une seule transaction, après sauvegarde.
-- Additif : complète l'offre d'exemple (référentiel, procédure, conditions, prestation, disponibilités),
-- donne à luc le rôle moniteur, puis ajoute des leçons, bilans publiés et observations de leçon.
-- Aucun compte, aucun mot de passe, aucune capture GPS. Refuse de s'exécuter une seconde fois.
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
SET LOCAL TIME ZONE 'Europe/Zurich';

CREATE TEMP TABLE seed_ctx(key text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;

CREATE FUNCTION pg_temp.ctx(k text) RETURNS uuid LANGUAGE sql STABLE AS $f$ SELECT id FROM seed_ctx WHERE key = k $f$;

CREATE FUNCTION pg_temp.competency(k text) RETURNS uuid LANGUAGE plpgsql STABLE AS $f$
DECLARE c uuid;
BEGIN
  SELECT id INTO c FROM drivy.competency_definition WHERE curriculum_version_id = pg_temp.ctx('curriculum') AND stable_key = k;
  IF c IS NULL THEN RAISE EXCEPTION 'unknown competency %', k; END IF;
  RETURN c;
END $f$;

-- Leçon planifiée, occupations et révision commerciale initiale, comme AP40.
CREATE FUNCTION pg_temp.add_lesson(p_training uuid, p_instructor uuid, p_start timestamptz, p_minutes int, p_meeting text)
RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE
  l uuid := gen_random_uuid(); qty int := p_minutes / 50; learner uuid; learner_person uuid; instructor_person uuid;
  selection jsonb; created timestamptz := least(now(), p_start - interval '5 days');
BEGIN
  IF p_minutes % 50 <> 0 THEN RAISE EXCEPTION 'duration must be a multiple of 50'; END IF;
  SELECT t.learner_id, lp.person_id INTO STRICT learner, learner_person
    FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.id = p_training;
  SELECT person_id INTO STRICT instructor_person FROM drivy.membership WHERE id = p_instructor;
  selection := jsonb_build_object('mode', 'UNIT_PRICE', 'serviceProductVersionId', pg_temp.ctx('product'), 'quantity', qty,
    'entitlementLotId', NULL, 'acceptedTermsVersionId', pg_temp.ctx('terms'));
  INSERT INTO drivy.lesson(id, school_id, training_id, learner_id, learner_person_id, instructor_membership_id, planned_start, planned_end,
    time_zone, meeting_point, price_cents_snapshot, buffer_minutes_snapshot, policy_version_id, commercial_selection, created_at)
  VALUES (l, pg_temp.ctx('school'), p_training, learner, learner_person, p_instructor, p_start, p_start + make_interval(mins => p_minutes),
    'Europe/Zurich', p_meeting, 9500 * qty, 10, pg_temp.ctx('policy'), selection, created);
  INSERT INTO drivy.reservation(school_id, lesson_id, resource_id, resource_role, during) VALUES
    (pg_temp.ctx('school'), l, learner_person, 'LEARNER', tstzrange(p_start, p_start + make_interval(mins => p_minutes), '[)')),
    (pg_temp.ctx('school'), l, instructor_person, 'INSTRUCTOR', tstzrange(p_start, p_start + make_interval(mins => p_minutes + 10), '[)'));
  INSERT INTO drivy.lesson_commercial_revision(school_id, lesson_id, revision, operation_id, commercial_selection, price_cents,
    duration_minutes, actor_membership_id, reason, created_at)
  VALUES (pg_temp.ctx('school'), l, 1, gen_random_uuid(), selection, 9500 * qty, p_minutes, p_instructor, 'Initial booking', created);
  RETURN l;
END $f$;

-- Constat (AP49) puis, si demandé, publication (AP53). p_levels : [[clé, niveau, contexte], ...]
CREATE FUNCTION pg_temp.complete_lesson(p_lesson uuid, p_worked text, p_observation text, p_next text, p_levels jsonb, p_publish boolean)
RETURNS uuid LANGUAGE plpgsql AS $f$
DECLARE
  ls drivy.lesson%ROWTYPE; draft uuid := gen_random_uuid(); account uuid := gen_random_uuid(); revision uuid;
  items jsonb; snapshot jsonb;
BEGIN
  SELECT * INTO STRICT ls FROM drivy.lesson WHERE id = p_lesson;
  SELECT coalesce(jsonb_agg(jsonb_build_object('competencyId', pg_temp.competency(x->>0), 'level', x->>1, 'context', x->>2)), '[]')
    INTO items FROM jsonb_array_elements(p_levels) x;
  SELECT coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'label', c.label, 'version', c.version, 'curriculumVersionId', c.curriculum_version_id) ORDER BY c.id), '[]')
    INTO snapshot FROM drivy.competency_definition c WHERE c.id IN (SELECT (i->>'competencyId')::uuid FROM jsonb_array_elements(items) i);
  UPDATE drivy.lesson SET status = 'COMPLETED', version = 2, actual_start = planned_start, actual_end = planned_end WHERE id = p_lesson;
  INSERT INTO drivy.report_draft(id, school_id, lesson_id, author_membership_id, version, base_publication_version,
    worked_on, observation_text, next_step, observations, created_at)
  VALUES (draft, ls.school_id, p_lesson, ls.instructor_membership_id, 2, CASE WHEN p_publish THEN 1 ELSE 0 END,
    p_worked, p_observation, p_next, items, ls.planned_end);
  INSERT INTO drivy.lesson_account(id, school_id, lesson_id, planned_price_cents) VALUES (account, ls.school_id, p_lesson, ls.price_cents_snapshot);
  INSERT INTO drivy.charge_entry(school_id, account_id, kind, amount_signed_cents, reason, operation_id, created_at)
  VALUES (ls.school_id, account, 'INITIAL', ls.price_cents_snapshot, 'Prix unitaire convenu à la réservation ; leçon réalisée.',
    gen_random_uuid(), ls.planned_end);
  IF p_publish THEN
    revision := gen_random_uuid();
    INSERT INTO drivy.report_revision(id, school_id, lesson_id, author_membership_id, sequence, published_at, worked_on,
      observation_text, next_step, observations, competency_snapshot, correction_reason, operation_id)
    VALUES (revision, ls.school_id, p_lesson, ls.instructor_membership_id, 1, ls.planned_end + interval '2 hours',
      p_worked, p_observation, p_next, items, snapshot, NULL, gen_random_uuid());
    UPDATE drivy.lesson SET version = 3, publication_version = 1, current_published_revision_id = revision WHERE id = p_lesson;
  END IF;
  RETURN draft;
END $f$;

-- Observation notée pendant la leçon (AP161), rattachée au brouillon lors du constat. Clé nulle : simple repère.
CREATE FUNCTION pg_temp.observe(p_lesson uuid, p_draft uuid, p_minute int, p_key text, p_status text, p_text text)
RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  INSERT INTO drivy.geo_observation(school_id, version, lesson_id, training_id, author_membership_id, draft_id, competency_id,
    text, origin, observed_at, event_kind, event_status, created_at)
  SELECT l.school_id, 2, l.id, l.training_id, l.instructor_membership_id, p_draft,
    CASE WHEN p_key IS NULL THEN NULL ELSE pg_temp.competency(p_key) END, p_text, 'LIVE',
    l.planned_start + make_interval(mins => p_minute), CASE WHEN p_key IS NULL THEN 'MARKER' ELSE 'QUALIFIED' END,
    CASE WHEN p_key IS NULL THEN NULL ELSE p_status END, l.planned_start + make_interval(mins => p_minute)
  FROM drivy.lesson l WHERE l.id = p_lesson;
END $f$;

CREATE FUNCTION pg_temp.prepare(p_lesson uuid, p_goals jsonb) RETURNS void LANGUAGE sql AS $f$
  UPDATE drivy.lesson_preparation SET version = version + 1, goals = (
    SELECT jsonb_agg(jsonb_build_object('label', g->>0, 'competencyId', pg_temp.competency(g->>1))) FROM jsonb_array_elements(p_goals) g)
  WHERE lesson_id = p_lesson
$f$;

DO $$
DECLARE
  op constant uuid := '5d3f1c2e-8a41-4c7b-9e2d-6b1a0f4c3e27';
  s uuid; luc uuid; luc_person uuid; alex uuid; offering uuid;
  curriculum uuid := gen_random_uuid(); policy uuid := gen_random_uuid(); terms uuid := gen_random_uuid(); product uuid := gen_random_uuid();
  t_lea uuid; t_noe uuid; t_emma uuid; t_lucas uuid; t_hugo uuid; t_sofia uuid;
  l uuid; d uuid;
BEGIN
  SELECT id INTO STRICT s FROM drivy.school WHERE name = 'Luc auto école' AND status = 'ACTIVE';
  SELECT m.id, m.person_id INTO STRICT luc, luc_person FROM drivy.membership m JOIN drivy.person p ON p.id = m.person_id
    WHERE m.school_id = s AND p.display_name = 'luc' AND m.status = 'ACTIVE' AND 'ADMIN' = ANY(m.roles);
  SELECT m.id INTO STRICT alex FROM drivy.membership m JOIN drivy.person p ON p.id = m.person_id
    WHERE m.school_id = s AND p.display_name = 'Alex Martin · exemple' AND m.status = 'ACTIVE';
  IF EXISTS (SELECT 1 FROM drivy.operation WHERE operation_id = op) THEN RAISE EXCEPTION 'already provisioned'; END IF;
  IF EXISTS (SELECT 1 FROM drivy.lesson WHERE school_id = s) OR EXISTS (SELECT 1 FROM drivy.curriculum_version WHERE school_id = s)
     OR EXISTS (SELECT 1 FROM drivy.commercial_terms_version WHERE school_id = s) THEN
    RAISE EXCEPTION 'school already has planning data; operator review required';
  END IF;
  SELECT id INTO STRICT offering FROM drivy.offering_version
    WHERE school_id = s AND offering_key = 'example-category-b' AND version = 1 AND NOT enabled AND curriculum_version_id IS NULL;
  SELECT t.id INTO STRICT t_lea FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.school_id = s AND lp.display_name = 'Léa Morel · exemple';
  SELECT t.id INTO STRICT t_noe FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.school_id = s AND lp.display_name = 'Noé Favre · exemple';
  SELECT t.id INTO STRICT t_emma FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.school_id = s AND lp.display_name = 'Emma Rochat · exemple';
  SELECT t.id INTO STRICT t_lucas FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.school_id = s AND lp.display_name = 'Lucas Perrin · exemple';
  SELECT t.id INTO STRICT t_hugo FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.school_id = s AND lp.display_name = 'Hugo Girard · exemple';
  SELECT t.id INTO STRICT t_sofia FROM drivy.training t JOIN drivy.learner_profile lp ON lp.id = t.learner_id WHERE t.school_id = s AND lp.display_name = 'Sofia Blanc · exemple';
  INSERT INTO seed_ctx VALUES ('school', s), ('curriculum', curriculum), ('policy', policy), ('terms', terms), ('product', product);

  -- 1. luc enseigne aussi : il peut planifier, conduire et rédiger les bilans de ses élèves.
  UPDATE drivy.membership SET roles = ARRAY['ADMIN', 'INSTRUCTOR'], grants = ARRAY['CONFIGURE_CATALOG', 'permit_review', 'cash_record'],
    version = version + 1, access_epoch = access_epoch + 1 WHERE id = luc;

  -- 2. Référentiel d'exemple de la catégorie B.
  INSERT INTO drivy.curriculum_version(id, school_id, category_code, version, revision, approved, approval_reason, created_by, approved_at)
  VALUES (curriculum, s, 'B', 1, 1, true, 'Référentiel d’exemple fourni à la demande du porteur ; à relire par l’école.', luc, now());
  INSERT INTO drivy.competency_definition(school_id, curriculum_version_id, stable_key, label, description, sort_order) VALUES
    (s, curriculum, 'vehicule', 'Maîtrise du véhicule', 'Démarrer, s’arrêter, diriger et changer de vitesse sans à-coups.', 0),
    (s, curriculum, 'observation', 'Observation et contrôles', 'Regard loin, rétroviseurs et angles morts au bon moment.', 1),
    (s, curriculum, 'priorites', 'Priorités', 'Priorité de droite, signalisation et céder le passage.', 2),
    (s, curriculum, 'intersections', 'Intersections et giratoires', 'Choix de voie, placement et sortie.', 3),
    (s, curriculum, 'vitesse', 'Adaptation de la vitesse', 'Vitesse adaptée aux limites, à la visibilité et au trafic.', 4),
    (s, curriculum, 'placement', 'Placement sur la chaussée', 'Position dans la voie, en virage et en croisement.', 5),
    (s, curriculum, 'manoeuvres', 'Manœuvres', 'Stationnements, marche arrière et demi-tour.', 6),
    (s, curriculum, 'autoroute', 'Autoroute', 'Insertion, dépassement et sortie.', 7),
    (s, curriculum, 'anticipation', 'Anticipation et partage de la route', 'Piétons, cyclistes, bus et situations imprévues.', 8);

  -- 3. Procédure de la catégorie, 4. offre complétée et ouverte.
  INSERT INTO drivy.school_policy_version(id, school_id, category_code, version, procedure_text, cancellation_policy_text, source_urls,
    approved, approval_reason, created_by, approved_at)
  VALUES (policy, s, 'B', 1,
    'Leçons de 50 minutes au départ de l’école ou d’un lieu convenu. Le permis d’élève est contrôlé avant la première leçon.',
    'Annulation gratuite jusqu’à 24 heures avant la leçon. Au-delà, la leçon est due, sauf cas de force majeure.',
    '{}', true, 'Procédure d’exemple fournie à la demande du porteur ; à relire par l’école.', luc, now());
  UPDATE drivy.offering_version SET curriculum_version_id = curriculum, policy_version_id = policy,
    default_duration_minutes = 50, default_price_cents = 9500, enabled = true WHERE id = offering;

  -- 5. Conditions commerciales et prestation.
  INSERT INTO drivy.commercial_terms_version(id, school_id, version, label, terms_text, valid_from, approved, approval_reason,
    approved_by, approved_at, created_by)
  VALUES (terms, s, 1, 'Conditions générales · exemple',
    'Leçon payable à la fin de la leçon. Annulation gratuite jusqu’à 24 heures avant ; au-delà, la leçon est due.',
    '2026-09-01', true, 'Conditions d’exemple fournies à la demande du porteur.', luc, now(), luc);
  INSERT INTO drivy.service_product_version(id, school_id, version, product_key, label, type, category_code, duration_minutes,
    unit_label, unit_price_cents, valid_from, terms_version_id, enabled)
  VALUES (product, s, 1, 'lecon-b-50', 'Leçon de conduite · 50 min', 'INDIVIDUAL_LESSON', 'B', 50, 'leçon', 9500, '2026-09-01', terms, true);

  -- 6. Disponibilités (lundi = 1).
  INSERT INTO drivy.availability_rule(school_id, instructor_membership_id, weekdays, local_start, local_end, valid_from) VALUES
    (s, luc, ARRAY[1, 2, 3, 4, 5], '07:30', '19:30', '2026-09-01'),
    (s, luc, ARRAY[6], '08:00', '12:00', '2026-09-01'),
    (s, alex, ARRAY[1, 2, 3, 4, 5], '08:00', '17:30', '2026-09-01');

  -- 7. luc suit quatre élèves ; Alex conserve ses affectations. Dates de début cohérentes avec l'historique.
  INSERT INTO drivy.instructor_assignment(id, school_id, training_id, instructor_membership_id, valid_from)
    SELECT gen_random_uuid(), s, t, luc, '2026-09-01 00:00' FROM unnest(ARRAY[t_lea, t_noe, t_emma, t_lucas]) t;
  UPDATE drivy.training SET started_on = CASE id WHEN t_lea THEN date '2026-08-31' WHEN t_noe THEN date '2026-09-07'
    WHEN t_emma THEN date '2026-09-07' WHEN t_lucas THEN date '2026-09-14' WHEN t_hugo THEN date '2026-09-01' ELSE date '2026-08-24' END
    WHERE id IN (t_lea, t_noe, t_emma, t_lucas, t_hugo, t_sofia);
  UPDATE drivy.training_wish SET version = version + 1, text = 'J’aimerais faire plus d’autoroute avant l’examen.' WHERE training_id = t_lea;

  -- 8. Léa Morel (compte « eleve ») avec luc.
  l := pg_temp.add_lesson(t_lea, luc, '2026-09-07 08:00', 50, 'Gare de Cernier');
  d := pg_temp.complete_lesson(l,
    'Prise en main du véhicule, démarrages et arrêts sur le parking de la gare, premiers kilomètres dans Cernier.',
    'Bonne écoute des consignes. Les démarrages en côte calent encore et le regard reste trop près du capot.',
    'Démarrages en côte et contrôles avant de quitter le stationnement.',
    '[["vehicule","DISCOVERING","Démarrages réussis sur le plat, calage en côte."],["observation","DISCOVERING","Regard trop proche, contrôles oubliés au départ."]]', true);
  PERFORM pg_temp.observe(l, d, 12, 'vehicule', 'TO_REWORK', 'Calage au démarrage en côte, rue de l’Épervier.');
  PERFORM pg_temp.observe(l, d, 25, 'observation', 'ATTENTION', 'Angle mort non contrôlé en quittant la place de parc.');
  PERFORM pg_temp.observe(l, d, 40, 'vehicule', 'POSITIVE', 'Arrêt en douceur au stop.');

  l := pg_temp.add_lesson(t_lea, luc, '2026-09-14 08:00', 50, 'Gare de Cernier');
  d := pg_temp.complete_lesson(l,
    'Circulation dans le Val-de-Ruz : Fontaines, Chézard et leurs giratoires.',
    'Les démarrages sont acquis. Les priorités de droite dans les villages ne sont pas encore anticipées.',
    'Priorités de droite et vitesse d’approche des giratoires.',
    '[["vehicule","GUIDED","Démarrages en côte réussis avec un rappel."],["priorites","DISCOVERING","Priorité de droite manquée à Fontaines."],["vitesse","DISCOVERING","Approche trop rapide des giratoires."]]', true);
  PERFORM pg_temp.observe(l, d, 14, 'priorites', 'ATTENTION', 'Priorité de droite non respectée à Fontaines, carrefour de la Grand-Rue.');
  PERFORM pg_temp.observe(l, d, 27, 'vitesse', 'TO_REWORK', 'Arrivée trop rapide au giratoire de Chézard.');
  PERFORM pg_temp.observe(l, d, 38, 'observation', 'POSITIVE', 'Rétroviseurs contrôlés régulièrement.');

  l := pg_temp.add_lesson(t_lea, luc, '2026-09-21 08:00', 50, 'Gare de Cernier');
  d := pg_temp.complete_lesson(l,
    'Trajet Cernier – Neuchâtel par la Vue-des-Alpes, giratoires de Malvilliers.',
    'Nette progression aux intersections. Le placement dans les virages reste à corriger.',
    'Placement en virage et premiers stationnements en épi.',
    '[["priorites","GUIDED","Priorités anticipées dans les villages, un rappel à Boudevilliers."],["intersections","GUIDED","Giratoire de Malvilliers bien négocié."],["placement","DISCOVERING","Trop à droite dans les virages."]]', true);
  PERFORM pg_temp.observe(l, d, 9, 'intersections', 'POSITIVE', 'Giratoire de Malvilliers bien négocié.');
  PERFORM pg_temp.observe(l, d, 22, 'placement', 'ATTENTION', 'Trop à droite dans le virage de la Vue-des-Alpes.');
  PERFORM pg_temp.observe(l, d, 41, 'manoeuvres', 'TO_REWORK', 'Stationnement en épi hésitant au parking du Mail.');

  l := pg_temp.add_lesson(t_lea, luc, '2026-09-25 16:00', 50, 'Place Pury, Neuchâtel');
  d := pg_temp.complete_lesson(l,
    'Circulation urbaine à Neuchâtel : Place Pury, avenue du 1er-Mars, stationnements.',
    'Bonne gestion du trafic urbain. Les piétons aux passages sont parfois vus tard.',
    'Anticipation des piétons et des bus ; préparer l’autoroute.',
    '[["placement","GUIDED","Placement correct, un rappel dans les virages serrés."],["manoeuvres","GUIDED","Stationnement en épi réussi au deuxième essai."],["anticipation","DISCOVERING","Piétons vus tardivement Place Pury."]]', true);
  PERFORM pg_temp.observe(l, d, 11, 'anticipation', 'ATTENTION', 'Piéton au passage de la Place Pury vu tard, freinage appuyé.');
  PERFORM pg_temp.observe(l, d, 19, NULL, NULL, 'Bus à l’arrêt dépassé proprement.');
  PERFORM pg_temp.observe(l, d, 33, 'manoeuvres', 'POSITIVE', 'Stationnement en épi réussi.');

  -- Aujourd'hui : leçon réalisée, bilan encore à terminer.
  l := pg_temp.add_lesson(t_lea, luc, '2026-09-28 08:00', 50, 'Gare de Cernier');
  d := pg_temp.complete_lesson(l, 'Première insertion sur la H20 et sortie à Neuchâtel-Vauseyon.', '', '',
    '[["autoroute","DISCOVERING","Insertion hésitante sur la H20."]]', false);
  PERFORM pg_temp.observe(l, d, 15, 'autoroute', 'ATTENTION', 'Vitesse trop faible à l’insertion sur la H20.');
  PERFORM pg_temp.observe(l, d, 28, 'observation', 'POSITIVE', 'Angle mort bien contrôlé avant le changement de voie.');
  PERFORM pg_temp.observe(l, d, 36, NULL, NULL, 'Revoir ensemble la sortie Vauseyon.');

  l := pg_temp.add_lesson(t_lea, luc, '2026-09-30 17:00', 50, 'Gare de Cernier');
  PERFORM pg_temp.prepare(l, '[["Insertion et sortie d’autoroute","autoroute"],["Piétons et bus en ville","anticipation"]]');
  l := pg_temp.add_lesson(t_lea, luc, '2026-10-02 16:00', 100, 'Gare de Neuchâtel');
  PERFORM pg_temp.prepare(l, '[["Dépassements sur autoroute","autoroute"]]');

  -- 9. Noé Favre avec luc.
  l := pg_temp.add_lesson(t_noe, luc, '2026-09-09 17:00', 50, 'Collège de Fontainemelon');
  d := pg_temp.complete_lesson(l,
    'Première leçon : installation, commandes et démarrages dans la zone industrielle de Fontainemelon.',
    'Très à l’aise avec les commandes. Tendance à regarder le volant en tournant.',
    'Regard loin et premières intersections.',
    '[["vehicule","GUIDED","Commandes maîtrisées dès la première leçon."],["observation","DISCOVERING","Regard trop souvent vers le volant."]]', true);
  PERFORM pg_temp.observe(l, d, 18, 'observation', 'ATTENTION', 'Regard vers le volant en tournant.');
  PERFORM pg_temp.observe(l, d, 35, 'vehicule', 'POSITIVE', 'Démarrage en côte réussi du premier coup.');

  l := pg_temp.add_lesson(t_noe, luc, '2026-09-23 17:00', 50, 'Collège de Fontainemelon');
  d := pg_temp.complete_lesson(l,
    'Intersections et giratoires entre Fontainemelon, Cernier et Dombresson.',
    'Les intersections simples sont acquises ; les giratoires à deux voies demandent encore de l’aide.',
    'Giratoires à deux voies et changements de voie.',
    '[["observation","GUIDED","Regard plus loin, contrôles réguliers."],["intersections","DISCOVERING","Hésitation sur la voie à choisir dans les giratoires."],["vitesse","GUIDED","Vitesse adaptée en traversée de village."]]', true);
  PERFORM pg_temp.observe(l, d, 21, 'intersections', 'TO_REWORK', 'Mauvaise voie dans le giratoire de Dombresson.');
  PERFORM pg_temp.observe(l, d, 33, 'vitesse', 'POSITIVE', '50 km/h bien tenus en traversée de Cernier.');
  PERFORM pg_temp.observe(l, d, 44, NULL, NULL, 'Cycliste dépassé avec la bonne distance.');

  l := pg_temp.add_lesson(t_noe, luc, '2026-09-28 18:30', 50, 'Collège de Fontainemelon');
  PERFORM pg_temp.prepare(l, '[["Giratoires à deux voies","intersections"],["Contrôles avant changement de voie","observation"]]');
  l := pg_temp.add_lesson(t_noe, luc, '2026-10-05 18:30', 50, 'Collège de Fontainemelon');

  -- 10. Emma Rochat avec luc (une annulation).
  l := pg_temp.add_lesson(t_emma, luc, '2026-09-11 10:00', 50, 'Place Pury, Neuchâtel');
  d := pg_temp.complete_lesson(l,
    'Évaluation de départ : Emma a déjà roulé avec ses parents. Circulation en ville de Neuchâtel.',
    'Bonne base. Vitesse souvent trop élevée en zone 30 ; les piétons sont à anticiper davantage.',
    'Adapter la vitesse en ville et anticiper les passages piétons.',
    '[["vehicule","INDEPENDENT","Véhicule bien maîtrisé."],["vitesse","DISCOVERING","Zone 30 dépassée à deux reprises."],["anticipation","DISCOVERING","Passages piétons vus tard."]]', true);
  PERFORM pg_temp.observe(l, d, 8, 'vitesse', 'TO_REWORK', '42 km/h en zone 30, rue des Parcs.');
  PERFORM pg_temp.observe(l, d, 20, 'anticipation', 'ATTENTION', 'Arrêt tardif au passage piéton de la rue de l’Hôpital.');
  PERFORM pg_temp.observe(l, d, 37, 'vehicule', 'POSITIVE', 'Créneau réussi rue du Seyon.');

  l := pg_temp.add_lesson(t_emma, luc, '2026-09-17 14:00', 100, 'Place Pury, Neuchâtel');
  d := pg_temp.complete_lesson(l,
    'Longue leçon : Neuchâtel – La Chaux-de-Fonds par la Vue-des-Alpes, retour par le tunnel.',
    'Vitesse désormais adaptée. Le placement en montée reste à travailler.',
    'Préparer l’autoroute ; placement dans les virages.',
    '[["vitesse","GUIDED","Vitesse adaptée, un rappel en descente."],["placement","DISCOVERING","Virages coupés à la montée."],["anticipation","GUIDED","Piétons et bus mieux anticipés."]]', true);
  PERFORM pg_temp.observe(l, d, 25, 'placement', 'ATTENTION', 'Virage coupé à la montée de la Vue-des-Alpes.');
  PERFORM pg_temp.observe(l, d, 48, 'vitesse', 'POSITIVE', 'Frein moteur bien utilisé en descente.');
  PERFORM pg_temp.observe(l, d, 71, 'anticipation', 'POSITIVE', 'Bus anticipé à l’arrêt.');
  PERFORM pg_temp.observe(l, d, 88, NULL, NULL, 'Parler du tunnel sous la Vue-des-Alpes.');

  l := pg_temp.add_lesson(t_emma, luc, '2026-09-24 10:00', 50, 'Place Pury, Neuchâtel');
  UPDATE drivy.lesson SET status = 'CANCELLED', version = 2, cancel_reason_code = 'LEARNER_REQUEST', cancel_comment = 'Élève malade.' WHERE id = l;
  UPDATE drivy.reservation SET active = false WHERE lesson_id = l;

  l := pg_temp.add_lesson(t_emma, luc, '2026-09-29 08:00', 50, 'Place Pury, Neuchâtel');
  PERFORM pg_temp.prepare(l, '[["Autoroute : insertion et sortie","autoroute"]]');

  -- 11. Lucas Perrin avec luc.
  l := pg_temp.add_lesson(t_lucas, luc, '2026-09-19 09:00', 50, 'Gare de Neuchâtel');
  d := pg_temp.complete_lesson(l,
    'Première leçon : commandes et démarrages au parking des Jeunes-Rives.',
    'Stressé au démarrage, mais progrès rapides en fin de leçon.',
    'Démarrages en côte et premières rues calmes.',
    '[["vehicule","DISCOVERING","Démarrages encore brusques."],["observation","DISCOVERING","Contrôles à construire."]]', true);
  PERFORM pg_temp.observe(l, d, 10, 'vehicule', 'TO_REWORK', 'Démarrage brusque, pied levé trop vite.');
  PERFORM pg_temp.observe(l, d, 42, 'vehicule', 'POSITIVE', 'Trois démarrages propres d’affilée.');
  l := pg_temp.add_lesson(t_lucas, luc, '2026-10-01 10:00', 50, 'Gare de Neuchâtel');

  -- 12. Élèves d'Alex (compte « moniteur »).
  l := pg_temp.add_lesson(t_sofia, alex, '2026-09-03 10:00', 50, 'Collège de Fontainemelon');
  d := pg_temp.complete_lesson(l, 'Prise en main du véhicule.',
    'Bonne première prise en main ; formation mise en pause ensuite à la demande de l’élève.',
    'Reprendre les démarrages en côte à la reprise.',
    '[["vehicule","DISCOVERING","Premiers démarrages."]]', true);
  l := pg_temp.add_lesson(t_hugo, alex, '2026-09-10 14:00', 50, 'Gare de Cernier');
  d := pg_temp.complete_lesson(l, 'Manœuvres : marche arrière et demi-tour à Cernier.',
    'Marche arrière précise ; le demi-tour manque de contrôles.', 'Contrôles pendant les manœuvres.',
    '[["manoeuvres","GUIDED","Marche arrière précise."],["observation","DISCOVERING","Contrôles oubliés pendant le demi-tour."]]', true);
  PERFORM pg_temp.observe(l, d, 16, 'manoeuvres', 'POSITIVE', 'Marche arrière en ligne droite précise.');
  PERFORM pg_temp.observe(l, d, 34, 'observation', 'ATTENTION', 'Demi-tour sans contrôle arrière.');
  l := pg_temp.add_lesson(t_hugo, alex, '2026-09-22 14:00', 50, 'Gare de Cernier');
  d := pg_temp.complete_lesson(l, 'Circulation dans le Val-de-Ruz et giratoires.', 'Contrôles nettement meilleurs.', 'Première approche de l’autoroute.',
    '[["observation","GUIDED","Contrôles réguliers."],["intersections","GUIDED","Giratoires bien négociés."]]', true);
  PERFORM pg_temp.observe(l, d, 22, 'intersections', 'POSITIVE', 'Giratoire de Chézard fluide.');
  l := pg_temp.add_lesson(t_hugo, alex, '2026-09-29 14:00', 50, 'Gare de Cernier');

  -- 13. Trace opérateur, sans donnée personnelle.
  INSERT INTO drivy.operation(actor_person_id, operation_id, school_id, command_type, payload_hash, resource_id, response_data)
  VALUES (luc_person, op, s, 'PROVISION_EXAMPLE_DATA', encode(sha256(convert_to('example-lessons-2026-09-28', 'UTF8')), 'hex'), s,
    jsonb_build_object('schoolId', s, 'synthetic', true, 'lessons', (SELECT count(*) FROM drivy.lesson WHERE school_id = s)));
  INSERT INTO drivy.audit_event(id, school_id, actor_person_id, actor_membership_id, operation_id, action, resource_type, resource_id, changed_fields)
  VALUES (gen_random_uuid(), s, luc_person, luc, op, 'OperatorProvisionedFictionalExamples', 'School', s,
    ARRAY['instructorRole', 'exampleCatalogue', 'exampleLessons', 'exampleReports', 'exampleObservations']);
END $$;

SELECT l.status, count(*) AS lessons, count(l.current_published_revision_id) AS published
FROM drivy.lesson l GROUP BY l.status ORDER BY 1;
SELECT count(*) AS observations FROM drivy.geo_observation;
SELECT count(*) AS progress_rows FROM drivy.training_progress;
COMMIT;
