-- Cours collectifs : socle commun (#80), consommé par la création et la publication (#38), puis par les inscriptions (#39),
-- la file prioritaire (#40), les annulations (#41), les présences (#42), les règlements sur place (#81) et l'accomplissement (#82).
-- Décisions : docs/implementation/cours-collectifs-cadrage-79.md et cours-collectifs-socle-80.md.
-- Aucune donnée existante n'est reprise : personne n'est marqué inscrit, présent, payé, formé ou prioritaire par cette migration.

-- Une seule règle de gestion : l'administration, ou un moniteur portant MANAGE_COURSES (droit déjà prévu dans membership.grants).
CREATE FUNCTION drivy.can_manage_courses(school uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.current_school_member(school) AND EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
  WHERE m.school_id=school AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND p.status='ACTIVE'
  AND ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND 'MANAGE_COURSES'=ANY(m.grants))))
$$;
REVOKE ALL ON FUNCTION drivy.can_manage_courses(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.can_manage_courses(uuid) TO drivy_app;

-- Type stable. Sensibilisation et Premiers secours sont communs à toutes les écoles (school_id NULL, clé stable) ; un type
-- personnalisé appartient à son école. Renommer garde l'identifiant : séries passées et accomplissements restent liés.
CREATE TABLE drivy.course_type (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid REFERENCES drivy.school(id),
 stable_key text UNIQUE CHECK(stable_key IN('AWARENESS','FIRST_AID')),
 title text NOT NULL CHECK(char_length(btrim(title)) BETWEEN 1 AND 120),
 description text NOT NULL DEFAULT '' CHECK(char_length(description)<=2000),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 created_by uuid,
 created_at timestamptz NOT NULL DEFAULT now(),
 archived_at timestamptz,
 CHECK((school_id IS NULL)=(stable_key IS NOT NULL)),
 CHECK((school_id IS NULL)=(created_by IS NULL)),
 FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id)
);
CREATE UNIQUE INDEX course_type_title ON drivy.course_type(school_id,lower(btrim(title))) WHERE school_id IS NOT NULL AND archived_at IS NULL;
INSERT INTO drivy.course_type(id,stable_key,title,description) VALUES
 ('0c0a5e00-0000-4000-8000-000000000001','AWARENESS','Sensibilisation','Cours de théorie de la circulation.'),
 ('0c0a5e00-0000-4000-8000-000000000002','FIRST_AID','Premiers secours','Cours de premiers secours aux blessés.');

-- Conditions d'annulation versionnées par école. Sans ligne, la version 1 implicite s'applique : 24 h avant la première séance.
-- offer_response_minutes NULL : la file prioritaire n'est pas activée (#40 exige un choix explicite de l'école).
CREATE TABLE drivy.course_policy_version (
 school_id uuid NOT NULL REFERENCES drivy.school(id),
 version integer NOT NULL CHECK(version>1),
 self_cancel_hours integer NOT NULL CHECK(self_cancel_hours BETWEEN 0 AND 720),
 offer_response_minutes integer CHECK(offer_response_minutes BETWEEN 15 AND 10080),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(school_id,version),
 FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id)
);

-- Série : ce que l'élève réserve en entier. Les conditions sont figées dans la série (copie de la politique au moment de
-- l'enregistrement) puis dans chaque inscription : un durcissement ultérieur n'est jamais rétroactif.
CREATE TABLE drivy.course_series (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL REFERENCES drivy.school(id),
 type_id uuid NOT NULL REFERENCES drivy.course_type(id),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 status text NOT NULL DEFAULT 'DRAFT' CHECK(status IN('DRAFT','PUBLISHED','CANCELLED','CLOSED')),
 title text NOT NULL CHECK(char_length(btrim(title)) BETWEEN 1 AND 200),
 description text NOT NULL DEFAULT '' CHECK(char_length(description)<=4000),
 location text NOT NULL DEFAULT '' CHECK(char_length(location)<=500),
 conditions text NOT NULL DEFAULT '' CHECK(char_length(conditions)<=4000),
 teaching_language text CHECK(teaching_language IN('fr','de','it','en')),
 responsible_membership_id uuid NOT NULL,
 capacity integer NOT NULL CHECK(capacity BETWEEN 1 AND 200),
 min_participants integer CHECK(min_participants BETWEEN 1 AND 200),
 policy_version integer NOT NULL DEFAULT 1 CHECK(policy_version>0),
 self_cancel_hours integer NOT NULL DEFAULT 24 CHECK(self_cancel_hours BETWEEN 0 AND 720),
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 updated_at timestamptz NOT NULL DEFAULT now(),
 published_at timestamptz,
 cancelled_at timestamptz,
 cancel_reason text CHECK(char_length(cancel_reason)<=1000),
 UNIQUE(school_id,id),
 CHECK(min_participants IS NULL OR min_participants<=capacity),
 CHECK((status='DRAFT')=(published_at IS NULL)),
 CHECK((status='CANCELLED')=(cancelled_at IS NOT NULL)),
 FOREIGN KEY(school_id,responsible_membership_id) REFERENCES drivy.membership(school_id,id),
 FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id)
);
CREATE INDEX course_series_school ON drivy.course_series(school_id,status,id);

