# Console des opérateurs de la plateforme — R01-T01 (#453)

Décisions d'implémentation du premier lot de l'épic #452 (administration commerciale de la plateforme). Date : 13 novembre 2026. Branche `tomyrms/r01-t01-operateurs`. Rien n'est déployé.

## Périmètre

Ouvrir la console Drivy à une équipe d'opérateurs administrable en base, inviter un opérateur identifié avec un code de plateforme, garantir qu'il reste toujours un opérateur actif, tracer chaque action commerciale dans un journal, et exposer une console web privée (équipe, invitations, journal). Les écoles, codes d'ouverture, offres, paiements et suspensions viendront dans les lots suivants (#454, #455) et réutiliseront le point d'entrée et le journal décrits ici.

Ce lot remplace, pour l'autorisation des routes d'ouverture d'école, la liste d'environnement `SCHOOL_OPENING_OPERATORS_JSON` décrite dans `realisation-onboarding-ecole-20261013.md` et `onboarding-api-20261013.md` : l'équipe en base est désormais la seule source, et l'ancienne liste ne sert plus qu'à la mise en service explicite.

L'opérateur n'est pas un rôle scolaire. Il n'a accès à aucun dossier, trajet, message ni rôle d'école ; un administrateur d'école, un élève ou un ancien opérateur ne peuvent pas appeler les routes de la plateforme.

## Modèle de données

Migration `apps/api/migrations/20261113_platform_operators.sql`. Son nom est daté : les tests de capture ne rejouent que les migrations numérotées `NNN_`, le compteur de tables à RLS forcée reste donc à 67 ; la RLS des tables de plateforme est prouvée dans `platform-operators.integration.test.ts`.

| Table | Rôle |
| --- | --- |
| `platform_operator` | Équipe. Identité (émetteur OIDC + sujet) fixe, `status` ACTIVE ou REVOKED (terminal), `added_via` BOOTSTRAP ou INVITATION, `version` incrémentée par déclencheur. Index uniques partiels : une seule ligne active par identité et par adresse. |
| `platform_operator_invitation` | Invitation. Empreinte HMAC du code (jamais le code), adresse de l'invité, statut AVAILABLE, USED ou REVOKED, expiration d'au plus 30 jours en base. |
| `platform_operation` | Reçus durables par émetteur, sujet et identifiant d'opération : un rejeu à l'identique rend le même résultat, un identifiant réutilisé avec un autre contenu est refusé. Ajout seul. |
| `platform_audit_event` | Journal commercial. Ajout seul (déclencheurs contre UPDATE et DELETE). |

Toutes sont sous RLS forcée. Deux fonctions `SECURITY DEFINER` relisent l'autorisation en base : `current_platform_operator()` (l'identité de la session est un opérateur actif) et `platform_invitation_acceptable()` (le code correspond à une invitation encore acceptable pour cette identité). Les politiques de `school_opening_link` exigent désormais `current_platform_operator()` : la liste d'opérateurs d'environnement n'accorde plus rien par elle-même.

Déclencheurs :

- `platform_operator_guard` : identité figée, état REVOKED terminal, pas de suppression, et garantie du dernier opérateur (voir plus bas) ;
- incrément de `version` à chaque modification ;
- ajout seul sur le journal et les reçus.

## Niveau de droits unique

Un seul niveau, `COMMERCIAL`. Droits accordés : `MANAGE_PLATFORM_TEAM`, `MANAGE_SCHOOL_OPENINGS`, `READ_COMMERCIAL_JOURNAL`. Droits jamais accordés, affichés comme tels avant l'acceptation : accès aux dossiers (`SCHOOL_RECORDS`), aux trajets (`TRIPS`), aux messages (`MESSAGES`) et aux rôles scolaires (`SCHOOL_ROLES`). Un lot qui ajoute une capacité l'ajoute à `platformRights` (`apps/api/src/platform-model.ts`) ; la console affiche un libellé de repli pour un droit qu'elle ne connaît pas encore.

## Invitations

Routes `/v1/platform/…` : `me`, `operators`, `invitations` (liste et création), `invitations/:id/revoke`, `operators/:id/revoke`, `operations/:operationId`, `journal`, `invitations/preview`, `invitations/accept`.

