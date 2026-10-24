-- Préparation explicite par l'administrateur PostgreSQL, avant migration 045 (même modèle que prepare-invitation-mailer.sql).
-- Ce fichier n'est jamais exécuté par le démarrage API ni par le service. Le mot de passe du login se génère côté serveur.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_course_worker') THEN
    CREATE ROLE drivy_course_worker NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_refonte_course_worker') THEN
    CREATE ROLE drivy_refonte_course_worker LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('drivy_course_worker','drivy_refonte_course_worker')
    AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole OR rolinherit OR (rolname='drivy_course_worker' AND rolcanlogin))) THEN
    RAISE EXCEPTION 'course_worker_role_privileges_invalid';
  END IF;
END $$;
GRANT drivy_course_worker TO drivy_refonte_owner WITH ADMIN OPTION;
GRANT drivy_course_worker TO drivy_refonte_course_worker;
GRANT CONNECT ON DATABASE drivy_refonte TO drivy_refonte_course_worker;
COMMIT;