-- Séance datée. attendance_required : présence obligatoire pour l'accomplissement (#42/#82).
CREATE TABLE drivy.course_occurrence (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 series_id uuid NOT NULL,
 position integer NOT NULL CHECK(position BETWEEN 1 AND 64),
 starts_at timestamptz NOT NULL,
 ends_at timestamptz NOT NULL,
 time_zone text NOT NULL,
 instructor_membership_id uuid NOT NULL,
 attendance_required boolean NOT NULL DEFAULT true,
 UNIQUE(school_id,id),
 UNIQUE(series_id,position),
 FOREIGN KEY(school_id,series_id) REFERENCES drivy.course_series(school_id,id) ON DELETE CASCADE,
 FOREIGN KEY(school_id,instructor_membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(ends_at>starts_at AND ends_at<=starts_at+interval '12 hours'),
 -- Les séances d'une même série ne se chevauchent pas.
 EXCLUDE USING gist(series_id WITH =,tstzrange(starts_at,ends_at,'[)') WITH &&)
);
CREATE INDEX course_occurrence_window ON drivy.course_occurrence(school_id,starts_at);

-- Inscription à toute la série. Le délai d'annulation accepté et sa version sont copiés : l'échéance ne bouge plus.
CREATE TABLE drivy.course_enrollment (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 series_id uuid NOT NULL,
 learner_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 status text NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','CANCELLED')),
 source text NOT NULL CHECK(source IN('SELF','STAFF','OFFER')),
 policy_version integer NOT NULL CHECK(policy_version>0),
 self_cancel_hours integer NOT NULL CHECK(self_cancel_hours BETWEEN 0 AND 720),
 self_cancel_deadline timestamptz NOT NULL,
 created_by uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 cancelled_at timestamptz,
 cancelled_by uuid,
 cancel_kind text CHECK(cancel_kind IN('SELF','STAFF','SERIES_CANCELLED')),
 cancel_reason text CHECK(char_length(cancel_reason)<=1000),
 UNIQUE(school_id,id),
 CHECK((status='CANCELLED')=(cancelled_at IS NOT NULL AND cancel_kind IS NOT NULL)),
 FOREIGN KEY(school_id,series_id) REFERENCES drivy.course_series(school_id,id),
 FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id),
 FOREIGN KEY(school_id,created_by) REFERENCES drivy.membership(school_id,id),
 FOREIGN KEY(school_id,cancelled_by) REFERENCES drivy.membership(school_id,id)
);
CREATE UNIQUE INDEX course_enrollment_active ON drivy.course_enrollment(series_id,learner_id) WHERE status='ACTIVE';

-- File prioritaire : l'ordre est celui d'entrée (queued_at puis seq), jamais recalculé.
CREATE TABLE drivy.course_waitlist_entry (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 series_id uuid NOT NULL,
 learner_id uuid NOT NULL,
 seq bigint GENERATED ALWAYS AS IDENTITY,
 queued_at timestamptz NOT NULL DEFAULT now(),
 status text NOT NULL DEFAULT 'WAITING' CHECK(status IN('WAITING','OFFERED','ACCEPTED','DECLINED','EXPIRED','WITHDRAWN','REMOVED')),
 resolved_at timestamptz,
 UNIQUE(school_id,id),
 FOREIGN KEY(school_id,series_id) REFERENCES drivy.course_series(school_id,id),
 FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id)
);
CREATE UNIQUE INDEX course_waitlist_open ON drivy.course_waitlist_entry(series_id,learner_id) WHERE status IN('WAITING','OFFERED');
CREATE INDEX course_waitlist_order ON drivy.course_waitlist_entry(series_id,queued_at,seq) WHERE status='WAITING';

