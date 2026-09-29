-- F07/F08 : absence constatée (AP44), correction encadrée d'un résultat (AP50/AP88) et retrait d'un bilan publié (AP57).
-- Les preuves sont append-only ; aucune révision, charge ni absence n'est effacée.
ALTER TABLE drivy.lesson ADD COLUMN no_show_reason text CHECK(no_show_reason IS NULL OR char_length(btrim(no_show_reason)) BETWEEN 1 AND 1000);
GRANT UPDATE(no_show_reason) ON drivy.lesson TO drivy_app;

-- Retrait de publication : le pointeur courant est effacé, la révision reste conservée pour le personnel affecté.
CREATE TABLE drivy.report_publication_withdrawal (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,revision_id uuid NOT NULL,
 revision_sequence integer NOT NULL CHECK(revision_sequence>0),publication_version integer NOT NULL CHECK(publication_version>0),
 reason text NOT NULL CHECK(char_length(btrim(reason)) BETWEEN 1 AND 1000),actor_membership_id uuid NOT NULL,operation_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),UNIQUE(lesson_id,publication_version),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 FOREIGN KEY(school_id,revision_id) REFERENCES drivy.report_revision(school_id,id),FOREIGN KEY(school_id,actor_membership_id) REFERENCES drivy.membership(school_id,id)
);
-- Approbation pédagogique d'une correction : contenu exact (hash), versions liées, 10 minutes, consommation unique.
CREATE TABLE drivy.outcome_approval (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,version integer NOT NULL DEFAULT 1 CHECK(version IN(1,2)),
 lesson_version integer NOT NULL CHECK(lesson_version>0),account_version integer NOT NULL CHECK(account_version>0),publication_version integer NOT NULL CHECK(publication_version>=0),
 proposal_hash text NOT NULL CHECK(proposal_hash ~ '^[0-9a-f]{64}$'),approved_by_membership_id uuid NOT NULL,expires_at timestamptz NOT NULL,
 consumed_at timestamptz,consumed_operation_id uuid,operation_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),
 UNIQUE(school_id,id),FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),
 FOREIGN KEY(school_id,approved_by_membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(expires_at>created_at),CHECK((consumed_at IS NULL)=(consumed_operation_id IS NULL) AND (consumed_at IS NULL)=(version=1))
);
-- Historique de chaque correction : l'état précédent reste lisible par l'administration.
CREATE TABLE drivy.lesson_outcome_correction (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),school_id uuid NOT NULL,lesson_id uuid NOT NULL,
 from_status text NOT NULL CHECK(from_status IN('COMPLETED','CANCELLED','NO_SHOW')),to_status text NOT NULL CHECK(to_status IN('PLANNED','COMPLETED','CANCELLED','NO_SHOW')),
 previous_actual_start timestamptz,previous_actual_end timestamptz,previous_revision_id uuid,reason text NOT NULL CHECK(char_length(btrim(reason)) BETWEEN 1 AND 1000),
 approval_id uuid,reversed_charge_cents bigint NOT NULL DEFAULT 0 CHECK(reversed_charge_cents>=0),actor_membership_id uuid NOT NULL,operation_id uuid NOT NULL,
 created_at timestamptz NOT NULL DEFAULT now(),UNIQUE(school_id,id),CHECK(from_status<>to_status),
 FOREIGN KEY(school_id,lesson_id) REFERENCES drivy.lesson(school_id,id),FOREIGN KEY(school_id,approval_id) REFERENCES drivy.outcome_approval(school_id,id),
 FOREIGN KEY(school_id,actor_membership_id) REFERENCES drivy.membership(school_id,id)
);
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['report_publication_withdrawal','outcome_approval','lesson_outcome_correction'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',t);EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',t);
  EXECUTE format('CREATE POLICY outcome_owner ON drivy.%I FOR ALL TO %I USING(true) WITH CHECK(true)',t,current_user);
 END LOOP;
END $$;
-- Rôle pédagogique actuel du membre donné sur la leçon (approbateur encore habilité au moment de l'exécution).
CREATE FUNCTION drivy.outcome_approver_current(lesson uuid,approver uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id AND m.id=approver AND m.id=l.instructor_membership_id
 JOIN drivy.person p ON p.id=m.person_id WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND m.status='ACTIVE' AND p.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles)
 AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a WHERE a.school_id=l.school_id AND a.training_id=l.training_id AND a.instructor_membership_id=m.id
 AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))
$$;
-- Une révision retirée n'est plus lisible par l'élève ; le moniteur actuellement affecté conserve l'historique.
CREATE FUNCTION drivy.report_revision_visible(lesson uuid,seq integer) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT NOT EXISTS(SELECT 1 FROM drivy.report_publication_withdrawal w WHERE w.lesson_id=lesson AND w.revision_sequence>=seq)
 OR EXISTS(SELECT 1 FROM drivy.lesson l JOIN drivy.membership m ON m.school_id=l.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND m.status='ACTIVE' AND 'INSTRUCTOR'=ANY(m.roles) AND EXISTS(SELECT 1 FROM drivy.instructor_assignment a
  WHERE a.school_id=l.school_id AND a.training_id=l.training_id AND a.instructor_membership_id=m.id AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())))
