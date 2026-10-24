-- Cours collectifs : appel (#42), règlements sur place (#81), accomplissement validé (#82).
-- Contrat : docs/implementation/cours-collectifs-faits-42-81-82.md. Trois faits distincts : aucun ne déduit l'autre.
-- Aucune donnée existante n'est créée : personne n'est présumé présent, payé ou formé.

-- Droits : appel = gestion des cours, droit TAKE_ATTENDANCE, ou formateur de la séance ; règlement = gestion des cours ou
-- droit cash_record ; validation = administrateur ou droit VALIDATE_REQUIREMENT.
CREATE FUNCTION drivy.course_can_take_attendance(occurrence uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.course_occurrence o JOIN drivy.membership m ON m.school_id=o.school_id JOIN drivy.person p ON p.id=m.person_id
  WHERE o.id=occurrence AND drivy.current_school_member(o.school_id) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND m.status='ACTIVE' AND p.status='ACTIVE' AND m.roles&&ARRAY['ADMIN','INSTRUCTOR']::text[]
  AND (drivy.can_manage_courses(o.school_id) OR 'TAKE_ATTENDANCE'=ANY(m.grants) OR m.id=o.instructor_membership_id))
$$;
CREATE FUNCTION drivy.course_can_record_payment(school uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT drivy.can_manage_courses(school) OR EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
  WHERE m.school_id=school AND drivy.current_school_member(school) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND m.status='ACTIVE' AND p.status='ACTIVE' AND m.roles&&ARRAY['ADMIN','INSTRUCTOR']::text[] AND 'cash_record'=ANY(m.grants))
$$;
CREATE FUNCTION drivy.course_can_validate(school uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
  WHERE m.school_id=school AND drivy.current_school_member(school) AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND m.status='ACTIVE' AND p.status='ACTIVE' AND ('ADMIN'=ANY(m.roles) OR ('INSTRUCTOR'=ANY(m.roles) AND 'VALIDATE_REQUIREMENT'=ANY(m.grants))))
$$;

-- Historique : chaque saisie ou correction de présence et chaque règlement ou annulation de règlement est conservé.
CREATE TABLE drivy.course_attendance_history (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 school_id uuid NOT NULL, enrollment_id uuid NOT NULL, occurrence_id uuid NOT NULL,
 status text NOT NULL CHECK(status IN('PRESENT','ABSENT','EXCUSED')), version integer NOT NULL,
 recorded_by uuid NOT NULL, recorded_at timestamptz NOT NULL DEFAULT now(), note text CHECK(char_length(note)<=500),
 FOREIGN KEY(school_id,enrollment_id) REFERENCES drivy.course_enrollment(school_id,id),
 FOREIGN KEY(school_id,occurrence_id) REFERENCES drivy.course_occurrence(school_id,id),
 FOREIGN KEY(school_id,recorded_by) REFERENCES drivy.membership(school_id,id)
);
ALTER TABLE drivy.course_payment_record ADD COLUMN voided_by uuid, ADD COLUMN void_reason text CHECK(char_length(void_reason)<=1000),
 ADD COLUMN note text CHECK(char_length(note)<=500),
 ADD CONSTRAINT course_payment_voided_by FOREIGN KEY(school_id,voided_by) REFERENCES drivy.membership(school_id,id),
 ADD CONSTRAINT course_payment_void_complete CHECK((voided_at IS NULL)=(voided_by IS NULL));
ALTER TABLE drivy.course_completion ADD COLUMN revoked_by uuid, ADD COLUMN revoke_reason text CHECK(char_length(revoke_reason)<=1000),
 ADD COLUMN note text CHECK(char_length(note)<=1000),
 ADD CONSTRAINT course_completion_revoked_by FOREIGN KEY(school_id,revoked_by) REFERENCES drivy.membership(school_id,id);

ALTER TABLE drivy.course_attendance_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.course_attendance_history FORCE ROW LEVEL SECURITY;
DO $$ BEGIN EXECUTE format('CREATE POLICY course_owner_all ON drivy.course_attendance_history TO %I USING(true) WITH CHECK(true)',current_user); END $$;
CREATE POLICY course_attendance_history_read ON drivy.course_attendance_history FOR SELECT TO drivy_app USING(drivy.can_manage_courses(school_id)
 OR drivy.course_can_take_attendance(occurrence_id));
GRANT SELECT ON drivy.course_attendance_history TO drivy_app;
-- La lecture des présences et règlements s'étend au formateur de la séance et aux droits dédiés.
CREATE POLICY course_attendance_staff_read ON drivy.course_attendance FOR SELECT TO drivy_app USING(drivy.course_can_take_attendance(occurrence_id));
CREATE POLICY course_payment_staff_read ON drivy.course_payment_record FOR SELECT TO drivy_app USING(drivy.course_can_record_payment(school_id));

-- Le formateur d'une séance voit les inscriptions de cette série (pour l'appel) et le nom affiché des inscrits.
CREATE POLICY course_enrollment_instructor_read ON drivy.course_enrollment FOR SELECT TO drivy_app USING(EXISTS(SELECT 1 FROM drivy.course_occurrence o
 WHERE o.series_id=course_enrollment.series_id AND drivy.course_can_take_attendance(o.id)) OR drivy.course_can_record_payment(school_id) OR drivy.course_can_validate(school_id));
