# Lot B — Catalogue web : éditeur de programme et référentiels sur la voie de commandes (#124)

Branche `tomyrms/lotb-programmes-124`, base `36c9b910` (`claude/lot-a-20261102`). Web uniquement : `apps/api`, l'app iOS et
`apps/web/client/portal/pricing/**` ne sont pas touchés. Aucun déploiement, aucune PR, aucun serveur lancé.

## Ce qui existait déjà

- Le socle du lot A : `client/command-lane.ts` (une intention par étiquette, `sending` / `followed` / résultat), l'option `scope` de
  `createCommand`, `client/command-conflicts.ts` (clés en chemins), `client/command-families.ts` (`catalogueReads`), `useCommandLane`
  dans `console/context.ts`.
- Le modèle à imiter (#124, tâche tarifs) : `portal/pricing/pricing-commands.ts`, `pricing-projection.ts` (+ test), `pricing-feedback.tsx`,
  et l'usage de `useCommandLane` dans `pricing-controllers.ts` / `tariffs-panel.tsx` : portée `catalogue:product:<id>`,
  marque « Enregistrement en cours » puis « À confirmer », bandeau « Reprendre la saisie ».
- L'éditeur de programme et la mise à jour de référence : `portal/formations/formation-controllers.ts` (`useProgrammeEditor`,
  `useReferenceUpdate`), `programme-sections.tsx` (Général, Compétences, Règles), `reference-update.tsx`, tous par le coureur unique
  `useCatalogueCommand` (`catalogue-command.ts`) : `command.submit` verrouille le formulaire (`disabled={command.busy}`), la relecture
  (`ReviewDialog`) reste ouverte jusqu'à la confirmation, un résultat incertain fermait la modale.
- Les règles conservées telles quelles : version attendue `expectedOfferingVersionId`, codes `FORMATION_CHANGED` /
  `FORMATION_UNCHANGED` (`changedCodes`, `unchangedCodes`), relecture ciblée `catalogueReads`, relecture et « à relire »
  (`waitingFor`, `rebased`), garde de navigation `useUnsavedChanges`.
- **La création de formation n'a aucun appelant dans le web** : `createFormation` est déclaré (`command-core.ts`,
  `command-families.ts`, `command-conflicts.ts`) et `createFormationBody` existe dans `console/formation-model.ts` (testé), mais aucune
  vue ne soumet cette commande. « Préparer un permis » ouvre le guide de préparation (`apercu`, `overview-page.tsx`), qui enregistre un
  brouillon d'école (`saveSetupDraft`), pas une formation. Le parcours de création n'était donc pas « verrouillé par le coureur » : il
  n'est pas encore branché. Voir « Limites ».
- Tests existants au départ : `test/command-conflicts.test.ts` (11 tests, dont les 4 ajoutés par la tâche tarifs),
  `test/pricing-lane.test.ts` (4), `portal/formations/formations.test.ts`, `portal/pricing/pricing-projection.test.ts` (10).

## Ce qui change

### 1. Clés de conflit par formation (`client/command-conflicts.ts`, `test/command-conflicts.test.ts`)

Changement minimal, borné à la branche demandée :

- `createFormation` reste dans la ligne de famille (`['catalogue']`), inchangée.
- `saveFormationProgramme` a désormais sa branche, sur le modèle exact de `saveTariff` : `scope` présent →
  `catalogue:offering:<scope>` ; absent → `catalogue` (famille entière). La mise à jour de référence n'a pas de type de commande
  propre : elle utilise `saveFormationProgramme` avec la même portée.
- Aucune autre ligne, aucun autre type, aucun commentaire existant modifié.

