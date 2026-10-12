-- Lecture des bilans (décisions du porteur du 12 octobre 2026, audit A2-02 et A2-09).
-- 1. Le bureau lit les bilans partagés : un administrateur actif de l'école lit la révision courante d'une leçon, comme l'élève
--    la voit. Un bilan gardé privé ou retiré n'a pas de révision courante (current_published_revision_id NULL) : il reste illisible.
-- 2. L'élève ne lit que la révision courante. Avec le partage automatique, chaque enregistrement du moniteur devient une révision :
--    les versions précédentes, réécrites par le moniteur, ne sont plus envoyées à l'élève.
-- 3. Le moniteur actuellement affecté à la formation garde tout l'historique, y compris les révisions retirées (inchangé).
-- La politique restrictive revision_withdrawn_scope (011) reste en place. Aucune donnée n'est lue ni modifiée ici ;
-- CREATE OR REPLACE et DROP POLICY IF EXISTS rendent la migration rejouable.

-- Moniteur actif, avec une affectation en cours sur la formation.
CREATE OR REPLACE FUNCTION drivy.report_training_instructor(training uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t
  JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)
  AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=t.school_id AND a.training_id=t.id AND a.instructor_membership_id=m.id
   AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))
$$;

-- Révision lisible : tout l'historique pour le moniteur affecté ; la seule révision courante pour l'élève de la formation
-- et pour l'administration de l'école.
CREATE OR REPLACE FUNCTION drivy.report_revision_readable(lesson uuid,revision uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND (
  drivy.report_training_instructor(l.training_id)
  OR (l.current_published_revision_id=revision
   AND (drivy.report_training_access(l.training_id,true) OR drivy.is_current_school_admin(l.school_id)))))
$$;
REVOKE ALL ON FUNCTION drivy.report_training_instructor(uuid),drivy.report_revision_readable(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.report_training_instructor(uuid),drivy.report_revision_readable(uuid,uuid) TO drivy_app;

DROP POLICY IF EXISTS revision_read ON drivy.report_revision;
CREATE POLICY revision_read ON drivy.report_revision FOR SELECT TO drivy_app USING(drivy.report_revision_readable(lesson_id,id));