CREATE FUNCTION drivy.lesson_learner_display_name_for_course(enrollment uuid) RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.display_name FROM drivy.course_enrollment e JOIN drivy.learner_profile l ON l.id=e.learner_id JOIN drivy.person p ON p.id=l.person_id
 WHERE e.id=enrollment AND (drivy.can_manage_courses(e.school_id) OR drivy.course_can_record_payment(e.school_id) OR drivy.course_can_validate(e.school_id)
  OR EXISTS(SELECT 1 FROM drivy.course_occurrence o WHERE o.series_id=e.series_id AND drivy.course_can_take_attendance(o.id)))
$$;
REVOKE ALL ON FUNCTION drivy.lesson_learner_display_name_for_course(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.lesson_learner_display_name_for_course(uuid) TO drivy_app;

-- Exigences d'une inscription : séances obligatoires passées marquées PRESENT. Une séance obligatoire future ou sans appel
-- n'est jamais présumée. Retour : nombre requis, présent, manquant.
CREATE FUNCTION drivy.course_requirements(enrollment uuid,OUT required integer,OUT present integer,OUT missing integer) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT count(*) FILTER (WHERE o.attendance_required)::integer,
  count(*) FILTER (WHERE o.attendance_required AND a.status='PRESENT')::integer,
  count(*) FILTER (WHERE o.attendance_required AND a.status IS DISTINCT FROM 'PRESENT')::integer
 FROM drivy.course_enrollment e JOIN drivy.course_occurrence o ON o.series_id=e.series_id
 LEFT JOIN drivy.course_attendance a ON a.enrollment_id=e.id AND a.occurrence_id=o.id
 WHERE e.id=enrollment
$$;

-- Appel (#42) : une présence par inscription et séance, versionnée. Pas de saisie avant le début de la séance, pas sur une
-- inscription annulée avant la séance, pas sur une série brouillon ou annulée avant la séance. Correction = nouvelle version
-- avec version attendue ; l'historique garde chaque saisie.
CREATE FUNCTION drivy.course_record_attendance(enrollment uuid,occurrence uuid,new_status text,expected integer,note text) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE e drivy.course_enrollment; o drivy.course_occurrence; actor drivy.membership; current drivy.course_attendance; next_version integer;
BEGIN
 SELECT * INTO o FROM drivy.course_occurrence WHERE id=occurrence;
 IF NOT FOUND OR NOT drivy.course_can_take_attendance(occurrence) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 PERFORM 1 FROM drivy.course_series WHERE id=o.series_id FOR UPDATE;
 SELECT * INTO e FROM drivy.course_enrollment WHERE id=enrollment AND series_id=o.series_id;
 IF NOT FOUND THEN PERFORM drivy.course_fail('NOT_FOUND'); END IF;
 IF new_status NOT IN('PRESENT','ABSENT','EXCUSED') THEN PERFORM drivy.course_fail('INVALID_REQUEST'); END IF;
 IF o.starts_at>statement_timestamp() THEN PERFORM drivy.course_fail('COURSE_OCCURRENCE_NOT_STARTED'); END IF;
 IF e.status='CANCELLED' AND e.cancelled_at<=o.starts_at THEN PERFORM drivy.course_fail('COURSE_ENROLLMENT_CLOSED'); END IF;
 actor:=drivy.course_actor_membership(o.school_id);
 SELECT * INTO current FROM drivy.course_attendance WHERE enrollment_id=enrollment AND occurrence_id=occurrence FOR UPDATE;
 IF FOUND THEN
  IF expected IS DISTINCT FROM current.version THEN PERFORM drivy.course_fail('VERSION_CONFLICT'); END IF;
  next_version:=current.version+1;
  UPDATE drivy.course_attendance SET status=new_status,version=next_version,recorded_by=actor.id,recorded_at=statement_timestamp() WHERE enrollment_id=enrollment AND occurrence_id=occurrence;
 ELSE
  IF expected IS NOT NULL THEN PERFORM drivy.course_fail('VERSION_CONFLICT'); END IF;
  next_version:=1;
  INSERT INTO drivy.course_attendance(school_id,enrollment_id,occurrence_id,status,version,recorded_by) VALUES(o.school_id,enrollment,occurrence,new_status,1,actor.id);
 END IF;
 INSERT INTO drivy.course_attendance_history(school_id,enrollment_id,occurrence_id,status,version,recorded_by,note) VALUES(o.school_id,enrollment,occurrence,new_status,next_version,actor.id,nullif(btrim(note),''));
 RETURN next_version;
END $$;

-- Règlement sur place (#81) : fait déclaratif, montant libre (informatif), annulable avec motif, jamais supprimé.
CREATE FUNCTION drivy.course_record_payment(enrollment uuid,amount bigint,note text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE e drivy.course_enrollment; actor drivy.membership; payment uuid;
BEGIN
 SELECT * INTO e FROM drivy.course_enrollment WHERE id=enrollment;
 IF NOT FOUND OR NOT drivy.course_can_record_payment(e.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 IF amount IS NULL OR amount<0 THEN PERFORM drivy.course_fail('INVALID_REQUEST'); END IF;
 actor:=drivy.course_actor_membership(e.school_id);
 PERFORM 1 FROM drivy.course_enrollment WHERE id=enrollment FOR UPDATE;
 INSERT INTO drivy.course_payment_record(school_id,enrollment_id,amount_cents,recorded_by,note) VALUES(e.school_id,enrollment,amount,actor.id,nullif(btrim(note),'')) RETURNING id INTO payment;
 RETURN payment;
END $$;
CREATE FUNCTION drivy.course_void_payment(payment uuid,reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE p drivy.course_payment_record; actor drivy.membership;
BEGIN
 SELECT * INTO p FROM drivy.course_payment_record WHERE id=payment FOR UPDATE;
 IF NOT FOUND OR NOT drivy.course_can_record_payment(p.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 IF p.voided_at IS NOT NULL THEN PERFORM drivy.course_fail('COURSE_PAYMENT_VOIDED'); END IF;
 IF reason IS NULL OR btrim(reason)='' THEN PERFORM drivy.course_fail('COURSE_REASON_REQUIRED'); END IF;
 actor:=drivy.course_actor_membership(p.school_id);
 UPDATE drivy.course_payment_record SET voided_at=statement_timestamp(),voided_by=actor.id,void_reason=btrim(reason) WHERE id=payment;
END $$;

-- Validation (#82) : explicite, par une personne habilitée, seulement si toutes les séances obligatoires sont marquées
-- présentes. Jamais déduite du paiement. Un accomplissement courant par élève et type (index unique) : une double
-- validation est refusée. Révocation avec motif, historique gardé. Valider retire l'élève des files à venir du même type.
CREATE FUNCTION drivy.course_validate(enrollment uuid,note text) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE e drivy.course_enrollment; s drivy.course_series; actor drivy.membership; req record; completion uuid;
BEGIN
 SELECT * INTO e FROM drivy.course_enrollment WHERE id=enrollment;
 IF NOT FOUND OR NOT drivy.course_can_validate(e.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 SELECT * INTO s FROM drivy.course_series WHERE id=e.series_id FOR UPDATE;
 IF e.status<>'ACTIVE' THEN PERFORM drivy.course_fail('COURSE_ENROLLMENT_CLOSED'); END IF;
 SELECT * INTO req FROM drivy.course_requirements(enrollment);
 IF req.required=0 THEN PERFORM drivy.course_fail('COURSE_NO_REQUIRED_OCCURRENCE'); END IF;
 IF req.missing>0 THEN PERFORM drivy.course_fail('COURSE_REQUIREMENTS_MISSING'); END IF;
 IF EXISTS(SELECT 1 FROM drivy.course_completion WHERE learner_id=e.learner_id AND type_id=s.type_id AND revoked_at IS NULL) THEN PERFORM drivy.course_fail('COURSE_ALREADY_COMPLETED'); END IF;
 actor:=drivy.course_actor_membership(e.school_id);
 INSERT INTO drivy.course_completion(school_id,learner_id,type_id,series_id,validated_by,note) VALUES(e.school_id,e.learner_id,s.type_id,s.id,actor.id,nullif(btrim(note),'')) RETURNING id INTO completion;
 UPDATE drivy.course_seat_offer o SET status='REVOKED',resolved_at=statement_timestamp() FROM drivy.course_waitlist_entry w JOIN drivy.course_series x ON x.id=w.series_id
  WHERE o.entry_id=w.id AND o.status='ACTIVE' AND w.learner_id=e.learner_id AND x.type_id=s.type_id;
 UPDATE drivy.course_waitlist_entry w SET status='REMOVED',resolved_at=statement_timestamp() FROM drivy.course_series x
  WHERE x.id=w.series_id AND w.learner_id=e.learner_id AND x.type_id=s.type_id AND w.status IN('WAITING','OFFERED');
 INSERT INTO drivy.course_event_outbox(school_id,series_id,series_version,event_type,target_learner_id,operation_id)
  VALUES(e.school_id,s.id,s.version,'CourseCompleted:'||completion,e.learner_id,gen_random_uuid());
 RETURN completion;
END $$;
CREATE FUNCTION drivy.course_revoke_completion(completion uuid,reason text) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
DECLARE c drivy.course_completion; actor drivy.membership;
BEGIN
 SELECT * INTO c FROM drivy.course_completion WHERE id=completion FOR UPDATE;
 IF NOT FOUND OR NOT drivy.course_can_validate(c.school_id) THEN PERFORM drivy.course_fail('COURSE_ACCESS_REQUIRED'); END IF;
 IF c.revoked_at IS NOT NULL THEN PERFORM drivy.course_fail('COURSE_COMPLETION_REVOKED'); END IF;
 IF reason IS NULL OR btrim(reason)='' THEN PERFORM drivy.course_fail('COURSE_REASON_REQUIRED'); END IF;
 actor:=drivy.course_actor_membership(c.school_id);
 UPDATE drivy.course_completion SET revoked_at=statement_timestamp(),revoked_by=actor.id,revoke_reason=btrim(reason) WHERE id=completion;
END $$;

DO $$ DECLARE f text; BEGIN
 FOREACH f IN ARRAY ARRAY['course_can_take_attendance(uuid)','course_can_record_payment(uuid)','course_can_validate(uuid)','course_requirements(uuid)',
  'course_record_attendance(uuid,uuid,text,integer,text)','course_record_payment(uuid,bigint,text)','course_void_payment(uuid,text)',
  'course_validate(uuid,text)','course_revoke_completion(uuid,text)'] LOOP
  EXECUTE format('REVOKE ALL ON FUNCTION drivy.%s FROM PUBLIC',f);EXECUTE format('GRANT EXECUTE ON FUNCTION drivy.%s TO drivy_app',f);
 END LOOP;
END $$;

-- Reçus et audit : la fonction relit le droit précis ; ici, la porte reste le personnel de l'école.
CREATE POLICY course_facts_operation_insert ON drivy.operation FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
 'RECORD_COURSE_ATTENDANCE','RECORD_COURSE_PAYMENT','VOID_COURSE_PAYMENT','VALIDATE_COURSE','REVOKE_COURSE_COMPLETION'));
CREATE POLICY course_facts_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app WITH CHECK(drivy.current_school_member(school_id) AND action IN(
 'CourseAttendanceRecorded','CoursePaymentRecorded','CoursePaymentVoided','CourseCompletionValidated','CourseCompletionRevoked'));
