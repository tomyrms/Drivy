-- F03/R07 : contrôle humain du permis, attesté par un membre habilité (grant permit_review).
-- Append-only : une nouvelle décision remplace l'état courant sans réécrire la précédente.
-- Aucune pièce F09 n'existe encore : document_id reste nul tant que le circuit documentaire n'est pas livré.
CREATE TABLE drivy.permit_check (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,training_id uuid NOT NULL,
 version integer NOT NULL DEFAULT 1 CHECK(version=1),document_id uuid CONSTRAINT permit_document_not_ready CHECK(document_id IS NULL),
 physical_seen boolean NOT NULL,category_code text NOT NULL CHECK(char_length(category_code) BETWEEN 1 AND 30),valid_until date,
 decision text NOT NULL CHECK(decision IN('APPROVED','REJECTED')),reviewer_membership_id uuid NOT NULL,
 reviewed_at timestamptz NOT NULL DEFAULT statement_timestamp(),reason text CHECK(reason IS NULL OR char_length(reason)<=2000),
 operation_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,training_id) REFERENCES drivy.training(school_id,id),
 FOREIGN KEY(school_id,reviewer_membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(decision<>'APPROVED' OR physical_seen OR document_id IS NOT NULL),
 CHECK(decision<>'REJECTED' OR char_length(btrim(coalesce(reason,'')))>0)
);
CREATE INDEX permit_check_current ON drivy.permit_check(training_id,reviewed_at DESC,created_at DESC,id DESC);
CREATE INDEX permit_check_page ON drivy.permit_check(school_id,training_id,created_at,id);
ALTER TABLE drivy.permit_check ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.permit_check FORCE ROW LEVEL SECURITY;
CREATE POLICY permit_owner_read ON drivy.permit_check FOR SELECT TO CURRENT_USER USING(true);

-- Contrôleur : ADMIN ou moniteur actuellement affecté, avec le grant explicite (jamais implicite par rôle).
CREATE FUNCTION drivy.permit_review_allowed(training uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.membership m ON m.school_id=t.school_id
 AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND 'permit_review'=ANY(m.grants) AND
 ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=t.school_id
 AND a.training_id=t.id AND a.instructor_membership_id=m.id AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))))
$$;
-- Lecture : ADMIN, élève sur sa formation, moniteur affecté habilité.
CREATE FUNCTION drivy.permit_read_allowed(training uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.permit_review_allowed(training) OR EXISTS(SELECT 1 FROM drivy.training t JOIN drivy.learner_profile l ON l.school_id=t.school_id AND l.id=t.learner_id
 JOIN drivy.membership m ON m.school_id=t.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
 WHERE t.id=training AND drivy.current_school_member(t.school_id) AND m.status='ACTIVE' AND
 ('ADMIN'=ANY(m.roles) OR ('LEARNER'=ANY(m.roles) AND l.person_id=m.person_id)))
$$;
-- Avertissement de leçon : faux seulement si la décision courante est APPROVED, de la catégorie actuelle de la
-- formation et non expirée à la date locale de la leçon. Aucun contrôle ou une date absente ne valent jamais approbation.
CREATE FUNCTION drivy.lesson_permit_warning(training uuid,lesson_date date) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT NOT coalesce((SELECT c.decision='APPROVED' AND c.category_code=o.category_code AND (c.valid_until IS NULL OR c.valid_until>=lesson_date)
  FROM drivy.training t JOIN drivy.offering_version o ON o.school_id=t.school_id AND o.id=t.offering_id
  JOIN drivy.permit_check c ON c.school_id=t.school_id AND c.training_id=t.id
  WHERE t.id=training AND drivy.current_school_member(t.school_id)
  ORDER BY c.reviewed_at DESC,c.created_at DESC,c.id DESC LIMIT 1),false)
$$;
REVOKE ALL ON FUNCTION drivy.permit_review_allowed(uuid),drivy.permit_read_allowed(uuid),drivy.lesson_permit_warning(uuid,date) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.permit_review_allowed(uuid),drivy.permit_read_allowed(uuid),drivy.lesson_permit_warning(uuid,date) TO drivy_app;

CREATE POLICY permit_read ON drivy.permit_check FOR SELECT TO drivy_app USING(drivy.permit_read_allowed(training_id));
CREATE POLICY permit_insert ON drivy.permit_check FOR INSERT TO drivy_app WITH CHECK(drivy.permit_review_allowed(training_id)
 AND reviewer_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.school_id=permit_check.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
GRANT SELECT,INSERT ON drivy.permit_check TO drivy_app;

-- If-Match d'AP30 vise la formation : la décision incrémente sa version dans le même commit.
CREATE POLICY permit_training_version ON drivy.training FOR UPDATE TO drivy_app USING(drivy.permit_review_allowed(id)) WITH CHECK(drivy.permit_review_allowed(id));
GRANT UPDATE(version) ON drivy.training TO drivy_app;

CREATE POLICY permit_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type='RECORD_PERMIT_CHECK');
CREATE POLICY permit_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action='PermitReviewed');
