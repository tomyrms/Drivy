-- #54 : suivi des examens théorique et pratique d'une formation (saisie manuelle du personnel, aucun lien avec une autorité).
-- Migration additive : aucune migration existante n'est modifiée. Décisions et limites : docs/implementation/examens-54.md.
-- Une date passée ne devient jamais une réussite ni un échec : le résultat est un fait saisi, corrigé avec motif, daté et signé.
-- L'examen d'une formation ne touche ni les autres formations de l'élève, ni les leçons, ni les bilans.

-- 1. Examens. Un examen est une tentative ; un report garde la tentative d'origine (POSTPONED) et en ouvre une nouvelle.
CREATE TABLE drivy.exam(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 training_id uuid NOT NULL,
 kind text NOT NULL CHECK(kind IN('THEORY','PRACTICAL')),
 category_code text NOT NULL,
 status text NOT NULL DEFAULT 'SCHEDULED' CHECK(status IN('SCHEDULED','POSTPONED','ABSENT','PASSED','FAILED')),
 starts_at timestamptz NOT NULL,
 time_zone text NOT NULL CHECK(char_length(time_zone) BETWEEN 1 AND 100),
 location text NOT NULL DEFAULT '' CHECK(char_length(location)<=200),
 escort_instructor_membership_id uuid,
 escort_starts_at timestamptz,
 escort_ends_at timestamptz,
 result_note text NOT NULL DEFAULT '' CHECK(char_length(result_note)<=1000),
 result_recorded_at timestamptz,
 postponed_to_exam_id uuid,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),
 FOREIGN KEY(school_id,training_id) REFERENCES drivy.training(school_id,id),
 FOREIGN KEY(school_id,escort_instructor_membership_id) REFERENCES drivy.membership(school_id,id),
 FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id),
 -- Différée : le report ferme l'ancienne tentative avant d'ouvrir la nouvelle, dans la même transaction.
 FOREIGN KEY(school_id,postponed_to_exam_id) REFERENCES drivy.exam(school_id,id) DEFERRABLE INITIALLY DEFERRED,
 CHECK((escort_instructor_membership_id IS NULL)=(escort_starts_at IS NULL) AND (escort_starts_at IS NULL)=(escort_ends_at IS NULL)),
 CHECK(escort_ends_at IS NULL OR (escort_ends_at>escort_starts_at AND escort_ends_at-escort_starts_at<=interval '12 hours')),
 CHECK((status IN('PASSED','FAILED','ABSENT'))=(result_recorded_at IS NOT NULL)),
 CHECK((status='POSTPONED')=(postponed_to_exam_id IS NOT NULL))
);
-- Une seule tentative prévue par formation et par épreuve ; une épreuve réussie ne se replanifie pas (corriger le résultat d'abord).
CREATE UNIQUE INDEX exam_one_scheduled ON drivy.exam(training_id,kind) WHERE status='SCHEDULED';
CREATE UNIQUE INDEX exam_one_passed ON drivy.exam(training_id,kind) WHERE status='PASSED';
CREATE INDEX exam_by_training ON drivy.exam(training_id,starts_at DESC,id DESC);
CREATE INDEX exam_inbox ON drivy.exam(school_id,status,starts_at);

-- 2. Historique : l'état complet après chaque écriture, son auteur et son motif. Ajout seul, jamais modifié.
CREATE TABLE drivy.exam_revision(
 school_id uuid NOT NULL,
 exam_id uuid NOT NULL,
 revision integer NOT NULL CHECK(revision>0),
 operation_id uuid NOT NULL,
 action text NOT NULL CHECK(action IN('CREATED','UPDATED','POSTPONED','RESULT_RECORDED','RESULT_CORRECTED')),
 status text NOT NULL CHECK(status IN('SCHEDULED','POSTPONED','ABSENT','PASSED','FAILED')),
 starts_at timestamptz NOT NULL,
 time_zone text NOT NULL,
 location text NOT NULL,
 escort_instructor_membership_id uuid,
 escort_starts_at timestamptz,
 escort_ends_at timestamptz,
 result_note text NOT NULL,
 actor_membership_id uuid NOT NULL,
 reason text NOT NULL DEFAULT '' CHECK(char_length(reason)<=1000),
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(exam_id,revision),
 FOREIGN KEY(school_id,exam_id) REFERENCES drivy.exam(school_id,id),
 FOREIGN KEY(school_id,actor_membership_id) REFERENCES drivy.membership(school_id,id)
);

-- 3. Portées. Lire : l'élève de la formation, son moniteur affecté et l'administration (règle du catalogue). Écrire : l'administration
-- et le moniteur actuellement affecté à la formation. L'élève ne saisit rien.
CREATE FUNCTION drivy.exam_manage(training uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND
  ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a
   WHERE a.school_id=t.school_id AND a.training_id=t.id AND a.instructor_membership_id=m.id
   AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;
CREATE FUNCTION drivy.exam_manage_exam(exam uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.exam e WHERE e.id=exam AND drivy.exam_manage(e.training_id))
$$;
-- Personne du moniteur d'accompagnement : seulement un moniteur actif actuellement affecté à la formation, relu par une fonction pour
-- que le choix ne dépende pas de la visibilité des autres membres de l'équipe.
CREATE FUNCTION drivy.exam_escort_person(training uuid,instructor uuid) RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.person_id FROM drivy.training t
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.id=instructor AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)
 JOIN drivy.person p ON p.id=m.person_id AND p.status='ACTIVE'
 WHERE t.id=training AND drivy.exam_manage(training) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a
  WHERE a.school_id=t.school_id AND a.training_id=t.id AND a.instructor_membership_id=m.id
  AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp()))
