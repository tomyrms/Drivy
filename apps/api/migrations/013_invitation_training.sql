-- Inviter un élève avec sa formation (décision du porteur du 28 septembre 2026) : l'invitation porte l'offre et le moniteur,
-- la formation et l'affectation sont créées à l'acceptation, dans la même transaction que le dossier.
ALTER TABLE drivy.invitation ADD COLUMN training_offering_id uuid REFERENCES drivy.offering_version(id);
ALTER TABLE drivy.invitation ADD COLUMN training_instructor_membership_id uuid;
ALTER TABLE drivy.invitation ADD FOREIGN KEY(school_id,training_instructor_membership_id) REFERENCES drivy.membership(school_id,id);
ALTER TABLE drivy.invitation ADD CONSTRAINT invitation_training_complete CHECK(
 (training_offering_id IS NULL)=(training_instructor_membership_id IS NULL) AND (training_offering_id IS NULL OR roles=ARRAY['LEARNER']));

-- La personne qui vient d'accepter n'ouvre que la formation portée par son invitation, pour son propre dossier.
CREATE FUNCTION drivy.invitation_training_allowed(school uuid,learner uuid,offering uuid,instructor uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.invitation i JOIN drivy.learner_profile l ON l.school_id=i.school_id AND l.person_id=i.accepted_by_person_id
  WHERE i.school_id=school AND i.status='ACCEPTED' AND i.accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND l.id=learner AND i.training_offering_id=offering AND (instructor IS NULL OR i.training_instructor_membership_id=instructor))
$$;
REVOKE ALL ON FUNCTION drivy.invitation_training_allowed(uuid,uuid,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_training_allowed(uuid,uuid,uuid,uuid) TO drivy_app;
CREATE POLICY invitation_training_insert ON drivy.training FOR INSERT TO drivy_app
 WITH CHECK(status='ACTIVE' AND drivy.invitation_training_allowed(school_id,learner_id,offering_id,NULL));
CREATE POLICY invitation_assignment_insert ON drivy.instructor_assignment FOR INSERT TO drivy_app
 WITH CHECK(valid_until IS NULL AND EXISTS(SELECT 1 FROM drivy.training t WHERE t.school_id=instructor_assignment.school_id AND t.id=training_id
  AND drivy.invitation_training_allowed(t.school_id,t.learner_id,t.offering_id,instructor_membership_id)));
