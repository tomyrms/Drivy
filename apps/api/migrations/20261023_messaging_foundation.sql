-- Foundation only. No plaintext column or validated cryptographic protocol; API disabled outside isolated tests.
CREATE TABLE drivy.messaging_admin_contact (
  school_id uuid NOT NULL REFERENCES drivy.school(id), learner_person_id uuid NOT NULL REFERENCES drivy.person(id),
  admin_person_id uuid NOT NULL REFERENCES drivy.person(id), assigned_by_membership_id uuid NOT NULL,
  assigned_at timestamptz NOT NULL DEFAULT now(), revoked_at timestamptz,
  PRIMARY KEY(school_id,learner_person_id,admin_person_id),
  FOREIGN KEY(school_id,assigned_by_membership_id) REFERENCES drivy.membership(school_id,id),
  CHECK(learner_person_id<>admin_person_id)
);
CREATE TABLE drivy.messaging_conversation (
  id uuid PRIMARY KEY, school_id uuid NOT NULL REFERENCES drivy.school(id),
  kind text NOT NULL CHECK(kind IN('PRIVATE','GENERAL')),
  person_low uuid REFERENCES drivy.person(id), person_high uuid REFERENCES drivy.person(id),
  last_sequence bigint NOT NULL DEFAULT 0 CHECK(last_sequence>=0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(school_id,id),
  CHECK((kind='GENERAL' AND person_low IS NULL AND person_high IS NULL)
    OR (kind='PRIVATE' AND person_low IS NOT NULL AND person_high IS NOT NULL AND person_low<person_high))
);
CREATE UNIQUE INDEX messaging_one_general ON drivy.messaging_conversation(school_id) WHERE kind='GENERAL';
CREATE UNIQUE INDEX messaging_one_private_pair ON drivy.messaging_conversation(school_id,person_low,person_high) WHERE kind='PRIVATE';
CREATE TABLE drivy.messaging_message (
  id uuid PRIMARY KEY, school_id uuid NOT NULL, conversation_id uuid NOT NULL,
  sequence bigint NOT NULL CHECK(sequence>0), sender_person_id uuid NOT NULL REFERENCES drivy.person(id),
  intent_id uuid NOT NULL, envelope jsonb NOT NULL,
  mention_person_ids uuid[] NOT NULL DEFAULT '{}'::uuid[] CHECK(cardinality(mention_person_ids)<=8),
  fingerprint text NOT NULL CHECK(fingerprint ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id),
  UNIQUE(school_id,conversation_id,sequence), UNIQUE(school_id,conversation_id,sender_person_id,intent_id),
  CHECK(jsonb_typeof(envelope)='object' AND envelope ?& ARRAY['scheme','keyId','payload']
    AND envelope - 'scheme' - 'keyId' - 'payload'='{}'::jsonb
    AND jsonb_typeof(envelope->'scheme')='string' AND jsonb_typeof(envelope->'keyId')='string'
    AND jsonb_typeof(envelope->'payload')='string' AND length(envelope->>'payload') BETWEEN 1 AND 12000)
);
CREATE INDEX messaging_message_page ON drivy.messaging_message(school_id,conversation_id,sequence DESC);
CREATE TABLE drivy.messaging_read_state (
  school_id uuid NOT NULL, conversation_id uuid NOT NULL,
  person_id uuid NOT NULL REFERENCES drivy.person(id),
  last_read_sequence bigint NOT NULL DEFAULT 0 CHECK(last_read_sequence>=0),
  muted_until timestamptz, version integer NOT NULL DEFAULT 1 CHECK(version>0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY(school_id,conversation_id,person_id),
  FOREIGN KEY(school_id,conversation_id) REFERENCES drivy.messaging_conversation(school_id,id)
);

-- SECURITY DEFINER prevents administrative person/membership SELECT policies from becoming a private chat directory.
-- Caller identity and school are always bound to transaction context, never only to function arguments.
CREATE FUNCTION drivy.messaging_member(school uuid, person uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT school=nullif(current_setting('app.school_id',true),'')::uuid
   AND EXISTS(SELECT 1 FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
     JOIN drivy.school s ON s.id=m.school_id WHERE m.school_id=school AND m.person_id=person
       AND m.status='ACTIVE' AND p.status='ACTIVE' AND s.status='ACTIVE')
$$;
-- Locks current authorization sources through commit, so a concurrent revocation cannot
-- commit between permission check and durable message write. Caller must recheck rights after locking.
CREATE FUNCTION drivy.messaging_lock_rights(school uuid, actor uuid, peer uuid, mentions uuid[] DEFAULT '{}'::uuid[]) RETURNS void
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
BEGIN
 IF school IS DISTINCT FROM nullif(current_setting('app.school_id',true),'')::uuid
   OR actor IS DISTINCT FROM nullif(current_setting('app.person_id',true),'')::uuid THEN
   RAISE EXCEPTION 'messaging_scope_denied' USING ERRCODE='42501';
 END IF;
 PERFORM 1 FROM drivy.school s WHERE s.id=school FOR SHARE;
 PERFORM 1 FROM drivy.person p WHERE p.id=actor OR p.id=peer OR p.id=ANY(mentions) ORDER BY p.id FOR SHARE;
 PERFORM 1 FROM drivy.membership m WHERE m.school_id=school AND (m.person_id=actor OR m.person_id=peer OR m.person_id=ANY(mentions))
   ORDER BY m.id FOR SHARE;
 PERFORM 1 FROM drivy.learner_profile lp WHERE lp.school_id=school AND (lp.person_id=actor OR lp.person_id=peer)
   ORDER BY lp.id FOR SHARE;
 PERFORM 1 FROM drivy.training t JOIN drivy.learner_profile lp ON lp.school_id=t.school_id AND lp.id=t.learner_id
   WHERE t.school_id=school AND (lp.person_id=actor OR lp.person_id=peer) ORDER BY t.id FOR SHARE OF t;
 PERFORM 1 FROM drivy.instructor_assignment a JOIN drivy.training t ON t.school_id=a.school_id AND t.id=a.training_id
   JOIN drivy.learner_profile lp ON lp.school_id=t.school_id AND lp.id=t.learner_id
   WHERE a.school_id=school AND (lp.person_id=actor OR lp.person_id=peer) ORDER BY a.id FOR SHARE OF a;
 PERFORM 1 FROM drivy.messaging_admin_contact ac WHERE ac.school_id=school
   AND (ac.learner_person_id=actor OR ac.learner_person_id=peer)
   AND (ac.admin_person_id=actor OR ac.admin_person_id=peer) ORDER BY ac.learner_person_id,ac.admin_person_id FOR SHARE;
END $$;
CREATE FUNCTION drivy.messaging_private_allowed(school uuid, actor uuid, peer uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND actor<>peer
  AND drivy.messaging_member(school,actor) AND drivy.messaging_member(school,peer)
  AND EXISTS(SELECT 1 FROM drivy.membership am JOIN drivy.membership pm ON pm.school_id=am.school_id
    WHERE am.school_id=school AND am.person_id=actor AND am.status='ACTIVE'
      AND pm.person_id=peer AND pm.status='ACTIVE' AND (
        EXISTS(SELECT 1 FROM drivy.learner_profile lp JOIN drivy.training t ON t.school_id=lp.school_id AND t.learner_id=lp.id
          JOIN drivy.instructor_assignment a ON a.school_id=t.school_id AND a.training_id=t.id
          WHERE lp.school_id=school AND lp.archived_at IS NULL AND t.status IN('ACTIVE','PAUSED')
            AND a.valid_from<=statement_timestamp() AND (a.valid_until IS NULL OR a.valid_until>statement_timestamp())
            AND ((lp.person_id=actor AND 'LEARNER'=ANY(am.roles) AND 'INSTRUCTOR'=ANY(pm.roles) AND a.instructor_membership_id=pm.id)
              OR (lp.person_id=peer AND 'LEARNER'=ANY(pm.roles) AND 'INSTRUCTOR'=ANY(am.roles) AND a.instructor_membership_id=am.id)))
        OR EXISTS(SELECT 1 FROM drivy.learner_profile lp JOIN drivy.messaging_admin_contact ac
          ON ac.school_id=lp.school_id AND ac.learner_person_id=lp.person_id AND ac.revoked_at IS NULL
          WHERE lp.school_id=school AND lp.archived_at IS NULL
            AND ((lp.person_id=actor AND 'LEARNER'=ANY(am.roles) AND 'ADMIN'=ANY(pm.roles) AND ac.admin_person_id=peer)
              OR (lp.person_id=peer AND 'LEARNER'=ANY(pm.roles) AND 'ADMIN'=ANY(am.roles) AND ac.admin_person_id=actor)))
      ))
$$;
CREATE FUNCTION drivy.messaging_conversation_allowed(school uuid, actor uuid, target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_member(school,actor)
   AND EXISTS(SELECT 1 FROM drivy.messaging_conversation c WHERE c.school_id=school AND c.id=target
     AND (c.kind='GENERAL' OR (actor IN(c.person_low,c.person_high)
       AND drivy.messaging_private_allowed(school,actor,CASE WHEN actor=c.person_low THEN c.person_high ELSE c.person_low END))))
$$;
CREATE FUNCTION drivy.messaging_contacts(school uuid, actor uuid) RETURNS TABLE(person_id uuid,display_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.id,p.display_name FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE m.school_id=school AND m.status='ACTIVE' AND p.status='ACTIVE'
   AND drivy.messaging_private_allowed(school,actor,p.id)
$$;
CREATE FUNCTION drivy.messaging_general_members(school uuid, actor uuid) RETURNS TABLE(person_id uuid,display_name text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT m.person_id,p.display_name FROM drivy.membership m JOIN drivy.person p ON p.id=m.person_id
 WHERE drivy.messaging_member(school,actor) AND actor=nullif(current_setting('app.person_id',true),'')::uuid
   AND m.school_id=school AND m.status='ACTIVE' AND p.status='ACTIVE'
$$;
CREATE FUNCTION drivy.messaging_mentions_allowed(school uuid, actor uuid, target uuid, mentions uuid[]) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT actor=nullif(current_setting('app.person_id',true),'')::uuid AND drivy.messaging_conversation_allowed(school,actor,target)
   AND cardinality(mentions)<=8 AND cardinality(mentions)=(SELECT count(DISTINCT ids.person_id) FROM unnest(mentions) AS ids(person_id))
   AND (cardinality(mentions)=0 OR (EXISTS(SELECT 1 FROM drivy.messaging_conversation c
     WHERE c.school_id=school AND c.id=target AND c.kind='GENERAL')
     AND NOT EXISTS(SELECT 1 FROM unnest(mentions) AS target_person(person_id)
       WHERE NOT drivy.messaging_member(school,target_person.person_id))))
$$;
REVOKE ALL ON FUNCTION drivy.messaging_member(uuid,uuid),drivy.messaging_private_allowed(uuid,uuid,uuid),
  drivy.messaging_conversation_allowed(uuid,uuid,uuid),drivy.messaging_contacts(uuid,uuid),drivy.messaging_general_members(uuid,uuid),drivy.messaging_lock_rights(uuid,uuid,uuid,uuid[]),drivy.messaging_mentions_allowed(uuid,uuid,uuid,uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.messaging_member(uuid,uuid),drivy.messaging_private_allowed(uuid,uuid,uuid),
  drivy.messaging_conversation_allowed(uuid,uuid,uuid),drivy.messaging_contacts(uuid,uuid),drivy.messaging_general_members(uuid,uuid),drivy.messaging_lock_rights(uuid,uuid,uuid,uuid[]),drivy.messaging_mentions_allowed(uuid,uuid,uuid,uuid[]) TO drivy_app;

DO $$ DECLARE table_name text; BEGIN
 FOREACH table_name IN ARRAY ARRAY['messaging_admin_contact','messaging_conversation','messaging_message','messaging_read_state'] LOOP
  EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',table_name);
  EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',table_name);
 END LOOP;
 EXECUTE format('CREATE POLICY messaging_owner_contacts ON drivy.messaging_admin_contact FOR SELECT TO %I USING(true)',current_user);
 EXECUTE format('CREATE POLICY messaging_owner_conversations ON drivy.messaging_conversation FOR SELECT TO %I USING(true)',current_user);
END $$;
CREATE POLICY messaging_contact_admin_read ON drivy.messaging_admin_contact FOR SELECT TO drivy_app
 USING(school_id=nullif(current_setting('app.school_id',true),'')::uuid
   AND (learner_person_id=nullif(current_setting('app.person_id',true),'')::uuid
     OR admin_person_id=nullif(current_setting('app.person_id',true),'')::uuid) AND drivy.messaging_member(school_id,learner_person_id));
CREATE POLICY messaging_conversation_read ON drivy.messaging_conversation FOR SELECT TO drivy_app
 USING((kind='GENERAL' AND drivy.messaging_member(school_id,nullif(current_setting('app.person_id',true),'')::uuid))
   OR (kind='PRIVATE' AND person_low=nullif(current_setting('app.person_id',true),'')::uuid
     AND drivy.messaging_private_allowed(school_id,person_low,person_high))
   OR (kind='PRIVATE' AND person_high=nullif(current_setting('app.person_id',true),'')::uuid
     AND drivy.messaging_private_allowed(school_id,person_high,person_low)));
CREATE POLICY messaging_conversation_insert ON drivy.messaging_conversation FOR INSERT TO drivy_app
 WITH CHECK((kind='GENERAL' AND drivy.messaging_member(school_id,nullif(current_setting('app.person_id',true),'')::uuid))
   OR (kind='PRIVATE' AND (person_low=nullif(current_setting('app.person_id',true),'')::uuid
     AND drivy.messaging_private_allowed(school_id,person_low,person_high)
     OR person_high=nullif(current_setting('app.person_id',true),'')::uuid
     AND drivy.messaging_private_allowed(school_id,person_high,person_low))));
CREATE POLICY messaging_conversation_update ON drivy.messaging_conversation FOR UPDATE TO drivy_app
 USING(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,id))
 WITH CHECK(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,id));
CREATE POLICY messaging_message_read ON drivy.messaging_message FOR SELECT TO drivy_app
 USING(drivy.messaging_conversation_allowed(school_id,nullif(current_setting('app.person_id',true),'')::uuid,conversation_id));
CREATE POLICY messaging_message_insert ON drivy.messaging_message FOR INSERT TO drivy_app
 WITH CHECK(sender_person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_mentions_allowed(school_id,sender_person_id,conversation_id,mention_person_ids));
CREATE POLICY messaging_read_state_select ON drivy.messaging_read_state FOR SELECT TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_conversation_allowed(school_id,person_id,conversation_id));
CREATE POLICY messaging_read_state_insert ON drivy.messaging_read_state FOR INSERT TO drivy_app
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_conversation_allowed(school_id,person_id,conversation_id));
CREATE POLICY messaging_read_state_update ON drivy.messaging_read_state FOR UPDATE TO drivy_app
 USING(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_conversation_allowed(school_id,person_id,conversation_id))
 WITH CHECK(person_id=nullif(current_setting('app.person_id',true),'')::uuid
   AND drivy.messaging_conversation_allowed(school_id,person_id,conversation_id));
GRANT SELECT ON drivy.messaging_conversation,drivy.messaging_message TO drivy_app;
GRANT INSERT ON drivy.messaging_conversation,drivy.messaging_message TO drivy_app;
GRANT UPDATE(last_sequence) ON drivy.messaging_conversation TO drivy_app;
GRANT SELECT,INSERT ON drivy.messaging_read_state TO drivy_app;
GRANT UPDATE(last_read_sequence,muted_until,version,updated_at) ON drivy.messaging_read_state TO drivy_app;
-- No admin-contact INSERT grant until an audited assignment command is implemented.
