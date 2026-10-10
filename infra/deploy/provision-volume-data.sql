-- Jeu de volume fictif pour « Luc auto école », demandé par le porteur le 4 octobre 2026
-- (« remplir la base avec un maximum d'infos, pour le moniteur et l'élève »).
-- Opérateur uniquement (psql superutilisateur sur CT113), en une seule transaction, après sauvegarde.
-- Additif : 80 élèves, 5 moniteurs sans compte, offres A et BE, environ 1 200 leçons avec bilans,
-- observations, objectifs, contrôles de permis, disponibilités et fermetures.
-- Aucun compte de connexion, aucun e-mail, aucune capture GPS ni position. Refuse une seconde exécution.
-- Seule ligne préexistante complétée : les champs vides du dossier de l'élève d'essai « Léa Morel · exemple ».
-- Essai sans écriture : psql -v dry_run=1 (la transaction est annulée après les contrôles).
\set ON_ERROR_STOP on
SET client_encoding = 'UTF8';
BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '300s';
SET LOCAL TIME ZONE 'Europe/Zurich';

CREATE TEMP TABLE seed_ctx(key text PRIMARY KEY, id uuid NOT NULL) ON COMMIT DROP;
CREATE FUNCTION pg_temp.ctx(k text) RETURNS uuid LANGUAGE sql STABLE AS $f$ SELECT id FROM seed_ctx WHERE key = k $f$;
-- Tirages reproductibles : la répétition et l'exécution réelle produisent le même jeu pour une même date.
CREATE FUNCTION pg_temp.h(label text) RETURNS integer LANGUAGE sql IMMUTABLE AS $f$
  SELECT ('x' || substr(md5('volume-20261004/' || label), 1, 7))::bit(28)::integer $f$;
-- Identifiants au format UUID v4 valide : l'API refuse tout autre format dans ses routes.
CREATE FUNCTION pg_temp.seed_uuid(label text) RETURNS uuid LANGUAGE sql IMMUTABLE AS $f$
  SELECT overlay(overlay(md5('volume-20261004/' || label) placing '4' from 13) placing '8' from 17)::uuid $f$;
CREATE FUNCTION pg_temp.pick(items text[], label text) RETURNS text LANGUAGE sql IMMUTABLE AS $f$
  SELECT items[1 + pg_temp.h(label) % cardinality(items)] $f$;

