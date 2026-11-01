-- #52 : l'élève demande le déplacement ou l'annulation de sa leçon, le personnel répond.
-- Migration additive : aucune migration existante n'est modifiée. Décisions et limites : docs/implementation/demandes-eleve-lecon-52.md.
-- Une demande n'a aucun effet sur la leçon, ses occupations ni son compte. Seule la réponse du personnel passe par les commandes
-- de déplacement et d'annulation existantes, qui relisent tous leurs contrôles. Aucun délai et aucun frais ne sont inventés : le délai
-- affiché est celui de la procédure approuvée de la leçon (cancellation_rules, migration 20261028), figé dans la demande pour que
-- les conditions consultées ne changent pas après coup.

-- 1. Demandes. Une seule demande en attente par leçon ; WITHDRAWN = retirée par l'élève, SUPERSEDED = la leçon a changé avant la réponse.
CREATE TABLE drivy.lesson_change_request(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 lesson_id uuid NOT NULL,
 requester_person_id uuid NOT NULL REFERENCES drivy.person(id),
 kind text NOT NULL CHECK(kind IN('RESCHEDULE','CANCEL')),
 status text NOT NULL DEFAULT 'PENDING' CHECK(status IN('PENDING','ACCEPTED','REFUSED','WITHDRAWN','SUPERSEDED')),
 note text NOT NULL DEFAULT '' CHECK(char_length(note)<=1000),
 lesson_version integer NOT NULL CHECK(lesson_version>0),
 policy_version_id uuid,
 cancellation_hours integer CHECK(cancellation_hours IS NULL OR cancellation_hours BETWEEN 0 AND 8760),
 deadline_at timestamptz,
 late boolean,
 resolved_by_membership_id uuid,
 resolved_at timestamptz,
 resolution_note text CHECK(resolution_note IS NULL OR char_length(resolution_note)<=1000),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),
 FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 CHECK((status='PENDING')=(resolved_at IS NULL)),
 CHECK(kind<>'RESCHEDULE' OR btrim(note)<>''),
 CHECK((deadline_at IS NULL)=(late IS NULL))
);
CREATE UNIQUE INDEX lesson_change_one_pending ON drivy.lesson_change_request(lesson_id) WHERE status='PENDING';
CREATE INDEX lesson_change_inbox ON drivy.lesson_change_request(school_id,status,created_at DESC,id DESC);
CREATE INDEX lesson_change_by_lesson ON drivy.lesson_change_request(lesson_id,created_at DESC,id DESC);

-- 2. Portées. Lire : l'élève de la leçon, son moniteur affecté et l'administration (même règle que la lecture de la leçon).
-- Traiter : l'administration et le moniteur de la leçon. Demander : l'élève de la leçon seulement.
CREATE FUNCTION drivy.lesson_change_read(lesson uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson AND drivy.lesson_access(l.training_id,l.instructor_membership_id,false))
$$;
CREATE FUNCTION drivy.lesson_change_staff(lesson uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson AND drivy.lesson_access(l.training_id,l.instructor_membership_id,true))
$$;
CREATE FUNCTION drivy.lesson_change_learner(lesson uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l WHERE l.id=lesson AND drivy.current_school_member(l.school_id)
  AND l.learner_person_id=nullif(current_setting('app.person_id',true),'')::uuid)
$$;
-- Conditions de la procédure approuvée au moment de la planification de la leçon : lisibles par tous ceux qui peuvent lire la leçon,
-- sans dépendre de la visibilité du catalogue.
CREATE FUNCTION drivy.lesson_change_conditions(lesson uuid) RETURNS TABLE(policy_version_id uuid,policy_version integer,cancellation_policy_text text,cancellation_rules jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.id,p.version,p.cancellation_policy_text,p.cancellation_rules
 FROM drivy.lesson l JOIN drivy.school_policy_version p ON p.school_id=l.school_id AND p.id=l.policy_version_id
 WHERE l.id=lesson AND drivy.lesson_change_read(lesson)
$$;
REVOKE ALL ON FUNCTION drivy.lesson_change_read(uuid),drivy.lesson_change_staff(uuid),drivy.lesson_change_learner(uuid),drivy.lesson_change_conditions(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_change_read(uuid),drivy.lesson_change_staff(uuid),drivy.lesson_change_learner(uuid),drivy.lesson_change_conditions(uuid) TO drivy_app;

-- 3. Accès par ligne. L'élève ne peut ni accepter ni refuser ; le personnel ne peut ni créer ni retirer à la place de l'élève.
ALTER TABLE drivy.lesson_change_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.lesson_change_request FORCE ROW LEVEL SECURITY;
DO $$ BEGIN EXECUTE format('CREATE POLICY lesson_change_owner_read ON drivy.lesson_change_request FOR SELECT TO %I USING(true)',current_user); END $$;
CREATE POLICY lesson_change_read ON drivy.lesson_change_request FOR SELECT TO drivy_app USING(drivy.lesson_change_read(lesson_id));
CREATE POLICY lesson_change_insert ON drivy.lesson_change_request FOR INSERT TO drivy_app
 WITH CHECK(status='PENDING' AND requester_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.lesson_change_learner(lesson_id));
CREATE POLICY lesson_change_withdraw ON drivy.lesson_change_request FOR UPDATE TO drivy_app
 USING(status='PENDING' AND requester_person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 WITH CHECK(status='WITHDRAWN' AND requester_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
CREATE POLICY lesson_change_resolve ON drivy.lesson_change_request FOR UPDATE TO drivy_app
 USING(status='PENDING' AND drivy.lesson_change_staff(lesson_id))
 WITH CHECK(status IN('ACCEPTED','REFUSED','SUPERSEDED') AND drivy.lesson_change_staff(lesson_id));
GRANT SELECT,INSERT ON drivy.lesson_change_request TO drivy_app;
GRANT UPDATE(status,version,resolved_by_membership_id,resolved_at,resolution_note,updated_at) ON drivy.lesson_change_request TO drivy_app;

-- 4. Reçus et audit des nouvelles commandes (les politiques de 006 énumèrent leurs valeurs). Déplacer et annuler gardent les leurs.
CREATE POLICY lesson_change_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
 'CREATE_LESSON_CHANGE_REQUEST','WITHDRAW_LESSON_CHANGE_REQUEST','REFUSE_LESSON_CHANGE_REQUEST'));
CREATE POLICY lesson_change_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN(
 'LessonChangeRequested','LessonChangeRequestWithdrawn','LessonChangeRequestRefused'));
