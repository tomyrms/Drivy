-- Corrections de planification : contrôle du permis sans habilitation préalable pour l'ADMIN et le moniteur affecté,
-- version courante d'une prestation, noms affichés d'une leçon et démarrage immédiat d'une leçon par son moniteur.

-- Contrôleur du permis : ADMIN ou moniteur actuellement affecté à la formation. Le grant permit_review n'est plus
-- une condition (l'ADMIN n'en possédait aucun au provisionnement et le moniteur voit le permis dès la première leçon).
CREATE OR REPLACE FUNCTION drivy.permit_review_allowed(training uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.membership m ON m.school_id=t.school_id
 AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND
 ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=t.school_id
 AND a.training_id=t.id AND a.instructor_membership_id=m.id AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;

-- Une prestation est réservable seulement dans sa dernière version (même product_key). La fonction lit toutes les versions,
-- y compris celles qu'un membre sans CONFIGURE_CATALOG ne voit pas (brouillons ou versions désactivées), pour ne jamais
-- prendre une ancienne version pour la courante.
CREATE FUNCTION drivy.service_product_current(product uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.service_product_version s WHERE s.id=product AND drivy.current_school_member(s.school_id)
  AND s.version=(SELECT max(v.version) FROM drivy.service_product_version v WHERE v.school_id=s.school_id AND v.product_key=s.product_key))
$$;
REVOKE ALL ON FUNCTION drivy.service_product_current(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.service_product_current(uuid) TO drivy_app;

-- Noms affichés d'une leçon. Les valeurs de la ligne sont passées en paramètres (et non l'identifiant de la leçon) pour que
-- le résultat suive une leçon déplacée dans la même instruction. Le droit de lecture de la leçon est vérifié dans la fonction.
CREATE FUNCTION drivy.lesson_learner_name(school uuid,training uuid,instructor uuid,learner uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT lp.display_name FROM drivy.learner_profile lp WHERE lp.school_id=school AND lp.id=learner AND drivy.current_school_member(school)
 AND (drivy.lesson_access(training,instructor,false) OR drivy.report_training_access(training,false))
$$;
CREATE FUNCTION drivy.lesson_instructor_name(school uuid,training uuid,instructor uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.display_name FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id WHERE m.school_id=school AND m.id=instructor
 AND drivy.current_school_member(school) AND (drivy.lesson_access(training,instructor,false) OR drivy.report_training_access(training,false))
$$;
REVOKE ALL ON FUNCTION drivy.lesson_learner_name(uuid,uuid,uuid,uuid),drivy.lesson_instructor_name(uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_learner_name(uuid,uuid,uuid,uuid),drivy.lesson_instructor_name(uuid,uuid,uuid) TO drivy_app;

-- Démarrage immédiat : nouvelle commande et nouvelle action d'audit (les politiques de 006 énumèrent leurs valeurs).
CREATE POLICY start_now_operation_insert ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND command_type='START_LESSON_NOW');
CREATE POLICY start_now_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND action='LessonStartedNow');