CREATE TEMP TABLE seed_instr(idx int PRIMARY KEY, membership uuid NOT NULL UNIQUE, person uuid NOT NULL UNIQUE) ON COMMIT DROP;
CREATE TEMP TABLE seed_cat(category text PRIMARY KEY, offering uuid NOT NULL, offering_key text NOT NULL, curriculum uuid NOT NULL,
  policy uuid NOT NULL, product uuid NOT NULL, terms uuid NOT NULL, price bigint NOT NULL, ncomp int NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE seed_learner(idx int PRIMARY KEY, id uuid NOT NULL UNIQUE, person uuid NOT NULL UNIQUE) ON COMMIT DROP;
CREATE TEMP TABLE seed_training(idx int PRIMARY KEY, id uuid NOT NULL UNIQUE, learner_idx int NOT NULL, category text NOT NULL,
  primary_instr int NOT NULL, secondary_instr int NOT NULL, fictive_instr int NOT NULL, alex_assigned boolean NOT NULL,
  ws date NOT NULL, we date NOT NULL, cadence int NOT NULL, status text NOT NULL, fresh boolean NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE seed_before(tbl text NOT NULL, id uuid NOT NULL, sig text NOT NULL, PRIMARY KEY(tbl, id)) ON COMMIT DROP;

-- Empreinte de chaque ligne existante : le contrôle final prouve que rien d'autre que le lot n'a changé.
DO $before$
DECLARE v_table text;
BEGIN
  FOREACH v_table IN ARRAY ARRAY['person','membership','learner_profile','training','instructor_assignment','onboarding_progress',
    'curriculum_version','competency_definition','school_policy_version','offering_version','commercial_terms_version',
    'service_product_version','availability_rule','closure','lesson','reservation','lesson_preparation','training_wish',
    'report_draft','report_revision','lesson_account','charge_entry','geo_observation','permit_check','capture_session'] LOOP
    EXECUTE format('INSERT INTO seed_before SELECT %L, x.id, md5(x::text) FROM drivy.%I x', v_table, v_table);
  END LOOP;
END $before$;

-- 1. Contexte, personnes, catalogue, formations.
DO $people$
DECLARE
  v_op constant uuid := pg_temp.seed_uuid('operation');
  v_today constant date := current_date;
  v_anchor constant date := current_date - 180;
  v_anchor_ts constant timestamptz := (current_date - 180)::timestamptz;
  v_school uuid; v_zone text; v_luc uuid; v_luc_person uuid; v_alex uuid; v_alex_person uuid;
  v_lea uuid; v_lea_person uuid; v_lea_training uuid; v_lea_started date;
  v_offering_b uuid; v_curriculum_b uuid; v_policy_b uuid; v_product_b uuid; v_terms uuid; v_price_b bigint;
  v_person uuid; v_member uuid; v_learner uuid; v_curriculum uuid; v_policy uuid; v_offering uuid; v_product uuid;
  v_cat text; v_price bigint; v_first text; v_last text; v_display text; v_created timestamptz; v_archived timestamptz;
  v_li int; v_fict int; v_primary int; v_secondary int; v_alex_assigned boolean; v_r int; v_p int;
  v_ws date; v_we date; v_cad int; v_status text; v_day date; v_pc int; v_reviewed timestamptz;
  i int; rec record;
  v_first_names constant text[] := ARRAY['Inès','Arthur','Zoé','Gabriel','Maëlle','Louis','Chloé','Nathan','Anaïs','Léo',
    'Camille','Théo','Élodie','Mathis','Océane','Jules','Marie-Louise','Jean-Baptiste','Éléonore','Sacha'];
  v_last_names constant text[] := ARRAY['Dubois','Jeanneret','Vuilleumier','Schneider','Aubert','Monnier','Perret','Humbert-Droz',
    'Matthey','Robert','Jacot','Borel','de Montmollin','Sandoz','Huguenin','Calame'];
  v_instructor_names constant text[] := ARRAY['Julien Rey','Nadia Keller','Marc Tissot','Sarah Grandjean','Olivier Favre-Bulle'];
  v_streets constant text[] := ARRAY['Rue de l’Exemple','Chemin des Essais','Avenue de la Recette','Rue du Jeu-de-Test','Chemin du Modèle','Rue Fictive'];
  v_places constant text[] := ARRAY['2000|Neuchâtel','2053|Cernier','2052|Fontainemelon','2046|Fontaines','2054|Chézard-Saint-Martin',
    '2300|La Chaux-de-Fonds','2034|Peseux','2072|Saint-Blaise'];
  v_wishes constant text[] := ARRAY['J’aimerais faire plus d’autoroute avant l’examen.','Je préfère les leçons en fin de journée.',
    'Je voudrais revoir les stationnements.','Peut-on faire une leçon de nuit ?','Je stresse dans les giratoires à deux voies.',
    'J’aimerais passer l’examen avant la fin de l’année.','Je souhaite des leçons doubles quand c’est possible.'];
BEGIN
  SELECT id, time_zone INTO STRICT v_school, v_zone FROM drivy.school WHERE name = 'Luc auto école' AND status = 'ACTIVE';
  IF v_zone <> 'Europe/Zurich' THEN RAISE EXCEPTION 'volume seed: unexpected school time zone %', v_zone; END IF;
  SELECT m.id, m.person_id INTO STRICT v_luc, v_luc_person FROM drivy.membership m JOIN drivy.person p ON p.id = m.person_id
    WHERE m.school_id = v_school AND p.display_name = 'luc' AND m.status = 'ACTIVE' AND m.roles @> ARRAY['ADMIN','INSTRUCTOR'];
  SELECT m.id, m.person_id INTO STRICT v_alex, v_alex_person FROM drivy.membership m JOIN drivy.person p ON p.id = m.person_id
    WHERE m.school_id = v_school AND p.display_name = 'Alex Martin · exemple' AND m.status = 'ACTIVE' AND 'INSTRUCTOR' = ANY(m.roles);
  SELECT lp.id, lp.person_id, t.id, t.started_on INTO STRICT v_lea, v_lea_person, v_lea_training, v_lea_started
    FROM drivy.learner_profile lp JOIN drivy.training t ON t.school_id = lp.school_id AND t.learner_id = lp.id
    WHERE lp.school_id = v_school AND lp.display_name = 'Léa Morel · exemple' AND lp.archived_at IS NULL
      AND t.offering_key = 'example-category-b' AND t.status = 'ACTIVE';

  IF EXISTS (SELECT 1 FROM drivy.operation o WHERE o.operation_id = v_op) THEN RAISE EXCEPTION 'volume seed: already provisioned'; END IF;
  IF EXISTS (SELECT 1 FROM drivy.offering_version o WHERE o.school_id = v_school AND o.category_code IN ('A','BE'))
     OR EXISTS (SELECT 1 FROM drivy.curriculum_version c WHERE c.school_id = v_school AND c.category_code IN ('A','BE'))
     OR EXISTS (SELECT 1 FROM drivy.school_policy_version c WHERE c.school_id = v_school AND c.category_code IN ('A','BE'))
     OR EXISTS (SELECT 1 FROM drivy.service_product_version s WHERE s.school_id = v_school AND s.product_key IN ('lecon-a-50','lecon-be-50')) THEN
    RAISE EXCEPTION 'volume seed: categories A or BE already configured; operator review required';
  END IF;
  -- Les déclencheurs d'accueil travaillent à l'échelle de l'école : ils ne doivent rien avoir à compléter sur l'existant.
  IF EXISTS (SELECT 1 FROM drivy.learner_profile l WHERE l.school_id = v_school AND l.administrative_policy_id IS NULL) THEN
    RAISE EXCEPTION 'volume seed: existing profile initialization would change old rows';
  END IF;
  IF EXISTS (SELECT 1 FROM drivy.membership m CROSS JOIN (VALUES ('STUDENT'),('STAFF')) AS k(kind)
    WHERE m.school_id = v_school AND m.status = 'ACTIVE'
      AND ((k.kind = 'STUDENT' AND 'LEARNER' = ANY(m.roles)) OR (k.kind = 'STAFF' AND m.roles && ARRAY['ADMIN','INSTRUCTOR']))
      AND NOT EXISTS (SELECT 1 FROM drivy.onboarding_progress o WHERE o.membership_id = m.id AND o.kind = k.kind)) THEN
    RAISE EXCEPTION 'volume seed: existing onboarding initialization would add old rows';
  END IF;

  -- Catégorie B : l'offre, le référentiel et la prestation déjà utilisés par l'école sont repris tels quels.
  SELECT o.id, o.curriculum_version_id, o.policy_version_id INTO STRICT v_offering_b, v_curriculum_b, v_policy_b
    FROM drivy.offering_version o JOIN drivy.school_policy_version p ON p.id = o.policy_version_id
    WHERE o.school_id = v_school AND o.offering_key = 'example-category-b' AND o.enabled AND p.approved
    ORDER BY o.version DESC LIMIT 1;
  SELECT s.id, s.terms_version_id, s.unit_price_cents INTO STRICT v_product_b, v_terms, v_price_b
    FROM drivy.service_product_version s JOIN drivy.commercial_terms_version c ON c.id = s.terms_version_id
    WHERE s.school_id = v_school AND s.product_key = 'lecon-b-50' AND s.enabled AND s.duration_minutes = 50 AND c.approved
    ORDER BY s.version DESC LIMIT 1;
  INSERT INTO seed_ctx VALUES ('school', v_school), ('luc', v_luc), ('lucPerson', v_luc_person), ('operation', v_op), ('lea', v_lea);
  INSERT INTO seed_cat SELECT 'B', v_offering_b, 'example-category-b', v_curriculum_b, v_policy_b, v_product_b, v_terms, v_price_b,
    (SELECT count(*) FROM drivy.competency_definition d WHERE d.curriculum_version_id = v_curriculum_b);
  IF (SELECT ncomp FROM seed_cat WHERE category = 'B') < 7 THEN RAISE EXCEPTION 'volume seed: category B curriculum too small'; END IF;
  IF EXISTS (SELECT 1 FROM (SELECT d.sort_order, row_number() OVER (ORDER BY d.sort_order) - 1 AS expected
      FROM drivy.competency_definition d WHERE d.curriculum_version_id = v_curriculum_b) x WHERE x.sort_order <> x.expected) THEN
    RAISE EXCEPTION 'volume seed: category B competencies must be ordered from 0 without gap';
  END IF;

  -- Moniteurs : luc, Alex, puis cinq moniteurs visibles au planning, sans identité de connexion.
  INSERT INTO seed_instr VALUES (1, v_luc, v_luc_person), (2, v_alex, v_alex_person);
  FOR i IN 1..5 LOOP
    v_person := pg_temp.seed_uuid('instructor/person/' || i);
    v_member := pg_temp.seed_uuid('instructor/member/' || i);
    INSERT INTO drivy.person(id, display_name) VALUES (v_person, v_instructor_names[i] || ' · exemple');
    INSERT INTO drivy.membership(id, school_id, person_id, roles, created_at)
      VALUES (v_member, v_school, v_person, ARRAY['INSTRUCTOR'], v_anchor_ts - interval '20 days');
    INSERT INTO seed_instr VALUES (2 + i, v_member, v_person);
    INSERT INTO drivy.availability_rule(school_id, instructor_membership_id, weekdays, local_start, local_end, valid_from, created_at)
      VALUES (v_school, v_member, ARRAY[1,2,3,4,5], '08:00', '18:00', v_anchor, v_anchor_ts);
    IF i <= 2 THEN
      INSERT INTO drivy.availability_rule(school_id, instructor_membership_id, weekdays, local_start, local_end, valid_from, created_at)
        VALUES (v_school, v_member, ARRAY[6], '08:00', '12:00', v_anchor, v_anchor_ts);
    END IF;
  END LOOP;

  -- Offres A (moto) et BE (remorque) : référentiel, procédure, offre ouverte et prestation de 50 minutes.
  FOREACH v_cat IN ARRAY ARRAY['A','BE'] LOOP
    v_curriculum := pg_temp.seed_uuid('curriculum/' || v_cat);
    v_policy := pg_temp.seed_uuid('policy/' || v_cat);
    v_offering := pg_temp.seed_uuid('offering/' || v_cat);
    v_product := pg_temp.seed_uuid('product/' || v_cat);
    v_price := CASE v_cat WHEN 'A' THEN 10000 ELSE 11000 END;
    INSERT INTO drivy.curriculum_version(id, school_id, category_code, revision, approved, approval_reason, created_by, approved_at, created_at)
      VALUES (v_curriculum, v_school, v_cat, 1, true, 'Référentiel d’exemple fourni à la demande du porteur ; à relire par l’école.', v_luc, v_anchor_ts, v_anchor_ts);
    IF v_cat = 'A' THEN
      INSERT INTO drivy.competency_definition(id, school_id, curriculum_version_id, stable_key, label, description, sort_order)
      SELECT pg_temp.seed_uuid('competency/A/' || d.key), v_school, v_curriculum, d.key, d.label, d.description, d.sort_order FROM (VALUES
        ('equipement','Équipement et vérifications','Casque, gants, tenue et contrôles avant le départ.',0),
        ('equilibre','Équilibre à basse vitesse','Slalom lent, demi-tours et arrêts sans poser le pied trop tôt.',1),
        ('freinage','Freinage','Dosage des deux freins, freinage d’urgence et en courbe.',2),
        ('trajectoires','Trajectoires en virage','Regard, point de corde et position dans la voie.',3),
        ('observation','Observation et contrôles','Rétroviseurs, angles morts et regard loin.',4),
        ('priorites','Priorités','Priorité de droite, signalisation et céder le passage.',5),
        ('intersections','Intersections et giratoires','Placement, choix de voie et sortie.',6),
        ('vitesse','Adaptation de la vitesse','Allure adaptée au revêtement, à la visibilité et au trafic.',7),
        ('depassement','Dépassements','Préparer, signaler et se rabattre en sécurité.',8),
        ('anticipation','Anticipation et partage de la route','Voitures qui déboîtent, piétons et chaussée glissante.',9)
      ) AS d(key, label, description, sort_order);
    ELSE
      INSERT INTO drivy.competency_definition(id, school_id, curriculum_version_id, stable_key, label, description, sort_order)
      SELECT pg_temp.seed_uuid('competency/BE/' || d.key), v_school, v_curriculum, d.key, d.label, d.description, d.sort_order FROM (VALUES
        ('attelage','Attelage et contrôles','Atteler, brancher, vérifier les feux, la charge et la pression.',0),
        ('gabarit','Gabarit et trajectoires','Élargir les virages et tenir compte de la longueur de l’ensemble.',1),
        ('marche-arriere','Marche arrière avec remorque','Reculer en ligne droite puis en courbe.',2),
        ('manoeuvres','Manœuvres et stationnement','Mise à quai, créneau et demi-tour avec l’ensemble.',3),
        ('freinage','Freinage et distances','Distances d’arrêt allongées, frein moteur en descente.',4),
        ('observation','Observation et contrôles','Rétroviseurs extérieurs et angles morts de l’ensemble.',5),
        ('vitesse','Adaptation de la vitesse','Limitations propres aux ensembles et stabilité.',6),
        ('autoroute','Autoroute','Insertion, dépassement et vent latéral.',7)
      ) AS d(key, label, description, sort_order);
    END IF;
    INSERT INTO drivy.school_policy_version(id, school_id, category_code, version, procedure_text, cancellation_policy_text, source_urls,
      approved, approval_reason, created_by, approved_at, created_at)
    VALUES (v_policy, v_school, v_cat, 1,
      CASE v_cat WHEN 'A' THEN 'Leçons de 50 minutes au départ de l’école. Équipement complet obligatoire ; le permis d’élève est contrôlé avant la première leçon.'
        ELSE 'Leçons de 50 minutes avec l’ensemble de l’école. Le permis B et le permis d’élève BE sont contrôlés avant la première leçon.' END,
      'Annulation gratuite jusqu’à 24 heures avant la leçon. Au-delà, la leçon est due, sauf cas de force majeure.',
      '{}', true, 'Procédure d’exemple fournie à la demande du porteur ; à relire par l’école.', v_luc, v_anchor_ts, v_anchor_ts);
    INSERT INTO drivy.offering_version(id, school_id, offering_key, category_code, version, enabled, curriculum_version_id,
      policy_version_id, default_duration_minutes, default_price_cents, created_at)
    VALUES (v_offering, v_school, 'example-category-' || lower(v_cat), v_cat, 1, true, v_curriculum, v_policy, 50, v_price, v_anchor_ts);
    INSERT INTO drivy.service_product_version(id, school_id, version, product_key, label, type, category_code, duration_minutes,
      unit_label, unit_price_cents, valid_from, terms_version_id, enabled, created_at)
    VALUES (v_product, v_school, 1, 'lecon-' || lower(v_cat) || '-50',
      CASE v_cat WHEN 'A' THEN 'Leçon de moto · 50 min' ELSE 'Leçon avec remorque · 50 min' END,
      'INDIVIDUAL_LESSON', v_cat, 50, 'leçon', v_price, v_anchor, v_terms, true, v_anchor_ts);
    INSERT INTO seed_cat VALUES (v_cat, v_offering, 'example-category-' || lower(v_cat), v_curriculum, v_policy, v_product, v_terms, v_price,
      (SELECT count(*) FROM drivy.competency_definition d WHERE d.curriculum_version_id = v_curriculum));
  END LOOP;

  -- Plan des formations : terminées, en pause, en cours ou à venir, pour que tous les états se rencontrent.
  INSERT INTO seed_training VALUES (0, v_lea_training, 0, 'B', 1, 2, 3, true, greatest(v_lea_started, v_today - 28), v_today + 45, 6, 'ACTIVE', false);
  FOR i IN 1..102 LOOP
    v_li := CASE WHEN i <= 80 THEN i WHEN i <= 100 THEN i - 80 ELSE 0 END;
    v_cat := CASE WHEN i <= 60 THEN 'B' WHEN i <= 72 THEN 'A' WHEN i <= 80 THEN 'BE' WHEN i <= 92 THEN 'A' WHEN i <= 100 THEN 'BE'
      WHEN i = 101 THEN 'A' ELSE 'BE' END;
    v_fict := 3 + (CASE WHEN i <= 60 THEN i / 5 ELSE i END) % 5;
    v_primary := CASE
      WHEN i <= 60 THEN CASE WHEN i % 5 IN (1, 2) THEN 1 WHEN i % 5 IN (3, 4) THEN 2 ELSE v_fict END
      WHEN i <= 80 THEN CASE WHEN i IN (61, 62, 63, 73) THEN 1 ELSE v_fict END
      WHEN i <= 100 THEN CASE WHEN i <= 88 THEN 2 ELSE v_fict END
      WHEN i = 101 THEN 2 ELSE 1 END;
    -- Les formations 61 à 80 ne sont pas confiées à Alex : son compte ne doit pas les voir.
    v_alex_assigned := i <= 60 OR i >= 81;
    v_secondary := CASE WHEN v_primary <> 1 THEN 1 WHEN v_alex_assigned THEN 2 ELSE v_fict END;
    v_r := pg_temp.h('span/' || i);
    v_p := pg_temp.h('phase/' || i) % 100;
    v_cad := CASE WHEN pg_temp.h('cadence/' || i) % 20 < 4 THEN 4 WHEN pg_temp.h('cadence/' || i) % 20 < 7 THEN 10 ELSE 7 END;
    IF i = 101 THEN
      v_ws := v_anchor; v_we := v_today + 45; v_cad := 2; v_status := 'ACTIVE';
    ELSIF i = 102 THEN
      v_ws := v_today - 120; v_we := v_today + 45; v_cad := 7; v_status := 'ACTIVE';
    ELSIF i IN (78, 79, 80) OR v_p < 22 THEN
      v_ws := v_anchor + v_r % 50; v_we := v_ws + 49 + (v_r / 50) % 50;
      v_status := CASE WHEN i = 80 THEN 'CANCELLED' WHEN i IN (78, 79) OR pg_temp.h('closed/' || i) % 10 < 7 THEN 'COMPLETED' ELSE 'ACTIVE' END;
    ELSIF v_p < 30 THEN
      v_ws := v_today - 150 + v_r % 60; v_we := v_ws + 42 + (v_r / 60) % 30; v_status := 'PAUSED';
    ELSIF v_p < 90 THEN
      v_ws := v_today - 90 + v_r % 80; v_we := v_today + 45; v_status := 'ACTIVE';
    ELSE
      v_ws := v_today + v_r % 8; v_we := v_today + 45; v_status := 'ACTIVE';
    END IF;
    INSERT INTO seed_training VALUES (i, pg_temp.seed_uuid('training/' || i), v_li, v_cat, v_primary, v_secondary, v_fict, v_alex_assigned,
      v_ws, v_we, v_cad, v_status, true);
  END LOOP;

  -- Élèves : dossier complet, avec quelques informations facultatives absentes et trois dossiers archivés.
  INSERT INTO seed_learner VALUES (0, v_lea, v_lea_person);
  FOR i IN 1..80 LOOP
    v_person := pg_temp.seed_uuid('learner/person/' || i);
    v_member := pg_temp.seed_uuid('learner/member/' || i);
    v_learner := pg_temp.seed_uuid('learner/profile/' || i);
    v_first := v_first_names[1 + (i - 1) % 20];
    v_last := v_last_names[1 + ((i - 1) * 7) % 16];
    v_display := v_first || ' ' || v_last || ' · exemple';
    SELECT (min(t.ws) - 6)::timestamptz + interval '10 hours 15 minutes',
           CASE WHEN i >= 78 THEN (max(t.we) + 5)::timestamptz + interval '9 hours' END
      INTO v_created, v_archived FROM seed_training t WHERE t.learner_idx = i;
    v_created := least(v_created, now() - interval '2 hours');
    INSERT INTO drivy.person(id, display_name) VALUES (v_person, v_display);
    INSERT INTO drivy.membership(id, school_id, person_id, roles, created_at) VALUES (v_member, v_school, v_person, ARRAY['LEARNER'], v_created);
    INSERT INTO drivy.learner_profile(id, school_id, person_id, display_name, first_name, last_name, birth_date, postal_address,
      contact_email, contact_phone, profile_readiness, entry_source, created_at, profile_updated_at, archived_at)
    VALUES (v_learner, v_school, v_person, v_display, v_first, v_last,
      CASE WHEN i % 17 <> 3 THEN make_date(1986 + pg_temp.h('birth/y/' || i) % 23, 1 + pg_temp.h('birth/m/' || i) % 12, 1 + pg_temp.h('birth/d/' || i) % 28) END,
      CASE WHEN i % 13 <> 5 THEN jsonb_build_object(
        'line1', pg_temp.pick(v_streets, 'street/' || i) || ' ' || (1 + pg_temp.h('number/' || i) % 48),
        'line2', CASE WHEN i % 6 = 0 THEN 'Appartement ' || (1 + i % 24) END,
        'postalCode', split_part(pg_temp.pick(v_places, 'place/' || i), '|', 1),
        'locality', split_part(pg_temp.pick(v_places, 'place/' || i), '|', 2), 'countryCode', 'CH') END,
      'volume.eleve' || lpad(i::text, 3, '0') || '@example.invalid',
      CASE WHEN i % 10 <> 7 THEN '+41000000' || lpad(i::text, 3, '0') END,
      CASE WHEN i % 19 = 4 THEN 'ACTION_REQUIRED' ELSE 'READY' END, 'STAFF_ASSISTED', v_created, v_created, v_archived);
    INSERT INTO seed_learner VALUES (i, v_learner, v_person);
  END LOOP;
  IF (SELECT count(DISTINCT p.display_name) FROM seed_learner s JOIN drivy.person p ON p.id = s.person) <> 81 THEN
    RAISE EXCEPTION 'volume seed: learner names must be distinct';
  END IF;

  -- Dossier de l'élève d'essai : seuls les champs vides sont complétés, rien de saisi n'est remplacé.
  UPDATE drivy.learner_profile l SET
    birth_date = coalesce(l.birth_date, date '2004-03-18'),
    postal_address = coalesce(l.postal_address, jsonb_build_object('line1', 'Rue de l’Exemple 12', 'line2', NULL,
      'postalCode', '2053', 'locality', 'Cernier', 'countryCode', 'CH')),
    contact_phone = coalesce(l.contact_phone, '+41000000999'),
    profile_updated_at = now(), version = l.version + 1
  WHERE l.id = v_lea AND (l.birth_date IS NULL OR l.postal_address IS NULL OR l.contact_phone IS NULL);

  -- Formations, affectations, souhaits et contrôles de permis.
  FOR rec IN SELECT t.*, l.id AS learner_id, c.offering, c.offering_key FROM seed_training t
      JOIN seed_learner l ON l.idx = t.learner_idx JOIN seed_cat c ON c.category = t.category WHERE t.fresh ORDER BY t.idx LOOP
    v_created := least((rec.ws - 5)::timestamptz + interval '10 hours 30 minutes', now() - interval '1 hour');
    v_pc := pg_temp.h('permit/' || rec.idx) % 100;
    IF rec.idx > 100 THEN v_pc := 0; END IF;
    INSERT INTO drivy.training(id, school_id, learner_id, offering_id, offering_key, status, started_on, closed_on, version, created_at)
    VALUES (rec.id, v_school, rec.learner_id, rec.offering, rec.offering_key, rec.status, rec.ws,
      CASE WHEN rec.status IN ('COMPLETED','CANCELLED') THEN rec.we + 3 END,
      1 + CASE WHEN rec.status <> 'ACTIVE' THEN 1 ELSE 0 END + CASE WHEN v_pc < 91 AND rec.ws <= v_today THEN 1 ELSE 0 END, v_created);
    INSERT INTO drivy.instructor_assignment(id, school_id, training_id, instructor_membership_id, valid_from, created_at)
    SELECT pg_temp.seed_uuid('assignment/' || rec.idx || '/' || s.idx), v_school, rec.id, s.membership, v_created, v_created
      FROM seed_instr s WHERE s.idx = 1 OR (s.idx = 2 AND rec.alex_assigned) OR s.idx = rec.fictive_instr;
    IF pg_temp.h('wish/' || rec.idx) % 100 < 60 THEN
      UPDATE drivy.training_wish w SET version = w.version + 1, text = pg_temp.pick(v_wishes, 'wish/text/' || rec.idx) WHERE w.training_id = rec.id;
    END IF;
    -- Contrôle de permis : approuvé le plus souvent, parfois bientôt échu, échu, refusé ou absent.
    IF v_pc < 91 AND rec.ws <= v_today THEN
      v_reviewed := least(rec.ws::timestamptz + interval '8 hours', now() - interval '30 minutes');
      INSERT INTO drivy.permit_check(id, school_id, training_id, physical_seen, category_code, valid_until, decision,
        reviewer_membership_id, reviewed_at, reason, operation_id, created_at)
      VALUES (pg_temp.seed_uuid('permit/' || rec.idx), v_school, rec.id, v_pc < 86, rec.category,
        CASE WHEN v_pc < 36 THEN NULL WHEN v_pc < 72 THEN v_today + 90 + pg_temp.h('permit/until/' || rec.idx) % 500
          WHEN v_pc < 80 THEN v_today + 5 + pg_temp.h('permit/until/' || rec.idx) % 20
          WHEN v_pc < 86 THEN v_today - 3 - pg_temp.h('permit/until/' || rec.idx) % 37 END,
        CASE WHEN v_pc < 86 THEN 'APPROVED' ELSE 'REJECTED' END, v_luc, v_reviewed,
        CASE WHEN v_pc >= 86 THEN pg_temp.pick(ARRAY['Permis d’élève illisible, à représenter.','Catégorie du permis différente de la formation.',
          'Permis d’élève échu à la date du contrôle.'], 'permit/reason/' || rec.idx) END,
        pg_temp.seed_uuid('permit/operation/' || rec.idx), v_reviewed);
    END IF;
  END LOOP;

  -- Fermetures : une journée de formation pour Alex, un congé pour un moniteur d'exemple.
  v_day := v_today + 21;
  WHILE extract(isodow FROM v_day) > 5 LOOP v_day := v_day + 1; END LOOP;
  INSERT INTO drivy.closure(school_id, instructor_membership_id, starts_at, ends_at, reason, created_at) VALUES
    (v_school, v_alex, v_day::timestamptz, (v_day + 1)::timestamptz, 'Formation continue · exemple', now() - interval '1 hour'),
    (v_school, (SELECT membership FROM seed_instr WHERE idx = 5), (v_today + 9)::timestamptz + interval '13 hours', (v_today + 11)::timestamptz,
      'Congé · exemple', now() - interval '1 hour');
END $people$;

-- 2. Créneaux possibles par moniteur. À partir d'aujourd'hui, luc et Alex gardent des journées peu chargées :
--    « Démarrer une leçon » doit rester possible la plupart du temps pendant les essais.
CREATE TEMP TABLE seed_slot(instr int NOT NULL, day date NOT NULL, hour int NOT NULL, start_ts timestamptz NOT NULL) ON COMMIT DROP;
INSERT INTO seed_slot
SELECT i.idx, d.day, hh.hour, (d.day + make_time(hh.hour, 0, 0))::timestamptz
FROM seed_instr i
CROSS JOIN (SELECT current_date - 180 + g AS day FROM generate_series(0, 225) AS g) d
CROSS JOIN unnest(ARRAY[8,9,10,11,13,14,15,16,17]) AS hh(hour)
WHERE CASE
  WHEN extract(isodow FROM d.day) = 7 THEN false
  WHEN extract(isodow FROM d.day) = 6 THEN i.idx IN (1, 3, 4) AND hh.hour <= 11 AND (i.idx <> 1 OR d.day < current_date OR hh.hour = 10)
  WHEN i.idx = 1 THEN d.day < current_date OR hh.hour = ANY(CASE WHEN extract(isodow FROM d.day) IN (1, 3, 5) THEN ARRAY[9, 14] ELSE ARRAY[10, 16] END)
  WHEN i.idx = 2 THEN hh.hour <= 16 AND (d.day < current_date OR hh.hour IN (8, 10, 15))
  ELSE true END;
CREATE INDEX seed_slot_lookup ON seed_slot(instr, day);

-- Toute occupation déjà connue, active ou non, est évitée : aucune leçon du lot ne recouvre un rendez-vous existant.
CREATE TEMP TABLE seed_busy(resource uuid NOT NULL, during tstzrange NOT NULL) ON COMMIT DROP;
INSERT INTO seed_busy SELECT r.resource_id, r.during FROM drivy.reservation r WHERE r.school_id = pg_temp.ctx('school');
INSERT INTO seed_busy SELECT l.learner_person_id, tstzrange(least(l.planned_start, coalesce(l.actual_start, l.planned_start)),
    greatest(l.planned_end, coalesce(l.actual_end, l.planned_end)), '[)') FROM drivy.lesson l WHERE l.school_id = pg_temp.ctx('school');
INSERT INTO seed_busy SELECT m.person_id, tstzrange(least(l.planned_start, coalesce(l.actual_start, l.planned_start)),
    greatest(l.planned_end, coalesce(l.actual_end, l.planned_end)) + make_interval(mins => l.buffer_minutes_snapshot), '[)')
  FROM drivy.lesson l JOIN drivy.membership m ON m.id = l.instructor_membership_id WHERE l.school_id = pg_temp.ctx('school');
INSERT INTO seed_busy SELECT m.person_id, tstzrange(c.starts_at, c.ends_at, '[)')
  FROM drivy.closure c JOIN drivy.membership m ON m.id = c.instructor_membership_id WHERE c.school_id = pg_temp.ctx('school') AND c.removed_at IS NULL;
CREATE INDEX seed_busy_lookup ON seed_busy(resource);

CREATE TEMP TABLE seed_request(n int PRIMARY KEY, training int NOT NULL, k int NOT NULL, target date NOT NULL, instr int NOT NULL, minutes int NOT NULL) ON COMMIT DROP;
INSERT INTO seed_request
SELECT row_number() OVER (ORDER BY q.prio, q.target, q.training, q.k), q.training, q.k, q.target, q.instr, q.minutes
FROM (
  SELECT t.idx AS training, g.k, d.target, t.we,
    CASE WHEN pg_temp.h('instructor/' || t.idx || '/' || g.k) % 100 < 15 THEN t.secondary_instr ELSE t.primary_instr END AS instr,
    CASE WHEN pg_temp.h('duration/' || t.idx || '/' || g.k) % 100 < 12 THEN 100 ELSE 50 END AS minutes,
    CASE WHEN t.learner_idx = 0 THEN 1 ELSE 2 END AS prio
  FROM seed_training t CROSS JOIN LATERAL generate_series(0, (t.we - t.ws) / t.cadence) AS g(k)
  CROSS JOIN LATERAL (SELECT t.ws + g.k * t.cadence + pg_temp.h('jitter/' || t.idx || '/' || g.k) % 3 AS raw) b
  -- Un rendez-vous tombant le week-end est réparti sur la semaine suivante plutôt que reporté en bloc au lundi.
  CROSS JOIN LATERAL (SELECT b.raw + CASE
      WHEN extract(isodow FROM b.raw) = 7 THEN 1 + pg_temp.h('weekend/' || t.idx || '/' || g.k) % 5
      WHEN extract(isodow FROM b.raw) = 6 AND pg_temp.h('weekend/' || t.idx || '/' || g.k) % 3 > 0 THEN 2 + pg_temp.h('weekend/' || t.idx || '/' || g.k) % 5
      ELSE 0 END AS target) d
  UNION ALL
  -- Leçons du jour assurées pour les deux comptes moniteur d'essai.
  SELECT x.idx, 900, current_date, current_date + 1, x.primary_instr, 50, 0
  FROM (SELECT t.idx, t.primary_instr, row_number() OVER (PARTITION BY t.primary_instr ORDER BY t.idx) AS rank
        FROM seed_training t WHERE t.fresh AND t.category = 'B' AND t.status = 'ACTIVE' AND t.primary_instr IN (1, 2)
          AND t.ws <= current_date - 7 AND t.we >= current_date) x WHERE x.rank <= 3
) q WHERE q.target <= q.we;

CREATE TEMP TABLE seed_lesson(n int PRIMARY KEY, training int NOT NULL, k int NOT NULL, instr int NOT NULL, start_ts timestamptz NOT NULL,
  minutes int NOT NULL, id uuid, status text, report text, price bigint, a_start timestamptz, a_end timestamptz) ON COMMIT DROP;

DO $allocate$
DECLARE
  rec record; v_start timestamptz; v_instructor uuid; v_skipped int := 0; v_buffer constant int := 10;
BEGIN
  FOR rec IN SELECT q.*, l.person AS learner_person FROM seed_request q JOIN seed_training t ON t.idx = q.training
      JOIN seed_learner l ON l.idx = t.learner_idx ORDER BY q.n LOOP
    SELECT person INTO STRICT v_instructor FROM seed_instr WHERE idx = rec.instr;
    SELECT s.start_ts INTO v_start FROM seed_slot s
     WHERE s.instr = rec.instr AND s.day BETWEEN rec.target AND rec.target + 9
       AND (rec.minutes = 50 OR s.hour IN (8, 10, 13, 15) OR (rec.instr = 1 AND s.day >= current_date AND extract(isodow FROM s.day) < 6))
       AND NOT EXISTS (SELECT 1 FROM seed_busy b WHERE b.resource = v_instructor
         AND b.during && tstzrange(s.start_ts, s.start_ts + make_interval(mins => rec.minutes + v_buffer), '[)'))
       AND NOT EXISTS (SELECT 1 FROM seed_busy b WHERE b.resource = rec.learner_person
         AND b.during && tstzrange(s.start_ts, s.start_ts + make_interval(mins => rec.minutes), '[)'))
     ORDER BY s.day, pg_temp.h('slot/' || rec.n || '/' || s.hour) LIMIT 1;
    IF NOT FOUND THEN v_skipped := v_skipped + 1; CONTINUE; END IF;
    INSERT INTO seed_busy VALUES
      (v_instructor, tstzrange(v_start, v_start + make_interval(mins => rec.minutes + v_buffer), '[)')),
      (rec.learner_person, tstzrange(v_start, v_start + make_interval(mins => rec.minutes), '[)'));
    INSERT INTO seed_lesson(n, training, k, instr, start_ts, minutes) VALUES (rec.n, rec.training, rec.k, rec.instr, v_start, rec.minutes);
  END LOOP;
  RAISE NOTICE 'volume seed: % lessons placed, % requests without free slot', (SELECT count(*) FROM seed_lesson), v_skipped;
END $allocate$;

-- 3. Issue de chaque leçon selon sa date : réalisée, annulée, absence, à constater ou à venir.
UPDATE seed_lesson s SET id = pg_temp.seed_uuid('lesson/' || s.n),
  price = c.price * (s.minutes / 50),
  status = CASE
    WHEN s.start_ts + make_interval(mins => s.minutes + 10) < now() THEN CASE
      WHEN s.start_ts::date >= current_date - CASE WHEN s.instr <= 2 THEN 6 ELSE 10 END
        AND pg_temp.h('status/' || s.n) % 100 < CASE WHEN s.instr <= 2 THEN 6 ELSE 14 END THEN 'PLANNED'
      WHEN pg_temp.h('status/' || s.n) % 100 BETWEEN 20 AND 28 THEN 'CANCELLED'
      WHEN pg_temp.h('status/' || s.n) % 100 BETWEEN 29 AND 34 THEN 'NO_SHOW'
      ELSE 'COMPLETED' END
    WHEN s.start_ts > now() AND pg_temp.h('status/' || s.n) % 100 < 8 THEN 'CANCELLED'
    ELSE 'PLANNED' END
FROM seed_training t JOIN seed_cat c ON c.category = t.category WHERE t.idx = s.training;
-- Bilan : partagé, repris une fois, gardé privé, ou encore à rédiger pour une leçon récente.
UPDATE seed_lesson s SET
  a_start = s.start_ts + make_interval(mins => pg_temp.h('actual/start/' || s.n) % 10 - 3),
  a_end = s.start_ts + make_interval(mins => s.minutes + pg_temp.h('actual/end/' || s.n) % 11 - 2),
  report = CASE
    WHEN s.start_ts > now() - interval '21 days' AND pg_temp.h('report/' || s.n) % 100 < 22 THEN 'EMPTY'
    WHEN pg_temp.h('report/' || s.n) % 100 BETWEEN 22 AND 29 THEN 'PRIVATE'
    WHEN pg_temp.h('report/' || s.n) % 100 BETWEEN 30 AND 43 THEN 'UPDATED'
    ELSE 'SHARED' END
WHERE s.status = 'COMPLETED';

INSERT INTO drivy.lesson(id, school_id, version, training_id, learner_id, learner_person_id, instructor_membership_id, planned_start, planned_end,
  time_zone, meeting_point, status, price_cents_snapshot, buffer_minutes_snapshot, policy_version_id, commercial_selection,
  publication_version, actual_start, actual_end, cancel_reason_code, cancel_comment, created_at, completion_anomaly_reason, no_show_reason,
  report_private, sharing_version)
SELECT s.id, pg_temp.ctx('school'),
  CASE WHEN s.status = 'PLANNED' THEN 1 WHEN s.report = 'SHARED' THEN 3 WHEN s.report = 'UPDATED' THEN 4 ELSE 2 END,
  t.id, l.id, l.person, i.membership, s.start_ts, s.start_ts + make_interval(mins => s.minutes), 'Europe/Zurich',
  pg_temp.pick(CASE t.category
    WHEN 'A' THEN ARRAY['Place de l’école, Cernier','Piste d’exercice de Lignières','Gare de Neuchâtel','Parking du Mail, Neuchâtel','']
    WHEN 'BE' THEN ARRAY['Place de l’école, Cernier','Zone industrielle de Boudevilliers','Gare des Hauts-Geneveys','']
    ELSE ARRAY['Gare de Cernier','Collège de Fontainemelon','Place Pury, Neuchâtel','Gare de Neuchâtel','Parking du Mail, Neuchâtel',
      'Centre sportif de la Fontenelle, Cernier','Place du Port, Neuchâtel','Gare des Hauts-Geneveys','Piscine d’Engollon','Domicile de l’élève','',
      'Parking couvert du centre commercial de la Maladière, niveau −2, devant les caisses automatiques, côté stade'] END,
    'meeting/' || s.training || '/' || (s.k / 4)),
  s.status, s.price, 10, c.policy,
  jsonb_build_object('mode', 'UNIT_PRICE', 'serviceProductVersionId', c.product, 'quantity', s.minutes / 50, 'entitlementLotId', NULL, 'acceptedTermsVersionId', c.terms),
  CASE s.report WHEN 'SHARED' THEN 1 WHEN 'UPDATED' THEN 2 ELSE 0 END,
  CASE WHEN s.status = 'COMPLETED' THEN s.a_start END, CASE WHEN s.status = 'COMPLETED' THEN s.a_end END,
  CASE WHEN s.status = 'CANCELLED' THEN CASE WHEN pg_temp.h('cancel/' || s.n) % 20 < 10 THEN 'LEARNER_REQUEST'
    WHEN pg_temp.h('cancel/' || s.n) % 20 < 15 THEN 'INSTRUCTOR_UNAVAILABLE' WHEN pg_temp.h('cancel/' || s.n) % 20 < 17 THEN 'SCHOOL_CLOSURE' ELSE 'OTHER' END END,
  CASE WHEN s.status = 'CANCELLED' AND pg_temp.h('cancel/comment/' || s.n) % 10 >= 3 THEN CASE
    WHEN pg_temp.h('cancel/' || s.n) % 20 < 10 THEN pg_temp.pick(ARRAY['Élève malade.','Empêchement professionnel.','Examen scolaire le même jour.','Demande de report à la semaine suivante.'], 'cancel/text/' || s.n)
    WHEN pg_temp.h('cancel/' || s.n) % 20 < 15 THEN pg_temp.pick(ARRAY['Moniteur malade.','Véhicule immobilisé au garage.','Examen pratique d’un autre élève à accompagner.'], 'cancel/text/' || s.n)
    WHEN pg_temp.h('cancel/' || s.n) % 20 < 17 THEN pg_temp.pick(ARRAY['École fermée ce jour-là.','Route fermée pour travaux.'], 'cancel/text/' || s.n)
    ELSE pg_temp.pick(ARRAY['Conditions météo trop mauvaises.','Rendez-vous créé par erreur.','Neige sur la Vue-des-Alpes, leçon reportée.'], 'cancel/text/' || s.n) END END,
  least(now() - interval '1 minute', s.start_ts - make_interval(days => 3 + pg_temp.h('created/' || s.n) % 12, hours => pg_temp.h('created/' || s.n) % 7)),
  -- R07 : une leçon réalisée sans contrôle de permis approuvé et valide à sa date porte un motif d'anomalie.
  CASE WHEN s.status = 'COMPLETED' AND NOT coalesce((SELECT p.decision = 'APPROVED' AND p.category_code = t.category
      AND (p.valid_until IS NULL OR p.valid_until >= s.start_ts::date) FROM drivy.permit_check p WHERE p.training_id = t.id
      ORDER BY p.reviewed_at DESC, p.created_at DESC, p.id DESC LIMIT 1), false)
    THEN pg_temp.pick(ARRAY['Permis d’élève non présenté ; leçon donnée après vérification de l’identité.',
      'Contrôle du permis à refaire : validité non confirmée à la date de la leçon.','Permis d’élève pas encore contrôlé par l’école.'], 'anomaly/' || s.n) END,
  CASE WHEN s.status = 'NO_SHOW' THEN pg_temp.pick(ARRAY['Élève absent au rendez-vous, sans nouvelles.','Absence non excusée ; message laissé sur le répondeur.',
    'Élève en retard de plus de vingt minutes, leçon non donnée.','Rendez-vous oublié par l’élève.'], 'noshow/' || s.n) END,
  coalesce(s.report = 'PRIVATE', false), CASE WHEN s.report = 'PRIVATE' THEN 2 ELSE 1 END
FROM seed_lesson s JOIN seed_training t ON t.idx = s.training JOIN seed_learner l ON l.idx = t.learner_idx
JOIN seed_instr i ON i.idx = s.instr JOIN seed_cat c ON c.category = t.category;

-- Occupations : libérées pour une leçon réalisée ou annulée, conservées pour une absence constatée après coup.
INSERT INTO drivy.reservation(school_id, lesson_id, resource_id, resource_role, during, active)
SELECT pg_temp.ctx('school'), s.id, x.resource, x.role, tstzrange(s.start_ts, s.start_ts + make_interval(mins => s.minutes + x.extra), '[)'),
  s.status IN ('PLANNED', 'NO_SHOW')
FROM seed_lesson s JOIN seed_training t ON t.idx = s.training JOIN seed_learner l ON l.idx = t.learner_idx JOIN seed_instr i ON i.idx = s.instr
CROSS JOIN LATERAL (VALUES (l.person, 'LEARNER', 0), (i.person, 'INSTRUCTOR', 10)) AS x(resource, role, extra);

INSERT INTO drivy.lesson_commercial_revision(school_id, lesson_id, revision, operation_id, commercial_selection, price_cents, duration_minutes,
  actor_membership_id, reason, created_at)
SELECT l.school_id, l.id, 1, pg_temp.seed_uuid('lesson/operation/' || s.n), l.commercial_selection, l.price_cents_snapshot, s.minutes,
  l.instructor_membership_id, 'Initial booking', l.created_at
FROM seed_lesson s JOIN drivy.lesson l ON l.id = s.id;

-- Objectifs de leçon pour une bonne moitié des rendez-vous, et quelques notes administratives gardées par le moniteur.
UPDATE drivy.lesson_preparation p SET version = 2,
  goals = (SELECT coalesce(jsonb_agg(jsonb_build_object('label', pg_temp.pick(ARRAY['Consolider : ','Revoir : ','Découvrir : ','Gagner en autonomie : '],
        'goal/' || s.n || '/' || d.sort_order) || d.label, 'competencyId', d.id) ORDER BY d.sort_order), '[]'::jsonb)
    FROM drivy.competency_definition d WHERE d.curriculum_version_id = c.curriculum
      AND d.sort_order IN (SELECT (s.k + j * 2) % c.ncomp FROM generate_series(0, pg_temp.h('goal/count/' || s.n) % 3) AS j)),
  administrative_check_note = CASE WHEN pg_temp.h('note/' || s.n) % 100 < 12 THEN pg_temp.pick(ARRAY['Vérifier le permis d’élève avant le départ.',
    'Rappeler le solde à régler.','Parent présent au début de la leçon.','Lunettes obligatoires : vérifier avant de partir.'], 'note/text/' || s.n) END
FROM seed_lesson s JOIN seed_training t ON t.idx = s.training JOIN seed_cat c ON c.category = t.category
WHERE p.lesson_id = s.id AND pg_temp.h('preparation/' || s.n) % 100 < 55;

-- Comptes : une charge initiale pour une leçon réalisée, un compte sans charge pour une annulation ou une absence.
INSERT INTO drivy.lesson_account(id, school_id, lesson_id, planned_price_cents)
SELECT pg_temp.seed_uuid('account/' || s.n), pg_temp.ctx('school'), s.id, s.price FROM seed_lesson s WHERE s.status <> 'PLANNED';
INSERT INTO drivy.charge_entry(school_id, account_id, kind, amount_signed_cents, reason, operation_id, created_at)
SELECT pg_temp.ctx('school'), pg_temp.seed_uuid('account/' || s.n), 'INITIAL', s.price, 'Prix unitaire convenu à la réservation ; leçon réalisée.',
  pg_temp.seed_uuid('complete/operation/' || s.n), s.a_end FROM seed_lesson s WHERE s.status = 'COMPLETED';

-- 4. Appréciations par compétence : le niveau monte au fil des leçons d'une même formation.
CREATE TEMP TABLE seed_assess(n int NOT NULL, comp uuid NOT NULL, sort_order int NOT NULL, label text NOT NULL, comp_version int NOT NULL,
  curriculum uuid NOT NULL, level text NOT NULL, context text NOT NULL, PRIMARY KEY(n, comp)) ON COMMIT DROP;
INSERT INTO seed_assess
WITH done AS (
  SELECT s.n, s.training, s.start_ts, row_number() OVER (PARTITION BY s.training ORDER BY s.start_ts) - 1 AS q
  FROM seed_lesson s WHERE s.status = 'COMPLETED' AND s.report <> 'EMPTY'
), picked AS (
  SELECT d.n, d.training, d.start_ts, cd.id AS comp, cd.sort_order, cd.label, cd.version AS comp_version, cd.curriculum_version_id AS curriculum
  FROM done d JOIN seed_training t ON t.idx = d.training JOIN seed_cat c ON c.category = t.category
  CROSS JOIN LATERAL generate_series(0, pg_temp.h('assess/count/' || d.n) % 4) AS j
  JOIN drivy.competency_definition cd ON cd.curriculum_version_id = c.curriculum AND cd.sort_order = ((d.q / 2) + j * 2) % c.ncomp
), ranked AS (
  SELECT p.*, row_number() OVER (PARTITION BY p.training, p.comp ORDER BY p.start_ts)
    - CASE WHEN pg_temp.h('assess/regress/' || p.n || '/' || p.sort_order) % 9 = 0 THEN 1 ELSE 0 END AS seen FROM picked p
)
SELECT r.n, r.comp, r.sort_order, r.label, r.comp_version, r.curriculum,
  CASE WHEN r.seen <= 1 THEN 'DISCOVERING' WHEN r.seen <= 3 THEN 'GUIDED' ELSE 'INDEPENDENT' END,
  CASE WHEN r.seen <= 1 THEN pg_temp.pick(ARRAY['Première approche, beaucoup de consignes nécessaires.','Découverte : gestes encore hésitants.',
      'À reprendre pas à pas à la prochaine leçon.','Notions posées, exécution encore guidée de bout en bout.'], 'assess/text/' || r.n || '/' || r.sort_order)
    WHEN r.seen <= 3 THEN pg_temp.pick(ARRAY['Réussi avec un rappel.','Correct quand la consigne est donnée à l’avance.',
      'En progrès, encore un oubli sous pression.','Bien dans le calme, à confirmer dans le trafic.'], 'assess/text/' || r.n || '/' || r.sort_order)
    ELSE pg_temp.pick(ARRAY['Réalisé seul, sans intervention.','Acquis et régulier sur toute la leçon.',
      'Autonome, y compris dans le trafic dense.','Maîtrisé : à entretenir.'], 'assess/text/' || r.n || '/' || r.sort_order) END
FROM ranked r;

CREATE TEMP TABLE seed_report(n int PRIMARY KEY, worked text NOT NULL, observation text NOT NULL, next_step text NOT NULL,
  items jsonb NOT NULL, snapshot jsonb NOT NULL) ON COMMIT DROP;
INSERT INTO seed_report
SELECT s.n,
  pg_temp.pick(CASE t.category
    WHEN 'A' THEN ARRAY['Piste d’exercice : slalom lent et freinages.','Route de la Tourne : enchaînement de virages.',
      'Traversée de Neuchâtel aux heures de pointe.','Boucle du Val-de-Ruz par Engollon et Savagnier.','Col de la Vue-des-Alpes, montée et descente.',
      'Exercices de demi-tour et d’évitement sur parking.']
    WHEN 'BE' THEN ARRAY['Attelage et contrôles sur la place de l’école.','Marche arrière en ligne droite, zone industrielle de Boudevilliers.',
      'Trajet avec remorque chargée vers La Chaux-de-Fonds.','Mise à quai et créneau avec l’ensemble.','H20 avec remorque : insertion et vent latéral.',
      'Giratoires serrés du Val-de-Ruz avec l’ensemble.']
    ELSE ARRAY['Circulation dans le Val-de-Ruz : Cernier, Fontaines et Chézard.','Trajet Cernier – Neuchâtel par la Vue-des-Alpes.',
      'Circulation urbaine à Neuchâtel, autour de la Place Pury.','Giratoires de Malvilliers et traversée de Boudevilliers.',
      'Parking du Mail : stationnements en épi et en bataille.','Boucle Fontainemelon – Dombresson – Savagnier.',
      'Insertion sur la H20 et sortie à Vauseyon.','Zone 30 et rues étroites du centre de Neuchâtel.',
      'Montée de la Vue-des-Alpes et retour par le tunnel.','Route cantonale vers La Chaux-de-Fonds, dépassements de véhicules lents.'] END, 'worked/' || s.n)
    || CASE WHEN a.labels IS NULL THEN '' ELSE ' Thèmes : ' || a.labels || '.' END,
  CASE WHEN pg_temp.h('observation/length/' || s.n) % 25 = 0 THEN (SELECT string_agg(pg_temp.pick(o.bank, 'observation/long/' || s.n || '/' || g), ' ')
      FROM generate_series(1, 9) AS g)
    WHEN pg_temp.h('observation/length/' || s.n) % 25 < 4 THEN pg_temp.pick(ARRAY['RAS.','Bonne leçon.','Leçon conforme au programme.'], 'observation/short/' || s.n)
    ELSE pg_temp.pick(o.bank, 'observation/' || s.n) || CASE WHEN pg_temp.h('observation/second/' || s.n) % 3 = 0
      THEN ' ' || pg_temp.pick(o.bank, 'observation/second/text/' || s.n) ELSE '' END END,
  CASE WHEN a.first_label IS NULL OR pg_temp.h('next/' || s.n) % 8 = 0 THEN ''
    ELSE pg_temp.pick(ARRAY['À reprendre : ','À consolider : ','Prochaine étape : ','Priorité de la prochaine leçon : '], 'next/' || s.n) || a.first_label || '.' END,
  coalesce(a.items, '[]'::jsonb), coalesce(a.snapshot, '[]'::jsonb)
FROM seed_lesson s JOIN seed_training t ON t.idx = s.training
CROSS JOIN (SELECT ARRAY['Bonne écoute des consignes, progression régulière.','Leçon appliquée ; la fatigue se fait sentir en fin de parcours.',
  'Beaucoup de progrès depuis la dernière fois.','Encore tendu au départ, plus à l’aise après dix minutes.',
  'Le regard porte plus loin, les décisions arrivent plus tôt.','Quelques hésitations dans le trafic dense, sans mise en danger.',
  'Les contrôles restent à automatiser avant chaque changement de direction.','Très bonne leçon, conduite fluide et anticipée.',
  'Gestion de la vitesse correcte, mais approche des intersections trop rapide.','Bonne maîtrise technique ; la lecture de la signalisation reste à travailler.',
  'Leçon difficile : plusieurs interventions nécessaires.','Conduite sûre et régulière ; prêt pour des parcours plus longs.',
  'Attention à la position des mains et au regard dans les virages.','À l’aise sur route, moins en ville.',
  'Trop de précipitation dans les manœuvres.','Bon dialogue pendant le bilan, les points à revoir sont compris.'] AS bank) o
LEFT JOIN LATERAL (
  SELECT string_agg(x.label, ', ' ORDER BY x.sort_order) AS labels, (array_agg(x.label ORDER BY x.level, x.sort_order))[1] AS first_label,
    jsonb_agg(jsonb_build_object('competencyId', x.comp, 'level', x.level, 'context', x.context) ORDER BY x.sort_order) AS items,
    jsonb_agg(jsonb_build_object('id', x.comp, 'label', x.label, 'version', x.comp_version, 'curriculumVersionId', x.curriculum) ORDER BY x.comp) AS snapshot
  FROM seed_assess x WHERE x.n = s.n
) a ON true
WHERE s.status = 'COMPLETED' AND s.report <> 'EMPTY';

INSERT INTO drivy.report_draft(id, school_id, lesson_id, author_membership_id, version, base_publication_version, worked_on, observation_text,
  next_step, observations, created_at)
SELECT pg_temp.seed_uuid('draft/' || s.n), pg_temp.ctx('school'), s.id, i.membership,
  CASE s.report WHEN 'EMPTY' THEN 1 WHEN 'PRIVATE' THEN 2 WHEN 'SHARED' THEN 3 ELSE 4 END,
  CASE s.report WHEN 'SHARED' THEN 1 WHEN 'UPDATED' THEN 2 ELSE 0 END,
  coalesce(r.worked, ''), coalesce(r.observation, ''), coalesce(r.next_step, ''), coalesce(r.items, '[]'::jsonb), s.a_end
FROM seed_lesson s JOIN seed_instr i ON i.idx = s.instr LEFT JOIN seed_report r ON r.n = s.n WHERE s.status = 'COMPLETED';

-- Révisions lues par l'élève. Un bilan repris garde sa première version, sans appréciation par compétence.
INSERT INTO drivy.report_revision(id, school_id, lesson_id, author_membership_id, sequence, published_at, worked_on, observation_text, next_step,
  observations, competency_snapshot, correction_reason, operation_id)
SELECT pg_temp.seed_uuid('revision/' || s.n || '/1'), pg_temp.ctx('school'), s.id, i.membership, 1,
  least(now(), s.a_end + make_interval(mins => CASE WHEN s.report = 'UPDATED' THEN 2 ELSE 10 + pg_temp.h('published/' || s.n) % 170 END)),
  r.worked, r.observation, CASE WHEN s.report = 'UPDATED' THEN '' ELSE r.next_step END,
  CASE WHEN s.report = 'UPDATED' THEN '[]'::jsonb ELSE r.items END, CASE WHEN s.report = 'UPDATED' THEN '[]'::jsonb ELSE r.snapshot END,
  NULL, pg_temp.seed_uuid('complete/operation/' || s.n)
FROM seed_lesson s JOIN seed_instr i ON i.idx = s.instr JOIN seed_report r ON r.n = s.n WHERE s.report IN ('SHARED', 'UPDATED');
INSERT INTO drivy.report_revision(id, school_id, lesson_id, author_membership_id, sequence, published_at, worked_on, observation_text, next_step,
  observations, competency_snapshot, correction_reason, operation_id)
SELECT pg_temp.seed_uuid('revision/' || s.n || '/2'), pg_temp.ctx('school'), s.id, i.membership, 2,
  least(now(), s.a_end + make_interval(mins => 60 + pg_temp.h('published/' || s.n) % 2800)),
  r.worked, r.observation, r.next_step, r.items, r.snapshot, 'Bilan mis à jour par le moniteur.', pg_temp.seed_uuid('save/operation/' || s.n)
FROM seed_lesson s JOIN seed_instr i ON i.idx = s.instr JOIN seed_report r ON r.n = s.n WHERE s.report = 'UPDATED';
UPDATE drivy.lesson l SET current_published_revision_id = pg_temp.seed_uuid('revision/' || s.n || '/' || CASE WHEN s.report = 'UPDATED' THEN 2 ELSE 1 END)
FROM seed_lesson s WHERE l.id = s.id AND s.report IN ('SHARED', 'UPDATED');

-- Observations notées pendant la leçon, sans position : appréciations rapides et simples repères, certains gardés privés.
INSERT INTO drivy.geo_observation(id, school_id, version, lesson_id, training_id, author_membership_id, draft_id, competency_id, text, origin,
  observed_at, event_kind, event_status, created_at, private)
SELECT pg_temp.seed_uuid('observation/' || s.n || '/' || j), pg_temp.ctx('school'), 2, s.id, t.id, i.membership, pg_temp.seed_uuid('draft/' || s.n),
  CASE WHEN x.marker THEN NULL ELSE d.id END,
  CASE WHEN x.marker THEN pg_temp.pick(ARRAY['Revoir ce carrefour ensemble au bilan.','Endroit à refaire à la prochaine leçon.','Bon exemple à réutiliser.',
      'Question de l’élève sur la signalisation : y revenir.','Travaux sur le parcours : prévoir un autre itinéraire.','Point à montrer sur la carte.'], 'observation/text/' || s.n || '/' || j)
    WHEN x.status = 'ATTENTION' THEN pg_temp.pick(ARRAY['Angle mort non contrôlé avant de déboîter.','Priorité de droite vue tardivement.',
      'Piéton engagé remarqué au dernier moment.','Clignotant oublié en sortie de giratoire.','Distance de sécurité trop courte derrière le bus.',
      'Regard trop près du capot en entrée de virage.','Arrêt au stop non marqué complètement.','Rétroviseur oublié avant le freinage.'], 'observation/text/' || s.n || '/' || j)
    WHEN x.status = 'TO_REWORK' THEN pg_temp.pick(ARRAY['Approche trop rapide du giratoire.','Calage au démarrage en côte.',
      'Trajectoire trop large en sortie de virage.','Créneau à reprendre : repères arrière mal utilisés.','Changement de voie sans marge suffisante.',
      'Vitesse inadaptée en zone 30.','Rétrogradage tardif avant le carrefour.','Placement trop à gauche sur la chaussée étroite.'], 'observation/text/' || s.n || '/' || j)
    ELSE pg_temp.pick(ARRAY['Giratoire parfaitement négocié.','Très bonne anticipation du cycliste.','Insertion fluide et à la bonne vitesse.',
      'Contrôles complets avant le dépassement.','Arrêt en douceur, à la bonne distance.','Stationnement réussi du premier coup.',
      'Céder le passage bien préparé.','Allure adaptée à la visibilité réduite.'], 'observation/text/' || s.n || '/' || j) END,
  'LIVE', s.a_start + make_interval(mins => j * s.minutes / 7 + 2), CASE WHEN x.marker THEN 'MARKER' ELSE 'QUALIFIED' END,
  CASE WHEN x.marker THEN NULL ELSE x.status END, s.a_start + make_interval(mins => j * s.minutes / 7 + 2),
  CASE WHEN x.marker THEN pg_temp.h('observation/private/' || s.n || '/' || j) % 2 = 0 ELSE pg_temp.h('observation/private/' || s.n || '/' || j) % 12 = 0 END
FROM seed_lesson s JOIN seed_training t ON t.idx = s.training JOIN seed_instr i ON i.idx = s.instr JOIN seed_cat c ON c.category = t.category
CROSS JOIN LATERAL generate_series(1, pg_temp.h('observation/count/' || s.n) % 6) AS j
CROSS JOIN LATERAL (SELECT pg_temp.h('observation/kind/' || s.n || '/' || j) % 5 = 0 AS marker,
  CASE WHEN pg_temp.h('observation/status/' || s.n || '/' || j) % 100 < 35 THEN 'ATTENTION'
    WHEN pg_temp.h('observation/status/' || s.n || '/' || j) % 100 < 60 THEN 'TO_REWORK' ELSE 'POSITIVE' END AS status) x
JOIN drivy.competency_definition d ON d.curriculum_version_id = c.curriculum AND d.sort_order = pg_temp.h('observation/competency/' || s.n || '/' || j) % c.ncomp
WHERE s.status = 'COMPLETED';

-- 5. Trace opérateur sans donnée personnelle, puis contrôles avant validation.
DO $finish$
DECLARE
  v_school constant uuid := pg_temp.ctx('school'); v_table text; v_changed bigint; v_lessons bigint;
BEGIN
  SELECT count(*) INTO v_lessons FROM seed_lesson;
  INSERT INTO drivy.operation(actor_person_id, operation_id, school_id, command_type, payload_hash, resource_id, response_data)
  VALUES (pg_temp.ctx('lucPerson'), pg_temp.ctx('operation'), v_school, 'PROVISION_EXAMPLE_DATA',
    encode(sha256(convert_to('volume-20261004', 'UTF8')), 'hex'), v_school,
    jsonb_build_object('schoolId', v_school, 'synthetic', true, 'batch', 'volume-20261004', 'learners', 80, 'instructors', 5, 'trainings', 102, 'lessons', v_lessons));
  INSERT INTO drivy.audit_event(id, school_id, actor_person_id, actor_membership_id, operation_id, action, resource_type, resource_id, changed_fields)
  VALUES (pg_temp.seed_uuid('audit'), v_school, pg_temp.ctx('lucPerson'), pg_temp.ctx('luc'), pg_temp.ctx('operation'),
    'OperatorProvisionedFictionalExamples', 'School', v_school,
    ARRAY['exampleLearners','exampleInstructors','exampleCatalogue','exampleLessons','exampleReports','exampleObservations','examplePermitChecks']);

  IF v_lessons NOT BETWEEN 900 AND 1700 THEN RAISE EXCEPTION 'volume seed: unexpected lesson count %', v_lessons; END IF;
  IF (SELECT count(*) FROM drivy.lesson l JOIN seed_lesson s ON s.id = l.id) <> v_lessons THEN RAISE EXCEPTION 'volume seed: lessons missing'; END IF;
  IF (SELECT count(*) FROM drivy.reservation r JOIN seed_lesson s ON s.id = r.lesson_id) <> 2 * v_lessons THEN RAISE EXCEPTION 'volume seed: two occupations per lesson expected'; END IF;
  IF (SELECT count(*) FROM drivy.lesson_preparation p JOIN seed_lesson s ON s.id = p.lesson_id) <> v_lessons THEN RAISE EXCEPTION 'volume seed: one preparation per lesson expected'; END IF;
  -- Aucune leçon du lot ne recouvre une autre leçon de la même personne, existante ou non.
  IF EXISTS (SELECT 1 FROM drivy.lesson a JOIN seed_lesson s ON s.id = a.id JOIN drivy.lesson b ON b.school_id = a.school_id AND b.id <> a.id
      AND (b.learner_person_id = a.learner_person_id OR b.instructor_membership_id = a.instructor_membership_id)
      AND tstzrange(a.planned_start, a.planned_end, '[)') && tstzrange(b.planned_start, b.planned_end, '[)')) THEN
    RAISE EXCEPTION 'volume seed: overlapping lessons';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_lesson s WHERE s.status = 'COMPLETED' AND (
      NOT EXISTS (SELECT 1 FROM drivy.report_draft d WHERE d.lesson_id = s.id)
      OR (SELECT count(*) FROM drivy.charge_entry c JOIN drivy.lesson_account a ON a.id = c.account_id WHERE a.lesson_id = s.id AND c.kind = 'INITIAL' AND c.amount_signed_cents = s.price) <> 1
      OR s.a_end > now())) THEN
    RAISE EXCEPTION 'volume seed: completed lesson without draft, charge or with a future end';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_lesson s JOIN drivy.lesson l ON l.id = s.id WHERE s.status IN ('CANCELLED', 'NO_SHOW') AND (
      NOT EXISTS (SELECT 1 FROM drivy.lesson_account a WHERE a.lesson_id = s.id)
      OR EXISTS (SELECT 1 FROM drivy.charge_entry c JOIN drivy.lesson_account a ON a.id = c.account_id WHERE a.lesson_id = s.id))) THEN
    RAISE EXCEPTION 'volume seed: closed lesson must own an account without charge';
  END IF;
  -- Partage : une révision courante exactement pour un bilan partagé, aucune pour un bilan privé ou vide.
  IF EXISTS (SELECT 1 FROM seed_lesson s JOIN drivy.lesson l ON l.id = s.id LEFT JOIN drivy.report_revision r ON r.id = l.current_published_revision_id
      WHERE coalesce(s.report IN ('SHARED', 'UPDATED'), false) <> (r.id IS NOT NULL)
        OR (r.id IS NOT NULL AND (r.lesson_id <> l.id OR r.sequence <> l.publication_version))
        OR (l.report_private AND l.current_published_revision_id IS NOT NULL)) THEN
    RAISE EXCEPTION 'volume seed: inconsistent shared report pointer';
  END IF;
  IF EXISTS (SELECT 1 FROM seed_lesson s JOIN drivy.lesson l ON l.id = s.id WHERE l.status = 'PLANNED' AND l.planned_start > now()
      AND (SELECT count(*) FROM drivy.reservation r WHERE r.lesson_id = l.id AND r.active) <> 2) THEN
    RAISE EXCEPTION 'volume seed: upcoming lesson without its two active occupations';
  END IF;
  IF (SELECT count(*) FROM drivy.capture_session) <> (SELECT count(*) FROM seed_before WHERE tbl = 'capture_session')
     OR EXISTS (SELECT 1 FROM drivy.geo_observation o JOIN seed_lesson s ON s.id = o.lesson_id WHERE o.capture_id IS NOT NULL) THEN
    RAISE EXCEPTION 'volume seed: no capture or position may be created';
  END IF;
  -- Hors lot : chaque ligne existante est restée identique, sauf le dossier complété de l'élève d'essai.
  FOREACH v_table IN ARRAY ARRAY(SELECT DISTINCT tbl FROM seed_before) LOOP
    EXECUTE format('SELECT count(*) FROM seed_before b LEFT JOIN drivy.%I x ON x.id = b.id WHERE b.tbl = %L AND (x.id IS NULL OR md5(x::text) <> b.sig) AND NOT (b.tbl = %L AND b.id = $1)',
      v_table, v_table, 'learner_profile') INTO v_changed USING pg_temp.ctx('lea');
    IF v_changed <> 0 THEN RAISE EXCEPTION 'volume seed: % pre-existing rows changed in %', v_changed, v_table; END IF;
  END LOOP;
