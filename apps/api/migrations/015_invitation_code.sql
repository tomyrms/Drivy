-- Invitation par code à usage unique, sans e-mail (décision du porteur du 28 septembre 2026) : aucun relais SMTP n'est disponible,
-- le moniteur transmet à l'élève un code de 8 caractères (SMS, WhatsApp) qu'il saisit dans l'app.
-- Le code n'est jamais stocké : token_hash porte le SHA-256 du code normalisé (majuscules, sans espaces ni tirets), comme pour un jeton.
ALTER TABLE drivy.invitation ALTER COLUMN email DROP NOT NULL;
ALTER TABLE drivy.invitation ADD COLUMN delivery text NOT NULL DEFAULT 'EMAIL' CHECK(delivery IN('EMAIL','CODE'));
-- Les lignes existantes valent EMAIL (défaut) et ont toutes une adresse. Un code ne porte que le rôle Élève et sa formation (013).
ALTER TABLE drivy.invitation ADD CONSTRAINT invitation_delivery_shape CHECK(
 (delivery='EMAIL' AND email IS NOT NULL)
 OR (delivery='CODE' AND email IS NULL AND roles=ARRAY['LEARNER']::text[] AND training_offering_id IS NOT NULL AND training_instructor_membership_id IS NOT NULL));

-- La cible d'une invitation se résout par jeton et adresse vérifiée (EMAIL) ou par le seul code (CODE) : les deux contextes sont
-- exclusifs (app.invitation_hash / app.invitation_code_hash) et une variable absente ne correspond jamais. Une seule fonction sert
-- toutes les politiques de 003 (personne, identité, adhésion, dossier élève, opération) : elles couvrent donc les deux flux.
CREATE OR REPLACE FUNCTION drivy.invitation_target() RETURNS SETOF drivy.invitation
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT i.* FROM drivy.invitation i WHERE
  (i.delivery='EMAIL' AND i.token_hash=current_setting('app.invitation_hash',true) AND i.email=current_setting('app.verified_email',true))
  OR (i.delivery='CODE' AND i.token_hash=current_setting('app.invitation_code_hash',true))
$$;
ALTER POLICY invitation_target_read ON drivy.invitation USING(
 (delivery='EMAIL' AND token_hash=current_setting('app.invitation_hash',true) AND email=current_setting('app.verified_email',true))
 OR (delivery='CODE' AND token_hash=current_setting('app.invitation_code_hash',true)));
ALTER POLICY invitation_target_update ON drivy.invitation USING(
 (delivery='EMAIL' AND token_hash=current_setting('app.invitation_hash',true) AND email=current_setting('app.verified_email',true))
 OR (delivery='CODE' AND token_hash=current_setting('app.invitation_code_hash',true)))
 WITH CHECK(
 ((delivery='EMAIL' AND token_hash=current_setting('app.invitation_hash',true) AND email=current_setting('app.verified_email',true))
 OR (delivery='CODE' AND token_hash=current_setting('app.invitation_code_hash',true)))
 AND status='ACCEPTED' AND accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid);

-- Aperçu d'un code : la catégorie de la formation portée par l'invitation, lisible par une identité qui n'est pas encore membre.
-- Réservée à l'offre de l'invitation par code que le contexte courant désigne.
CREATE FUNCTION drivy.invitation_code_category(offering uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT o.category_code FROM drivy.offering_version o WHERE o.id=offering AND EXISTS(SELECT 1 FROM drivy.invitation i
  WHERE i.training_offering_id=o.id AND i.delivery='CODE' AND i.token_hash=current_setting('app.invitation_code_hash',true))
$$;
REVOKE ALL ON FUNCTION drivy.invitation_code_category(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_code_category(uuid) TO drivy_app;

-- L'offre d'une invitation a pu être republiée depuis son envoi (nouvelle version, ancienne plus « dernière »). À l'acceptation, la formation
-- s'ouvre sur la dernière version prête de la MÊME offre (offering_key). Le nouveau membre ne lit pas l'ancienne version (offering_scope) :
-- cette fonction la résout pour lui, uniquement pour l'invitation qu'il vient d'accepter, et rend NULL si aucune version n'est prête.
CREATE FUNCTION drivy.invitation_ready_offering(offering uuid) RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT n.id FROM drivy.offering_version o JOIN drivy.offering_version n ON n.school_id=o.school_id AND n.offering_key=o.offering_key
 WHERE o.id=offering AND EXISTS(SELECT 1 FROM drivy.invitation i WHERE i.training_offering_id=o.id AND i.status='ACCEPTED'
  AND i.accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid)
 AND drivy.catalogue_offering_ready(n.id) ORDER BY n.version DESC LIMIT 1
$$;
REVOKE ALL ON FUNCTION drivy.invitation_ready_offering(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.invitation_ready_offering(uuid) TO drivy_app;
-- La politique d'insertion de formation (013) accepte désormais toute version de l'offre invitée, pas seulement celle de l'invitation.
CREATE OR REPLACE FUNCTION drivy.invitation_training_allowed(school uuid,learner uuid,offering uuid,instructor uuid) RETURNS boolean
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
 SELECT EXISTS(SELECT 1 FROM drivy.invitation i JOIN drivy.learner_profile l ON l.school_id=i.school_id AND l.person_id=i.accepted_by_person_id
  JOIN drivy.offering_version invited ON invited.school_id=i.school_id AND invited.id=i.training_offering_id
  JOIN drivy.offering_version wanted ON wanted.school_id=i.school_id AND wanted.id=offering AND wanted.offering_key=invited.offering_key
  WHERE i.school_id=school AND i.status='ACCEPTED' AND i.accepted_by_person_id=nullif(current_setting('app.person_id',true),'')::uuid
  AND l.id=learner AND (instructor IS NULL OR i.training_instructor_membership_id=instructor))
$$;
