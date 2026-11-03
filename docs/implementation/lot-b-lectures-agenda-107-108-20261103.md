# Lot B — Lectures agenda et aperçu (#107, #108) : périodes retenues, réponses hors ordre, préchargement borné (3 novembre 2026)

Branche `tomyrms/lotb-lectures-107` (base `2c0eaefd`). Web uniquement : `apps/api`, l'iOS et le contrat OpenAPI ne sont pas touchés. Aucun déploiement, aucune PR, aucun envoi réel. Les garanties du lot A et de la planification (#109) restent : droits relus au serveur, aucune autorisation déduite d'une projection locale, aucune intention de planification effacée par une relecture.

## Étape 1 — audit : ce que le web fait réellement (avant)

### Clés de lecture en place

| Vue | Lecture | Portée transmise à `useLoad` (3ᵉ argument) | Clé de cache (4ᵉ argument) |
| --- | --- | --- | --- |
| Agenda, semaine/jour, leçons | `readAll(schoolId, 'lessons', …, { from, to, instructorMembershipId? })` — `use-agenda.ts:41-44` | `${schoolId}/${monday}/${instructor}` | **aucune** (`resourceKey` omis) |
| Agenda, cours collectifs | `readSchool(schoolId, 'course-series', …)` — `use-agenda.ts:45-48` | `${schoolId}/${monday}` (le moniteur filtre à la projection) | **aucune** |
| Agenda, annuaire (membres + élèves) | deux `readAll` en `Promise.all` — `use-agenda.ts:37-40` | `schoolId` (défaut `deps[0]`) | **aucune** |
| Aperçu, préparation | `setup-draft/next-actions` + `setup-draft` — `overview-page.tsx:61-64` | `schoolId` | **aucune** |

La portée de `useLoad` inclut déjà la personne, le rattachement et l'époque d'accès (`context.ts:117`) : une réponse d'une autre école, d'un autre compte ou d'une autre époque n'est jamais affichée. La portée des leçons inclut la semaine et le moniteur filtré ; celle des cours la semaine. **La clé d'affichage est donc complète, mais aucune des quatre lectures n'adopte le cache de lecture** : `resourceKey` est absent, donc `cacheKey` est `undefined` (`context.ts:116`) et `ScopedReadCache` n'est jamais sollicité.

### Réponses aux questions de l'audit

| Question | Réponse (lue dans le code) |
| --- | --- |
| Changer de semaine puis revenir : affichage immédiat ou squelette ? | **Squelette.** La portée change avec la semaine (`…/${monday}/…`) ; `readStateFor` refuse les données de l'ancienne portée (`load-model.ts:11-13`) et il n'y a pas de cache pour la semaine déjà lue. `start(false)` repart donc en `loading`, `data` `undefined` (`context.ts:130-134`), et `ReadFeedback` affiche un squelette (`presentation.tsx:12`). |
| Deux changements rapides : une réponse ancienne peut-elle écraser la plus récente ? | **Non.** `useLoad` incrémente `generation` à chaque lecture et n'applique une réponse que si elle est la dernière (`context.ts:126`, `136-137`, `146`). Aucun défaut constaté ici ; la règle est reprise telle quelle, par clé de période, dans le nouveau module et prouvée par test. |
| Un échec de relecture efface-t-il la période affichée ? | **Pas pour la même période** : `failedReadState` garde les données pour une panne (0/5xx) et les retire pour 401/403/404 (`load-model.ts:19-26`) ; `presentation.tsx:14` propose « Réessayer ». **Mais** un échec après changement de semaine n'a jamais de données à garder (pas de cache), et rien n'indique à l'écran que les rendez-vous affichés datent d'une lecture antérieure à l'échec. |
| Une liste partielle peut-elle devenir « aucune leçon » ? | **Pas dans le texte** : `partial` (troncature de pagination, 200 cours) (`use-agenda.ts:64`) et `emptyConfirmed` (`:66`) exigent `status === 'ready'` et `!partial`. **Mais la grille reste dessinée vide** pendant une lecture : rail horaire seul, sans squelette, ce qui se lit visuellement comme une semaine sans rendez-vous alors que la réponse n'est pas arrivée. Aucun texte « Aucun rendez-vous » avant la réponse. |
| État « avant » du calendrier pendant un chargement | Portée différente ⇒ `data` `undefined` ⇒ `agendaDays([])` : grille vide, pas de squelette de période ; seuls les trois `ReadFeedback` des notices signalent la lecture. |
| Moniteur filtré | La portée contient le moniteur, donc aucune leçon d'un autre moniteur n'est affichée (garanti par `readStateFor`). En revanche, changer de moniteur vers un filtre déjà lu repasse par un squelette et une lecture réseau ; le retour à « Tous les moniteurs » aussi. |
| Mémoire / disque | Aucune rétention de période dans l'agenda ; le cache de lecture (`ScopedReadCache`) est en mémoire, borné à 40 projections / 2 min / 1 Mo par projection / 4 Mo (`load-model.ts:35`, `:56-59`), recréé à chaque changement de portée (`management-runtime.ts:62-65`). Rien sur le disque. |

