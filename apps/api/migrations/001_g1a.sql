-- G1A : lectures d'identité, d'école, de dossier et de formation.
CREATE SCHEMA drivy;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'drivy_app') THEN
    CREATE ROLE drivy_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOBYPASSRLS;
  END IF;
  EXECUTE format('GRANT drivy_app TO %I', current_user);
END $$;

CREATE TABLE drivy.person (
  id uuid PRIMARY KEY,
  display_name text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 200),
  locale text NOT NULL DEFAULT 'fr-CH',
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'SUSPENDED'))
);
CREATE TABLE drivy.identity_link (
  issuer text NOT NULL,
  subject text NOT NULL,
  person_id uuid NOT NULL REFERENCES drivy.person(id),
  PRIMARY KEY (issuer, subject)
);
CREATE TABLE drivy.school (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  time_zone text NOT NULL DEFAULT 'Europe/Zurich',
  status text NOT NULL CHECK (status IN ('DRAFT', 'ACTIVE', 'ARCHIVED')),
  contact_email text NOT NULL,
  contact_phone text,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  configuration_version integer NOT NULL DEFAULT 1 CHECK (configuration_version > 0),
  modules jsonb NOT NULL DEFAULT '{"gpsEnabled":false,"packsEnabled":false,"collectiveCoursesEnabled":false,"courseOffersVisibleByDefault":false}'
);
CREATE TABLE drivy.membership (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  person_id uuid NOT NULL REFERENCES drivy.person(id),
  status text NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','REVOKED')),
  roles text[] NOT NULL CHECK (cardinality(roles) > 0 AND roles <@ ARRAY['ADMIN','INSTRUCTOR','LEARNER']::text[]),
  grants text[] NOT NULL DEFAULT '{}' CHECK (grants <@ ARRAY['permit_review','cash_record','CONFIGURE_CATALOG','SELL_SERVICES','MANAGE_COURSES','TAKE_ATTENDANCE','VALIDATE_REQUIREMENT','REVIEW_REGULATORY_PROFILE','MANAGE_LEARNER_ARCHIVES','VIEW_SCHOOL_METRICS','VIEW_FINANCIAL_METRICS','EXPORT_MANAGEMENT']::text[]),
  access_epoch integer NOT NULL DEFAULT 1 CHECK (access_epoch > 0),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  UNIQUE (school_id, person_id),
  UNIQUE (school_id, id)
);
CREATE TABLE drivy.learner_profile (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  person_id uuid NOT NULL REFERENCES drivy.person(id),
  display_name text NOT NULL,
  contact_email text,
  contact_phone text,
  archived_at timestamptz,
  profile_readiness text NOT NULL DEFAULT 'MINIMAL' CHECK (profile_readiness IN ('MINIMAL','ACTION_REQUIRED','READY')),
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id, person_id),
  UNIQUE (school_id, id),
  FOREIGN KEY (school_id, person_id) REFERENCES drivy.membership(school_id, person_id)
);
-- Référence d'offre nécessaire à Training ; politique/référentiel détaillés en G1B.
CREATE TABLE drivy.offering_version (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  offering_key text NOT NULL,
  category_code text NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  enabled boolean NOT NULL DEFAULT false,
  UNIQUE (school_id, offering_key, version),
  UNIQUE (school_id, id, offering_key)
);
CREATE TABLE drivy.training (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL REFERENCES drivy.school(id),
  learner_id uuid NOT NULL,
  offering_id uuid NOT NULL,
  offering_key text NOT NULL,
  status text NOT NULL CHECK (status IN ('ACTIVE','PAUSED','COMPLETED','CANCELLED')),
  started_on date,
  closed_on date,
  version integer NOT NULL DEFAULT 1 CHECK (version > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (school_id, id),
  FOREIGN KEY (school_id, learner_id) REFERENCES drivy.learner_profile(school_id,id),
  FOREIGN KEY (school_id, offering_id, offering_key) REFERENCES drivy.offering_version(school_id,id,offering_key),
  CHECK (closed_on IS NULL OR started_on IS NULL OR closed_on >= started_on)
);
CREATE UNIQUE INDEX training_current_offering ON drivy.training(school_id, learner_id, offering_key)
  WHERE status IN ('ACTIVE','PAUSED');
CREATE INDEX learner_page ON drivy.learner_profile(school_id, created_at, id);
CREATE INDEX training_page ON drivy.training(school_id, created_at, id);
CREATE TABLE drivy.instructor_assignment (
  id uuid PRIMARY KEY,
  school_id uuid NOT NULL,
  training_id uuid NOT NULL,
  instructor_membership_id uuid NOT NULL,
  valid_from timestamptz NOT NULL,
  valid_until timestamptz,
  FOREIGN KEY (school_id, training_id) REFERENCES drivy.training(school_id,id),
  FOREIGN KEY (school_id, instructor_membership_id) REFERENCES drivy.membership(school_id,id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
CREATE INDEX assignment_access ON drivy.instructor_assignment(school_id, instructor_membership_id, training_id);

CREATE FUNCTION drivy.validate_membership_roles() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF cardinality(NEW.roles) <> (SELECT count(DISTINCT role) FROM unnest(NEW.roles) AS role) THEN
    RAISE EXCEPTION 'duplicate_membership_role' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER membership_unique_roles BEFORE INSERT OR UPDATE OF roles ON drivy.membership
  FOR EACH ROW EXECUTE FUNCTION drivy.validate_membership_roles();
CREATE FUNCTION drivy.validate_instructor_assignment() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM drivy.membership WHERE id=NEW.instructor_membership_id
      AND school_id=NEW.school_id AND status='ACTIVE' AND 'INSTRUCTOR'=ANY(roles)) THEN
    RAISE EXCEPTION 'instructor_membership_required' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER assignment_instructor BEFORE INSERT OR UPDATE OF school_id,instructor_membership_id ON drivy.instructor_assignment
  FOR EACH ROW EXECUTE FUNCTION drivy.validate_instructor_assignment();

-- Toute lecture scolaire utilise un rôle sans BYPASSRLS et un contexte transactionnel.
ALTER TABLE drivy.identity_link ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.identity_link FORCE ROW LEVEL SECURITY;
CREATE POLICY identity_current ON drivy.identity_link FOR SELECT TO drivy_app USING (
  issuer = current_setting('app.issuer', true) AND subject = current_setting('app.subject', true)
);
ALTER TABLE drivy.person ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.person FORCE ROW LEVEL SECURITY;
CREATE POLICY person_current ON drivy.person FOR SELECT TO drivy_app USING (
  id = nullif(current_setting('app.person_id', true),'')::uuid
);
ALTER TABLE drivy.membership ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.membership FORCE ROW LEVEL SECURITY;
CREATE POLICY membership_current ON drivy.membership FOR SELECT TO drivy_app USING (
  person_id = nullif(current_setting('app.person_id', true),'')::uuid
);
ALTER TABLE drivy.school ENABLE ROW LEVEL SECURITY;
ALTER TABLE drivy.school FORCE ROW LEVEL SECURITY;
CREATE POLICY school_current ON drivy.school FOR SELECT TO drivy_app USING (
  EXISTS (SELECT 1 FROM drivy.membership m WHERE m.school_id = school.id AND m.status = 'ACTIVE')
);
DO $$ DECLARE table_name text; BEGIN
  FOREACH table_name IN ARRAY ARRAY['learner_profile','offering_version','training','instructor_assignment'] LOOP
    EXECUTE format('ALTER TABLE drivy.%I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE drivy.%I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('CREATE POLICY school_current ON drivy.%I FOR SELECT TO drivy_app USING (
      school_id = nullif(current_setting(''app.school_id'', true),'''')::uuid
      AND EXISTS (SELECT 1 FROM drivy.membership m WHERE m.school_id = %I.school_id AND m.status = ''ACTIVE'')
    )', table_name, table_name);
  END LOOP;
END $$;
GRANT USAGE ON SCHEMA drivy TO drivy_app;
GRANT SELECT ON ALL TABLES IN SCHEMA drivy TO drivy_app;
