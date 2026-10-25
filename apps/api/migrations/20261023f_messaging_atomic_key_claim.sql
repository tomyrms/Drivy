-- #78/#84 : FOR UPDATE exige UPDATE, jamais accordé aux pairs sur leurs clés.
-- Réserver l'opération atomique de réclamation au propriétaire et relire les droits.
DO $$ BEGIN
 EXECUTE format('CREATE POLICY messaging_owner_otk_claim ON drivy.messaging_one_time_key FOR ALL TO %I USING(true) WITH CHECK(true)',current_user);
END $$;
CREATE FUNCTION drivy.messaging_claim_one_time_key(school uuid, target uuid, device text, algo text)
RETURNS TABLE(key_id text, key jsonb)
LANGUAGE sql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 DELETE FROM drivy.messaging_one_time_key k
 WHERE (k.school_id,k.person_id,k.device_id,k.key_id)=(
   SELECT o.school_id,o.person_id,o.device_id,o.key_id
   FROM drivy.messaging_one_time_key o JOIN drivy.messaging_device d
     ON d.school_id=o.school_id AND d.person_id=o.person_id AND d.device_id=o.device_id AND d.revoked_at IS NULL
   WHERE drivy.messaging_key_peer(school,target)
     AND o.school_id=school AND o.person_id=target AND o.device_id=device AND o.algorithm=algo
   ORDER BY o.key_id LIMIT 1 FOR UPDATE OF o SKIP LOCKED)
 RETURNING k.key_id,k.key
$$;
REVOKE ALL ON FUNCTION drivy.messaging_claim_one_time_key(uuid,uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_claim_one_time_key(uuid,uuid,text,text) TO drivy_app;
