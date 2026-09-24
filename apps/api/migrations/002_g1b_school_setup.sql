-- G1B : seules les commandes de configuration ADMIN obtiennent des droits d'écriture.
CREATE TABLE drivy.school_setup (
  school_id uuid PRIMARY KEY REFERENCES drivy.school(id),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  current_step text NOT NULL DEFAULT 'IDENTITY' CHECK (current_step IN ('IDENTITY','ORGANISATION','OFFERINGS','COLLECTIVE','DATA','REVIEW')),
  completed_steps text[] NOT NULL DEFAULT '{}' CHECK (cardinality(completed_steps) <= 6
    AND completed_steps <@ ARRAY['IDENTITY','ORGANISATION','OFFERINGS','COLLECTIVE','DATA','REVIEW']::text[]),
  configured_by uuid NOT NULL,
  last_saved_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  FOREIGN KEY (school_id,configured_by) REFERENCES drivy.membership(school_id,id)
);
-- Une révision de politique n'est jamais réécrite ; version 1 = aucun texte ni accord.
CREATE TABLE drivy.school_data_policy (
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  version integer NOT NULL CHECK (version > 0),
  notice_text text NOT NULL,
  retention_text text NOT NULL,
  contact_email text,
  approved_by uuid,
  approved_at timestamptz,
  PRIMARY KEY (school_id,version),
  FOREIGN KEY (school_id,approved_by) REFERENCES drivy.membership(school_id,id),
  CHECK ((approved_by IS NULL AND approved_at IS NULL AND version=1 AND notice_text='' AND retention_text='' AND contact_email IS NULL)
    OR (approved_by IS NOT NULL AND approved_at IS NOT NULL AND length(btrim(notice_text)) BETWEEN 1 AND 20000
      AND length(btrim(retention_text)) BETWEEN 1 AND 20000 AND contact_email IS NOT NULL))
);
CREATE TABLE drivy.school_settings_version (
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  version integer NOT NULL CHECK (version > 0),
  settings jsonb NOT NULL,
  created_by uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (school_id,version),
  FOREIGN KEY (school_id,created_by) REFERENCES drivy.membership(school_id,id)
);
CREATE TABLE drivy.operation (
  actor_person_id uuid NOT NULL REFERENCES drivy.person(id),
  operation_id uuid NOT NULL,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  command_type text NOT NULL,
  payload_hash text NOT NULL CHECK (payload_hash ~ '^[a-f0-9]{64}$'),
  resource_id uuid NOT NULL,
  response_data jsonb NOT NULL,
  committed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (actor_person_id,operation_id),
  UNIQUE (school_id,actor_person_id,operation_id)
);
CREATE TABLE drivy.audit_event (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  actor_person_id uuid NOT NULL,
  actor_membership_id uuid NOT NULL,
  operation_id uuid NOT NULL,
  action text NOT NULL,
  resource_type text NOT NULL,
  resource_id uuid NOT NULL,
  changed_fields text[] NOT NULL,
  server_time timestamptz NOT NULL DEFAULT now(),
  FOREIGN KEY (school_id,actor_membership_id) REFERENCES drivy.membership(school_id,id),
  FOREIGN KEY (school_id,actor_person_id,operation_id) REFERENCES drivy.operation(school_id,actor_person_id,operation_id)
);

