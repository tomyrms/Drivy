# Entrée élève avec plusieurs rôles

La destination native d’une école ACTIVE est le terrain moniteur si le compte possède INSTRUCTOR, sinon les onglets élève s’il possède LEARNER, sinon le bureau web pour ADMIN. Un compte ADMIN + LEARNER sans INSTRUCTOR doit donc retrouver son dossier personnel, même s’il apparaît après les cinquante premiers dossiers administratifs ou s’il est archivé.

L’extension de réalisation GET `/v1/schools/{schoolId}/learners?own=true` ajoute le prédicat `learner.person_id = actor.personId` aux contrôles existants de rôle et d’école. Elle ne reçoit aucun identifiant de personne du client et n’accorde aucun accès supplémentaire. `own` accepte seulement les chaînes `true` et `false` ; absent ou faux, la liste garde son comportement antérieur. Le filtre fait partie de la portée du curseur. `status=ALL` doit être demandé séparément pour inclure le dossier archivé. La contrainte unique `(school_id, person_id)` borne cette lecture personnelle à un dossier. Le canon OpenAPI 3.11.0 est conservé sans modification ; l’enveloppe de réponse reste celle de la liste existante.

`DrivyAPIClient.ownLearners` demande explicitement `own=true&status=ALL`. `SchoolWorkspace` choisit cette lecture à l’entrée et au rafraîchissement lorsque la destination est élève. Les listes moniteur, y compris ADMIN + INSTRUCTOR + LEARNER, conservent leur recherche et pagination ordinaires.

Mettre à jour l’API avant de distribuer cette nouvelle IPA : l’ancien serveur rejette le paramètre `own` inconnu. L’API étendue reste compatible avec les clients précédents qui ne l’envoient pas.

La régression est décrite dans `g1a.integration.test.ts` sur PostgreSQL avec cinquante et un autres dossiers ajoutés, un dossier personnel actif puis archivé, l’annuaire inchangé, l’identité serveur, l’isolation scolaire, la révocation et la portée du curseur. Les tests Swift contrôlent la requête HTTP et les lectures du workspace pour LEARNER et ADMIN + LEARNER, ainsi que la liste ordinaire des combinaisons INSTRUCTOR. Le scénario UI `SchoolEntryTests/testAdminLearnerFindsOwnDossierBeyondTheFirstDirectoryPage` utilise une première page de cinquante autres dossiers et une lecture personnelle distincte : il exige « Aucune formation » plutôt que « Dossier pas encore ouvert », puis retrouve « Mes informations » dans Profil. Ces nouveaux contrôles doivent être qualifiés sur PostgreSQL et runner Apple ; leur présence dans les sources ne constitue pas une exécution.

## Limites des preuves d’entrée existantes

Les trois tests UI `SchoolEntryTests` montent `SchoolHomeView` avec une API en mémoire. Ils qualifient les écrans DRAFT ADMIN et INSTRUCTOR, ACTIVE ADMIN seul, ARCHIVED et la transition vers le terrain après le bouton Actualiser. Ils ne montent pas `SchoolRootView` ou `DrivyApp` : l’assertion d’absence d’accueil ne prouve donc pas à elle seule la garde de présentation automatique racine. Cette garde est relue dans le code et son prédicat possède des tests unitaires.

Les tests unitaires de retour appellent `refreshOnForeground` et le branchement de cette méthode au premier plan est présent dans `DrivyApp`. Aucune de ces campagnes UI n’ouvre Safari, ne traverse un vrai OIDC natif ni ne change de compte entre Safari et l’app. Le comportement d’un retour externe réel reste une qualification distincte ; aucune qualification physique n’est déduite des simulateurs.
