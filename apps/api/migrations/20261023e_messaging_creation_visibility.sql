-- #78/#84 : INSERT ... ON CONFLICT ... RETURNING applique aussi la politique SELECT.
-- Une fonction STABLE qui relit la ligne en cours d'insertion ne la voit pas encore.
-- Évaluer les droits depuis la ligne proposée sans assouplir l'isolement ou la fin du lien.
CREATE FUNCTION drivy.messaging_conversation_row_allowed(school uuid, actor uuid, target uuid, conversation_kind text, low_person uuid, high_person uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_member(school,actor)
   AND ((conversation_kind='GENERAL' AND drivy.messaging_general_participant(school,actor))
     OR (conversation_kind='PRIVATE' AND actor IN(low_person,high_person)
       AND drivy.messaging_pair_eligible(school,low_person,high_person))
     OR EXISTS(SELECT 1 FROM drivy.messaging_member_link l
       WHERE l.school_id=school AND l.conversation_id=target AND l.person_id=actor))
$$;
REVOKE ALL ON FUNCTION drivy.messaging_conversation_row_allowed(uuid,uuid,uuid,text,uuid,uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_conversation_row_allowed(uuid,uuid,uuid,text,uuid,uuid) TO drivy_app;
DROP POLICY messaging_conversation_read ON drivy.messaging_conversation;
CREATE POLICY messaging_conversation_read ON drivy.messaging_conversation FOR SELECT TO drivy_app
 USING(drivy.messaging_conversation_row_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,id,kind,person_low,person_high));