-- Proposition exclusive : une place retenue pour une seule personne jusqu'à expires_at. Elle compte dans la capacité,
-- n'est pas une inscription et ne crée aucune occupation d'agenda.
CREATE TABLE drivy.course_seat_offer (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 series_id uuid NOT NULL,
 entry_id uuid NOT NULL,
 offered_at timestamptz NOT NULL DEFAULT now(),
 expires_at timestamptz NOT NULL,
 status text NOT NULL DEFAULT 'ACTIVE' CHECK(status IN('ACTIVE','ACCEPTED','DECLINED','EXPIRED','REVOKED')),
 resolved_at timestamptz,
 enrollment_id uuid,
 UNIQUE(school_id,id),
 CHECK(expires_at>offered_at),
 CHECK((status='ACCEPTED')=(enrollment_id IS NOT NULL)),
 FOREIGN KEY(school_id,series_id) REFERENCES drivy.course_series(school_id,id),
 FOREIGN KEY(school_id,entry_id) REFERENCES drivy.course_waitlist_entry(school_id,id),
 FOREIGN KEY(school_id,enrollment_id) REFERENCES drivy.course_enrollment(school_id,id)
);
CREATE UNIQUE INDEX course_offer_active_entry ON drivy.course_seat_offer(entry_id) WHERE status='ACTIVE';
CREATE INDEX course_offer_active ON drivy.course_seat_offer(series_id,expires_at) WHERE status='ACTIVE';