CREATE FUNCTION drivy.is_current_school_admin(target_school uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,drivy AS $$
  SELECT target_school = nullif(current_setting('app.school_id',true),'')::uuid
    AND EXISTS (SELECT 1 FROM drivy.membership m WHERE m.school_id=target_school
      AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
      AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
$$;
REVOKE ALL ON FUNCTION drivy.is_current_school_admin(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.is_current_school_admin(uuid) TO drivy_app;

DO $$ DECLARE table_name text; BEGIN
  FOREACH table_name IN ARRAY ARRAY['school_setup','school_data_policy','school_settings_version','operation','audit_event'] LOOP
    EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY',table_name);
    EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY',table_name);
    EXECUTE format('CREATE POLICY school_admin_read ON drivy.%I FOR SELECT TO drivy_app USING (drivy.is_current_school_admin(school_id))',table_name);
    EXECUTE format('CREATE POLICY school_admin_insert ON drivy.%I FOR INSERT TO drivy_app WITH CHECK (drivy.is_current_school_admin(school_id))',table_name);
  END LOOP;
END $$;
-- La preuve d'une clé d'un autre périmètre est comparable, jamais retournée au client.
DROP POLICY school_admin_read ON drivy.operation;
CREATE POLICY operation_actor_read ON drivy.operation FOR SELECT TO drivy_app USING (
  actor_person_id=nullif(current_setting('app.person_id',true),'')::uuid
);
CREATE POLICY operation_actor_insert ON drivy.operation AS RESTRICTIVE FOR INSERT TO drivy_app WITH CHECK (
  actor_person_id=nullif(current_setting('app.person_id',true),'')::uuid
);
CREATE POLICY audit_actor_insert ON drivy.audit_event AS RESTRICTIVE FOR INSERT TO drivy_app WITH CHECK (
  actor_person_id=nullif(current_setting('app.person_id',true),'')::uuid AND EXISTS (
    SELECT 1 FROM drivy.membership m WHERE m.id=actor_membership_id AND m.school_id=audit_event.school_id
      AND m.person_id=actor_person_id AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
);
CREATE POLICY policy_approver_insert ON drivy.school_data_policy AS RESTRICTIVE FOR INSERT TO drivy_app WITH CHECK (
  approved_by IS NOT NULL AND EXISTS (SELECT 1 FROM drivy.membership m WHERE m.id=approved_by
    AND m.school_id=school_data_policy.school_id AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid
    AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
);
CREATE POLICY settings_author_insert ON drivy.school_settings_version AS RESTRICTIVE FOR INSERT TO drivy_app WITH CHECK (
  EXISTS (SELECT 1 FROM drivy.membership m WHERE m.id=created_by AND m.school_id=school_settings_version.school_id
    AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE' AND 'ADMIN'=ANY(m.roles))
);
CREATE POLICY setup_admin_update ON drivy.school_setup FOR UPDATE TO drivy_app
  USING (drivy.is_current_school_admin(school_id)) WITH CHECK (drivy.is_current_school_admin(school_id));
CREATE POLICY school_admin_update ON drivy.school FOR UPDATE TO drivy_app
  USING (drivy.is_current_school_admin(id)) WITH CHECK (drivy.is_current_school_admin(id));
-- SELECT FOR SHARE exige un droit UPDATE ; WITH CHECK false interdit toute écriture réelle.
CREATE POLICY person_access_lock ON drivy.person FOR UPDATE TO drivy_app
  USING (id=nullif(current_setting('app.person_id',true),'')::uuid) WITH CHECK (false);
CREATE POLICY membership_access_lock ON drivy.membership FOR UPDATE TO drivy_app
  USING (person_id=nullif(current_setting('app.person_id',true),'')::uuid) WITH CHECK (false);
GRANT UPDATE(version) ON drivy.person,drivy.membership TO drivy_app;
GRANT UPDATE(name,time_zone,contact_email,contact_phone,version,configuration_version,status) ON drivy.school TO drivy_app;
GRANT SELECT ON drivy.school_setup TO drivy_app;
GRANT SELECT,INSERT ON drivy.school_data_policy,drivy.school_settings_version,drivy.operation,drivy.audit_event TO drivy_app;
GRANT UPDATE(version,current_step,completed_steps,configured_by,last_saved_at,completed_at) ON drivy.school_setup TO drivy_app;

-- Le propriétaire de migration initialise les nouveaux agrégats au provisionnement.
-- Ce rôle DDL n'est pas le rôle runtime ; aucune politique globale n'est accordée à drivy_app.
DO $$ DECLARE table_name text; BEGIN
  FOREACH table_name IN ARRAY ARRAY['school','membership'] LOOP
    EXECUTE format('CREATE POLICY g1b_migration_read ON drivy.%I FOR SELECT TO %I USING (true)',table_name,current_user);
  END LOOP;
  FOREACH table_name IN ARRAY ARRAY['school_setup','school_data_policy','school_settings_version'] LOOP
    EXECUTE format('CREATE POLICY g1b_migration_initialize ON drivy.%I TO %I USING (true) WITH CHECK (true)',table_name,current_user);
  END LOOP;
END $$;
CREATE FUNCTION drivy.initialize_school_setup() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF NEW.status='ACTIVE' AND 'ADMIN'=ANY(NEW.roles) THEN
    INSERT INTO drivy.school_setup(school_id,configured_by) VALUES (NEW.school_id,NEW.id) ON CONFLICT DO NOTHING;
    INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text)
      VALUES (NEW.school_id,1,'','') ON CONFLICT DO NOTHING;
    INSERT INTO drivy.school_settings_version(school_id,version,settings,created_by)
      SELECT id,configuration_version,jsonb_build_object('name',name,'timeZone',time_zone,'contactEmail',contact_email,
        'contactPhone',contact_phone,'modules',modules,'dataPolicyVersion',1),NEW.id
      FROM drivy.school WHERE id=NEW.school_id ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION drivy.initialize_school_setup() FROM PUBLIC;
CREATE TRIGGER initialize_school_setup AFTER INSERT OR UPDATE OF roles,status ON drivy.membership
  FOR EACH ROW EXECUTE FUNCTION drivy.initialize_school_setup();
INSERT INTO drivy.school_setup(school_id,configured_by)
  SELECT DISTINCT ON (school_id) school_id,id FROM drivy.membership WHERE status='ACTIVE' AND 'ADMIN'=ANY(roles) ORDER BY school_id,id;
INSERT INTO drivy.school_data_policy(school_id,version,notice_text,retention_text)
  SELECT school_id,1,'','' FROM drivy.school_setup;
INSERT INTO drivy.school_settings_version(school_id,version,settings,created_by)
  SELECT s.id,s.configuration_version,jsonb_build_object('name',s.name,'timeZone',s.time_zone,'contactEmail',s.contact_email,
    'contactPhone',s.contact_phone,'modules',s.modules,'dataPolicyVersion',1),p.configured_by
  FROM drivy.school s JOIN drivy.school_setup p ON p.school_id=s.id;