### Appels réseau comptés (lecture du code, une page par `readAll`)

Parcours : ouvrir l'agenda (semaine courante), avancer d'une semaine, revenir, changer de moniteur (« Tous » → un moniteur).

| Geste | Appels de la période | Appels d'annuaire | Total | Attente à l'écran |
| --- | --- | --- | --- | --- |
| Ouvrir l'agenda | 2 (leçons + cours) | 2 (membres + élèves) | **4** | squelette partout |
| Avancer d'une semaine | 2 | 0 | **2** | grille vide puis données |
| Revenir à la semaine de départ | 2 | 0 | **2** | grille vide puis données (3ᵉ lecture de la même semaine) |
| Changer de moniteur | 1 (leçons seules ; les cours sont partagés, l'annuaire aussi) | 0 | **1** | grille vide puis données |
| Revenir depuis une autre rubrique | 4 | | **4** | tout en squelette |

Total des quatre gestes de période : **7 lectures**, dont **3 lectures identiques de la même semaine**, avec un squelette à chaque retour. L'aperçu relit `next-actions` + `setup-draft` à chaque montage (2 lectures, squelette). Ces comptes sont déduits du code (une page par `readAll`) ; ils ne sont pas mesurés dans un navigateur — `NOT_EXECUTED`.

### Écarts réels retenus pour l'étape 2

1. Aucune rétention de période : retour sur une semaine/moniteur déjà lus ⇒ squelette + 2 lectures (`use-agenda.ts:41-48`).
2. La grille d'une période jamais lue est dessinée vide sans squelette honnête (`agenda-page.tsx:70-74`).
3. Aucun préchargement borné des périodes voisines.
4. Aucune mention, lors d'un échec de relecture d'une période affichée, que les données sont antérieures à l'échec (`presentation.tsx:10-16`).
5. L'annuaire de l'agenda et la préparation de l'aperçu n'adoptent pas le cache de lecture : chaque retour remonte un squelette et relit (`use-agenda.ts:37-40`, `overview-page.tsx:61-64`).
6. La rétention en mémoire n'existe pas, donc sa purge au changement de compte/école/époque/droits reste à construire et à prouver.

Non-écarts (déjà corrects, conservés) : clé d'affichage complète (école, époque, moniteur, période) ; réponses hors ordre ignorées ; données conservées sur une panne de la même période ; `partial` exclut tout « aucune leçon » ; rien sur le disque.

Le web ne possède pas de vue « mois » : `presentation` vaut `day` ou `week` (`use-agenda.ts:26`, `agenda-page.tsx:41-43`) ; un jour est affiché depuis la projection de sa semaine, sans lecture séparée. La période de lecture est donc toujours la semaine.

## Étape 2 — ce qui change (seulement les écarts trouvés)

### `client/console/period-cache.ts` (nouveau, pur, sans React ni réseau)

- `PeriodReads<T>` : fenêtre de projections d'agenda par période. Clé de lecture complète `agenda/<ressource>/<école>/<époque>/<moniteur|*>/<période>` ; l'instance est en plus liée à la personne, au rattachement et aux rôles (elle est recréée avec eux). Une période jamais lue rend `loading` sans données ; une période déjà lue rend ses données immédiatement.
- **Réponses hors ordre** : un numéro de génération par clé ; seule la réponse de la dernière lecture de la clé est appliquée. Une réponse d'une autre période n'écrit que dans sa propre clé. Une réponse antérieure à une `purge` est ignorée (époque de purge).
- **Échec** : panne (0/5xx) ⇒ données conservées avec `status: 'error'`, message et « date de lecture » inchangée ; 401/403/404 ⇒ données retirées ; 401 ⇒ `needsLogin`. Une période en échec n'est pas relancée d'elle-même : « Réessayer » appelle `reload`.
- **Préchargement borné** : `prefetchNeighbours` ne lit que `période − 7 j` et `période + 7 j`, seulement si la période demandée est celle affichée et qu'elle est `ready`. Rien au-delà, rien avant l'affichage.
- **Mémoire** : `PERIOD_MEMORY_LIMIT = 8` périodes par ressource (leçons et cours), soit 16 projections au plus ; éviction de la plus anciennement touchée, jamais la période affichée ; la clé évincée est aussi retirée du cache de lecture de la portée. `PERIOD_FRESH_MS = 30 000` : une période lue il y a moins de 30 s est montrée sans relancer de lecture. Rien sur le disque.
- **Retour sur l'agenda** : la fenêtre s'appuie sur le `ScopedReadCache` existant (`readCache` de la console, mémoire seulement, recréé avec la portée) : un remontage de l'agenda retrouve ses périodes sans lecture, puis les relit discrètement.

### `portal/agenda/use-agenda.ts`

- `usePeriodRead` (crochet local, `useSyncExternalStore`) remplace `useLoad` pour les **leçons** et les **cours**. La période est la semaine (`monday`) ; un jour s'affiche depuis sa semaine, sans lecture séparée (le web n'a pas de vue mois).
- Clé : `${personId}/${schoolId}/${membershipId}/${accessEpoch}/${roles}` pour l'instance, puis ressource + moniteur filtré + semaine pour chaque projection. Un changement de compte, d'école, de rattachement, de droits ou d'époque crée une instance neuve : mémoire vide.
- `revision` (confirmation de commande) déclenche une **relecture discrète** de la période affichée au lieu d'un rechargement bloquant ; le rafraîchissement manuel et le minuteur de 60 s passent aussi par la relecture discrète.
- L'annuaire de l'agenda adopte le cache de lecture (`resourceKey 'agenda/directory'`) : un retour sur l'agenda ne remonte plus deux squelettes.
- `lessonSchema`, `readAll`, `readSchool`, `bounds` servent toujours ; `weekWindow` est recalculé **par période lue** (le préchargement lit une autre semaine que celle affichée).
- `use-lesson.ts`, `use-cancellation.ts`, `use-lesson-intentions.ts`, `agenda-projection.ts`, `agenda-intentions.ts` ne sont pas modifiés : les intentions suivies restent dans `drafts` et la projection les relit telles quelles.

