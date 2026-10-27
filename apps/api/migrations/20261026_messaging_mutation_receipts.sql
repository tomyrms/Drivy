-- #104: reuse operation + audit_event for replay-safe mutations. No message content or ciphertext is copied.
CREATE POLICY messaging_mutation_operation_insert ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND command_type IN(
  'MESSAGING_REACTION','MESSAGING_PIN','MESSAGING_VOTE','MESSAGING_HIDE','MESSAGING_DELETE'));
CREATE POLICY messaging_mutation_audit_insert ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND action='MessagingMutationCommitted' AND resource_type='MessagingMessage');
-- School administration alone does not reveal metadata about somebody else's private conversation.
CREATE POLICY messaging_mutation_audit_private ON drivy.audit_event AS RESTRICTIVE FOR SELECT TO drivy_app
 USING(action<>'MessagingMutationCommitted' OR actor_person_id=nullif(current_setting('app.person_id',true),'')::uuid);
