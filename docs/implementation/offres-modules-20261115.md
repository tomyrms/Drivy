# Offres, modules et droits par école — R01-T03 (#455)

Décisions d'implémentation du troisième lot de l'épic #452 (administration commerciale de la plateforme). Date : 14 novembre 2026 ; la migration porte la date 20261115 pour se classer après celles du lot précédent. Branche `tomyrms/r01-t03-offres-modules`, issue de `tomyrms/r01-t02-ecoles-codes`. Rien n'est déployé, aucune PR n'est ouverte, et aucun test n'a été exécuté (règle du porteur du 13 novembre : les tests de l'épic R01 se lanceront une fois, les onze issues codées).

## Périmètre

L'opérateur de la plateforme définit des offres (un ensemble nommé de modules), les attribue à la fiche d'une école avec une date d'effet après avoir vu les conséquences, ajuste un module pour une école avec un motif, et l'API refuse côté serveur l'usage nouveau d'un module que l'école n'a pas. La web (console et espace école) et l'iPhone/iPad affichent ces droits ; ils n'en sont jamais l'autorité.

Ce lot ne contient ni montant, ni essai, ni échéance, ni suspension, ni impayé : ils relèvent de #456. Il laisse seulement des emplacements propres (voir « À savoir pour #456 »). Les écoles existantes ne changent pas : tant qu'aucune offre n'est attribuée à la fiche d'une école, son périmètre reste exactement celui d'aujourd'hui.

## Trois notions qui restent distinctes

Reprise de la fiche R03 :

| Notion | Où elle vit | Ce que ce lot en fait |
| --- | --- | --- |
| Droits de l'offre | `platform_offer`, `platform_offer_assignment`, `platform_module_adjustment` | Défini ici. Seule source de droit commercial. |
| Choix de l'école | `school.modules` (réglages d'activation) | Inchangé. Un réglage de l'école n'accorde jamais un module. |
| Permissions des personnes | rôles et droits scolaires | Inchangées. Le droit commercial s'ajoute au droit de la personne, il ne le remplace pas. |

Un module est utilisable seulement si les trois le permettent. Masquer une rubrique ne suffit jamais : le refus est écrit côté serveur.

## Catalogue de modules

Deux modules, seulement ceux que le code livre réellement :

| Code | Contenu | Surfaces fermées côté serveur |
| --- | --- | --- |
| `MESSAGING` | Messagerie de l'école | Envoi, réactions, épingles, votes, téléversement de médias, nouvelle conversation |
| `COLLECTIVE_COURSES` | Cours collectifs | Gestion des types, de la politique, des séries ; inscription, liste d'attente, acceptation d'une place |

