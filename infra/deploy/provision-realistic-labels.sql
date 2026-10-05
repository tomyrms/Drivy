-- Lot « libellés réalistes » du 5 octobre 2026, à la demande du porteur.
-- Les données fictives de l'école ne doivent plus se présenter comme telles à l'écran :
-- le suffixe « · exemple » quitte les noms, les fermetures et les conditions générales,
-- et les rues inventées (« Rue de l'Exemple », « Rue du Jeu-de-Test »…) deviennent des rues de la région.
--
-- Ne touche que des libellés. Aucune ligne créée ou supprimée, aucun identifiant, droit, statut,
-- date ou version modifié. E-mails et téléphones restent sur des plages non attribuées
-- (example.invalid, +41 000…) : l'app propose d'appeler et d'écrire, et une adresse ou un numéro
-- vraisemblable pourrait appartenir à quelqu'un.
--
-- Une transaction ; refuse une seconde exécution ; `-v dry_run=1` annule à la fin.
-- Répéter d'abord sur une copie restaurée, puis sauvegarder la base avant l'application.

\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE TEMP TABLE label_counts(step text PRIMARY KEY, changed bigint NOT NULL) ON COMMIT DROP;

DO $$
DECLARE
  v_persons bigint; v_learners bigint; v_addresses bigint; v_closures bigint; v_terms bigint;
  v_before_persons bigint; v_before_learners bigint; v_before_lessons bigint;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM drivy.person WHERE display_name LIKE '% · exemple') THEN
    RAISE EXCEPTION 'realistic labels: nothing to rename, the lot was already applied';
  END IF;
  SELECT count(*) INTO v_before_persons FROM drivy.person;
  SELECT count(*) INTO v_before_learners FROM drivy.learner_profile;
  SELECT count(*) INTO v_before_lessons FROM drivy.lesson;

  -- Le nom du dossier et celui de la personne restent identiques, comme avant le lot.
  UPDATE drivy.person SET display_name = left(display_name, length(display_name) - length(' · exemple'))
    WHERE display_name LIKE '% · exemple';
  GET DIAGNOSTICS v_persons = ROW_COUNT;
  UPDATE drivy.learner_profile SET display_name = left(display_name, length(display_name) - length(' · exemple'))
    WHERE display_name LIKE '% · exemple';
  GET DIAGNOSTICS v_learners = ROW_COUNT;

  UPDATE drivy.learner_profile l SET postal_address = jsonb_set(l.postal_address, '{line1}', to_jsonb(s.real_name || substr(l.postal_address->>'line1', length(s.seed_name) + 1)))
    FROM (VALUES
      ('Rue de l’Exemple', 'Rue des Parcs'),
      ('Chemin des Essais', 'Chemin des Carrels'),
      ('Avenue de la Recette', 'Avenue de la Gare'),
      ('Rue du Jeu-de-Test', 'Rue du Seyon'),
      ('Chemin du Modèle', 'Chemin des Mulets'),
      ('Rue Fictive', 'Rue de l’Écluse')) AS s(seed_name, real_name)
    WHERE l.postal_address->>'line1' LIKE s.seed_name || ' %';
  GET DIAGNOSTICS v_addresses = ROW_COUNT;

  UPDATE drivy.closure SET reason = left(reason, length(reason) - length(' · exemple')) WHERE reason LIKE '% · exemple';
  GET DIAGNOSTICS v_closures = ROW_COUNT;
  UPDATE drivy.commercial_terms_version SET label = left(label, length(label) - length(' · exemple')) WHERE label LIKE '% · exemple';
  GET DIAGNOSTICS v_terms = ROW_COUNT;

  IF EXISTS (SELECT 1 FROM drivy.person WHERE display_name ~* 'exemple' OR btrim(display_name) = '')
     OR EXISTS (SELECT 1 FROM drivy.learner_profile WHERE display_name ~* 'exemple' OR btrim(display_name) = '') THEN
    RAISE EXCEPTION 'realistic labels: a name still carries the example mark or became empty';
  END IF;
  IF EXISTS (SELECT 1 FROM drivy.learner_profile l JOIN drivy.person p ON p.id = l.person_id WHERE p.display_name <> l.display_name) THEN
    RAISE EXCEPTION 'realistic labels: dossier and person names diverge';
  END IF;
  IF EXISTS (SELECT 1 FROM drivy.learner_profile l WHERE l.display_name <> l.first_name || ' ' || l.last_name) THEN
    RAISE EXCEPTION 'realistic labels: a dossier name no longer matches its first and last names';
  END IF;
  IF EXISTS (SELECT 1 FROM drivy.learner_profile
      WHERE postal_address->>'line1' ~* 'exemple|essais|recette|jeu-de-test|modèle|fictive') THEN
    RAISE EXCEPTION 'realistic labels: an invented street name remains';
  END IF;
  IF (SELECT count(*) FROM drivy.person) <> v_before_persons OR (SELECT count(*) FROM drivy.learner_profile) <> v_before_learners
     OR (SELECT count(*) FROM drivy.lesson) <> v_before_lessons THEN
    RAISE EXCEPTION 'realistic labels: row counts changed';
  END IF;

  INSERT INTO label_counts VALUES ('persons', v_persons), ('learners', v_learners), ('addresses', v_addresses),
    ('closures', v_closures), ('terms', v_terms);
END $$;

SELECT step || '=' || changed FROM label_counts ORDER BY step;

\if :{?dry_run}
ROLLBACK;
\echo dry run: rolled back
\else
COMMIT;
\echo committed
\endif
