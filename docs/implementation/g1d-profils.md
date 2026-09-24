# G1D1 — politiques de champs et profils scolaires

Tranche isolée dans `codex/g1d-profils`. Canon 3.11 immuable ; migrations 001–003 inchangées. Pas de catalogue, formation, agenda ou déploiement dans cette tranche.

## READY

1. L'ADMIN définit une politique de champs, relit sa notice adoptée puis publie ; l'élève ou le personnel autorisé complète le profil scolaire et reprend son accueil.
2. Profil et contact AP16/AP176 ont une source et une version communes. Les noms légaux restent null tant qu'ils ne sont pas saisis. Politique publiée immuable, auteur réel, finalités/stades bornés et photo toujours facultative.
3. Idempotence/audit au même commit ; If-Match, droits relus après attente, champs non autorisés refusant toute la commande. Une réponse incertaine ne peut être oubliée sur un simple refus ultérieur.
4. Réutiliser learner_profile pour le profil administratif, ajouter politique versionnée et accueil par appartenance/kind. UUID persisté par révision de notice G1B, sans modifier les preuves d'adoption. Aucun GET ne crée un objet.
5. Contrats AP169–177/AP16 ; formulaires français, valeurs absentes distinctes des champs non lisibles, stages expliqués et reprise des commandes. Politique absente : état explicite et parcours ADMIN vers sa création.
6. PostgreSQL dédié port 55434 : RLS sous propriétaire non privilégié, champs/portées, AP16↔176, double publication, droits retirés sous verrou, replay/rollback, schémas canoniques et photo facultative ; recettes clients séparées.

## Contrat d'intégration

- AP169 : limit/cursor canoniques ; ADMIN lit DRAFT/PUBLISHED/RETIRED, les autres membres actifs lisent uniquement la politique publiée applicable à leur accueil. La RLS impose cette limite, y compris sans filtre applicatif. La politique applicable est la PUBLISHED dont effectiveFrom est la plus récente sans dépasser l'heure serveur.
- AP170 : If-Match porte sur **School.version** ; création DRAFT, School.version incrémentée, aucune approbation. AP171 : If-Match porte sur **ProfileFieldPolicy.version** ; publication explicite, version +1 et School.version/configurationVersion incrémentées. Une révision de réglages conserve la référence de politique publiée dans ce même commit.
- `GET/PUT data-policy` conserve son id scolaire et ses versions entières ; ajoute `noticeVersionId` UUID stable de révision. GET accepte `noticeVersionId` facultatif : ADMIN peut lire le brouillon, les autres membres actifs seulement une révision approuvée de leur école.
- AP175/176 : version commune avec Learner ; id de profil stable distinct de learnerId. ADMIN ou LEARNER sur soi peut saisir les champs admis. INSTRUCTOR affecté lit identité/contact utiles et écrit seulement contactEmail/contactPhone ; naissance/adresse/photo sont omises de sa projection, y compris au rejeu d'une ancienne commande après réduction des droits. L'identité OIDC ne change jamais avec un contact scolaire. `policyVersionId` projette la politique applicable actuelle ; la référence de dernière saisie reste stockée séparément. Un PATCH obsolète reçoit PROFILE_POLICY_CHANGED et doit être relu avant une nouvelle intention.
- AP172 exige kind STUDENT ou STAFF. STUDENT exige LEARNER, STAFF exige ADMIN/INSTRUCTOR ; accueil propre à l'acteur, jamais à un élève assisté. AP173/AP174 portent l'If-Match de la progression.
- AP177 : ENTER reste permis à l'identité minimale ; PLAN_LESSON et ENROLL_COURSE ne deviennent pas prêts par simple complétion du profil. Les modules non implémentés restent explicitement bloqués. Les exigences conditionnelles dépendent d'un contexte réglementaire qualifié, jamais d'une hypothèse de collecte.