Le catalogue est la table `platform_module` (amorcée par la migration, jamais modifiée ni vidée : déclencheur `platform_module_guard`) ; `entitlements-model.ts` en garde une copie typée et un test d'intégration vérifie qu'elles ne divergent pas. Ajouter un module est une migration qui ajoute une ligne, une entrée de la copie et ses gardes de route ; une offre ou une attribution ne peut pas citer un module inconnu (`platform_offer_modules_invalid`). Le socle (compte, accès, profil, préparation de l'école, consultation commerciale), les leçons et le GPS ne sont pas des modules : aucune offre ne peut les retirer.

## Modèle de données

Migration `apps/api/migrations/20261115_platform_offers_modules.sql` (datée, hors compteur des migrations numérotées ; la RLS est prouvée dans `platform-offers.integration.test.ts`). Aucune donnée n'est créée ni modifiée hors le catalogue : `platform_client.commercial_state` n'est pas touchée.

| Table | Rôle |
| --- | --- |
| `platform_module` | Catalogue. Lecture pour les opérateurs ; pas de mise à jour ni de suppression. |
| `platform_offer` | Offre : nom unique (sans casse), modules rangés dans l'ordre du catalogue, statut ACTIVE ou ARCHIVED, version incrémentée par déclencheur. Jamais supprimée ; une offre archivée est figée. |
| `platform_offer_assignment` | Attribution d'une offre à une fiche, avec date d'effet. Elle copie le nom et les modules de l'offre : modifier l'offre ensuite ne touche pas l'école. Jamais supprimée ni réécrite ; seule une attribution encore future s'annule. |
| `platform_module_adjustment` | Ajustement d'une école : un module accordé (GRANT) ou retiré (REVOKE) en plus de l'offre, avec motif de 3 à 500 caractères, auteur et date. Lié à l'attribution en vigueur. Jamais supprimé ; on le lève (levée motivée, une seule fois). |

Toutes sont sous RLS forcée, lisibles par un opérateur actif relu en base (`current_platform_operator()`), et leurs colonnes modifiables sont limitées par `GRANT UPDATE`. Les déclencheurs (`platform_offer_guard`, `platform_assignment_guard`, `platform_adjustment_guard`) portent les invariants : identité figée, pas de suppression, attribution seulement sur une offre active et non antidatée, instantané conforme à l'offre, ajustement seulement sur l'attribution actuellement en vigueur.

Fonctions `SECURITY DEFINER` à projection fixe :

- `platform_client_entitlement_core(client)` : seul calcul des droits, non exposé ; le service, la lecture de l'école, la fiche de la console et le contrôle de module le partagent, donc ne divergent pas ;
- `school_entitlements(school)` : état, modules accordés ou non, version, prochaine échéance ; réservée à l'équipe et aux membres actifs de l'école ; ni offre, ni motif, ni auteur ;
- `school_module_entitled(school, module)` : booléen pour les gardes de route, faux pour un appelant étranger à l'école et pour un module inconnu (échec fermé) ;
- `platform_client_entitlements(client)` : détail et historique pour l'équipe (50 dernières attributions, 100 derniers ajustements) ;
- `platform_module_usage(client)` : volumes seulement (conversations ; séries publiées, inscriptions actives, séances à venir), jamais un contenu ;
- `platform_offer_overview(...)` : offres avec le nombre d'écoles pour lesquelles chacune est en vigueur (un compte, jamais la liste) ;
- `platform_client_overview(...)` (remplacée) : l'annuaire et la fiche portent l'état dérivé, l'offre en vigueur, l'offre programmée et `entitlement_version`.

## Calcul des droits

- **En vigueur** : la dernière attribution ACTIVE dont la date d'effet est atteinte (ordre : date d'effet, création, identifiant). **Programmée** : la première attribution ACTIVE à date future.
- **État dérivé** : `NOT_CONFIGURED` sans attribution en vigueur ; `OFFER_ACTIVE` sinon. `NOT_CONFIGURED` veut dire « aucune restriction » : tous les modules du catalogue sont accordés, une école sans fiche aussi. Ce n'est jamais une restriction implicite.
- **Droit par module** : sans attribution, accordé ; avec, `GRANT` accorde, `REVOKE` retire, sinon la présence du module dans l'offre. Un ajustement non levé s'applique à l'attribution qu'il ajuste seulement : quand une autre attribution prend effet, il cesse de s'appliquer et reste dans l'historique (phase `ENDED`).
- **Version** : `1 + Σ attributions (1 + annulée + en vigueur) + Σ ajustements (1 + levé)`. Elle ne décroît jamais ; chaque création, annulation, levée et prise d'effet l'augmente. Elle sert d'`If-Match` aux commandes et d'ETag à la lecture de l'école.
- **Prochaine échéance** : `nextChangeAt`, la date de la prochaine attribution programmée ; un client relit avant qu'elle n'arrive.
- Une nouvelle attribution remplace celle qui était programmée (jamais deux échéances concurrentes) et met fin aux ajustements de l'attribution précédente ; l'aperçu le dit avant l'écriture.

## Routes

Toutes sous `/v1/platform/…`, réservées à un opérateur actif, par `platformCommand` / `platformRead` (acteur relu en base, `Idempotency-Key` égale à `operationId`, `If-Match`, reçu durable, journal dans la même transaction). Le droit `MANAGE_OFFERS` rejoint `platformRights` et s'affiche dans l'aperçu d'une invitation de plateforme.