Conséquence assumée : une écriture de programme nommée ne s'attend plus elle-même qu'avec la même formation, mais attend toujours les
écritures qui ne nomment pas d'agrégat (`catalogue`) : créations, tarif à conditions partagées, commande restaurée sans portée. Deux
formations différentes partent ensemble. Comme un tarif à conditions propres (déjà depuis #124), un programme nommé ne s'attend plus
avec un produit tarifaire nommé ni avec une révision d'un jeu de conditions nommé : chacun porte son agrégat et la relecture du
catalogue remet les lectures d'accord. Les relations avec la planification (famille sœur) et avec les accès (`*`, qui bloque tout) sont
identiques à avant : c'est prouvé par test.

Quatre tests ajoutés : deux formations indépendantes / la même ordonnée (insensible à la casse), sans portée → famille entière et
témoins `createFormation` / `createOffering` inchangés, attente des écritures de famille, relations planification et accès inchangées.

### 2. Projection pure (`portal/formations/formation-projection.ts` + `formation-projection.test.ts`)

Aucun DOM, aucun réseau, aucune version fabriquée :

- `FormationIntention` : `create` (avec le brouillon d'assistant `WizardDraft`, `offeringKey: null`) ou `programme` (rubrique
  `general` / `competences` / `deroulement` / `reference`, `offeringKey` de l'école, saisie de la rubrique).
- `resolveFormationIntentions` rend les marques : `saving` (« Enregistrement en cours ») tant que le magasin n'a pas répondu, puis
  `creating` (« À confirmer », création) ou `changing` (« Modification à confirmer », programme) ; une demande confirmée garde `null`
  jusqu'à la relecture, une demande abandonnée disparaît.
- `projectCategories` : les permis publiés d'abord, puis une ligne provisoire `pending:<opération>` par création, avec le code saisi
  mais **aucun identifiant de l'école**. `isOpenable` rend `false` et `schoolIdentifier` rend `null` pour cette ligne : ni un dossier, ni
  une leçon, ni une fiche ne peut la désigner. `isProvisional` expose le préfixe.
- `projectProgramme` : rend **l'objet publié de l'école tel quel** (`programme`), la version voulue de la rubrique (`wanted`) et sa
  marque, et **l'historique de l'école inchangé** (`history`, même référence) : rien de provisoire n'y entre. Une intention d'une autre
  formation ou d'une autre rubrique ne marque pas ce parcours.
- `programmeRefusal` : un refus ne porte que son intention, sa rubrique, la saisie exacte et la raison ; il ne touche ni la fiche ni les
  autres rubriques.

Sept tests couvrent la création provisoire inutilisable, la version voulue marquée sans remplacer la publiée, « À confirmer » après la
réponse, l'historique intact, la disparition après une lecture plus récente, le refus qui rend la saisie, et les étiquettes de portée.

### 3. Voie de commandes de la fiche (`portal/formations/formation-commands.ts`)

`useProgrammeLane(programmes, reload?)`, sur le modèle de `useTariffLane` :

- une intention par formation (`formationTag(offeringKey)`, `formation:new` pour une création) ; intentions gardées en mémoire dans
  `formations/intentions` (`drafts`), jamais dans le stockage du navigateur, renouvelées avec la portée de la console ;
- `save` construit `saveFormationProgramme` avec `scope: offeringKey`, la confie à `lane.run` et rend `admitted` : vrai = le magasin la
  conserve, l'éditeur se ferme tout de suite ; faux = refus local (une demande de la même formation attend), le formulaire reste avec sa
  saisie ;
- refus (`FORMATION_CHANGED`, validation, conflit local) : l'intention disparaît et un `ProgrammeRefusal` porte la saisie et l'outcome ;
  `changedCodes` déclenche la relecture (`reload`), `unchangedCodes` seulement la relecture sans bandeau ;
- confirmation : seule la réponse vérifiée ou le reçu appelle le retour de la voie ; le succès affiché vient de la voie (« Confirmé par
  l'école »), jamais d'un envoi ;
- une relecture plus récente que la confirmation retire les intentions confirmées : l'école redevient la seule source affichée.

### 4. Contrôleurs et vues (`formation-controllers.ts`, `programme-sections.tsx`, `reference-update.tsx`, `permit-sheet.tsx`, `catalogue-ui.tsx`, `formation-feedback.tsx`)

- `useProgrammeEditor` prend la voie et sa rubrique (`section`), plus le coureur ; `confirm` est synchrone et ferme l'éditeur sur
  `admitted` ; `cancel` et `closeReview` ne dépendent plus d'un `busy` global ; `resume(refusal)` rouvre l'éditeur avec la saisie exacte et
  la raison, et signale « La fiche a changé » quand le refus est `FORMATION_CHANGED` ; le comportement `waitingFor` / `rebased` reste.
- Le formulaire n'est plus désactivé pendant l'envoi (`disabled={false}` sur les champs), le bouton « Relire les changements » ne dépend
  que des changements réels.
- Rubrique fermée : bandeau « Reprendre la saisie » pour un refus de cette rubrique, puis marque textuelle (`StateBadge`, donc jamais une
  couleur seule) dans une ligne `role="status"` avec la valeur voulue quand elle est courte (nom et durée ; nombre de compétences).
  Quand une autre demande de la même formation attend, une seule phrase l'explique.
- `useReferenceUpdate` prend la voie : le dialogue se ferme dès que le magasin conserve la demande, un refus le rouvre avec la raison et
  la référence recalculée depuis la fiche relue ; la marque de la rubrique `reference` s'affiche à côté du bouton.
- `PermitSheet` possède la voie de la fiche (une seule par permis), l'affiche pour le succès confirmé et la passe aux rubriques ; la
  coquille ne crée plus de coureur, et `TariffsPanel` ne reçoit plus la prop `command` (elle reste optionnelle côté tarifs).
- `catalogue-ui.tsx` : `ReviewDialog` accepte un `outcome` de la voie (et garde `runner` pour les appelants tarifs non migrés) ;
  `CommandFeedback` est retiré, plus aucun appelant.
- `formation-feedback.tsx` : `LaneFeedback` (succès/refus, « Se reconnecter » si la session est perdue comme avant) et `RefusalBanner`
  (« Reprendre la saisie » / « Ignorer »).

## Preuve par critère

| Critère | Preuve |
| --- | --- |
| 1. L'éditeur se libère dès que la demande est conservée ; « Enregistrement en cours » puis marque d'attente ; rien d'annoncé publié avant la réponse vérifiée ou le reçu | Code : `save` rend `admitted` de façon synchrone (`store.get` juste après `submit`) et `confirm` ferme l'éditeur seulement si `admitted` ; l'état en cours vit dans la projection (`saving` / `changing`), pas dans un `busy` de formulaire ; le succès ne peut venir que de `CommandLane.settle` (`confirmed`) ou du reçu (`reconcile`). Tests : `formation-projection.test.ts` (marques, publication non remplacée), `test/formation-lane.test.ts` (« rien n'est confirmé avant la réponse vérifiée », `outcome: null` pendant l'envoi, reçu sans seconde écriture). Non mesuré sous latence dans un navigateur. |
| 2. Ordre par agrégat : une demande à la fois par formation, `scope` utilisé | `command-conflicts.ts` (une branche) + `test/command-conflicts.test.ts` (4 tests) + `test/formation-lane.test.ts` (4 tests contre le vrai magasin) : deux formations indépendantes partent ensemble ; même formation refusée (`LOCAL_COMMAND_CONFLICT`) ; création sans portée refusée pendant une écriture du catalogue ; refus d'une formation sans toucher l'autre ; planification et accès inchangés. |
| 3. Projection pure : création provisoire sans identifiant d'école, non ouvrable et inutilisable ailleurs ; version voulue marquée sans remplacer la publiée ; historique sans rien de provisoire | `formation-projection.test.ts` (7 tests) : ligne `pending:<op>` avec `isOpenable === false` et `schoolIdentifier === null` ; `projected.programme` est l'objet de l'école (`head.label` et `defaultDurationMinutes` intacts alors que la saisie diffère) ; `history` est la même référence et ne contient aucune ligne provisoire. |
| 4. Refus ou conflit : seule l'intention concernée est touchée ; « Reprendre la saisie » rouvre l'éditeur avec la saisie et la raison ; « à relire » conservé | Code : le refus ne retire que son intention (`filter operationId`) et `resume` rouvre avec `refusal.draft` et `refusal.outcome`, `rebased` si `changedCodes` ; `waitingFor` / `rebased` existants conservés. Tests : `formation-projection.test.ts` (`programmeRefusal` rend la saisie et la raison, la fiche publiée reste intacte) ; `formation-lane.test.ts` (refus d'une formation sans effet sur l'autre). Le refus serveur réel n'est pas rejoué : voir limites. |
| 5. Les appelants de `catalogue-command.ts` dans `portal/pricing/` fonctionnent sans modification | `catalogue-command.ts` n'est pas modifié (`changedCodes`, `unchangedCodes`, `createdId`, `CatalogueCommand`, `useCatalogueCommand`). `portal/pricing/**` n'est pas modifié ; typage et suite complète verts, y compris `test/pricing-lane.test.ts` et `portal/pricing/pricing-projection.test.ts`. `ReviewDialog` garde `runner` pour ces appelants. |

## Vérifications exécutées (3 novembre 2026, machine locale, Windows)

| Vérification | Résultat |
| --- | --- |
| `git log -1 --format=%h` avant modification | `36c9b910` |
| `npm ci` dans `apps/web` | 153 paquets ajoutés ; avertissement `EBADENGINE` (Node v26.8.1, `engines` demande `>=24 <25`) — signalé, non bloquant |
| `npm run typecheck` (`tsc --noEmit` + `tsconfig.check.json`) | PASS (avant et après) |
| `npm run test:unit` avant le lot | 67 fichiers, 693 réussis, 1 échec attendu (`test.fails`, 694 au total) |
| `npm run test:unit` après le lot | 69 fichiers, 708 réussis, 1 échec attendu (`test.fails`, 709 au total) |
| Tests ajoutés | `portal/formations/formation-projection.test.ts` (7), `test/formation-lane.test.ts` (4), `test/command-conflicts.test.ts` (+4) = 15 |
| `npm run build` (tsc serveur + `vite build`, contrôle des modules interdits) | PASS, `built in 791ms` |

## Non fait, non prouvé, limites

- **Création de formation sans appelant** : la projection d'une création et sa clé de conflit sont en place et testées, mais aucune vue
  ne soumet `createFormation` aujourd'hui (le guide de préparation #320 enregistre un brouillon d'école). Je n'ai pas inventé d'écran de
  création : le brancher appartient au guide. C'est un écart entre l'énoncé de la tâche (« la création de formation utilise encore le
  coureur unique ») et le code réel.
- **Aucun navigateur, aucune recette visuelle** : pas de parcours Edge/Playwright, pas de capture relue. L'assemblage React (hooks,
  ordre des rendus, focus, marques, bandeaux) est vérifié par le typage, le build et la lecture, pas par un test de composant : le dépôt
  n'a pas d'outil de rendu.
- **Aucun serveur réel** : `apps/api` non lancé (PostgreSQL non fourni), donc `FORMATION_CHANGED`, `FORMATION_UNCHANGED`, la relecture
  après refus et la création d'une nouvelle version ne sont couverts que par le chemin de code (voie + magasin) et le magasin simulé,
  pas par une réponse réelle.
- **Aucune mesure de latence** : la libération de l'éditeur repose sur l'admission synchrone du magasin, prouvée par les tests de voie,
  pas chronométrée.
- **Marque d'attente** : « Modification à confirmer » pour un programme (étiquette `changing` du modèle tarifs) ; la famille des
  étiquettes contient bien « À confirmer » pour une création.
- **Refus par rubrique** : le bandeau d'un refus et la marque s'affichent dans la rubrique concernée. Un refus survenu pendant que la
  personne est sur une autre rubrique du même permis reste en mémoire (intentions et refus dans `drafts`) et s'affiche en revenant :
  rien n'est perdu, mais il n'est pas annoncé sur l'autre onglet.
- **Conséquence de l'agrégat** : un programme nommé ne s'attend plus avec un produit tarifaire nommé ni avec une révision de conditions
  nommée (avant, `catalogue` les sérialisait). C'est le prix du découpage par agrégat, cohérent avec le choix déjà fait pour les tarifs à
  conditions propres ; les écritures de famille continuent de tout sérialiser.
- **Duplication de présentation** : `formation-feedback.tsx` reprend `LaneFeedback` / `RefusalBanner` de `pricing-feedback.tsx` parce que
  `portal/pricing/**` est hors périmètre ; une factorisation commune reste possible plus tard.
- **`CommandFeedback` retiré de `catalogue-ui.tsx`** (plus aucun appelant) ; le commentaire de `pricing-feedback.tsx` qui le nomme n'a pas
  été modifié (fichier hors périmètre).
- **`useCatalogueCommand` conservé** dans `catalogue-command.ts` : `portal/pricing/tariffs-panel.tsx` type encore sa prop optionnelle
  `command` avec `CatalogueCommand`. Aucun éditeur de formation ne l'utilise plus ; la prop pourra disparaître avec la tâche qui migre ces
  appelants.
- `package-lock.json` à la racine était déjà modifié avant ce lot ; il n'est pas committé. `apps/web/package-lock.json` n'est pas modifié.
- Appareil, VoiceOver, `apps/api`, PostgreSQL, déploiement, homelab : **NOT_EXECUTED**.