### `portal/agenda/agenda-page.tsx`, `presentation.tsx`, `agenda.css`

- Période jamais lue ⇒ `PeriodLoading` (`role="status"`, « Lecture de la période ») à la place de la grille, jamais une grille vide qui se lirait comme « rien de prévu ». Le squelette de notice des leçons est supprimé quand la grille porte déjà le squelette (un seul squelette).
- Le texte « Aucun rendez-vous » reste conditionné à `emptyConfirmed` (lecture `ready`, rien de partiel) : une liste partielle ou une lecture en cours ne devient jamais « aucune leçon ».
- `ReadFeedback` accepte `stale` : sur un échec de relecture, il ajoute « Les données affichées datent d'une lecture précédente. » et garde « Réessayer » (défaut `false` : les autres pages ne changent pas).

### `portal/overview/overview-page.tsx`

- La préparation de l'école adopte le cache de lecture (`resourceKey 'apercu/preparation'`) : un retour sur l'aperçu affiche les actions connues pendant la relecture, sans squelette.

## Preuve par critère

| Critère demandé | Preuve |
| --- | --- |
| 1. Clé de lecture complète (école, époque, moniteur, période) ; retour sur une période lue immédiat et relecture discrète ; jamais la période ou le moniteur d'un autre | `test/period-cache.test.ts` : « revient sur une semaine lue sans squelette, avec une relecture discrète » (données présentes dès l'appel, `loading` seulement pour la période jamais lue, 0 lecture dans les 30 s, 1 relecture discrète après) ; « ne montre jamais la période d'un autre moniteur » (deux clés, aucune fuite) ; « un remontage retrouve la période lue sans aucune lecture » (cache de la portée). Les clés sont construites par `PeriodReads.keyOf` et l'instance porte personne/rattachement/rôles/époque. |
| 2. Réponses hors ordre ignorées : seule la dernière réponse de la clé affichée est appliquée | « une réponse ancienne pour une autre semaine ne touche pas la semaine affichée » (la réponse tardive de A ne remplace pas l'objet affiché de B) ; « une réponse antérieure à une purge ne repeuple pas une mémoire vidée » (époque de purge). La règle est par clé, pas globale : une réponse tardive remplit sa propre période, jamais celle qui est à l'écran. |
| 3. Préchargement borné à ±1, après affichage, mémoire bornée et documentée | « ne précharge que la période précédente et la suivante, et seulement après l'affichage » (pendant `loading` : 0 appel ; ensuite exactement `−7 j` et `+7 j`, une seconde demande dans la fraîcheur : 0 appel) ; « ne garde qu'un nombre limité de périodes » (`size ≤ PERIOD_MEMORY_LIMIT = 8`, période affichée conservée) ; « une période évincée quitte le cache de la portée ». |
| 4. Échec de relecture d'une période affichée : données gardées, mention discrète, « Réessayer » ; purge au changement de compte/école/époque/droits | « une panne garde la période affichée et sa date de lecture ; un refus la retire » (503 : `data` et `readAt` conservés, message ; 403 : données retirées) ; « une période en échec n'est pas relancée d'elle-même au retour » ; `ReadFeedback stale` ajoute la mention et garde « Réessayer » ; « une instance neuve (autre compte, école, époque ou droits) est vide » et « une purge retire aussi les périodes du cache de la portée ». En production, `usePeriodRead` recrée l'instance avec la portée et `management-runtime.ts` recrée déjà `readCache` par portée (fichier non modifié). |
| 5. Sélection, défilement et focus conservés lors d'une relecture discrète | La relecture discrète ne change ni `status`, ni la clé de la période, ni la sélection (`routeQuery`/`localSelection`) ; la grille n'est pas démontée et ses clés d'événement sont stables : « mêmes clés d'événement avant et après la relecture : rien n'est remonté à l'écran ». Mesure réelle du focus et du défilement dans un navigateur : `NOT_EXECUTED`. |
| 6. Les intentions de planification restent affichées et cohérentes à travers les relectures | « les créations provisoires et les déplacements restent projetés après une relecture discrète » (après une relecture qui apporte de nouveaux faits : `create:op-create` et `move:op-move` toujours projetés, `l1` toujours `moving`, totaux = faits seuls) ; « une intention confirmée n'est retirée que par une lecture plus récente que sa confirmation » (`visibleIntentions` avec le `readAt` de la période relue). |

## Comptes d'appels : avant / après

Comptes de **lectures de période** (leçons + cours) pour un agenda ouvert, mesurés par le transport compté du test « compte les lectures de la séquence » ; en production chaque lecture est un `GET` (une page de `readAll` ou un `readSchool`).

| Geste | Avant (code) | Après (test) | Détail de l'après |
| --- | --- | --- | --- |
| Ouvrir l'agenda | 2 | **6** | 2 affichées + 4 préchargées (2 voisines × 2 ressources) |
| Avancer d'une semaine | 2 | **0** | déjà préchargée ; +2 pour précharger la semaine suivante (total 8) |
| Revenir | 2 | **0** | dans la fenêtre de fraîcheur (total 8) |
| Changer de moniteur | 1 | **1** | nouvelle clé de leçons ; +2 pour ses voisines (total 11) |
| Revenir à « Tous les moniteurs » | 1 | **0** | clé encore retenue (total 11) |
| Total des cinq gestes | 8 | **11** | 3 lectures de plus, aucune attente sur les gestes 2, 3 et 5 |

Hors période : l'annuaire reste à 2 lectures au premier montage et **2 au remontage** (le cache sert l'affichage, la relecture réseau reste) ; l'aperçu reste à 2 lectures, affichées immédiatement au retour. Aucun gain n'est annoncé sur le nombre total de requêtes : le préchargement coûte 4 lectures à l'ouverture pour supprimer l'attente des semaines voisines. Aucun de ces comptes n'est une mesure de latence : la latence réelle n'a pas été rejouée (`NOT_EXECUTED`).