$$;
-- Numéro de la révision courante, sans exposer son texte (l'administration seule ne lit pas le bilan).
CREATE FUNCTION drivy.lesson_current_revision_sequence(lesson uuid) RETURNS integer LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT r.sequence FROM drivy.lesson l JOIN drivy.report_revision r ON r.school_id=l.school_id AND r.id=l.current_published_revision_id
 WHERE l.id=lesson AND drivy.current_school_member(l.school_id) AND drivy.lesson_access(l.training_id,l.instructor_membership_id,true)
$$;
REVOKE ALL ON FUNCTION drivy.outcome_approver_current(uuid,uuid),drivy.report_revision_visible(uuid,integer),drivy.lesson_current_revision_sequence(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.outcome_approver_current(uuid,uuid),drivy.report_revision_visible(uuid,integer),drivy.lesson_current_revision_sequence(uuid) TO drivy_app;
CREATE POLICY revision_withdrawn_scope ON drivy.report_revision AS RESTRICTIVE FOR SELECT TO drivy_app USING(drivy.report_revision_visible(lesson_id,sequence));

CREATE POLICY withdrawal_read ON drivy.report_publication_withdrawal FOR SELECT TO drivy_app USING(drivy.report_lesson_read(lesson_id) OR drivy.is_current_school_admin(school_id));
CREATE POLICY withdrawal_insert ON drivy.report_publication_withdrawal FOR INSERT TO drivy_app WITH CHECK((drivy.report_lesson_author(lesson_id) OR drivy.is_current_school_admin(school_id))
 AND actor_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.school_id=report_publication_withdrawal.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY approval_read ON drivy.outcome_approval FOR SELECT TO drivy_app USING(drivy.report_lesson_author(lesson_id) OR drivy.is_current_school_admin(school_id));
CREATE POLICY approval_insert ON drivy.outcome_approval FOR INSERT TO drivy_app WITH CHECK(drivy.report_lesson_author(lesson_id)
 AND approved_by_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.school_id=outcome_approval.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
CREATE POLICY approval_consume ON drivy.outcome_approval FOR UPDATE TO drivy_app USING(drivy.is_current_school_admin(school_id)) WITH CHECK(drivy.is_current_school_admin(school_id));
CREATE POLICY correction_read ON drivy.lesson_outcome_correction FOR SELECT TO drivy_app USING(drivy.is_current_school_admin(school_id));
CREATE POLICY correction_insert ON drivy.lesson_outcome_correction FOR INSERT TO drivy_app WITH CHECK(drivy.is_current_school_admin(school_id)
 AND actor_membership_id IN(SELECT m.id FROM drivy.membership m WHERE m.school_id=lesson_outcome_correction.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'));
GRANT SELECT,INSERT ON drivy.report_publication_withdrawal,drivy.outcome_approval,drivy.lesson_outcome_correction TO drivy_app;
GRANT UPDATE(version,consumed_at,consumed_operation_id) ON drivy.outcome_approval TO drivy_app;

-- Compte de leçon des issues sans réalisation : il existe, sans charge ni pénalité inventée (R14/R23).
CREATE POLICY account_insert_closed ON drivy.lesson_account FOR INSERT TO drivy_app WITH CHECK(EXISTS(SELECT 1 FROM drivy.lesson l
 WHERE l.school_id=lesson_account.school_id AND l.id=lesson_id AND l.status IN('CANCELLED','NO_SHOW') AND drivy.lesson_access(l.training_id,l.instructor_membership_id,true)));
CREATE POLICY account_admin_version ON drivy.lesson_account FOR UPDATE TO drivy_app USING(drivy.is_current_school_admin(school_id)) WITH CHECK(drivy.is_current_school_admin(school_id));
GRANT UPDATE(version) ON drivy.lesson_account TO drivy_app;
-- Contre-écriture d'une charge par l'administration lors d'une correction motivée.
CREATE POLICY charge_correction_insert ON drivy.charge_entry FOR INSERT TO drivy_app WITH CHECK(kind='REVERSAL' AND amount_signed_cents<0 AND drivy.is_current_school_admin(school_id)
 AND EXISTS(SELECT 1 FROM drivy.lesson_account a WHERE a.school_id=charge_entry.school_id AND a.id=account_id));
INSERT INTO drivy.lesson_account(school_id,lesson_id,planned_price_cents)
 SELECT l.school_id,l.id,l.price_cents_snapshot FROM drivy.lesson l WHERE l.status IN('CANCELLED','NO_SHOW')
 AND NOT EXISTS(SELECT 1 FROM drivy.lesson_account a WHERE a.lesson_id=l.id);

CREATE POLICY outcome_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
 'MARK_NO_SHOW','APPROVE_OUTCOME_CORRECTION','CORRECT_OUTCOME','WITHDRAW_REPORT_PUBLICATION'));
CREATE POLICY outcome_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN(
 'LessonMarkedNoShow','OutcomeCorrectionApproved','LessonOutcomeCorrected','ReportPublicationWithdrawn'));
