-- Un trajet en cours n'est révoqué que par une vraie perte de droit, plus par un simple changement d'époque d'accès.
-- `access_epoch` augmente aussi quand un droit s'ajoute (nouvelle affectation du moniteur à une autre formation, fin d'une autre
-- affectation) : l'ancienne comparaison (status, roles, access_epoch) coupait alors le trajet de la leçon en cours.
-- La fin de l'affectation à la formation de la leçon reste couverte par capture_assignment_changed (008), le retrait d'accès
-- par le statut, le retrait du rôle par les rôles. La fonction ne lit que l'état après mise à jour : la rejouer est sans effet.
CREATE OR REPLACE FUNCTION drivy.capture_membership_changed() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 BEGIN
  IF NEW.status<>'ACTIVE' OR NOT ('INSTRUCTOR'=ANY(NEW.roles)) THEN
   UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
   WHERE c.school_id=NEW.school_id AND c.capture_state='AUTHORIZED' AND c.instructor_membership_id=NEW.id;
  END IF;
  IF NEW.status<>'ACTIVE' OR NOT ('LEARNER'=ANY(NEW.roles)) THEN
   UPDATE drivy.capture_session c SET capture_state='REVOKED',cutoff_at=least(coalesce(c.cutoff_at,c.expires_at),statement_timestamp()),version=c.version+1
   WHERE c.school_id=NEW.school_id AND c.capture_state='AUTHORIZED'
    AND EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.school_id=c.school_id AND l.id=c.learner_id AND l.person_id=NEW.person_id);
  END IF;
  RETURN NEW;
 END $$;
REVOKE ALL ON FUNCTION drivy.capture_membership_changed() FROM PUBLIC;

-- Index de lecture. Aucune donnée n'est modifiée ; IF NOT EXISTS rend la migration rejouable.
-- Reçu d'une écriture (GET /operations/:id) : jointure operation ⨝ audit_event sur ces trois colonnes.
CREATE INDEX IF NOT EXISTS audit_event_operation ON drivy.audit_event(school_id,actor_person_id,operation_id);
-- Déplacement, annulation et constat libèrent les occupations d'une leçon.
CREATE INDEX IF NOT EXISTS reservation_lesson ON drivy.reservation(school_id,lesson_id);
-- Résumé de trajet de chaque leçon projetée, trajets d'une leçon, observations tardives.
CREATE INDEX IF NOT EXISTS capture_session_lesson ON drivy.capture_session(school_id,lesson_id,authorized_at DESC,id DESC);