-- Faits pédagogiques et administratifs distincts : présence (#42), règlement sur place (#81), accomplissement (#82).
CREATE TABLE drivy.course_attendance (
 school_id uuid NOT NULL,
 enrollment_id uuid NOT NULL,
 occurrence_id uuid NOT NULL,
 status text NOT NULL CHECK(status IN('PRESENT','ABSENT','EXCUSED')),
 version integer NOT NULL DEFAULT 1 CHECK(version>0),
 recorded_by uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 PRIMARY KEY(enrollment_id,occurrence_id),
 FOREIGN KEY(school_id,enrollment_id) REFERENCES drivy.course_enrollment(school_id,id),
 FOREIGN KEY(school_id,occurrence_id) REFERENCES drivy.course_occurrence(school_id,id),
 FOREIGN KEY(school_id,recorded_by) REFERENCES drivy.membership(school_id,id)
);
CREATE TABLE drivy.course_payment_record (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 enrollment_id uuid NOT NULL,
 amount_cents bigint NOT NULL CHECK(amount_cents BETWEEN 0 AND 9007199254740991),
 method text NOT NULL DEFAULT 'ON_SITE' CHECK(method='ON_SITE'),
 recorded_by uuid NOT NULL,
 recorded_at timestamptz NOT NULL DEFAULT now(),
 voided_at timestamptz,
 FOREIGN KEY(school_id,enrollment_id) REFERENCES drivy.course_enrollment(school_id,id),
 FOREIGN KEY(school_id,recorded_by) REFERENCES drivy.membership(school_id,id)
);
-- Accomplissement validé explicitement par une personne habilitée, par élève et par type : il empêche une nouvelle
-- inscription au même type, jamais la lecture des offres. Absence de ligne = inconnu, pas « non accompli ».
CREATE TABLE drivy.course_completion (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 learner_id uuid NOT NULL,
 type_id uuid NOT NULL REFERENCES drivy.course_type(id),
 series_id uuid,
 validated_by uuid NOT NULL,
 validated_at timestamptz NOT NULL DEFAULT now(),
 revoked_at timestamptz,
 FOREIGN KEY(school_id,learner_id) REFERENCES drivy.learner_profile(school_id,id),
 FOREIGN KEY(school_id,series_id) REFERENCES drivy.course_series(school_id,id),
 FOREIGN KEY(school_id,validated_by) REFERENCES drivy.membership(school_id,id)
);
CREATE UNIQUE INDEX course_completion_current ON drivy.course_completion(school_id,learner_id,type_id) WHERE revoked_at IS NULL;

-- Événements métier pour #43 (push) : une proposition vise une seule personne ; un événement périmé se reconnaît à son échéance.
CREATE TABLE drivy.course_event_outbox (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL,
 series_id uuid NOT NULL,
 series_version integer NOT NULL,
 event_type text NOT NULL,
 target_learner_id uuid,
 valid_until timestamptz,
 operation_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 delivered_at timestamptz,
 UNIQUE(series_id,series_version,event_type,target_learner_id),
 FOREIGN KEY(school_id,series_id) REFERENCES drivy.course_series(school_id,id)
);

-- Occupation commune : une séance publiée occupe son formateur, une inscription occupe l'élève, dans la même table et sous la
-- même contrainte d'exclusion que les leçons. Conflits cours/leçon et cours/cours sont donc refusés dans les deux sens.
ALTER TABLE drivy.reservation ALTER COLUMN lesson_id DROP NOT NULL;
ALTER TABLE drivy.reservation ADD COLUMN course_occurrence_id uuid, ADD COLUMN course_enrollment_id uuid,
 ADD CONSTRAINT reservation_course_occurrence FOREIGN KEY(school_id,course_occurrence_id) REFERENCES drivy.course_occurrence(school_id,id),
 ADD CONSTRAINT reservation_course_enrollment FOREIGN KEY(school_id,course_enrollment_id) REFERENCES drivy.course_enrollment(school_id,id),
 ADD CONSTRAINT reservation_single_source CHECK((lesson_id IS NOT NULL AND course_occurrence_id IS NULL AND course_enrollment_id IS NULL)
  OR (lesson_id IS NULL AND course_occurrence_id IS NOT NULL));
CREATE INDEX reservation_course ON drivy.reservation(course_occurrence_id) WHERE course_occurrence_id IS NOT NULL;

-- Places occupées = inscriptions actives + propositions actives non échues. Seule source pour l'affichage et les commandes.
CREATE FUNCTION drivy.course_seats_taken(series uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT ((SELECT count(*) FROM drivy.course_enrollment e WHERE e.series_id=series AND e.status='ACTIVE')
  +(SELECT count(*) FROM drivy.course_seat_offer o WHERE o.series_id=series AND o.status='ACTIVE' AND o.expires_at>statement_timestamp()))::integer
 WHERE EXISTS(SELECT 1 FROM drivy.course_series s WHERE s.id=series AND drivy.current_school_member(s.school_id))
$$;
REVOKE ALL ON FUNCTION drivy.course_seats_taken(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_seats_taken(uuid) TO drivy_app;

-- Prévalidation anonyme d'une séance : vrai si le formateur a déjà une occupation (leçon ou cours) sur l'intervalle.
-- Comme lesson_slot_conflict, aucun détail d'un autre rendez-vous ne sort du serveur.
CREATE FUNCTION drivy.course_instructor_conflict(school uuid,instructor uuid,starts timestamptz,ends timestamptz,excluded_series uuid DEFAULT NULL)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE instructor_person uuid;
BEGIN
 IF drivy.can_manage_courses(school) IS DISTINCT FROM true THEN RAISE EXCEPTION 'Course access required' USING ERRCODE='42501'; END IF;
 IF starts IS NULL OR ends IS NULL OR ends<=starts THEN RAISE EXCEPTION 'Invalid interval' USING ERRCODE='22023'; END IF;
 SELECT m.person_id INTO instructor_person FROM drivy.membership m WHERE m.school_id=school AND m.id=instructor AND m.status='ACTIVE';
 IF instructor_person IS NULL THEN RAISE EXCEPTION 'Course access required' USING ERRCODE='42501'; END IF;
 RETURN EXISTS(SELECT 1 FROM drivy.reservation r LEFT JOIN drivy.course_occurrence o ON o.id=r.course_occurrence_id
  WHERE r.school_id=school AND r.active AND r.resource_id=instructor_person AND r.during&&tstzrange(starts,ends,'[)')
  AND (excluded_series IS NULL OR o.series_id IS DISTINCT FROM excluded_series));
END $$;
REVOKE ALL ON FUNCTION drivy.course_instructor_conflict(uuid,uuid,timestamptz,timestamptz,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_instructor_conflict(uuid,uuid,timestamptz,timestamptz,uuid) TO drivy_app;

-- Accomplissement validé : lecture booléenne pour l'élève lui-même ou le personnel, sans liste exposée.
CREATE FUNCTION drivy.course_type_completed(learner uuid,course_type uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.course_completion c WHERE c.learner_id=learner AND c.type_id=course_type AND c.revoked_at IS NULL
  AND drivy.profile_access(learner) IS NOT NULL)
$$;
REVOKE ALL ON FUNCTION drivy.course_type_completed(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_type_completed(uuid,uuid) TO drivy_app;

-- Formateurs proposables pour une séance : moniteurs actifs de l'école, nom affiché seulement, pour qui gère les cours.
CREATE FUNCTION drivy.course_instructors(school uuid) RETURNS TABLE(membership_id uuid,display_name text) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.id,p.display_name FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE m.school_id=school AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles) AND drivy.can_manage_courses(school)
 ORDER BY p.display_name,m.id
$$;
-- Nom affiché d'un membre de l'équipe dans une série visible (formateur responsable ou de séance).
CREATE FUNCTION drivy.course_staff_name(school uuid,member uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.display_name FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE m.school_id=school AND m.id=member AND m.roles&&ARRAY['ADMIN','INSTRUCTOR']::text[] AND drivy.current_school_member(school)
$$;
REVOKE ALL ON FUNCTION drivy.course_instructors(uuid),drivy.course_staff_name(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_instructors(uuid),drivy.course_staff_name(uuid,uuid) TO drivy_app;
-- Responsable proposable : membre actif de l'équipe (administration ou moniteur), lu pour qui gère les cours.
CREATE FUNCTION drivy.course_staff_active(school uuid,member uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.can_manage_courses(school) AND EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
  WHERE m.school_id=school AND m.id=member AND m.status='ACTIVE' AND p.status='ACTIVE' AND m.roles&&ARRAY['ADMIN','INSTRUCTOR']::text[])
$$;
REVOKE ALL ON FUNCTION drivy.course_staff_active(uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.course_staff_active(uuid,uuid) TO drivy_app;

-- RLS. Le propriétaire de migration garde la lecture (convention des migrations précédentes).
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['course_type','course_policy_version','course_series','course_occurrence','course_enrollment','course_waitlist_entry',
  'course_seat_offer','course_attendance','course_payment_record','course_completion','course_event_outbox'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY course_owner_all ON drivy.%I TO %I USING(true) WITH CHECK(true)',t,current_user);
 END LOOP;
END $$;
-- Types : communs lisibles par tout membre ; personnalisés par leur école ; écriture par la gestion des cours.
CREATE POLICY course_type_read ON drivy.course_type FOR SELECT TO drivy_app
 USING(school_id IS NULL OR drivy.current_school_member(school_id));
CREATE POLICY course_type_insert ON drivy.course_type FOR INSERT TO drivy_app
 WITH CHECK(school_id IS NOT NULL AND drivy.can_manage_courses(school_id) AND created_by=nullif(current_setting('app.membership_id',true),'')::uuid);
CREATE POLICY course_type_update ON drivy.course_type FOR UPDATE TO drivy_app
 USING(school_id IS NOT NULL AND drivy.can_manage_courses(school_id)) WITH CHECK(school_id IS NOT NULL AND drivy.can_manage_courses(school_id));
CREATE POLICY course_policy_read ON drivy.course_policy_version FOR SELECT TO drivy_app USING(drivy.current_school_member(school_id));
CREATE POLICY course_policy_insert ON drivy.course_policy_version FOR INSERT TO drivy_app
 WITH CHECK(drivy.can_manage_courses(school_id) AND created_by=nullif(current_setting('app.membership_id',true),'')::uuid);
-- Séries : un brouillon reste au personnel qui gère les cours ou à son formateur responsable ; une série publiée est visible de l'école.
CREATE POLICY course_series_read ON drivy.course_series FOR SELECT TO drivy_app USING(drivy.current_school_member(school_id)
 AND (status<>'DRAFT' OR drivy.can_manage_courses(school_id) OR responsible_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid));
CREATE POLICY course_series_insert ON drivy.course_series FOR INSERT TO drivy_app
 WITH CHECK(drivy.can_manage_courses(school_id) AND created_by=nullif(current_setting('app.membership_id',true),'')::uuid AND status='DRAFT');
CREATE POLICY course_series_update ON drivy.course_series FOR UPDATE TO drivy_app
 USING(drivy.can_manage_courses(school_id)) WITH CHECK(drivy.can_manage_courses(school_id));
CREATE POLICY course_occurrence_read ON drivy.course_occurrence FOR SELECT TO drivy_app
 USING(EXISTS(SELECT 1 FROM drivy.course_series s WHERE s.id=series_id AND s.school_id=course_occurrence.school_id));
CREATE POLICY course_occurrence_write ON drivy.course_occurrence FOR ALL TO drivy_app
 USING(drivy.can_manage_courses(school_id) AND EXISTS(SELECT 1 FROM drivy.course_series s WHERE s.id=series_id AND s.status='DRAFT'))
 WITH CHECK(drivy.can_manage_courses(school_id) AND EXISTS(SELECT 1 FROM drivy.course_series s WHERE s.id=series_id AND s.status='DRAFT'));
-- Inscriptions, file, propositions et faits : l'élève voit les siens, le personnel qui gère les cours voit ceux de l'école.
-- Écritures ouvertes par les lots suivants (#39–#42, #81, #82) : aucune politique d'écriture applicative ici.
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['course_enrollment','course_waitlist_entry','course_completion'] LOOP
  EXECUTE format('CREATE POLICY course_fact_read ON drivy.%I FOR SELECT TO drivy_app USING(drivy.can_manage_courses(school_id) OR EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.id=learner_id AND l.school_id=%I.school_id AND l.person_id=nullif(current_setting(''app.person_id'',true),'''')::uuid))',t,t);
 END LOOP;
END $$;
CREATE POLICY course_offer_read ON drivy.course_seat_offer FOR SELECT TO drivy_app USING(drivy.can_manage_courses(school_id)
 OR EXISTS(SELECT 1 FROM drivy.course_waitlist_entry w WHERE w.id=entry_id AND w.school_id=course_seat_offer.school_id));
CREATE POLICY course_attendance_read ON drivy.course_attendance FOR SELECT TO drivy_app USING(drivy.can_manage_courses(school_id)
 OR EXISTS(SELECT 1 FROM drivy.course_enrollment e WHERE e.id=enrollment_id AND e.school_id=course_attendance.school_id));
CREATE POLICY course_payment_read ON drivy.course_payment_record FOR SELECT TO drivy_app USING(drivy.can_manage_courses(school_id)
 OR EXISTS(SELECT 1 FROM drivy.course_enrollment e WHERE e.id=enrollment_id AND e.school_id=course_payment_record.school_id));
CREATE POLICY course_outbox_insert ON drivy.course_event_outbox FOR INSERT TO drivy_app WITH CHECK(drivy.can_manage_courses(school_id));
-- Occupations des séances : lues et écrites par la gestion des cours ; les politiques des leçons restent inchangées.
CREATE POLICY reservation_course_read ON drivy.reservation FOR SELECT TO drivy_app
 USING(course_occurrence_id IS NOT NULL AND drivy.can_manage_courses(school_id));
CREATE POLICY reservation_course_insert ON drivy.reservation FOR INSERT TO drivy_app
 WITH CHECK(course_occurrence_id IS NOT NULL AND drivy.can_manage_courses(school_id));
CREATE POLICY reservation_course_update ON drivy.reservation FOR UPDATE TO drivy_app
 USING(course_occurrence_id IS NOT NULL AND drivy.can_manage_courses(school_id)) WITH CHECK(course_occurrence_id IS NOT NULL);
CREATE POLICY course_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.can_manage_courses(school_id) AND command_type IN(
 'CREATE_COURSE_TYPE','UPDATE_COURSE_TYPE','SAVE_COURSE_POLICY','CREATE_COURSE_SERIES','UPDATE_COURSE_SERIES','PUBLISH_COURSE_SERIES','CHANGE_COURSE_CAPACITY'));
CREATE POLICY course_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.can_manage_courses(school_id) AND action IN(
 'CourseTypeCreated','CourseTypeUpdated','CoursePolicySaved','CourseSeriesCreated','CourseSeriesUpdated','CourseSeriesPublished','CourseCapacityChanged'));

GRANT SELECT ON drivy.course_type,drivy.course_policy_version,drivy.course_series,drivy.course_occurrence,drivy.course_enrollment,drivy.course_waitlist_entry,
 drivy.course_seat_offer,drivy.course_attendance,drivy.course_payment_record,drivy.course_completion TO drivy_app;
GRANT INSERT ON drivy.course_type,drivy.course_policy_version,drivy.course_series,drivy.course_occurrence,drivy.course_event_outbox TO drivy_app;
GRANT DELETE ON drivy.course_occurrence TO drivy_app;
GRANT UPDATE(title,description,version,archived_at) ON drivy.course_type TO drivy_app;
GRANT UPDATE(version,status,type_id,title,description,location,conditions,teaching_language,responsible_membership_id,capacity,min_participants,
 policy_version,self_cancel_hours,updated_at,published_at) ON drivy.course_series TO drivy_app;