AP72 : `CREATE_PROFILE_FIELD_POLICY`/`PUBLISH_PROFILE_FIELD_POLICY` → `ProfileFieldPolicy` ; `UPDATE_ADMINISTRATIVE_PROFILE` → `AdministrativeProfile` ; `UPDATE_LEARNER` → `Learner` ; `SAVE_ONBOARDING`/`COMPLETE_ONBOARDING` → `OnboardingProgress`. Création de politique : resourceId encore inconnu et resourceVersion locale 0, mais If-Match School.version conservé séparément dans la demande durable.

Erreurs métier : PROFILE_POLICY_NOT_READY, PROFILE_POLICY_CHANGED, PROFILE_POLICY_RULE_INVALID, PROFILE_POLICY_ALREADY_PUBLISHED, PROFILE_POLICY_DATE_CONFLICT, PROFILE_FIELD_FORBIDDEN, ONBOARDING_NOT_READY, DOCUMENT_NOT_READY, INVALID_BIRTH_DATE, LEARNER_ARCHIVED ; préconditions 428/412 et erreurs d'idempotence habituelles. PROFILE_ACTION_REQUIRED est un blocker de readiness. Une photo non nulle ne peut être admise sans le pipeline documentaire F09 qualifié ; son absence ne bloque aucun profil.

La politique exige exactement une règle prénom et une règle nom REQUIRED/JOIN/IDENTIFICATION. Les autres champs obligatoires ne peuvent bloquer JOIN ; un champ OPTIONAL reste au stade OPTIONAL. La photo n'accepte que OPTIONAL/OPTIONAL/PERSONALISATION. Le téléphone/email ont LESSON_CONTACT, la naissance COURSE_ELIGIBILITY ou CERTIFICATE, l'adresse POSTAL_CONTACT ou CERTIFICATE. Les exigences CONDITIONAL sont réservées à BEFORE_COURSE dans cette tranche et ne sont jamais assimilées à une obligation sans contexte réglementaire qualifié.

La publication initialise les progressions manquantes selon les rôles effectifs, sans prénom extrait du nom public, sans changement des coordonnées existantes et sans accord implicite. Une invitation acceptée ensuite bénéficie de la même initialisation transactionnelle. Un accueil déjà terminé reste COMPLETED lorsque les données JOIN et sa revue restent adéquates, même si une nouvelle politique concerne une future leçon (R99). STAFF ne certifie ici ni disponibilités ni qualification de l'appareil : ces modules restent hors tranche.

Les identités globales de l'acteur et de l'élève sont verrouillées dans l'ordre des UUID, puis la clé d'opération, l'école, l'appartenance et la ressource. Les futures commandes d'affectation doivent reprendre le verrou scolaire commun. La preuve AP72 reste liée à l'auteur et à la portée actuelle ; un 404 après révocation ne prouve pas l'absence d'un ancien commit.

## Qualification

Le 24 septembre 2026, sur PostgreSQL **17.11** dédié au port 55434 : **113 tests serveur réussis**, dont **24 G1D1**, puis typecheck et build réussis. La suite G1B applique 001 puis 002–004 sous un propriétaire NOSUPERUSER, NOBYPASSRLS, NOCREATEDB et NOCREATEROLE ; le backfill est vérifié avec des données préexistantes. Les 17 tables métier conservent ENABLE/FORCE RLS.

Les tests G1D1 valident les enveloppes canoniques, la notice UUID persistée et la projection compatible d'une ancienne preuve G1B, l'initialisation sans effet de GET, la publication concurrente, l'effet différé, les champs protégés en SQL et HTTP, le rejeu avec droits réduits ou révoqués, les versions AP16/AP176, les noms Unicode sans troncature, la readiness minimale, l'accueil propre, l'acceptation G1C après publication et les rollbacks réels de profil/publication provoqués par échec d'audit. Les politiques futures/historiques sont invisibles aux non-ADMIN.

Ces preuves sont locales. Aucun déploiement de 004 ni recette sur appareil n'est revendiqué ici. Les qualifications web/iOS restent distinctes ; catalogue, approbation de formation, documents, agenda et contexte réglementaire conditionnel ne sont pas rendus disponibles par la complétion du profil.
