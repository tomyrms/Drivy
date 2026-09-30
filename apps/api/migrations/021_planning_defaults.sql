-- Personal planning suggestions, never a substitute for booking authorization or commercial snapshots.
CREATE TABLE drivy.planning_defaults (
 school_id uuid NOT NULL,
 membership_id uuid NOT NULL,
 version integer NOT NULL CHECK(version > 1),
 training_category_code text,
 service_product_key text,
 PRIMARY KEY(school_id,membership_id),
 FOREIGN KEY(school_id,membership_id) REFERENCES drivy.membership(school_id,id),
 CHECK(training_category_code IS NULL OR length(training_category_code) BETWEEN 1 AND 30),
 CHECK(service_product_key IS NULL OR length(service_product_key) BETWEEN 1 AND 100)
);
ALTER TABLE drivy.planning_defaults ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.planning_defaults FORCE ROW LEVEL SECURITY;
CREATE POLICY planning_defaults_own ON drivy.planning_defaults TO drivy_app
 USING(drivy.current_school_member(school_id) AND EXISTS(
  SELECT 1 FROM drivy.membership m WHERE m.school_id=planning_defaults.school_id AND m.id=membership_id
   AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
   AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]))
 WITH CHECK(drivy.current_school_member(school_id) AND EXISTS(
  SELECT 1 FROM drivy.membership m WHERE m.school_id=planning_defaults.school_id AND m.id=membership_id
   AND m.person_id=nullif(current_setting('app.person_id',true),'')::uuid AND m.status='ACTIVE'
   AND m.roles && ARRAY['ADMIN','INSTRUCTOR']::text[]));
GRANT SELECT,INSERT ON drivy.planning_defaults TO drivy_app;
GRANT UPDATE(version,training_category_code,service_product_key) ON drivy.planning_defaults TO drivy_app;
CREATE POLICY planning_defaults_operation ON drivy.operation FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND command_type='SAVE_PLANNING_DEFAULTS');
CREATE POLICY planning_defaults_audit ON drivy.audit_event FOR INSERT TO drivy_app
 WITH CHECK(drivy.current_school_member(school_id) AND action='PlanningDefaultsSaved');
