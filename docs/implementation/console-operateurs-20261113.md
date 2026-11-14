# Console des opérateurs de la plateforme — R01-T01 (#453)

Décisions d'implémentation du premier lot de l'épic #452 (administration commerciale de la plateforme). Date : 13 novembre 2026. Branche `tomyrms/r01-t01-operateurs`. Rien n'est déployé.

## Périmètre

Ouvrir la console Drivy à une équipe d'opérateurs administrable en base, inviter un opérateur identifié avec un code de plateforme, garantir qu'il reste toujours un opérateur actif, tracer chaque action commerciale dans un journal, et exposer une console web privée (équipe, invitations, journal). Les écoles, codes d'ouverture, offres, paiements et suspensions viendront dans les lots suivants (#454, #455) et réutiliseront le point d'entrée et le journal décrits ici.

Ce lot remplace, pour l'autorisation des routes d'ouverture d'école, la liste d'environnement `SCHOOL_OPENING_OPERATORS_JSON` décrite dans `realisation-onboarding-ecole-20261013.md` et `onboarding-api-20261013.md` : l'équipe en base est désormais la seule source, et l'ancienne liste ne sert plus qu'à la mise en service explicite.

L'opérateur n'est pas un rôle scolaire. Il n'a accès à aucun dossier, trajet, message ni rôle d'école ; un administrateur d'école, un élève ou un ancien opérateur ne peuvent pas appeler les routes de la plateforme.

## Modèle de données

Migration `apps/api/migrations/20261113_platform_operators.sql`. Son nom est daté : les tests de capture ne rejouent que les migrations numérotées `NNN_`, le compteur de tables à RLS forcée reste donc à 67 ; la RLS des tables de plateforme est prouvée dans `platform-operators.integration.test.ts`.

Migration complémentaire `apps/api/migrations/20261113b_platform_invitation_creator_active.sql` (correction de la revue indépendante, voir « Révocation effective »). Elle est séparée de la première parce que `npm run migrate` enregistre l'empreinte SHA-256 de chaque fichier dans `public.drivy_migrations` et refuse une migration appliquée puis modifiée : une base où `20261113_` a déjà tourné aurait été en erreur. Le suffixe `b` est accepté par `migrationFilePattern` et la trie après `20261113_` (`_` précède `b`).

| Table | Rôle |
| --- | --- |
| `platform_operator` | Équipe. Identité (émetteur OIDC + sujet) fixe, `status` ACTIVE ou REVOKED (terminal), `added_via` BOOTSTRAP ou INVITATION, `version` incrémentée par déclencheur. Index uniques partiels : une seule ligne active par identité et par adresse. |
| `platform_operator_invitation` | Invitation. Empreinte HMAC du code (jamais le code), adresse de l'invité, statut AVAILABLE, USED ou REVOKED, expiration d'au plus 30 jours en base. |
| `platform_operation` | Reçus durables par émetteur, sujet et identifiant d'opération : un rejeu à l'identique rend le même résultat, un identifiant réutilisé avec un autre contenu est refusé. Ajout seul. |
| `platform_audit_event` | Journal commercial. Ajout seul (déclencheurs contre UPDATE et DELETE). |

Toutes sont sous RLS forcée. Trois fonctions `SECURITY DEFINER` relisent l'autorisation en base : `current_platform_operator()` (l'identité de la session est un opérateur actif), `platform_invitation_acceptable()` (le code correspond à une invitation encore acceptable pour cette identité, et son auteur est toujours un opérateur actif) et `platform_invitation_creator_active()` (réponse booléenne pour le seul code de la session, utilisée pour un refus lisible). Les politiques de `school_opening_link` exigent désormais `current_platform_operator()` : la liste d'opérateurs d'environnement n'accorde plus rien par elle-même.

Déclencheurs :

- `platform_operator_guard` : identité figée, état REVOKED terminal, pas de suppression, et garantie du dernier opérateur (voir plus bas) ;
- incrément de `version` à chaque modification ;
- ajout seul sur le journal et les reçus.

## Niveau de droits unique

