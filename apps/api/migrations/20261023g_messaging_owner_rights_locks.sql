-- #78/#84 : FORCE RLS soumet aussi le propriétaire non privilégié aux politiques.
-- SELECT ... FOR SHARE exige une politique UPDATE USING, même sans mutation.
-- Le propriétaire peut déjà lire ces tables pour les fonctions de droits. Autoriser
-- seulement leurs verrous : WITH CHECK(false) n'autorise aucune nouvelle écriture.
-- Aucun droit supplémentaire n'est attribué à drivy_app, aucune RLS n'est désactivée.
DO $$ DECLARE table_name text; BEGIN
 FOREACH table_name IN ARRAY ARRAY['school','person','membership','learner_profile','training','instructor_assignment','messaging_admin_contact'] LOOP
  EXECUTE format('CREATE POLICY messaging_owner_rights_lock ON drivy.%I FOR UPDATE TO %I USING(true) WITH CHECK(false)',table_name,current_user);
 END LOOP;
END $$;
