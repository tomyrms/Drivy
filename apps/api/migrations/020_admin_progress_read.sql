-- Progression de la formation lisible par l'administration de l'école (essai terrain du 30 septembre 2026).
-- Le rôle ADMIN seul n'ouvrait ni la progression ni les bilans (007). Le porteur, administrateur et moniteur de son école,
-- n'avait donc accès au contenu que pour les élèves de ses affectations. Un administrateur actif relit maintenant, en lecture
-- seule, la progression de toutes les formations de son école. Cette progression ne contient que les niveaux issus des bilans
-- partagés (révision courante d'une leçon dont le bilan n'est pas privé) ; les bilans, brouillons et révisions restent inchangés.
CREATE FUNCTION drivy.progress_training_access(training uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.report_training_access(training,false) OR EXISTS(SELECT 1 FROM drivy.training t
  JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  WHERE t.id=training AND t.school_id=nullif(current_setting('app.school_id',true),'')::uuid
  AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
$$;
-- La vue est en security_invoker : les politiques des bilans empêcheraient l'administrateur de la lire. La fonction porte donc
-- elle-même la vérification de droit et ne rend que les lignes de la formation demandée.
CREATE FUNCTION drivy.training_progress_read(training uuid) RETURNS SETOF drivy.training_progress
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.* FROM drivy.training_progress p WHERE p.training_id=training AND drivy.progress_training_access(training)
$$;
REVOKE ALL ON FUNCTION drivy.progress_training_access(uuid),drivy.training_progress_read(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.progress_training_access(uuid),drivy.training_progress_read(uuid) TO drivy_app;