## Non fait, non prouvé

- Aucun parcours dans un navigateur (Edge/Playwright), aucune capture, aucune mesure de défilement, de focus ou de VoiceOver : `NOT_EXECUTED`. Les critères d'écran reposent sur le typage, la lecture du code et les fonctions pures testées.
- Aucun test de composant React : le projet n'a ni `@testing-library` ni environnement DOM. Le crochet `usePeriodRead` (branchement `useSyncExternalStore` + effets) n'est pas exécuté par un test ; seuls le module pur `PeriodReads` et ses compositions avec `agendaDays`/`visibleIntentions` le sont.
- Latence 15 s, réseau réel, serveur réel, API et PostgreSQL : `NOT_EXECUTED` (aucune base fournie, `apps/api` non modifié).
- Les comptes d'appels sont des appels de lecture (une page) : une semaine paginée au-delà d'une page n'est pas simulée ; le compteur ne distingue pas les pages.
- La borne mémoire est un **nombre** de périodes (8 par ressource), pas un budget d'octets ; le cache de lecture partagé garde ses bornes existantes (40 projections, 2 min, 1 Mo par projection, 4 Mo). Une projection de semaine de plus de 1 Mo n'est pas rangée dans le cache partagé : elle reste retenue dans la fenêtre de la session mais un remontage la relit.
- Le web n'a pas de vue « mois » (jour/semaine seulement) : la période préchargée est toujours la semaine.
- Les droits ne sont purgés que par l'époque d'accès (`accessEpoch`), mécanisme existant : un changement de rôle qui ne changerait pas d'époque ne créerait pas d'instance neuve (le cache de la portée, lui, est déjà recréé sur cette même clé).
- Le préchargement des voisines d'un moniteur filtré coûte 2 lectures de plus par filtre affiché ; il n'a pas été mesuré avec un calendrier réel.

