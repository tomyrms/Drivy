-- Audit identité du 7 novembre 2026 (issues #421 et #450). Aucune version numérique existante ne change de sens : elles ne font que croître.
--
-- #421 : l'identité (nom, e-mail, téléphone, date de naissance, adresse) vit sur drivy.person mais se lit et s'écrit aussi par les
-- dossiers d'élève de chaque école, dont chacun a sa propre version (If-Match). Une écriture d'identité, d'où qu'elle vienne,
-- fait donc avancer d'un cran la version de TOUS les dossiers de cette personne, hors celui que la commande en cours incrémente
-- déjà elle-même (app.identity_origin_profile). Seules les écritures qui font avancer person.version propagent (toutes les routes le font ;
-- un correctif SQL hors version ne périme rien). Un formulaire ouvert avant la modification est alors refusé (412) au lieu
-- d'écraser. Les photos ne touchent pas à ces champs : elles ne périment pas les dossiers.
--
-- #450 : photo_version servait à la fois de drapeau de présence (0 = aucune photo) et de compteur de contenu ; le retrait
-- remettait 0 et le remplacement suivant réutilisait 1. photo_generation est le dernier compteur émis : il ne diminue jamais et
-- n'est jamais remis à 0. photo_version reste la génération de la photo présente (0 si aucune), donc les portraits chiffrés
-- existants, dont l'AAD porte photo_version, restent lisibles sans réécriture.

ALTER TABLE drivy.person ADD COLUMN photo_generation integer NOT NULL DEFAULT 0 CHECK(photo_generation>=0);
-- La RLS est forcée aussi pour le propriétaire : une politique temporaire, retirée aussitôt, autorise ce seul rattrapage.
DO $$ BEGIN EXECUTE format('CREATE POLICY identity_generation_backfill ON drivy.person TO %I USING(true) WITH CHECK(true)',current_user); END $$;
UPDATE drivy.person SET photo_generation=photo_version WHERE photo_version>0;
DROP POLICY identity_generation_backfill ON drivy.person;
ALTER TABLE drivy.person ADD CONSTRAINT person_photo_generation_covers_version CHECK(photo_generation>=photo_version);
GRANT UPDATE(photo_generation) ON drivy.person TO drivy_app;

CREATE FUNCTION drivy.guard_photo_generation() RETURNS trigger LANGUAGE plpgsql SET search_path=pg_catalog,drivy AS $$ BEGIN
  IF NEW.photo_generation<OLD.photo_generation THEN
    RAISE EXCEPTION 'photo_generation_monotone' USING ERRCODE='23514';
  END IF;
  -- Une photo présente porte une génération nouvelle : jamais celle d'un contenu antérieur.
  IF NEW.photo_version>0 AND NEW.photo_version<>OLD.photo_version AND NEW.photo_version<=OLD.photo_generation THEN
    RAISE EXCEPTION 'photo_generation_reused' USING ERRCODE='23514';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER person_photo_generation_guard BEFORE UPDATE OF photo_version,photo_generation ON drivy.person
  FOR EACH ROW EXECUTE FUNCTION drivy.guard_photo_generation();

CREATE FUNCTION drivy.bump_identity_dependents() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$ BEGIN
  -- Ordre d'identifiant : deux écritures d'identité simultanées verrouillent les dossiers dans le même ordre.
  UPDATE drivy.learner_profile l SET version=l.version+1
  WHERE l.id IN (SELECT d.id FROM drivy.learner_profile d WHERE d.person_id=NEW.id
    AND d.id IS DISTINCT FROM nullif(current_setting('app.identity_origin_profile',true),'')::uuid ORDER BY d.id FOR UPDATE);
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION drivy.bump_identity_dependents() FROM PUBLIC;
CREATE TRIGGER person_identity_bumps_profiles AFTER UPDATE OF display_name,first_name,last_name,contact_email,contact_phone,birth_date,postal_address
  ON drivy.person FOR EACH ROW
  WHEN (OLD.version IS DISTINCT FROM NEW.version AND (OLD.display_name IS DISTINCT FROM NEW.display_name OR OLD.first_name IS DISTINCT FROM NEW.first_name OR OLD.last_name IS DISTINCT FROM NEW.last_name
    OR OLD.contact_email IS DISTINCT FROM NEW.contact_email OR OLD.contact_phone IS DISTINCT FROM NEW.contact_phone
    OR OLD.birth_date IS DISTINCT FROM NEW.birth_date OR OLD.postal_address IS DISTINCT FROM NEW.postal_address))
  EXECUTE FUNCTION drivy.bump_identity_dependents();
