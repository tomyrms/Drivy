-- Retrait d'accès, cycle de vie des formations, dossiers archivés, module GPS et affectation du moniteur créateur.
-- Extensions hors canon OpenAPI 3.11.0 (docs/implementation/corrections-api-2026-09-29.md). Aucune donnée n'est réécrite.

-- Membre : un ADMIN passe une appartenance ACTIVE à REVOKED. Le retour à ACTIVE reste réservé à l'acceptation d'une invitation.
-- (catalogue_member_update, migration 005, impose status='ACTIVE' après écriture : il ne permet donc jamais ce passage.)
CREATE POLICY member_deactivate ON drivy.membership FOR UPDATE TO drivy_app
  USING(drivy.is_current_school_admin(school_id) AND status='ACTIVE')
  WITH CHECK(drivy.is_current_school_admin(school_id) AND status='REVOKED'
    AND school_id=nullif(current_setting('app.school_id',true),'')::uuid);

-- Affectation : un ADMIN termine une affectation (valid_until) ; aucune autre colonne n'est modifiable.
-- Une affectation future annulée a un intervalle vide : elle ne doit jamais redonner accès, même pendant une seconde.
ALTER TABLE drivy.instructor_assignment DROP CONSTRAINT instructor_assignment_check;
ALTER TABLE drivy.instructor_assignment ADD CONSTRAINT instructor_assignment_check CHECK(valid_until IS NULL OR valid_until>=valid_from);
GRANT UPDATE(valid_until,version) ON drivy.instructor_assignment TO drivy_app;
CREATE POLICY assignment_admin_end ON drivy.instructor_assignment FOR UPDATE TO drivy_app
  USING(drivy.is_current_school_admin(school_id)) WITH CHECK(drivy.is_current_school_admin(school_id));

-- Affectation automatique du moniteur qui crée une formation : uniquement lui-même, uniquement tant que la formation n'a
-- aucune affectation. La sous-requête vit dans une fonction SECURITY DEFINER pour ne pas réentrer dans les politiques.
CREATE FUNCTION drivy.instructor_self_assignable(school uuid,training uuid,instructor uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT drivy.current_school_member(school)
    AND instructor=nullif(current_setting('app.membership_id',true),'')::uuid
    AND EXISTS(SELECT 1 FROM drivy.membership m WHERE m.id=instructor AND m.school_id=school
      AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles))
    AND EXISTS(SELECT 1 FROM drivy.training t WHERE t.id=training AND t.school_id=school)
    AND NOT EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=school AND a.training_id=training)
$$;
REVOKE ALL ON FUNCTION drivy.instructor_self_assignable(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.instructor_self_assignable(uuid,uuid,uuid) TO drivy_app;
CREATE POLICY assignment_creator_insert ON drivy.instructor_assignment FOR INSERT TO drivy_app
  WITH CHECK(valid_until IS NULL AND drivy.instructor_self_assignable(school_id,training_id,instructor_membership_id));

-- Formation : statut et date de clôture, réservés à l'ADMIN. Le déclencheur protège aussi contre la politique
-- permit_training_version (010), qui ouvre la mise à jour de la formation à d'autres rôles pour sa seule version.
GRANT UPDATE(status,closed_on,version) ON drivy.training TO drivy_app;
CREATE POLICY training_admin_update ON drivy.training FOR UPDATE TO drivy_app
  USING(drivy.is_current_school_admin(school_id)) WITH CHECK(drivy.is_current_school_admin(school_id));
CREATE FUNCTION drivy.guard_training_lifecycle() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF current_user='drivy_app' AND (NEW.status IS DISTINCT FROM OLD.status OR NEW.closed_on IS DISTINCT FROM OLD.closed_on)
    AND NOT drivy.is_current_school_admin(NEW.school_id) THEN
    RAISE EXCEPTION 'training_lifecycle_admin_only' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER training_lifecycle_admin_only BEFORE UPDATE ON drivy.training
  FOR EACH ROW EXECUTE FUNCTION drivy.guard_training_lifecycle();

-- Dossier élève : archivage par l'ADMIN. La lecture reste ouverte (profile_read_scope) : l'historique demeure lisible.
GRANT UPDATE(archived_at) ON drivy.learner_profile TO drivy_app;
CREATE POLICY learner_admin_archive ON drivy.learner_profile FOR UPDATE TO drivy_app
  USING(drivy.is_current_school_admin(school_id) AND archived_at IS NULL)
  WITH CHECK(drivy.is_current_school_admin(school_id) AND archived_at IS NOT NULL);
CREATE POLICY learner_admin_restore ON drivy.learner_profile FOR UPDATE TO drivy_app
  USING(drivy.is_current_school_admin(school_id) AND archived_at IS NOT NULL)
  WITH CHECK(drivy.is_current_school_admin(school_id) AND archived_at IS NULL);
CREATE FUNCTION drivy.guard_learner_archive() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF current_user='drivy_app' AND NEW.archived_at IS DISTINCT FROM OLD.archived_at AND NOT drivy.is_current_school_admin(NEW.school_id) THEN
    RAISE EXCEPTION 'learner_archive_admin_only' USING ERRCODE='42501';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER learner_archive_admin_only BEFORE UPDATE ON drivy.learner_profile
  FOR EACH ROW EXECUTE FUNCTION drivy.guard_learner_archive();

-- Modules de l'école : seul l'ADMIN modifie le JSON (la politique school_admin_update, 002, borne déjà la ligne).
GRANT UPDATE(modules) ON drivy.school TO drivy_app;
