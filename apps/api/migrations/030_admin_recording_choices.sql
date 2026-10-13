-- Accord GPS lisible par l'administration dans le dossier web (analyse du 13 octobre 2026, lot 1).
-- L'administration lit déjà tous les trajets de son école (014) ; elle ne lisait pas les accords des élèves qu'elle ne suit pas
-- comme moniteur. Cette fonction rend, pour chaque élève, le choix général en vigueur (sans leçon précise) avec la même priorité
-- que drivy.capture_effective_choice (008) : un refus donné par l'élève lui-même l'emporte sur un accord oral plus récent.
-- Sans choix général, le dernier choix donné pour une leçon est rendu (`lesson_scoped`) : l'accord donné au départ d'une leçon
-- ne doit pas apparaître comme « pas encore donné ». `current_notice` dit si ce choix vaut pour les textes actuels.
-- Lecture seule, rejouable.
CREATE OR REPLACE FUNCTION drivy.admin_recording_choices(target_school uuid)
 RETURNS TABLE(learner_id uuid, status text, source text, recorded_at timestamptz, current_notice boolean, lesson_scoped boolean)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 WITH notice AS (
  SELECT notice_version_id FROM drivy.school_data_policy
  WHERE school_id=target_school AND approved_at IS NOT NULL ORDER BY version DESC LIMIT 1),
 latest AS (
  SELECT DISTINCT ON (r.learner_id) r.* FROM drivy.recording_choice r
  WHERE r.school_id=target_school ORDER BY r.learner_id,(r.lesson_id IS NULL) DESC,r.version DESC),
 own_refusal AS (
  SELECT DISTINCT ON (r.learner_id) r.* FROM drivy.recording_choice r
  WHERE r.school_id=target_school AND r.lesson_id IS NULL AND r.source='SELF' ORDER BY r.learner_id,r.version DESC)
 SELECT l.learner_id,
  CASE WHEN o.status='REFUSED' THEN o.status ELSE l.status END,
  CASE WHEN o.status='REFUSED' THEN o.source ELSE l.source END,
  CASE WHEN o.status='REFUSED' THEN o.recorded_at ELSE l.recorded_at END,
  coalesce((CASE WHEN o.status='REFUSED' THEN o.notice_version_id ELSE l.notice_version_id END)=(SELECT notice_version_id FROM notice),false),
  o.status IS DISTINCT FROM 'REFUSED' AND l.lesson_id IS NOT NULL
 FROM latest l LEFT JOIN own_refusal o ON o.learner_id=l.learner_id
 WHERE drivy.is_current_school_admin(target_school)
$$;
REVOKE ALL ON FUNCTION drivy.admin_recording_choices(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.admin_recording_choices(uuid) TO drivy_app;