| Route | Rôle |
| --- | --- |
| `GET /modules` | Catalogue. |
| `GET /offers` | Offres (filtre de statut), avec le nombre d'écoles en vigueur. |
| `POST /offers` · `PATCH /offers/:id` | Création et modification versionnée (nom, modules). |
| `POST /offers/:id/archive` · `…/restore` | Archivage et restauration. |
| `GET /clients/:id/entitlements` | Droits d'une fiche : en vigueur, programmés, historique. |
| `GET /clients/:id/assignment-preview` | Conséquences d'une attribution avant toute écriture. |
| `POST /clients/:id/assignments` | Attribution, immédiate ou à date. |
| `POST /clients/:id/assignments/:assignmentId/cancel` | Annulation d'une attribution encore future. |
| `POST /clients/:id/adjustments` · `…/:adjustmentId/lift` | Ajustement motivé et levée motivée. |

Refus nommés (409 sauf mention) : `OFFER_NAME_TAKEN`, `OFFER_ARCHIVED`, `OFFER_NOT_ARCHIVED`, `EFFECTIVE_DATE_PAST` (une date d'effet ne remonte pas dans le passé), `ASSIGNMENT_NOT_PENDING` (seule une attribution future s'annule), `ADJUSTMENT_REQUIRES_OFFER` (pas d'ajustement sans offre en vigueur), `ADJUSTMENT_NO_EFFECT` (un ajustement qui ne change rien est refusé), `ADJUSTMENT_ACTIVE` (un seul ajustement actif par module), `ADJUSTMENT_NOT_ACTIVE`, `MODULE_UNKNOWN`, et 412 `VERSION_CONFLICT`. Une date d'effet doit être strictement future ; l'attribution immédiate n'envoie pas de date.

Côté école : `GET /v1/schools/:schoolId/entitlements`, lisible par tous les membres actifs de l'école, ETag `"version"`, `no-store`. Réponse : `state`, `modules[{code, entitled}]`, `version`, `nextChangeAt`, `computedAt`.

Journal commercial (actions ajoutées, toujours avec `schoolId` quand l'école est connue) : `CREATE_OFFER`, `UPDATE_OFFER`, `ARCHIVE_OFFER`, `RESTORE_OFFER`, `ASSIGN_OFFER`, `CANCEL_OFFER_ASSIGNMENT`, `ADJUST_SCHOOL_MODULE`, `LIFT_MODULE_ADJUSTMENT`. Les refus sont journalisés comme REFUSED. Le motif d'un ajustement et ses auteurs sont visibles de l'équipe dans la fiche ; ils ne sortent jamais vers l'école. Extensions de contrat : `apps/api/contracts/platform-offers.json` et `school-entitlements.json` (OpenAPI canonique 3.11.0 inchangé), générées par `generate-platform-contract.ts` et gardées par `platform-offers-contract.test.ts`.

## Matrice module × action × état commercial

Trois classes d'action (`ActionClass`) :

- `READ_HISTORY` : consulter ce qui existe ; toujours permis ;
- `COMPLETE_COMMITMENT` : terminer ou défaire un engagement déjà pris ; toujours permis ;
- `WRITE_NEW` : un nouvel usage (écrire, créer, publier, inscrire) ; exige le droit.

La règle est un point unique : `moduleActionAllowed(entitled, action)` et `requireModule(...)` (`apps/api/src/entitlements.ts`). Refus : 403 `MODULE_NOT_ENTITLED`, message français nommant le module.

### Messagerie (`MESSAGING`)

| Action | Classe | `NOT_CONFIGURED` | Offre, module accordé | Offre, module non accordé |
| --- | --- | --- | --- | --- |
| Lire les conversations existantes, l'historique, les accusés de lecture | `READ_HISTORY` | permis | permis | permis, en lecture seule (`access.canWrite` faux) |
| Supprimer son message, signaler, retirer sa réaction, vote vide, télécharger ou annuler un média | `COMPLETE_COMMITMENT` | permis | permis | permis |
| Envoyer un message, ajouter une réaction, épingler ou désépingler, voter, clore un sondage, téléverser un média | `WRITE_NEW` | permis | permis | refusé (403) |
| Ouvrir une nouvelle conversation privée ou générale | `WRITE_NEW` | permis | permis | refusé ; une conversation existante est rendue en lecture seule |

### Cours collectifs (`COLLECTIVE_COURSES`)

| Action | Classe | `NOT_CONFIGURED` | Offre, module accordé | Offre, module non accordé |
| --- | --- | --- | --- | --- |
| Lire l'agenda, le catalogue, les séries, les inscriptions, les faits de cours | `READ_HISTORY` | permis | permis | permis |
| Quitter une liste d'attente, refuser une place, annuler une inscription (élève ou moniteur), annuler une série, replanifier | `COMPLETE_COMMITMENT` | permis | permis | permis |
| Créer ou modifier un type, la politique, une série ; publier ; changer la capacité | `WRITE_NEW` | permis | permis | refusé (403) |
| S'inscrire, inscrire un élève, entrer en liste d'attente, accepter une place | `WRITE_NEW` | permis | permis | refusé (403) |

### États que #456 ajoutera

Essai, impayé, suspension et résiliation ne sont pas définis ici : aucune règle de la matrice n'en dépend et aucun état n'est déduit de `NOT_CONFIGURED`. Quand #456 les définira, il ajoutera une colonne à cette matrice et un cas à `moduleActionAllowed`, sans changer les classes : consulter et terminer un engagement restent permis dans tous les cas tant que le porteur n'en décide pas autrement.

## Transitions

1. **Bloquer le nouvel usage non autorisé.** La garde `requireModule` relit le droit en base à chaque commande de classe `WRITE_NEW`, après le droit de la personne et hors rejeu d'une opération déjà enregistrée. L'interface en cache ou hors ligne ne change rien : le serveur répond 403 `MODULE_NOT_ENTITLED`.
2. **Garder l'historique consultable selon les règles existantes.** Les lectures ne passent pas par la garde. Les conversations existantes restent lisibles et rendues en lecture seule ; l'onglet Messages de l'iPhone est conservé.
3. **Laisser terminer les engagements en cours.** Annuler une inscription, quitter une liste d'attente, refuser une place, replanifier, annuler une série, supprimer ou signaler un message restent permis. Les leçons et le GPS ne sont pas des modules et ne sont jamais touchés par une offre.
4. **Réactiver sans perte.** Un retrait ne supprime rien : lever un ajustement REVOKE, ou attribuer une offre qui contient de nouveau le module, rend le droit à la prochaine lecture avec toutes les données intactes. L'aperçu d'une attribution montre ce qui reste en place (volumes) avant tout retrait.
5. **Ne jamais supprimer l'historique.** Les attributions, ajustements et offres n'ont aucun DELETE (déclencheurs) ; une offre archivée est figée ; le journal est en ajout seul. Retirer un droit modifie un calcul, pas des données.

Une attribution à date future reste annulable jusqu'à sa prise d'effet ; ensuite elle ne se réécrit plus, on en attribue une autre. Aucune tâche de fond n'est nécessaire : l'état se calcule à la lecture, et la prise d'effet est visible par `nextChangeAt`.

## Archivage d'une offre

Une offre archivée n'est plus proposée à l'attribution (409 `OFFER_ARCHIVED` si on tente), et son nom et ses modules sont figés. Les écoles qui l'ont déjà gardent leurs droits : leur attribution porte un instantané et ne dépend plus de l'offre. Aucun déclencheur n'est posé sur les tables existantes. Une offre archivée se restaure (`restore`), et le nombre d'écoles en vigueur est écrit au journal à l'archivage.

## Console web

Onglet « Offres » (deuxième, après « Écoles ») de `/app/plateforme` : liste des offres avec leur nombre d'écoles, création, modification, archivage et restauration, modules cochés parmi le catalogue. Dans la fiche d'une école, la rubrique « Offre et modules » montre l'offre en vigueur, l'offre programmée (annulable), chaque module avec son droit, et les actions « Attribuer une offre » (aperçu des conséquences, puis confirmation), « Retirer » ou « Accorder » un module (motif obligatoire), « Lever » un ajustement (motif obligatoire), puis l'historique des attributions et des ajustements avec auteur et motif. Conflit de version : la fiche est rechargée, rien n'est écrasé ; réponse perdue : état non confirmé avec reprise de la même demande. Peu de texte, comme ailleurs : pas de sous-titre explicatif, une explication seulement en cas d'erreur.

Passerelle : `apps/web/server/platform-routes.ts` (liste fermée étendue : toute route d'API appelée par le web y figure, et dans `generate-platform-contract.ts`) et `apps/web/server/school-routes.ts` pour `GET entitlements`. Aperçu synthétique étendu (`apps/web/client/portal/preview/families/platform-offers.ts`), avec des données fictives.

## Espace école web

`useSchoolEntitlements` relit les droits à l'ouverture, à chaque changement de commande et au retour sur l'onglet. `coursesManageable` y ajoute le droit commercial : la gestion des cours est masquée quand `COLLECTIVE_COURSES` n'est pas accordé. Un droit encore inconnu ne masque rien (`moduleEntitled` rend vrai) : l'écran n'est jamais l'autorité, le serveur reste le garde et répond 403 si l'écran était resté ouvert. La web de l'école n'a pas de surface de messagerie à fermer.

## iPhone et iPad

Le code est écrit sans compilateur Swift (aucune toolchain sur ce poste) : il n'a jamais été compilé ni exécuté.

- `SchoolEntitlements` (modèle, `SchoolEntitlementsPolicy`, protocole `SchoolEntitlementsReading`) ; `DrivyAPIClient` l'adopte. Le protocole `SchoolAPI` n'est pas étendu (ses doublons de test se briseraient) ; `SchoolWorkspace` retient la source par défaut à partir de `api`.
- `SchoolWorkspace` lit les droits à la sélection d'une école active (lecture forcée), au retour au premier plan et avec les sources de l'agenda, au plus une fois toutes les 300 secondes, ou dès que `nextChangeAt` est passé. Il écarte toute réponse arrivée après un changement d'école, vide les droits en quittant l'école, et garde la projection précédente après une panne (hors ligne, API plus ancienne qui répond 404, 401, 403, réponse invalide) sans jamais retirer l'accès au compte.
- **Affichage ouvert par défaut** : sans lecture aboutie, ou pour un module non cité, `isEntitled` rend vrai. Seule la création d'un cours collectif (nouvel usage) se ferme (« Planifier une leçon » reste proposé). Un vieux client ou un client hors ligne n'est donc jamais une autorité, ni dans un sens ni dans l'autre.
- Refus nommé : `MessagingFailure.moduleNotEntitled` (le message est conservé sur l'appareil, la file d'envoi s'arrête sans rien perdre, le refus se dit une fois) et un message dédié pour les cours collectifs, au lieu d'un « accès retiré ».
- Tests Swift écrits : `SchoolEntitlementsTests.swift` (12 tests : décodage, modules inconnus jamais fermés, projections refusées, cadence, route et en-têtes du client, 404, absence de source, lecture à l'entrée, panne sans effet sur le compte, module rétabli à la lecture suivante, sortie d'école, réponse tardive d'une autre école), un cas ajouté à `SchoolCourseClientTests.swift` et un à `MessagingHTTPTransportTests.swift`. Jamais compilés ni joués.

## Concurrence et idempotence

Mêmes règles que les lots précédents : chaque mutation porte `Idempotency-Key` et `If-Match` (la version du droit de la fiche, ou de l'offre), version périmée : 412 `VERSION_CONFLICT`, identifiant réutilisé avec un autre contenu : 409 `IDEMPOTENCY_MISMATCH`, reçu durable relu après une réponse perdue. Les commandes d'une fiche prennent un verrou sur la fiche ; l'attribution lit l'offre avec un verrou partagé pour que la copie des modules soit celle de la lecture. Une attribution et un ajustement concurrents sur la même fiche : une seule issue attendue (l'autre reçoit un conflit de version, par le verrou de fiche et l'`If-Match`) ; cette propriété découle du modèle, aucun test de concurrence propre à ce lot ne l'éprouve.

## Arbitrages hors énoncé

1. **Pas d'état commercial stocké** : l'état est dérivé des attributions ; la colonne `platform_client.commercial_state` reste à `NOT_CONFIGURED` pour #456.
2. **`NOT_CONFIGURED` accorde tout** : une école sans offre n'est jamais restreinte, y compris une école sans fiche.
3. **Instantané dans l'attribution** : modifier ou archiver une offre ne change jamais une école déjà attribuée.
4. **Un ajustement suit son attribution** : il s'arrête quand une autre attribution prend effet, au lieu de glisser silencieusement sur la suivante.
5. **Nouvelle attribution remplace la programmée** : jamais deux échéances concurrentes.
6. **Seule la création d'un cours se ferme sur l'iPhone** ; les autres surfaces gardent leur affichage et laissent le serveur refuser avec son message français.
7. **Droit `MANAGE_OFFERS`** : ajouté à `platformRights` et accordé au niveau unique `COMMERCIAL` ; il apparaît dans l'aperçu d'une invitation.
8. **Volumes seulement dans l'aperçu** : jamais un contenu, un nom ou un message ; l'opérateur ne voit aucune donnée pédagogique.

## Limites connues

- L'affichage ouvert par défaut de l'iPhone suppose que le serveur refuse : c'est le cas pour tous les chemins listés dans la matrice, et c'est ce que les tests d'intégration vérifient. Un chemin d'écriture ajouté plus tard sans `requireModule` resterait ouvert.
- Le transport des médias de la messagerie traduit encore un 403 `MODULE_NOT_ENTITLED` en « accès modifié » (`.accessChanged`) au lieu du refus nommé ; le serveur refuse correctement, seul le message diffère.
- Sur l'iPhone, le bouton « S'inscrire » de l'élève et l'ouverture d'un brouillon de cours existant ne sont pas masqués : le serveur refuse avec le message français.
- La lecture des droits sur l'iPhone n'est pas déclenchée par un refus `MODULE_NOT_ENTITLED` : la mise à jour vient du prochain retour au premier plan, de l'agenda ou de la fenêtre de 300 secondes.
- Aucun envoi de courriel ni de notification à l'école lors d'un changement d'offre (pas de SMTP, CC1.1) ; l'école le constate à la prochaine lecture.
- L'aperçu d'une attribution est un calcul instantané : si les droits changent entre l'aperçu et l'envoi, la version (`If-Match`) fait refuser et recharger.
- Le catalogue vit en deux copies (table et modèle) : un test d'intégration les compare, mais ajouter un module sans les tenir ensemble échoue seulement dans ce test.
- Aucun test de ce lot n'a tourné (règle du porteur) : les gardes, les triggers, les fonctions SQL et la migration elle-même n'ont été exécutés ni sur PostgreSQL ni en CI. Seuls le typecheck et le build ont été passés.
- Non vérifié : appareil physique, VoiceOver, GPS, iOS (Swift jamais compilé ici), console contre la vraie API dans un navigateur, déploiement.

## À savoir pour #456 (conditions commerciales)

- `platform_client.commercial_state` n'est pas touchée et son `CHECK` n'admet encore que `NOT_CONFIGURED`. L'état affiché (`NOT_CONFIGURED` ou `OFFER_ACTIVE`) vient de `platform_client_entitlement_core`. Pour ajouter essai, impayé, suspension ou résiliation : élargir `commercialStates` (`entitlements-model.ts`), le `CASE` de `state` dans cette fonction, et `moduleActionAllowed` ; la matrice ci-dessus gagne une colonne.
- Les emplacements sont prêts : `dueDates: []` dans `commercialView` (fiche et annuaire), `entitlementVersion` et `nextChangeAt` (un événement daté, comme la fin d'un essai, peut alimenter `nextChangeAt` pour que les clients relisent à temps).
- Aucun montant, prix ni devise n'existe dans `platform_offer` : les ajouter par migration, jamais dans `modules`. Une attribution garde déjà un instantané ; faire de même pour tout montant attribué.
- Toute mutation passe par `platformCommand` avec `schoolId` ; les actions ci-dessus s'ajoutent au journal existant ; toute nouvelle route appelée par le web va dans `platform-routes.ts` et dans `generate-platform-contract.ts`.
- Une suspension qui ferme une surface doit dire laquelle des trois classes elle touche : fermer `WRITE_NEW` est ce que fait déjà un retrait de module ; fermer `READ_HISTORY` ou `COMPLETE_COMMITMENT` est un autre choix, à prendre explicitement.
- Qualification restante à la fin de l'épic R01 : migration `20261115_platform_offers_modules.sql` sur une copie de la base du homelab avant tout déploiement (sauvegarde préalable, décision du porteur), suites API et web, compilation et tests Swift sur le runner Apple, essai de l'attribution et du retrait contre l'API réelle.