## Vérifications exécutées (3 novembre 2026)

| Vérification | Résultat |
| --- | --- |
| Base | `git log -1 --format=%h` = `2c0eaefd` avant toute modification |
| `npm ci` dans `apps/web` | PASS (153 paquets) ; avertissement `EBADENGINE` : Node v26.8.1 installé, `engines` demande `>=24 <25` — ce n'est pas une erreur |
| `npm run typecheck` dans `apps/web` | PASS |
| `npm run test:unit` avant travail | PASS : 69 fichiers, 714 tests réussis, 1 échec attendu (`test.fails`) |
| `npm run test:unit` après travail | PASS : 70 fichiers, 730 tests réussis, 1 échec attendu |
| Tests ajoutés | `test/period-cache.test.ts` : 16 cas |
| `npm run build` dans `apps/web` | PASS (tsc serveur + vite) |
| Tests `apps/api`, PostgreSQL, navigateur, VoiceOver, appareil | `NOT_EXECUTED` |

Fichiers modifiés : `client/console/period-cache.ts` (nouveau), `client/portal/agenda/use-agenda.ts`, `client/portal/agenda/agenda-page.tsx`, `client/portal/agenda/presentation.tsx`, `client/portal/agenda/agenda.css`, `client/portal/overview/overview-page.tsx`, `test/period-cache.test.ts` (nouveau), ce document. `console/context.ts`, `console/load-model.ts`, `command-*.ts`, `agenda-projection.ts`, `agenda-intentions.ts`, `use-lesson.ts`, `use-cancellation.ts`, `use-lesson-intentions.ts`, `apps/api` et `apps/ios` ne sont pas modifiés.