$$;
-- Nom de l'élève d'une formation lisible par qui lit cette formation (le nom vit dans person depuis la migration 041).
CREATE FUNCTION drivy.exam_learner_name(training uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.display_name FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
 JOIN drivy.person p ON p.id=l.person_id WHERE t.id=training AND drivy.catalogue_training_visible(training)
$$;
-- Moniteurs proposables à l'accompagnement : les moniteurs actifs actuellement affectés à la formation, pour qui peut la gérer.
CREATE FUNCTION drivy.exam_escort_candidates(training uuid) RETURNS TABLE(membership_id uuid,display_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT DISTINCT m.id,p.display_name FROM drivy.training t
 JOIN drivy.instructor_assignment a ON a.school_id=t.school_id AND a.training_id=t.id
  AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.id=a.instructor_membership_id AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)
 JOIN drivy.person p ON p.id=m.person_id AND p.status='ACTIVE'
 WHERE t.id=training AND drivy.exam_manage(training)
$$;
REVOKE ALL ON FUNCTION drivy.exam_manage(uuid),drivy.exam_manage_exam(uuid),drivy.exam_escort_person(uuid,uuid),drivy.exam_escort_candidates(uuid),drivy.exam_learner_name(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.exam_manage(uuid),drivy.exam_manage_exam(uuid),drivy.exam_escort_person(uuid,uuid),drivy.exam_escort_candidates(uuid),drivy.exam_learner_name(uuid) TO drivy_app;

-- 4. Accès par ligne.
ALTER TABLE drivy.exam ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.exam FORCE ROW LEVEL SECURITY;
ALTER TABLE drivy.exam_revision ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.exam_revision FORCE ROW LEVEL SECURITY;
DO $$ BEGIN
 EXECUTE format('CREATE POLICY exam_owner_read ON drivy.exam FOR SELECT TO %I USING(true)',current_user);
 EXECUTE format('CREATE POLICY exam_revision_owner_read ON drivy.exam_revision FOR SELECT TO %I USING(true)',current_user);
END $$;
CREATE POLICY exam_read ON drivy.exam FOR SELECT TO drivy_app USING(drivy.catalogue_training_visible(training_id));
CREATE POLICY exam_insert ON drivy.exam FOR INSERT TO drivy_app WITH CHECK(drivy.exam_manage(training_id));
CREATE POLICY exam_update ON drivy.exam FOR UPDATE TO drivy_app USING(drivy.exam_manage(training_id)) WITH CHECK(drivy.exam_manage(training_id));
-- L'historique est du personnel : l'élève lit ses examens, pas qui les a corrigés ni pourquoi.
CREATE POLICY exam_revision_read ON drivy.exam_revision FOR SELECT TO drivy_app USING(drivy.exam_manage_exam(exam_id));
CREATE POLICY exam_revision_insert ON drivy.exam_revision FOR INSERT TO drivy_app WITH CHECK(drivy.exam_manage_exam(exam_id));
GRANT SELECT,INSERT ON drivy.exam,drivy.exam_revision TO drivy_app;
GRANT UPDATE(status,starts_at,time_zone,location,escort_instructor_membership_id,escort_starts_at,escort_ends_at,result_note,result_recorded_at,
 postponed_to_exam_id,version,updated_at) ON drivy.exam TO drivy_app;

-- 5. Accompagnement : une occupation du moniteur dans la table commune, sous la même contrainte d'exclusion que les leçons et les
-- séances de cours. Conflits examen/leçon et examen/cours refusés dans les deux sens. Un examen sans accompagnement n'occupe personne.
ALTER TABLE drivy.reservation ADD COLUMN exam_id uuid, ADD CONSTRAINT reservation_exam FOREIGN KEY(school_id,exam_id) REFERENCES drivy.exam(school_id,id);
ALTER TABLE drivy.reservation DROP CONSTRAINT reservation_single_source;
ALTER TABLE drivy.reservation ADD CONSTRAINT reservation_single_source CHECK(
 (lesson_id IS NOT NULL AND course_occurrence_id IS NULL AND course_enrollment_id IS NULL AND exam_id IS NULL)
 OR (lesson_id IS NULL AND course_occurrence_id IS NOT NULL AND exam_id IS NULL)
 OR (lesson_id IS NULL AND course_occurrence_id IS NULL AND course_enrollment_id IS NULL AND exam_id IS NOT NULL AND resource_role='INSTRUCTOR'));
CREATE INDEX reservation_exam ON drivy.reservation(exam_id) WHERE exam_id IS NOT NULL;
CREATE POLICY reservation_exam_read ON drivy.reservation FOR SELECT TO drivy_app USING(exam_id IS NOT NULL AND drivy.exam_manage_exam(exam_id));
CREATE POLICY reservation_exam_insert ON drivy.reservation FOR INSERT TO drivy_app WITH CHECK(exam_id IS NOT NULL AND drivy.exam_manage_exam(exam_id));
CREATE POLICY reservation_exam_update ON drivy.reservation FOR UPDATE TO drivy_app USING(exam_id IS NOT NULL AND drivy.exam_manage_exam(exam_id)) WITH CHECK(exam_id IS NOT NULL);

-- 6. Reçus et audit des nouvelles commandes (les politiques de 006 énumèrent leurs valeurs).
CREATE POLICY exam_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
 'CREATE_EXAM','UPDATE_EXAM','POSTPONE_EXAM','SET_EXAM_RESULT'));
CREATE POLICY exam_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN(
 'ExamCreated','ExamUpdated','ExamPostponed','ExamResultRecorded','ExamResultCorrected'));
