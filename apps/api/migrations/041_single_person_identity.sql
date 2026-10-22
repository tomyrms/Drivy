-- Une seule identité par personne (22 octobre 2026, issue #94, décision du porteur) : prénom, nom, nom affiché, e-mail,
-- téléphone, date de naissance et adresse vivent sur drivy.person, le compte Drivy de la personne. Le dossier d'élève
-- (drivy.learner_profile) ne garde que ce qui appartient à l'école : politique acceptée, auteur de la saisie, archivage.
-- Toutes les écoles d'un élève lisent les mêmes valeurs. Les données existantes sont des données d'essai : rien n'est repris.

-- Fonctions qui lisaient les colonnes du dossier : elles lisent le compte.
CREATE OR REPLACE FUNCTION drivy.lesson_learner_name(school uuid,training uuid,instructor uuid,learner uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT p.display_name FROM drivy.learner_profile lp JOIN drivy.person p ON p.id=lp.person_id
 WHERE lp.school_id=school AND lp.id=learner AND drivy.current_school_member(school)
 AND (drivy.lesson_access(training,instructor,false) OR drivy.report_training_access(training,false))
$$;
CREATE OR REPLACE FUNCTION drivy.capture_trip_names(capture uuid) RETURNS TABLE(learner_name text,instructor_name text)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT lp_person.display_name,ip.display_name FROM drivy.capture_session c
 JOIN drivy.learner_profile lp ON lp.school_id=c.school_id AND lp.id=c.learner_id
 JOIN drivy.person lp_person ON lp_person.id=lp.person_id
 JOIN drivy.membership im ON im.school_id=c.school_id AND im.id=c.instructor_membership_id
 JOIN drivy.person ip ON ip.id=im.person_id
 WHERE c.id=capture AND drivy.current_school_member(c.school_id)
 AND (drivy.capture_private_access(c.lesson_id)
  OR (c.publication_state='PRIVATE' AND c.finalized_at IS NOT NULL AND c.sync_state IN('SYNCED','PARTIAL') AND drivy.learner_shared_lesson(c.lesson_id,'capture')))
$$;

-- L'écriture du dossier ne porte plus de champ d'identité : la vérification CONTACT disparaît avec eux.
DROP POLICY profile_update ON drivy.learner_profile;
DROP FUNCTION drivy.profile_fields_writable(uuid,text,text,date,jsonb,uuid,text);
CREATE POLICY profile_update ON drivy.learner_profile FOR UPDATE TO drivy_app USING(drivy.profile_access(id) IS NOT NULL AND archived_at IS NULL)
  WITH CHECK(drivy.profile_access(id) IS NOT NULL AND entered_by_membership_id=nullif(current_setting('app.membership_id',true),'')::uuid);

-- Une valeur saisie seulement dans un dossier complète le compte s'il ne l'a pas : rien n'est écrasé ; un conflit
-- garde le compte. Les données actuelles sont d'essai, cette reprise évite seulement de vider les comptes de recette.
-- La RLS est forcée aussi pour le propriétaire : une politique temporaire, retirée aussitôt, autorise cette seule reprise.
DO $$ BEGIN EXECUTE format('CREATE POLICY single_identity_reprise ON drivy.person TO %I USING(true) WITH CHECK(true)',current_user); END $$;
UPDATE drivy.person p SET first_name=COALESCE(p.first_name,l.first_name),last_name=COALESCE(p.last_name,l.last_name),
  contact_email=COALESCE(p.contact_email,l.contact_email),contact_phone=COALESCE(p.contact_phone,l.contact_phone),
  birth_date=COALESCE(p.birth_date,l.birth_date),postal_address=COALESCE(p.postal_address,l.postal_address)
FROM (SELECT DISTINCT ON (person_id) * FROM drivy.learner_profile ORDER BY person_id,profile_updated_at DESC,id) l
WHERE l.person_id=p.id;
DROP POLICY single_identity_reprise ON drivy.person;

ALTER TABLE drivy.learner_profile DROP COLUMN display_name, DROP COLUMN contact_email, DROP COLUMN contact_phone,
  DROP COLUMN first_name, DROP COLUMN last_name, DROP COLUMN birth_date, DROP COLUMN postal_address,
  DROP COLUMN profile_photo_document_id, DROP COLUMN profile_readiness;

-- Lecture du compte d'un élève par son école : la personne derrière un dossier lisible (administration, élève lui-même,
-- moniteur affecté). Le service ne projette au moniteur que le nom et les coordonnées de contact (profiles.ts).
CREATE FUNCTION drivy.school_reads_person(target uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.person_id=target
   AND l.school_id=nullif(current_setting('app.school_id',true),'')::uuid AND drivy.profile_access(l.id) IS NOT NULL)
$$;
-- Écriture par l'école : l'administration (ou l'élève lui-même) pour toute l'identité, le moniteur affecté pour le contact.
-- Seule la route du dossier pose app.school_profile, dans sa transaction ; la colonne écrite est contrôlée par le service.
CREATE FUNCTION drivy.school_writes_person(target uuid) RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT current_setting('app.school_profile',true)='true' AND EXISTS(SELECT 1 FROM drivy.learner_profile l WHERE l.person_id=target
   AND l.school_id=nullif(current_setting('app.school_id',true),'')::uuid AND l.archived_at IS NULL AND drivy.profile_access(l.id) IS NOT NULL)
$$;
REVOKE ALL ON FUNCTION drivy.school_reads_person(uuid),drivy.school_writes_person(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.school_reads_person(uuid),drivy.school_writes_person(uuid) TO drivy_app;
CREATE POLICY school_person_read ON drivy.person FOR SELECT TO drivy_app USING(drivy.school_reads_person(id));
CREATE POLICY school_person_update ON drivy.person FOR UPDATE TO drivy_app USING(drivy.school_writes_person(id) AND status='ACTIVE')
  WITH CHECK(drivy.school_writes_person(id) AND status='ACTIVE');
-- À l'acceptation d'une invitation, la personne complète son propre compte (noms signés, e-mail vérifié) dans la même
-- transaction que son dossier : seulement sa ligne, seulement quand la route pose app.school_profile.
CREATE POLICY school_person_self_update ON drivy.person FOR UPDATE TO drivy_app
  USING(id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE' AND current_setting('app.school_profile',true)='true')
  WITH CHECK(id=nullif(current_setting('app.person_id',true),'')::uuid AND status='ACTIVE' AND current_setting('app.school_profile',true)='true');
