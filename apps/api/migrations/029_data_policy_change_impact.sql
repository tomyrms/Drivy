-- Impact d'une nouvelle version des textes de confidentialité (analyse du 13 octobre 2026, lot 0).
-- Adopter une version arrête les trajets en cours de l'école (capture_notice_changed, 008) et rend caducs les accords GPS
-- donnés sur la version précédente (captures.ts exige la version actuelle). L'administrateur doit le savoir avant de confirmer.
-- Il lit déjà les trajets (014) mais pas les accords des élèves qu'il ne suit pas : cette fonction ne lui rend que deux nombres,
-- jamais une ligne, un nom ni un statut individuel. Aucune donnée n'est modifiée ; CREATE OR REPLACE rend la migration rejouable.
CREATE OR REPLACE FUNCTION drivy.data_policy_change_impact(target_school uuid)
 RETURNS TABLE(gps_agreements integer, active_captures integer)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 WITH current_notice AS (
  SELECT notice_version_id FROM drivy.school_data_policy
  WHERE school_id=target_school AND approved_at IS NOT NULL ORDER BY version DESC LIMIT 1)
 SELECT
  (SELECT count(DISTINCT r.learner_id)::integer FROM drivy.recording_choice r JOIN current_notice n ON n.notice_version_id=r.notice_version_id
    WHERE r.school_id=target_school AND r.status='ALLOWED'),
  (SELECT count(*)::integer FROM drivy.capture_session c
    WHERE c.school_id=target_school AND c.capture_state='AUTHORIZED' AND c.expires_at>statement_timestamp())
 WHERE drivy.is_current_school_admin(target_school)
$$;
REVOKE ALL ON FUNCTION drivy.data_policy_change_impact(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.data_policy_change_impact(uuid) TO drivy_app;
