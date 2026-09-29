-- Une invitation peut porter plusieurs permis. Les choix supplémentaires restent embarqués dans l'invitation,
-- sans cycle de vie indépendant ; les deux colonnes historiques conservent le premier choix et les anciennes invitations.
ALTER TABLE drivy.invitation ADD COLUMN additional_training_intents jsonb NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE drivy.invitation ADD CONSTRAINT invitation_additional_trainings_shape CHECK(
 jsonb_typeof(additional_training_intents)='array' AND jsonb_array_length(additional_training_intents)<=15
 AND (additional_training_intents='[]'::jsonb OR training_offering_id IS NOT NULL));

CREATE FUNCTION drivy.invitation_trainings(i drivy.invitation) RETURNS TABLE(offering_id uuid,instructor_membership_id uuid)
LANGUAGE sql IMMUTABLE SET search_path=pg_catalog,drivy AS $$
 SELECT i.training_offering_id,i.training_instructor_membership_id WHERE i.training_offering_id IS NOT NULL
 UNION ALL SELECT (value->>'offeringId')::uuid,(value->>'instructorMembershipId')::uuid
 FROM jsonb_array_elements(i.additional_training_intents)
$$;
REVOKE ALL ON FUNCTION drivy.invitation_trainings(drivy.invitation) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_trainings(drivy.invitation) TO drivy_app;

-- Les références embarquées ont les mêmes contraintes d'école que les références principales.
CREATE FUNCTION drivy.validate_invitation_trainings() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$
DECLARE choice jsonb; BEGIN
 FOR choice IN SELECT value FROM jsonb_array_elements(NEW.additional_training_intents) LOOP
  IF jsonb_typeof(choice)<>'object' OR (SELECT count(*) FROM jsonb_object_keys(choice))<>2
   OR jsonb_typeof(choice->'offeringId') IS DISTINCT FROM 'string' OR jsonb_typeof(choice->'instructorMembershipId') IS DISTINCT FROM 'string' THEN
   RAISE EXCEPTION 'invalid invitation training' USING ERRCODE='23514';
  END IF;
 END LOOP;
 IF EXISTS(SELECT 1 FROM drivy.invitation_trainings(NEW) t
  LEFT JOIN drivy.offering_version o ON o.id=t.offering_id AND o.school_id=NEW.school_id
  LEFT JOIN drivy.membership m ON m.id=t.instructor_membership_id AND m.school_id=NEW.school_id
  WHERE o.id IS NULL OR m.id IS NULL)
  OR EXISTS(SELECT 1 FROM drivy.invitation_trainings(NEW) GROUP BY offering_id HAVING count(*)>1) THEN
  RAISE EXCEPTION 'invalid invitation training reference' USING ERRCODE='23514';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER invitation_trainings_valid BEFORE INSERT OR UPDATE OF school_id,training_offering_id,training_instructor_membership_id,additional_training_intents
 ON drivy.invitation FOR EACH ROW EXECUTE FUNCTION drivy.validate_invitation_trainings();

-- L'acceptation peut relire et verrouiller les moniteurs choisis et leurs comptes avant tout rattachement.
-- Cette fonction ne révèle que les identifiants prévus par l'invitation désignée par le secret courant.
CREATE FUNCTION drivy.invitation_training_staff() RETURNS TABLE(membership_id uuid,person_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.id,m.person_id FROM drivy.invitation_target() i CROSS JOIN LATERAL drivy.invitation_trainings(i) t
 JOIN drivy.membership m ON m.school_id=i.school_id AND m.id=t.instructor_membership_id
$$;
REVOKE ALL ON FUNCTION drivy.invitation_training_staff() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_training_staff() TO drivy_app;
CREATE POLICY invitation_training_person_read ON drivy.person FOR SELECT TO drivy_app USING(
 EXISTS(SELECT 1 FROM drivy.invitation_training_staff() s WHERE s.person_id=person.id));
CREATE POLICY invitation_training_person_lock ON drivy.person FOR UPDATE TO drivy_app USING(
 EXISTS(SELECT 1 FROM drivy.invitation_training_staff() s WHERE s.person_id=person.id)) WITH CHECK(false);
CREATE POLICY invitation_training_member_read ON drivy.membership FOR SELECT TO drivy_app USING(
 EXISTS(SELECT 1 FROM drivy.invitation_training_staff() s WHERE s.membership_id=membership.id));
CREATE POLICY invitation_training_member_lock ON drivy.membership FOR UPDATE TO drivy_app USING(
 EXISTS(SELECT 1 FROM drivy.invitation_training_staff() s WHERE s.membership_id=membership.id)) WITH CHECK(false);

CREATE OR REPLACE FUNCTION drivy.invitation_code_category(offering uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT o.category_code FROM drivy.offering_version o WHERE o.id=offering AND EXISTS(
  SELECT 1 FROM drivy.invitation_target() i CROSS JOIN LATERAL drivy.invitation_trainings(i) t
  WHERE i.delivery='CODE' AND t.offering_id=o.id)
$$;
CREATE OR REPLACE FUNCTION drivy.invitation_ready_offering(offering uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT n.id FROM drivy.offering_version o JOIN drivy.offering_version n ON n.school_id=o.school_id AND n.offering_key=o.offering_key
 WHERE o.id=offering AND EXISTS(SELECT 1 FROM drivy.invitation_target() i CROSS JOIN LATERAL drivy.invitation_trainings(i) t
  WHERE t.offering_id=o.id AND i.status='ACCEPTED' AND i.accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 AND drivy.catalogue_offering_ready(n.id) ORDER BY n.version DESC LIMIT 1
$$;
CREATE OR REPLACE FUNCTION drivy.invitation_training_allowed(school uuid,learner uuid,offering uuid,instructor uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.invitation_target() i CROSS JOIN LATERAL drivy.invitation_trainings(i) t
  JOIN drivy.learner_profile l ON l.school_id=i.school_id AND l.person_id=i.accepted_by_person_id
  JOIN drivy.offering_version invited ON invited.school_id=i.school_id AND invited.id=t.offering_id
  JOIN drivy.offering_version wanted ON wanted.school_id=i.school_id AND wanted.id=offering AND wanted.offering_key=invited.offering_key
  WHERE i.school_id=school AND i.status='ACCEPTED' AND i.accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND l.id=learner AND (instructor IS NULL OR t.instructor_membership_id=instructor))
$$;
