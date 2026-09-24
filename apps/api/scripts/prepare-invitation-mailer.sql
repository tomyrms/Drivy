-- Préparation explicite par l'administrateur PostgreSQL, avant migration 003.
-- Ce fichier n'est jamais exécuté par le démarrage API ni par le worker.
-- Le mot de passe du login se génère séparément côté serveur et n'entre pas dans ce fichier.
BEGIN;
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_invitation_mailer') THEN
    CREATE ROLE drivy_invitation_mailer NOLOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='drivy_refonte_mailer') THEN
    CREATE ROLE drivy_refonte_mailer LOGIN NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT;
  END IF;
  IF EXISTS(SELECT 1 FROM pg_roles WHERE rolname IN('drivy_invitation_mailer','drivy_refonte_mailer')
    AND (rolsuper OR rolbypassrls OR rolcreatedb OR rolcreaterole OR rolinherit OR (rolname='drivy_invitation_mailer' AND rolcanlogin))) THEN
    RAISE EXCEPTION 'invitation_mailer_role_privileges_invalid';
  END IF;
END $$;
GRANT drivy_invitation_mailer TO drivy_refonte_owner WITH ADMIN OPTION;
GRANT drivy_invitation_mailer TO drivy_refonte_mailer;
GRANT CONNECT ON DATABASE drivy_refonte TO drivy_refonte_mailer;
COMMIT;
