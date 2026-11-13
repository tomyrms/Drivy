-- R01-T01 (#453), correction de revue : un code d'accès n'est acceptable que tant que l'opérateur qui l'a émis fait encore partie de l'équipe.
-- Le retrait d'un opérateur révoque déjà, dans la même transaction, ses invitations en attente (service). Cette condition est la dernière barrière :
-- elle couvre toute invitation qui aurait échappé à cette révocation (retrait hors service, invitation émise pendant le retrait de son auteur).
-- Migration datée à part : 20261113_platform_operators.sql est un fichier scellé par son empreinte, il n'est pas réécrit.

CREATE OR REPLACE FUNCTION drivy.platform_invitation_acceptable(invitation uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT EXISTS(SELECT 1 FROM drivy.platform_operator_invitation i
    JOIN drivy.platform_operator creator ON creator.id = i.created_by
    WHERE i.id = invitation AND i.code_hash = current_setting('app.platform_invitation_hash', true)
      AND i.status = 'AVAILABLE' AND i.expires_at > now() AND i.invitee_email = current_setting('app.verified_email', true)
      AND creator.status = 'ACTIVE')
$$;

-- Lecture par le service, pour dire « révoquée » au porteur du code plutôt que « inconnue » : le porteur ne lit pas l'équipe lui-même.
-- Ne rend qu'un booléen, et seulement pour le code que l'identité courante porte (jamais pour une invitation devinée par son identifiant).
CREATE FUNCTION drivy.platform_invitation_creator_active(invitation uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,drivy AS $$
  SELECT EXISTS(SELECT 1 FROM drivy.platform_operator_invitation i
    JOIN drivy.platform_operator creator ON creator.id = i.created_by
    WHERE i.id = invitation AND i.code_hash = current_setting('app.platform_invitation_hash', true) AND creator.status = 'ACTIVE')
$$;
REVOKE ALL ON FUNCTION drivy.platform_invitation_creator_active(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION drivy.platform_invitation_creator_active(uuid) TO drivy_app;