- Le code de plateforme a la forme `XXXXX-XXXXX`, alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sans O, 0, I, 1). Il est distinct des codes d'ouverture d'école : autre format, autre table, autre étiquette de dérivation de la clé HMAC (`drivy/platform-operator-invitation/v1`, dérivée de `INVITATION_CODE_SECRET`, optionnel, 32 caractères au moins, repli sur le secret de curseur).
- Validité : 7 jours par défaut, de 1 à 14 jours côté service, 30 jours au plus côté base.
- L'aperçu (`preview`) montre, avant toute acceptation : adresse masquée, droits accordés, droits jamais accordés, expiration. L'acceptation exige la confirmation liée à cet aperçu ; si les droits changent entre l'aperçu et l'envoi, la confirmation est annulée.
- Aucun privilège avant l'acceptation confirmée par le serveur : la ligne `platform_operator` n'est créée que dans la transaction d'acceptation, qui relit l'invitation avec verrou.
- L'invité doit déjà avoir un compte dont l'adresse est vérifiée et identique à celle de l'invitation.
- Refus distincts et lisibles : code mal formé ou inconnu (`PLATFORM_INVITATION_INVALID`), mauvaise adresse ou adresse non vérifiée (`PLATFORM_INVITATION_EMAIL_MISMATCH`), expirée (`PLATFORM_INVITATION_EXPIRED`), révoquée (`PLATFORM_INVITATION_REVOKED`), déjà consommée (`PLATFORM_INVITATION_USED`), compte déjà membre (`PLATFORM_ALREADY_MEMBER`), invitation déjà en attente pour cette adresse (`PLATFORM_INVITATION_PENDING`).
- Frein sur les essais de code : 10 essais par identité sur 15 minutes (`INVITATION_CODE_ATTEMPTS`) ; seul le compte qui essaie est ralenti.
- Deux comptes visant la même invitation, ou une acceptation concurrente d'une révocation : une seule issue, jamais d'accès accordé à une invitation révoquée.

## Dernier opérateur actif

Trois barrières :

1. le service refuse le retrait du dernier actif avec un message précis ;
2. le déclencheur `platform_operator_guard` prend un verrou consultatif de transaction sur toute l'équipe (`hashtextextended('drivy.platform_operator.team', 0)`), relit l'équipe et refuse un retrait qui laisserait zéro opérateur actif ;
3. le même déclencheur couvre le SQL direct : aucune route ne peut le contourner.

Preuves, dans `platform-operators.integration.test.ts` : « dernier opérateur : refusé par le service puis par la base, y compris en SQL direct », « dernier opérateur sous concurrence », « dernier opérateur sous rafale : cinq retraits simultanés en SQL, il en reste exactement un », « retraits croisés par le service ».

Un opérateur peut se retirer lui-même tant qu'un autre reste actif ; l'action est tracée à son nom et son accès se ferme ensuite.

## Révocation effective

L'API relit l'équipe en base à chaque requête (`requirePlatformOperator`) et les politiques RLS relisent `current_platform_operator()` à chaque instruction : un opérateur retiré perd l'accès à sa prochaine requête, sans attendre l'expiration d'un jeton. Côté web, une réponse 403 `PLATFORM_OPERATOR_REQUIRED` fait retirer de la session l'invitation en cours d'émission, et un autre compte ne reçoit ni le code émis ni l'acceptation en cours du compte précédent. La console n'affiche ni équipe, ni invitation, ni journal avant la preuve du serveur.

## Journal commercial

Une ligne par action : acteur de plateforme (ou SYSTEM pour la mise en service), date, école si l'action en vise une, action, résultat (SUCCESS ou REFUSED), motif de refus, identifiant d'opération, sujet et modification utile. Ni code, ni lien, ni jeton n'y figurent. Actions actuelles : `CREATE_PLATFORM_INVITATION`, `REVOKE_PLATFORM_INVITATION`, `REVOKE_PLATFORM_OPERATOR`, `ACCEPT_PLATFORM_INVITATION`, `BOOTSTRAP_PLATFORM_OPERATOR`, ainsi que `CREATE_SCHOOL_OPENING_LINK` et `REVOKE_SCHOOL_OPENING_LINK` (les routes d'ouverture existantes écrivent maintenant au journal).

Lecture : `GET /v1/platform/journal`, filtres `schoolId` et `result`, pagination par curseur (50 par défaut, 100 au plus).

### Point d'entrée réutilisable pour les lots suivants

`apps/api/src/platform-command.ts` :

- `requirePlatformOperator(pool, identity)` : relit l'opérateur en base, sinon 403 `PLATFORM_OPERATOR_REQUIRED` ;
- `platformRead(pool, identity, work)` : lecture réservée à un opérateur actif, avec l'acteur confirmé par la base ;
- `platformCommand(...)` et `platformTransaction(...)` : exécutent une commande de plateforme avec acteur confirmé, clé d'idempotence, reçu durable, contrôle de version et écriture au journal dans la même transaction ;
- `recordPlatformAction(db, actor, entry, { operationId })` : écrit une ligne de journal depuis une transaction existante (utilisé par l'ouverture d'école).