END $finish$;

SELECT 'lessons ' || json_object_agg(x.status, x.n)::text FROM (SELECT status, count(*) AS n FROM seed_lesson GROUP BY status) x;
SELECT 'reports ' || json_object_agg(x.report, x.n)::text FROM (SELECT report, count(*) AS n FROM seed_lesson WHERE report IS NOT NULL GROUP BY report) x;
SELECT 'instructors ' || json_object_agg(x.name, x.n)::text FROM (SELECT p.display_name AS name, count(*) AS n FROM seed_lesson s
  JOIN seed_instr i ON i.idx = s.instr JOIN drivy.person p ON p.id = i.person GROUP BY p.display_name) x;
SELECT 'window ' || json_build_object('first', min(start_ts), 'last', max(start_ts), 'today', count(*) FILTER (WHERE start_ts::date = current_date),
  'future', count(*) FILTER (WHERE start_ts > now()))::text FROM seed_lesson;
SELECT 'trialLearner ' || json_object_agg(x.category, x.n)::text FROM (SELECT t.category, count(*) AS n FROM seed_lesson s
  JOIN seed_training t ON t.idx = s.training WHERE t.learner_idx = 0 GROUP BY t.category) x;
SELECT 'totals ' || json_build_object('learners', (SELECT count(*) FROM drivy.learner_profile), 'trainings', (SELECT count(*) FROM drivy.training),
  'lessons', (SELECT count(*) FROM drivy.lesson), 'revisions', (SELECT count(*) FROM drivy.report_revision),
  'observations', (SELECT count(*) FROM drivy.geo_observation), 'permitChecks', (SELECT count(*) FROM drivy.permit_check),
  'progressRows', (SELECT count(*) FROM drivy.training_progress))::text;

\if :{?dry_run}
ROLLBACK;
\echo 'volume seed: dry run, transaction rolled back'
\else
COMMIT;
\echo 'volume seed: committed'
\endif
