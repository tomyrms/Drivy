-- Trajets visibles par l'administration (décision du porteur du 28 septembre 2026) : un membre ADMIN actif de l'école lit,
-- en lecture seule, toutes les captures de son école (tous moniteurs, tous élèves). Le moniteur garde sa règle (008) :
-- les trajets des formations auxquelles il est affecté. Les écritures restent réservées à l'auteur (capture_insert,
-- capture_update, chunk_insert n'appellent pas cette fonction).
-- Les lots (capture_chunk) et le replay suivent la session par leur politique existante : un trajet lisible donne accès à ses mesures.
-- Les observations géolocalisées gardent leurs propres politiques (009, 012) : auteur courant seulement, ou élève pour celles qui lui
-- sont partagées. Un administrateur relit donc le trajet sans en lire les observations.
CREATE OR REPLACE FUNCTION drivy.capture_private_access(lesson uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id
 WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a
 WHERE a.school_id=l.school_id AND a.training_id=l.training_id AND a.instructor_membership_id=m.id
 AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))
 OR EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson AND drivy.is_current_school_admin(l.school_id))
$$;

-- Liste des trajets : noms de l'élève et du moniteur. Un élève ne lit pas la fiche personne de son moniteur (politiques de
-- drivy.person) ; cette fonction ne révèle ces deux noms que pour un trajet que l'appelant peut déjà lire (moniteur affecté,
-- administrateur, ou élève pour un trajet partagé), sans élargir la lecture générale des personnes.
CREATE FUNCTION drivy.capture_trip_names(capture uuid) RETURNS TABLE(learner_name text,instructor_name text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT lp.display_name,ip.display_name FROM drivy.capture_session c
 JOIN drivy.learner_profile lp ON lp.school_id=c.school_id AND lp.id=c.learner_id
 JOIN drivy.membership im ON im.school_id=c.school_id AND im.id=c.instructor_membership_id
 JOIN drivy.person ip ON ip.id=im.person_id
 WHERE c.id=capture AND drivy.current_school_member(c.school_id)
 AND (drivy.capture_private_access(c.lesson_id)
  OR (c.publication_state='PRIVATE' AND c.finalized_at IS NOT NULL AND c.sync_state IN('SYNCED','PARTIAL') AND drivy.learner_shared_lesson(c.lesson_id,'capture')))
$$;
REVOKE ALL ON FUNCTION drivy.capture_trip_names(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.capture_trip_names(uuid) TO drivy_app;
