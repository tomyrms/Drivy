# Reprise web #106 : conservation honnête des métadonnées et barrière d'horaire au renvoi

Date : 4 novembre 2026. Base **`0bdaf32483e3dc4dba9e75056eedb0c74cd43d4e`**, worktree neuf isolé `C:/Users/jtoma/orca/workspaces/Drivy/issues-reprise-web-106`, branche `tomyrms/issues-reprise-web-106`. Code et tests : commit **`631f9869f11e969e3941e7329e014b9b77227429`**. Ce document est livré dans le commit qui le porte. **Aucune issue fermée, aucun push, aucune PR, aucune CI distante, aucun déploiement.**

Ce lot traite deux restes vérifiés de L1 web (#106) : la vérité de conservation des métadonnées et la barrière d'horaire au renvoi. **Aucune interface n'est créée ni modifiée** : pas de TSX, pas de composant, pas de texte de présentation nouveau. L1 natif, l'expiration par une autre famille, L2, L3 et L4 restent séparés.

## 1. Contexte et méthode

Références lues avant d'écrire : `AGENTS.md` ; `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md` ; R11/R12 de `03-fonctionnel/regles-etats.md` ; AP72 et la reprise d'opération de `04-technique/synchronisation.md` ; le contrat L1 du rapport `issues-reactivite-106/docs/implementation/reactivite-restes-contrat-20261104.md` §5 ; l'instantané d'issue #106. La conception n'est pas modifiée.

**Runtime.** Modèle effectif `opencode-go/deepseek-v4.1-flash`, agent OpenCode, tâche logique/test. L'effort de raisonnement n'est pas exposé par ce runtime : aucune valeur n'est inventée et aucun modèle, fournisseur ou effort n'a été changé.

**Skills Superpowers réellement chargés** (outil `skill` d'OpenCode, fichiers lus sous `C:/Users/jtoma/.config/opencode/node_modules/superpowers/skills/`) :

| Skill | Usage effectif dans ce lot |
|---|---|
| `systematic-debugging` | Phase 1 avant toute correction : reproduction du constat source (constructeur/`update`/`clear` qui avalent les exceptions ; `resend` sans contrôle d'horaire), lecture du code réel, cause racine par composant. |
| `test-driven-development` | RED observé puis GREEN : tests écrits avant le code, échec vérifié avec messages d'assertion réels, aucune assertion affaiblie, aucune fixture de date passée transformée en cas futur. |
| `verification-before-completion` | Toutes les affirmations de §5 viennent de commandes exécutées après la dernière modification, avec code de sortie lu. |

**Codebase Memory.** MCP disponible ; CE worktree indexé par chemin absolu avant l'analyse (projet `drivy-reprise-web-106`, mode `full`, `async`, génération `2026-11-04T15:14:23Z`, **51 903 nœuds / 196 343 arêtes**). Fraîcheur et couverture contrôlées sur `command-store.ts`, `console/agenda-intentions.ts`, `command-core.ts` et les deux fichiers de tests : `no_recorded_issue`, `metadata_match`. Recherches : `trace_path` sur `CommandStore.resend` (appelants réels : `pending-requests.act`, `PortalPendingRequests`, `PortalConsole`, `access-preview.Preview`) et sur `lessonResendAllowed` (appelants : `lessonResendReason`, `pending-requests.PortalPendingRequests`, `portal-console`, `access-preview`, deux tests) ; `search_code` sur `pendingActions|useCommandSnapshot|commandStore\.`. Le source a ensuite été lu intégralement, jamais déduit du graphe.

**Limites de l'index** : 963 fichiers non indexés, 85 analyses partielles, 4 fichiers non analysables (dont `04-technique/openapi.yaml`) ; `watch` inactif (`not_session_project`) — l'index ne s'actualise pas seul, il faut le relancer. Aucun autre worktree n'a servi de référence d'index.

## 2. Ce qui est livré

### A. État honnête de la conservation des métadonnées

`apps/web/client/command-store.ts` expose désormais, dans l'état observable du magasin, le résultat **observé** des opérations sur la liste v1 :

```ts
export type MetadataDurability = 'saved' | 'memoryOnly' | 'unknown';
export interface MetadataStorageState {
  readonly durability: MetadataDurability;
  readonly last: 'read' | 'write' | 'clear';
}
```

Lisible par le futur consommateur UI sans toucher au magasin : `useCommandSnapshot().metadata` (ou `commandStore.getSnapshot().metadata`). Sens précis :

| Valeur | Ce que cela affirme | Ce que cela n'affirme jamais |
|---|---|---|
| `saved` | La dernière écriture d'identifiants a été acceptée sans exception par le stockage de l'onglet. | Qu'un corps, un chemin, un code, un jeton CSRF ou une identité soit conservé ; qu'une confirmation serveur existe ; qu'une purge a eu lieu ; que la liste survivra à la fermeture (quota, navigation privée, purge du navigateur restent possibles). |
| `memoryOnly` | La dernière écriture a été refusée : le suivi et la saisie vivent en mémoire pour cette page seulement. | Qu'une commande soit perdue, annulée ou refusée par l'école : rien n'est détruit en mémoire. |
| `unknown` | Aucun résultat concluant ; `last` dit laquelle des trois opérations n'a pas abouti. | Qu'il n'y ait rien dans le stockage : après un effacement refusé, de vieilles métadonnées peuvent encore y être. |

Le champ `last` distingue les trois situations que `durability` seule confondrait : lecture initiale refusée (`unknown`/`read`), écriture refusée (`memoryOnly`/`write`), effacement refusé (`unknown`/`clear`). Aucune de ces valeurs n'entre dans la liste persistée.

Comportement, cas par cas :

- **Lecture refusée au chargement** : aucune exception ne remonte, aucune commande n'est inventée, l'état reste `unknown`/`read` ; rien ne prétend que le suivi est enregistré.
- **Valeur illisible** (JSON valide mais qui n'est pas une liste) : elle n'est pas reprise, l'état dit `unknown`/`read`.
- **Écriture refusée** : la commande, son corps et la saisie restent en mémoire ; l'état passe à `memoryOnly`/`write` ; aucune confirmation, aucune revision, aucune purge ne sont fabriquées.
- **Écriture réussie ensuite** : l'état ne redevient `saved` que dans la branche où `setItem` a réellement rendu la main sans lever.
- **Effacement refusé** : l'état passe à `unknown`/`clear` ; les anciennes métadonnées restent dans le stockage et **reviendront au prochain chargement** — sans corps, en phase `orphaned`, sans renvoi possible (voir ci-dessous). Aucun succès de purge n'est affiché.

**Migration et rollback v1.** La clé (`drivy-gestion-demandes-v1`) et le format strict ne changent pas : le lecteur `parseMetadata` rejette toute clé additionnelle, donc les nouveaux états ne sont **jamais** écrits dans le JSON. Une liste v1 remplie par une page antérieure reste relisible ; une liste écrite par ce lot reste lisible par un client antérieur (le test vérifie que `parseMetadata` accepte chaque entrée écrite). Aucun repli vers `localStorage` ou IndexedDB.

**Après rechargement.** Les entrées reviennent avec `command: null`, phase `orphaned`, `pendingActions(...).resend === false` : la vérification AP72 reste possible, le renvoi ne l'est pas, et un 404 ne devient jamais un refus définitif.

### B. Barrière d'horaire au renvoi, dans le magasin

Cause racine traitée : `CommandStore.resend` émettait dès que `pendingActions` l'autorisait ; `lessonResendAllowed`/`lessonResendReason` ne protégeaient que le consommateur `PortalPendingRequests`. Un appel direct au magasin pouvait donc renvoyer une création ou un déplacement à un horaire passé.

- La règle est extraite **à l'identique** dans `apps/web/client/command-recovery.ts` (`desiredSlotOf`, `lessonResendAllowed`, `lessonResendReason`) : primitives pures, ni DOM ni réseau, horloge en dernier paramètre.
- `apps/web/client/console/agenda-intentions.ts` ne fait plus que **réexporter** ces trois fonctions ; aucune projection agenda, aucun autre helper n'est modifié. Les deux consommateurs existants (`pending-requests.tsx`, `agenda-lane.test.ts`) continuent de fonctionner sans changement.
- `resend(schoolId, csrf, operationId?, now = Date.now())` applique l'ordre : porte `pendingActions` → **barrière d'horaire** → transport. Pour `createLesson`/`moveLesson` seulement, un créneau demandé invalide, absent ou `<= now` renvoie `{ status: 'pending', message: lessonResendReason(...) }` : **aucun paquet**, même `operationId`, même corps, même version, même précondition, phase et `attempts` inchangés, `revision` inchangée.
- Ce n'est **ni un rejet définitif ni une annulation** : l'entrée reste suivie, la vérification AP72 reste possible et un reçu valide tardif confirme normalement. Le premier envoi garde son contrat (c'est l'école qui juge un horaire déjà passé) ; les autres familles gardent leur renvoi actuel. Aucun TTL universel, aucun seuil d'âge, aucun renvoi automatique.
- L'horloge est explicite (`now`), donc testable ; les fixtures existantes gardent leurs dates et leur `now` explicites, aucune assertion n'a été affaiblie.

## 3. Interface pour la tâche UI suivante (non réalisée ici)

Ce qui existe et ce qui **n'existe pas** :

- **Existe** : `metadata.durability`, `metadata.last` dans l'état du magasin, avec les types exportés ci-dessus ; la barrière de renvoi, identique pour l'écran et pour un appel direct ; les helpers de reprise réexportés par `console/agenda-intentions.ts`.
- **N'existe pas** : aucun avertissement, badge, texte ou composant affiché. **Rien n'est rendu aujourd'hui.** Aucun texte français nouveau n'a été ajouté : la seule chaîne réutilisée est le motif existant de `lessonResendReason`.
- Consommation attendue : lire `metadata` pour expliquer, seulement si nécessaire, qu'un suivi ne survivra pas à la fermeture (formulation à décider par la tâche UI) ; ne pas réimplémenter la règle de renvoi, ne pas présenter `saved` comme « contenu conservé », ne pas présenter un renvoi bloqué comme un échec de la demande. L'adoption est une tâche séparée, avec Impeccable/Uncodixfy requis par le mandat UI.

## 4. Fichiers

| Fichier | Nature |
|---|---|
| `apps/web/client/command-recovery.ts` | **nouveau** : primitives pures de reprise (règle déplacée à l'identique). |
| `apps/web/client/command-store.ts` | types et état de conservation, `writeMetadata`/`eraseMetadata`, barrière dans `resend`. |
| `apps/web/client/console/agenda-intentions.ts` | réexport uniquement ; projection agenda intacte. |
| `apps/web/test/command-recovery-106.test.ts` | **nouveau** : barrière, horloge, AP72 tardif, rejeu identique, rechargement v1, règle partagée. |
| `apps/web/test/command-store-code.test.ts` | injection de panne du faux stockage ; 6 tests de conservation. |
| `docs/implementation/command-recovery-web-106-20261104.md` | ce rapport. |

Exclus et non touchés : TSX/composants/UI, `console/context`, `pending-requests`, `protocol`/`school-api`, `command-core`/`command-conflicts`/`command-families`, API/SQL/iOS, dépendances et locks, `STATUS`, conception.

## 5. Preuves exécutées (Node `v24.22.2`, npm `11.19.1`, hors PATH système)

Dépendances déjà verrouillées, installées dans CE worktree : `npm ci --prefix apps/web --ignore-scripts` → **153 paquets, exit 0**, aucun lock modifié.

| Commande | Résultat réel |
|---|---|
| `npm test --prefix apps/web -- test/command-core.test.ts test/command-store-code.test.ts test/command-latency-106.test.ts test/command-conflicts.test.ts test/agenda-intentions.test.ts` (avant toute modification) | **5 fichiers, 98 tests verts, exit 0** (base reproduite) |
| Même commande + `test/command-recovery-106.test.ts` (RED, avant implémentation) | **9 échecs / 40 passés (49), exit 1** — assertions comportementales : « expected vi.fn() to be called 1 times, but got 2 times », « expected undefined to deeply equal { durability: 'unknown', last: 'read' } ». Aucun échec de compilation, aucun test miroir. |
| Même commande + `test/command-recovery-106.test.ts` (GREEN) | **6 fichiers, 116 tests verts, exit 0** |
| `npm test --prefix apps/web` (suite web complète) | **79 fichiers, 840 passés + 1 échec attendu (841), exit 0** |
| `npm run typecheck --prefix apps/web` | **exit 0** (`tsc --noEmit` puis `tsc -p tsconfig.check.json`) |
| `npm run build --prefix apps/web` | **exit 0**, `✓ built in 649ms` |
| `git diff --check` / `git diff --cached --check` | **exit 0** |

Couverture des critères par les tests ajoutés : `setItem`/`getItem`/`removeItem` qui lèvent ; commande toujours suivie en mémoire ; retour à `saved` après une vraie écriture ; sentinelle de corps absente de **chaque** valeur persistée ; clés strictes v1 et `parseMetadata` acceptant ce qui est écrit ; aucun état de conservation dans le JSON ; liste v1 ancienne relue sans corps et sans renvoi ; échéance juste avant/à/après et date absente ou invalide ; appel **direct** `store.resend` sans UI avec zéro émission ; reçu AP72 valide tardif après blocage ; rejeu autorisé avec même clé/`If-Match`/corps ; non-régression des autres familles et de la garde d'époque.

Ces tests sont des tests de **transport simulé** (`fetch` remplacé par un double, faux `window.sessionStorage`). Aucune preuve PostgreSQL, Apple, navigateur réel, GPS, batterie ou VoiceOver n'est revendiquée.

## 6. Limites et risques résiduels

- `saved` signifie « écriture acceptée », pas « conservé durablement » : il n'y a pas de relecture de contrôle après `setItem`. Une relecture serait plus forte mais ajoute un accès au stockage et une nouvelle panne possible ; non retenue ici.
- Un onglet n'observe pas les écritures d'un autre onglet (aucun écouteur d'événement de stockage) : `metadata` décrit les opérations de **cette** page.
- Après un `clear` refusé, de vieilles métadonnées peuvent revenir au prochain chargement, en `orphaned` et sans corps. C'est documenté et testé ; aucune purge forcée n'est tentée en boucle.
- Aucun avertissement n'est visible par une personne aujourd'hui : la tâche UI séparée doit consommer `metadata` pour cela. Tant qu'elle n'existe pas, l'état est honnête mais silencieux.
- Restent hors périmètre, inchangés : L1 natif (coffre chiffré, migration/rollback Swift), expiration par famille (offre/invitation côté serveur, revue explicite pour droits/consentement/finances), L2 (annulation avant envoi), L3 (réconciliation par champ), L4 (sortie sûre et purge). `STATUS.md` n'est pas modifié (exclu du périmètre) ; il appartient au propriétaire d'intégration.
