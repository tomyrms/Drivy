# G1D2 — catalogue, formations et affectations

Implémentation du 24 septembre 2026, selon [le READY](g1d-catalogue-ready.md). Migration005 uniquement : curriculum_version, competency_definition et school_policy_version ; compléments des offres, affectations et audits existants. Les versions001–004 restent inchangées. Aucun contenu ni approbation n'est créé pour les anciennes offres incomplètes : elles restent désactivées, leurs formations lisibles.

Routes livrées : AP07/08 membres, AP18/19 offres, AP20/21 référentiels, AP94/95 procédures, AP23 création de formation, AP26/27 lecture/création d'affectation. Les DTO et préconditions du READY sont conservés. Chaque écriture conserve opération et audit au même commit ; les modifications de rôles conservent aussi leur motif. AP23 et AP27 restent deux commandes distinctes, sans affectation automatique.

ADMIN lit toutes les versions complètes ; les autres membres lisent les offres actuelles activées avec contenus approuvés et les versions historiques de leurs formations autorisées. Le calcul de la dernière version utilise un accès interne borné qui n'est pas réduit par la projection du lecteur : une ancienne offre devenue historique ne redevient pas activable après désactivation de sa dernière version.

AP08 exige `auth_time` signé par le fournisseur, conservé après vérification OIDC. `REAUTH_MAX_AGE_SECONDS` vaut300 par défaut, borné de30 à900 ; valeur absente ou trop ancienne dans le jeton :401 REAUTH_REQUIRED. Aucun recours à iat/refresh. Le dernier ADMIN est protégé ; retirer INSTRUCTOR avec affectations courantes/futures ou LEARNER avec dossier actif refuse MEMBER_RELATIONS_REQUIRE_REVIEW. Rôles/grants et accessEpoch changent ensemble. Les nouveaux dossiers liés à un rôle LEARNER restent minimaux, sans prénom extrait ni formation.

Bornes techniques : catégorie30 caractères, clé offre/compétence80, libellé200, description4000, motif1000,200 compétences maximum,30 URL de source web maximum de2048 caractères chacune ; aucune URL n'est téléchargée. Durée1–480 minutes, prix entier CHF de0 à Number.MAX_SAFE_INTEGER centimes. Référentiel : corps≤1Mo ; procédure :≤100Ko. Ces limites ne sont pas des obligations réglementaires. Les versions de catalogue approuvées et leurs références demeurent immuables.

Codes principaux : OFFERING_NOT_READY, OFFERING_CATEGORY_CHANGED, ACTIVE_TRAINING_EXISTS, ASSIGNMENT_CONFLICT, INSTRUCTOR_REQUIRED, TRAINING_NOT_ACTIVE, LEARNER_ARCHIVED, LEARNER_NOT_ACTIVE, LAST_ADMIN, MEMBER_RELATIONS_REQUIRE_REVIEW, REAUTH_REQUIRED ; versions/idempotence inchangées. Le contrôle de permis et la qualification réglementaire ne sont pas acquis par la création d'une formation.

AP72 : CREATE_CURRICULUM_VERSION/Curriculum, CREATE_SCHOOL_POLICY/SchoolPolicy, CREATE_OFFERING_VERSION/Offering, CREATE_TRAINING/Training, CREATE_ASSIGNMENT/Assignment, UPDATE_MEMBER/Member. La preuve reste propre à l'auteur et soumise à ses droits actuels ; une modification de sa propre appartenance reste recherchable après perte du rôle ADMIN, sans restitution du payload.

## Contrôle exécuté

Deux recettes PostgreSQL17.11 sur conteneur indépendant drivy-catalogue-postgres, port55435, base drivy_test : **PASS**. Migration001–005 appliquée sous propriétaire NOSUPERUSER/NOBYPASSRLS/NOCREATEROLE/NOCREATEDB ; parcours approuvé→offre→formation→affectation, reprise de création, ancien catalogue désactivé, formations héritées, création INSTRUCTOR déjà affecté au dossier sans auto-affectation, auth_time absent/ancien, dernier ADMIN et lecture des membres interdite aux non-ADMIN.

Typecheck et build ont réussi pour le catalogue avant ajout de la tranche006 en travail parallèle. Ce contrôle borné ne constitue pas une campagne exhaustive de concurrence ni une recette native. Aucun déploiement n'a été effectué par cette sous-tâche. La migration006 et les leçons appartiennent à la tranche suivante.