Une commande décrit `kind`, `operationId`, `body`, `expectedVersion`, `teamWide` (verrou d'équipe) et `refusal` (action à journaliser si la commande est refusée), puis un effet : `data`, `status`, `journal` (action, école, sujet, modification) et `apply`. Un refus est journalisé comme REFUSED sans secret. Les lots #454 (écoles et codes), #455 (offres et modules), puis paiements, suspension et annulation y ajoutent leurs actions, avec `schoolId` pour rattacher la ligne à l'école ; aucune nouvelle machinerie de version, de reçu ou de journal n'est à écrire.

## Concurrence et idempotence

- Chaque mutation porte `Idempotency-Key` égale à `operationId` et, sur une ressource existante, `If-Match` avec la version attendue (validateur fort). Version périmée : 412 `VERSION_CONFLICT`, rien n'est écrasé. Identifiant réutilisé avec un autre contenu : 409 `IDEMPOTENCY_MISMATCH`.
- Le reçu est durable : une réponse perdue se reprend en renvoyant la même demande (même identifiant), ou en lisant `GET /v1/platform/operations/:operationId`.
- Erreurs au format problem+json.

## Mise en service des premiers comptes

Aucun opérateur n'a accès tant que la mise en service n'a pas tourné. Procédure :

1. appliquer les migrations (`npm run migrate`) ;
2. fournir en configuration privée, jamais dans le dépôt : `MIGRATION_DATABASE_URL` (propriétaire de la base, obligatoire) et `PLATFORM_OPERATORS_BOOTSTRAP_JSON`, un tableau JSON de 10 entrées au plus, chaque entrée portant `issuer`, `subject` et, facultativement, `displayName` (entrée stricte : tout autre champ est refusé) ;
3. lancer `npm run operators:bootstrap` dans `apps/api` ;
4. redémarrer l'API ensuite.

Le script prend le verrou d'équipe, est idempotent (relancé, il n'ajoute rien), écrit un événement de journal par compte mis en service avec l'acteur SYSTEM, et ne rapporte que des compteurs, jamais un identifiant.

Migration des opérateurs existants : l'option `--legacy-opening-operators` lit en plus `SCHOOL_OPENING_OPERATORS_JSON` (l'ancienne liste d'environnement) et inscrit ces comptes explicitement dans l'équipe. Sans cette option, ou sans passage du script, l'ancienne liste n'ouvre plus rien : aucun accès général n'est ouvert par la migration seule.

Aucun identifiant réel n'est publié dans le dépôt, les tests ni cette documentation. Le déploiement lui-même (migration, mise en service, redémarrage) reste à décider et à faire par le porteur ; il n'a pas eu lieu.

## Console web

Pages privées `/app/plateforme` (onglets Équipe, Invitations, Journal) et `/app/plateforme/rejoindre` (saisie du code, aperçu des droits, acceptation). Passerelle `apps/web/server/platform-routes.ts`, sous `/app/bff/platform/…`, avec une liste fermée de routes : une route absente de la liste est refusée sans requête amont. Origine et jeton CSRF sont vérifiés avant tout appel.

Décisions :

- le code d'invitation naît dans le relais web, n'est rendu à l'écran qu'à la création, reste en mémoire de session le temps d'une réponse perdue (même code, même demande) et n'est jamais relu ; `invitations/clear` l'efface après « J'ai transmis le code » ;
- confirmation précise seulement pour le retrait d'un opérateur (adresse nommée, effet, retour impossible) ; la révocation d'une invitation et l'émission n'en demandent pas ;
- conflit de version : la liste est rechargée, rien n'est écrasé ; réponse perdue : état « non confirmé » avec reprise de la même demande ; accès refusé : aucune donnée d'équipe affichée ;
- peu de texte : pas de sous-titre ni de note sous les sections, les titres de section qui répètent l'onglet restent dans l'arbre d'accessibilité sans être affichés, une explication seulement en cas d'erreur ;
- aperçu synthétique (`?page=plateforme`, `?page=plateforme-rejoindre`, scénarios `refused`, `conflict`, `slow`, `lost-reply`) avec des données fictives et un faux code `DEMNK-X7K42`.

Contrôle navigateur reproductible : `scripts/dev/check-platform-console.mjs` (27 vérifications sur l'aperçu, Edge, bureau 1280 x 900 et mobile 390 x 844, clair et sombre) produit les captures. Il porte sur l'aperçu synthétique : ce n'est ni une qualification sur appareil ni un essai contre la vraie API.

## Contrat

`apps/api/contracts/platform-operators.json` : extension OpenAPI générée par `apps/api/scripts/generate-platform-contract.ts` et gardée par `platform-contract.test.ts`. Le contrat canonique 3.11.0 est inchangé.

## Écarts et limites

- Node 24 demandé, Node 26.8.1 seul disponible sur le poste : toutes les vérifications ont tourné sous Node 26.8.1.
- Les tests de la base se sont exécutés sur un PostgreSQL 17 de test local, pas sur le homelab.
- L'invité doit déjà avoir un compte à l'adresse vérifiée ; il n'y a pas d'envoi de courriel (pas de SMTP en production, CC1.1) : le code est transmis par l'opérateur hors de la console.
- Les droits sont transmis par la passerelle tels que l'API les envoie ; un droit nouveau sans libellé s'affiche avec un libellé de repli.
- Non vérifié : appareil physique, VoiceOver, console contre la vraie API dans un navigateur, déploiement.