Un seul niveau, `COMMERCIAL`. Droits accordés : `MANAGE_PLATFORM_TEAM`, `MANAGE_SCHOOL_OPENINGS`, `MANAGE_OFFERS` (ajouté par R01-T03, #455 : offres, attributions et ajustements de modules), `READ_COMMERCIAL_JOURNAL`. Droits jamais accordés, affichés comme tels avant l'acceptation : accès aux dossiers (`SCHOOL_RECORDS`), aux trajets (`TRIPS`), aux messages (`MESSAGES`) et aux rôles scolaires (`SCHOOL_ROLES`). Un lot qui ajoute une capacité l'ajoute à `platformRights` (`apps/api/src/platform-model.ts`) ; la console affiche un libellé de repli pour un droit qu'elle ne connaît pas encore.

## Invitations

Routes `/v1/platform/…` : `me`, `operators`, `invitations` (liste et création), `invitations/:id/revoke`, `operators/:id/revoke`, `operations/:operationId`, `journal`, `invitations/preview`, `invitations/accept`.

- Le code de plateforme a la forme `XXXXX-XXXXX`, alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` (sans O, 0, I, 1). Il est distinct des codes d'ouverture d'école : autre format, autre table, autre étiquette de dérivation de la clé HMAC (`drivy/platform-operator-invitation/v1`, dérivée de `INVITATION_CODE_SECRET`, optionnel, 32 caractères au moins, repli sur le secret de curseur). Conséquence à connaître : tant que `INVITATION_CODE_SECRET` n'est pas défini, changer `CURSOR_SECRET` invalide les invitations en attente (leur code ne correspond plus à l'empreinte stockée) ; elles sont à réémettre. Définir `INVITATION_CODE_SECRET` à part, avant la première invitation en production, découple les deux rotations. Limite documentée, non corrigée : rendre le secret dédié obligatoire changerait la configuration de tous les environnements.
- Validité : 7 jours par défaut, de 1 à 14 jours côté service, 30 jours au plus côté base.
- L'aperçu (`preview`) montre, avant toute acceptation : adresse masquée, droits accordés, droits jamais accordés, expiration. L'acceptation exige la confirmation liée à cet aperçu ; si les droits changent entre l'aperçu et l'envoi, la confirmation est annulée.
- Aucun privilège avant l'acceptation confirmée par le serveur : la ligne `platform_operator` n'est créée que dans la transaction d'acceptation, qui relit l'invitation avec verrou.
- L'invité doit déjà avoir un compte dont l'adresse est vérifiée et identique à celle de l'invitation.
- Refus distincts et lisibles : code mal formé ou inconnu (`PLATFORM_INVITATION_INVALID`), mauvaise adresse ou adresse non vérifiée (`PLATFORM_INVITATION_EMAIL_MISMATCH`), expirée (`PLATFORM_INVITATION_EXPIRED`), révoquée (`PLATFORM_INVITATION_REVOKED`), déjà consommée (`PLATFORM_INVITATION_USED`), compte déjà membre (`PLATFORM_ALREADY_MEMBER`), invitation déjà en attente pour cette adresse (`PLATFORM_INVITATION_PENDING`).
- Frein sur les essais de code : 10 essais par identité sur 15 minutes (`INVITATION_CODE_ATTEMPTS`) ; seul le compte qui essaie est ralenti.
- Deux comptes visant la même invitation, ou une acceptation concurrente d'une révocation : une seule issue, jamais d'accès accordé à une invitation révoquée.
- Une invitation ne survit pas à son auteur : voir « Révocation effective ».
- Le code est généré par le relais web (`platformInvitationCode`) puis empreinté et comparé par l'API (`generatePlatformCode`, `normalizePlatformCode`) : la normalisation et l'alphabet existent donc en deux copies. `apps/api/test/platform-code-parity.test.ts` importe les deux et échoue dès qu'elles divergent (entrées normalisées une à une, mêmes refus, 4 000 codes par côté dont l'alphabet observé doit être identique et sans O, 0, I, 1).

## Dernier opérateur actif

Trois barrières :

1. le service refuse le retrait du dernier actif avec un message précis ;
2. le déclencheur `platform_operator_guard` prend un verrou consultatif de transaction sur toute l'équipe (`hashtextextended('drivy.platform_operator.team', 0)`), relit l'équipe et refuse un retrait qui laisserait zéro opérateur actif ;
3. le même déclencheur couvre le SQL direct : aucune route ne peut le contourner.

Preuves, dans `platform-operators.integration.test.ts` : « dernier opérateur : refusé par le service puis par la base, y compris en SQL direct », « dernier opérateur sous concurrence », « dernier opérateur sous rafale : cinq retraits simultanés en SQL, il en reste exactement un », « retraits croisés par le service ».

Un opérateur peut se retirer lui-même tant qu'un autre reste actif ; l'action est tracée à son nom et son accès se ferme ensuite.

## Révocation effective

L'API relit l'équipe en base à chaque requête (`requirePlatformOperator`) et les politiques RLS relisent `current_platform_operator()` à chaque instruction : un opérateur retiré perd l'accès à sa prochaine requête, sans attendre l'expiration d'un jeton. Côté web, une réponse 403 `PLATFORM_OPERATOR_REQUIRED` fait retirer de la session l'invitation en cours d'émission, et un autre compte ne reçoit ni le code émis ni l'acceptation en cours du compte précédent. La console n'affiche ni équipe, ni invitation, ni journal avant la preuve du serveur.

Les invitations d'un opérateur retiré s'arrêtent avec lui (revue indépendante, point I1). Avant correction, une invitation créée par un opérateur ensuite retiré restait acceptable : le retrait fermait son accès mais pas le code qu'il avait émis. Trois barrières, dans cet ordre :

1. le retrait d'un opérateur révoque, dans la même transaction, toutes ses invitations encore disponibles (statut REVOKED, `revoked_by` = l'opérateur qui retire), y compris lors d'un retrait volontaire ; le nombre d'invitations révoquées est écrit au journal (`changes.revokedInvitations`) et la console l'affiche (« 1 invitation révoquée ») ;
2. `platform_invitation_acceptable()` (migration `20261113b`) exige que l'auteur de l'invitation soit ACTIVE : même une ligne restée AVAILABLE n'ouvre plus rien, et la politique d'insertion dans `platform_operator` la refuse ;
3. le service relit cette condition (`assertOpen`) et répond 410 `PLATFORM_INVITATION_REVOKED` avec le message « Cette invitation a été révoquée. Demandez-en une nouvelle. ».

Fenêtre résiduelle, assumée : une invitation dont la création a démarré avant le retrait de son auteur peut être validée juste après lui. Elle reste alors listée « En attente », mais elle est inerte (barrières 2 et 3) et ne peut jamais produire de ligne `platform_operator`. Preuves : trois tests de `platform-operators.integration.test.ts` (A invite, B retire A, l'acceptation est refusée, aucune ligne d'opérateur n'est créée, la console reflète la révocation et le journal porte le compte), plus `journalDetail` dans `platform-model.test.tsx`.

Côté client, la console ne se fie plus au seul couple `email|displayName` pour détecter un changement de compte : elle relit `platform/me` au retour de focus et se réinitialise si l'identifiant d'opérateur diffère (`use-platform-console.ts`). Côté passerelle, la session compare le sujet OIDC sans l'émetteur (`session.ts`) parce que la refonte ne configure qu'un seul émetteur OIDC (`Principal` ne porte pas l'émetteur) : ajouter un second émetteur imposerait d'y ajouter l'émetteur. Limite documentée.

## Journal commercial

Une ligne par action : acteur de plateforme (ou SYSTEM pour la mise en service), date, école si l'action en vise une, action, résultat (SUCCESS ou REFUSED), motif de refus, identifiant d'opération, sujet et modification utile. Ni code, ni lien, ni jeton n'y figurent. `REVOKE_PLATFORM_OPERATOR` porte `changes.revokedInvitations` (nombre d'invitations disponibles révoquées avec l'opérateur). Actions actuelles : `CREATE_PLATFORM_INVITATION`, `REVOKE_PLATFORM_INVITATION`, `REVOKE_PLATFORM_OPERATOR`, `ACCEPT_PLATFORM_INVITATION`, `BOOTSTRAP_PLATFORM_OPERATOR`, ainsi que `CREATE_SCHOOL_OPENING_LINK` et `REVOKE_SCHOOL_OPENING_LINK` (les routes d'ouverture existantes écrivent maintenant au journal).

Lecture : `GET /v1/platform/journal`, filtres `schoolId` et `result`, pagination par curseur (50 par défaut, 100 au plus).

### Point d'entrée réutilisable pour les lots suivants

`apps/api/src/platform-command.ts` :

- `requirePlatformOperator(pool, identity)` : relit l'opérateur en base, sinon 403 `PLATFORM_OPERATOR_REQUIRED` ;
- `platformRead(pool, identity, work)` : lecture réservée à un opérateur actif, avec l'acteur confirmé par la base ;
- `platformCommand(...)` et `platformTransaction(...)` : exécutent une commande de plateforme avec acteur confirmé, clé d'idempotence, reçu durable, contrôle de version et écriture au journal dans la même transaction ;
- `recordPlatformAction(db, actor, entry, { operationId })` : écrit une ligne de journal depuis une transaction existante (utilisé par l'ouverture d'école).

Une commande décrit `kind`, `operationId`, `body`, `expectedVersion`, `teamWide` (verrou d'équipe) et `refusal` (action à journaliser si la commande est refusée), puis un effet : `data`, `status`, `journal` (action, école, sujet, modification) et `apply`. Un refus est journalisé comme REFUSED sans secret, dans une seconde transaction ouverte après l'annulation de la première : cette écriture est faite au mieux (si la base est indisponible à cet instant, le refus est rendu au demandeur mais n'apparaît pas au journal). Un succès, lui, est écrit dans la transaction même de l'effet : pas d'effet sans ligne de journal. Les lots #454 (écoles et codes), #455 (offres et modules), puis paiements, suspension et annulation y ajoutent leurs actions, avec `schoolId` pour rattacher la ligne à l'école ; aucune nouvelle machinerie de version, de reçu ou de journal n'est à écrire.

## Concurrence et idempotence

- Chaque mutation porte `Idempotency-Key` égale à `operationId` et, sur une ressource existante, `If-Match` avec la version attendue (validateur fort). Version périmée : 412 `VERSION_CONFLICT`, rien n'est écrasé. Identifiant réutilisé avec un autre contenu : 409 `IDEMPOTENCY_MISMATCH`.
- Le reçu est durable : une réponse perdue se reprend en renvoyant la même demande (même identifiant), ou en lisant `GET /v1/platform/operations/:operationId`.
- Erreurs au format problem+json.

## Mise en service des premiers comptes

### Ce qui change au déploiement, et pourquoi c'est bloquant par construction

Depuis ce lot, l'autorisation des routes d'ouverture d'école se lit dans la table `platform_operator`, et les politiques RLS de `school_opening_link` relisent `current_platform_operator()` à chaque instruction. Conséquence : **après la migration, tant qu'aucun opérateur n'est inscrit en base, toute ouverture d'école répond 403 `OPERATOR_REQUIRED`** ; l'ancienne liste `SCHOOL_OPENING_OPERATORS_JSON` ne donne plus aucun droit par elle-même. C'est voulu : la migration seule n'ouvre aucun accès général et ne devine aucune identité.

Ce blocage est porté par la base, pas par le code de l'API : il touche aussi la release précédente tant que son lien `current` est actif. La fenêtre entre « migration appliquée » et « premier opérateur inscrit » doit donc être la plus courte possible, d'où l'ordre ci-dessous. Elle est acceptable seulement parce que le script d'installation la referme dans la même exécution et refuse de basculer le lien sans opérateur actif (voir l'étape 3).

Ce blocage a été constaté, avant correction, par la recette navigateur « Refonte · ouverture école navigateur » (run 43401665351) : elle ne définissait son opérateur que par configuration et recevait 403 `OPERATOR_REQUIRED` à la création du lien. La recette amorce maintenant son opérateur par la voie officielle (`operators:bootstrap`) ; la règle d'autorisation n'a pas été touchée.

### Ordre imposé

1. **Sauvegarde** de la base `drivy_refonte` (point de retour du schéma ; une migration ne se défait pas) avant tout le reste, selon la procédure de `deploiement-refonte.md`.
2. **Configuration privée**, jamais dans le dépôt : dans `/etc/drivy-refonte/migration.env`, `MIGRATION_DATABASE_URL` (propriétaire de la base) et, si les comptes ne figurent pas déjà dans `SCHOOL_OPENING_OPERATORS_JSON` de `api.env`, `PLATFORM_OPERATORS_BOOTSTRAP_JSON` : un tableau JSON de 10 entrées au plus, chaque entrée portant `issuer`, `subject` et, facultativement, `displayName` (entrée stricte : tout autre champ est refusé). Une liste vide est refusée avec un message explicite.
3. **Migration, amorçage et vérification, en une seule commande** :

   ```sh
   python3 /root/drivy-deploy/install-api-release.py --apply /opt/drivy-refonte/releases/<SHA-complet> --bootstrap-operators
   ```

   Le script enchaîne : installation verrouillée, compilation, `npm run migrate` (migrations `20261113` et `20261113b`), puis `npm run operators:bootstrap -- --legacy-opening-operators`, puis le contrôle « au moins un opérateur ACTIVE » sur la connexion propriétaire, puis le contrôle runtime/RLS, puis `npm prune --omit=dev` et enfin la bascule du lien `current`. L'amorçage passe avant le retrait des dépendances de développement parce qu'il utilise `tsx`. **Le contrôle d'équipe est obligatoire** : s'il ne trouve aucun opérateur actif, le script s'arrête avec « Aucun opérateur de plateforme actif », le lien `current` reste inchangé et rien n'est démarré. Oublier l'amorçage fait donc échouer le déploiement au lieu de passer inaperçu ; on relance la même commande avec `--bootstrap-operators` (les migrations déjà appliquées sont sautées, l'amorçage est idempotent). Entre l'échec et la relance, ne pas redémarrer l'API. Le script n'écrit que des compteurs (« N ajouté(s), M déjà actif(s) »), jamais un identifiant ni une adresse de connexion ; il ne transmet à l'amorçage que les deux clés `PLATFORM_OPERATORS_BOOTSTRAP_JSON` et `SCHOOL_OPENING_OPERATORS_JSON`, pas l'environnement runtime entier. `deployment.json` porte `platformTeamVerified: true`.
4. **Redémarrage de l'API** (le script ne démarre ni ne redémarre rien).
5. **Vérification finale** : au moins un opérateur ACTIVE (déjà contrôlé par le script), puis un essai réel avec un opérateur amorcé : ouvrir `/app/plateforme` (l'équipe s'affiche) et créer puis révoquer un lien d'ouverture d'école d'essai. Cet essai de bout en bout en production reste à faire par le porteur.

Sur les déploiements suivants, ne pas repasser `--bootstrap-operators` : le contrôle d'équipe tourne de toute façon et passe dès qu'un opérateur est actif. L'option n'est pas inoffensive après une première mise en service : un compte retiré de l'équipe mais encore présent dans la configuration d'amorçage y serait réinscrit. Après la première mise en service, retirer les entrées d'amorçage de la configuration privée.

Le script d'amorçage (`npm run operators:bootstrap`, lançable seul depuis `apps/api` avec `MIGRATION_DATABASE_URL`) prend le verrou d'équipe, est idempotent pour les comptes déjà actifs, écrit un événement de journal par compte mis en service avec l'acteur SYSTEM, et ne rapporte que des compteurs. L'option `--legacy-opening-operators` lit en plus `SCHOOL_OPENING_OPERATORS_JSON` et inscrit explicitement ces comptes dans l'équipe : c'est le chemin de migration des opérateurs existants. Sans cette option, ou sans passage du script, l'ancienne liste n'ouvre plus rien.

Preuves : `infra/deploy/test_install_api_release.py` (13 tests sans réseau ni base : arguments, clés transmises, codes de sortie du contrôle, ordre amorçage puis contrôle, aucun détail de connexion imprimé, ordre `migrate` < contrôle d'équipe < `prune` < bascule du lien dans le texte du script), enregistré dans `scripts/qualification/run-python-tests.py`. Le script complet ne se rejoue pas hors CT114 : le déroulé réel sur le homelab n'a pas eu lieu.

Aucun identifiant réel n'est publié dans le dépôt, les tests ni cette documentation. Le déploiement lui-même (sauvegarde, migration, mise en service, redémarrage) reste à décider et à faire par le porteur ; il n'a pas eu lieu.

## Console web

Pages privées `/app/plateforme` (onglets Équipe, Invitations, Journal) et `/app/plateforme/rejoindre` (saisie du code, aperçu des droits, acceptation). Passerelle `apps/web/server/platform-routes.ts`, sous `/app/bff/platform/…`, avec une liste fermée de routes : une route absente de la liste est refusée sans requête amont. Origine et jeton CSRF sont vérifiés avant tout appel.

Décisions :

- le code d'invitation naît dans le relais web, n'est rendu à l'écran qu'à la création, reste en mémoire de session le temps d'une réponse perdue (même code, même demande) et n'est jamais relu ; `invitations/clear` l'efface après « J'ai transmis le code » ;
- confirmation précise seulement pour le retrait d'un opérateur (adresse nommée, effet, retour impossible) ; la révocation d'une invitation et l'émission n'en demandent pas ;
- conflit de version : la liste est rechargée, rien n'est écrasé ; réponse perdue : état « non confirmé » avec reprise de la même demande ; accès refusé : aucune donnée d'équipe affichée ;
- peu de texte : pas de sous-titre ni de note sous les sections, les titres de section qui répètent l'onglet restent dans l'arbre d'accessibilité sans être affichés, une explication seulement en cas d'erreur ;
- aperçu synthétique (`?page=plateforme`, `?page=plateforme-rejoindre`, scénarios `refused`, `conflict`, `slow`, `lost-reply`) avec des données fictives et un faux code `DEMNK-X7K42`.

Recette contre la vraie API : `scripts/dev/check-school-opening.ts` (workflow « Refonte · ouverture école navigateur », Chromium, OIDC Keycloak, passerelle web, API, PostgreSQL) amorce son opérateur par `operators:bootstrap`, vérifie que l'équipe est vide avant l'amorçage, puis appelle `scripts/dev/check-platform-team.ts`, qui parcourt la console dans le navigateur : équipe lue en base, retrait du dernier opérateur refusé, invitation d'un collègue (le code n'est conservé nulle part), aucun accès avant l'acceptation, aperçu puis acceptation par un second compte, invitation créée par ce nouvel opérateur, retrait par l'opérateur amorcé, accès fermé pour le retiré, invitation orpheline révoquée (le journal porte `revokedInvitations = 1`), et refus de son code par l'invité sans qu'aucune ligne d'opérateur soit créée. Les vérifications d'état lisent la base par un compte d'administration réservé à la recette.

Contrôle navigateur reproductible : `scripts/dev/check-platform-console.mjs` (27 vérifications sur l'aperçu, Edge, bureau 1280 x 900 et mobile 390 x 844, clair et sombre) produit les captures. Il porte sur l'aperçu synthétique : ce n'est ni une qualification sur appareil ni un essai contre la vraie API.

## Contrat

`apps/api/contracts/platform-operators.json` : extension OpenAPI générée par `apps/api/scripts/generate-platform-contract.ts` et gardée par `platform-contract.test.ts`. Le contrat canonique 3.11.0 est inchangé.

## Écarts et limites

- Node 24 demandé, Node 26.8.1 seul disponible sur le poste : toutes les vérifications ont tourné sous Node 26.8.1.
- Les tests de la base du premier lot se sont exécutés sur un PostgreSQL 17 de test local, pas sur le homelab. Les corrections de la revue (migration `20261113b`, trois tests d'invitation d'un opérateur retiré, recette navigateur) ont été écrites alors que Docker ne répondait plus sur le poste : elles ne se sont pas exécutées en local et ne sont qualifiées que par la CI (résultats dans `STATUS.md`).
- Reçus : `ACCEPT_PLATFORM_INVITATION` est le seul genre de reçu qu'une identité authentifiée non opératrice peut insérer, sous son propre nom, pour rendre son acceptation rejouable. Elle ne lit que ses propres reçus et un reçu ne confère aucun droit ; limite connue, sans effet d'accès.
- Frein d'essais de code : `AttemptLimiter` vit en mémoire du processus. Un redémarrage remet les compteurs à zéro, et plusieurs processus d'API multiplieraient la limite effective. Un seul processus d'API tourne aujourd'hui ; un frein partagé (base) serait à écrire avant d'en exploiter plusieurs. Limite connue.
- Le contrôle d'équipe du script d'installation vérifie qu'au moins un opérateur est actif, pas que ce soit le bon compte : l'essai de l'étape 5 reste nécessaire.
- L'invité doit déjà avoir un compte à l'adresse vérifiée ; il n'y a pas d'envoi de courriel (pas de SMTP en production, CC1.1) : le code est transmis par l'opérateur hors de la console.
- Les droits sont transmis par la passerelle tels que l'API les envoie ; un droit nouveau sans libellé s'affiche avec un libellé de repli.
- Non vérifié : appareil physique, VoiceOver, console contre la vraie API dans un navigateur, déploiement.
