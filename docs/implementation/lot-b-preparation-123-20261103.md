# Lot B — #123 Assistant de préparation : « Enregistrer et continuer » sans verrouiller la fiche (3 novembre 2026)

Branche `tomyrms/lotb-preparation-123`, base `34d4c01a`. Web uniquement : `apps/api` et l'iOS ne sont pas touchés, aucune route n'est ajoutée. Aucun déploiement, aucune PR, aucun commentaire d'issue. Les garanties restent celles du dépôt : aucun succès avant la réponse vérifiée de l'école, droits relus au serveur, aucun contenu de préparation dans `localStorage` ni `sessionStorage`.

## Ce qui existait déjà

- Un seul brouillon persistant (`setup-draft`, `If-Match`), une relecture serveur (`setup-draft/preview`) et une adoption explicite (`setup-draft/complete`) : `client/portal/setup/use-setup-guide.ts` (fonctions `save`, `finish`, `refreshReview`), `apps/api/src/school-onboarding.ts`.
- La navigation entre étapes ne dépendait plus du réseau (lot A), mais « Enregistrer et continuer » appelait encore `save()`, qui attendait la réponse avec la fiche entière verrouillée (`blocked`) et ne changeait d'étape qu'après la confirmation.
- Le moteur de commandes (`client/command-store.ts`) : clé d'idempotence, même corps et même version à la reprise, reçu AP72, rien de confirmé avant la réponse. `client/command-lane.ts` et `useCommandLane` (`console/context.ts`, non modifié) suivent plusieurs intentions d'une section sans bloquer le formulaire.
- Le modèle cité par l'issue : `client/notification-preferences-store.ts`. Il coalesce par catégorie, garde une seule écriture en vol, renvoie le corps exact et la version d'origine après une réponse perdue, et distingue `conflict`, `uncertain`, `rejected`. Il est lu, non copié : la préparation enregistre un objet entier versionné, pas des champs indépendants.
- Tests existants de la préparation : `client/portal/setup/setup-guide-model.test.ts` (4 tests), `test/setup-model.test.ts`. Aucun test ne montait le hook : `vite.config.ts` ne déclare pas d'environnement DOM et aucune dépendance de rendu de test n'est installée (dépendances verrouillées, non touchées).

## Ce qui a changé

| Fichier | Rôle |
| --- | --- |
| `client/portal/setup/setup-save-queue.ts` (nouveau, pur) | `SetupSaveQueue` : un seul PUT de brouillon en vol, la dernière saisie retenue part après la réponse avec la version que l'école vient de renvoyer, aucune requête pour une saisie identique à celle que l'école détient. Aucun DOM, aucun réseau, aucune minuterie : l'appelant fournit `send`. Exposition par instantané (`phase`, `message`, `saving`, `synced`, `held`, `heldVersion`, `conflictStep`). |
| `client/portal/setup/use-setup-guide.ts` | « Enregistrer et continuer » (`continueStep`) remet le brouillon à la file et ouvre l'étape suivante tout de suite. `dirty` devient « le brouillon de l'école n'est pas le brouillon local » (`synced`) au lieu d'un drapeau posé à la main. Un envoi de brouillon encore en vol ne bloque plus la fiche ; un résultat que l'école doit encore trancher (`verifying`) bloque toujours. |
| `client/portal/setup/setup-guide.tsx` | Statut discret, alertes d'échec avec « Réessayer », revue désactivée avec sa raison courte, marque « À relire » sur l'étape. |
| `client/portal/setup/setup.css` | `.setup-saved:empty::before` (pas de pastille sans texte), `.setup-reason`. |
| `client/portal/setup/setup-save-queue.test.ts` (nouveau) | 10 tests du module de coalescence. |

### La file d'enregistrement

- `adopt(version, body)` : brouillon lu à l'école. Une lecture plus ancienne que la version détenue est ignorée.
- `track(body)` : saisie locale, pour savoir si l'école la détient déjà. N'envoie rien (frappe, navigation).
- `enqueue(body)` : « Enregistrer et continuer ». Retient la dernière saisie et démarre l'envoi ; un envoi déjà en vol n'est jamais doublé, la version la plus récente part après la réponse.
- `flush(body)` : enregistrement explicite attendu. Se résout quand la file est au repos ; si le même brouillon est déjà en vol, il attend sa réponse au lieu de le renvoyer.
- `retry()` : nouvel essai explicite après un refus ou un résultat non établi.
- `forgetLocal()` / `dispose()` : « quitter sans enregistrer » et changement de portée. `dispose()` incrémente une génération : une réponse tardive n'est ni affichée ni rejouée.
- La comparaison de saisie est canonique (clés triées, champs `undefined` ignorés) : deux contenus identiques ne produisent pas de requête, et une confirmation qui renvoie le même contenu rend le brouillon « synchronisé » sans nouvel envoi.

### Ce que voit la personne

- En-tête : « Enregistrement… » pendant l'envoi, puis plus rien une fois confirmé (`Enregistré` est retiré) ; « Modifications non enregistrées » seulement s'il reste une saisie non détenue par l'école.
- Refus ou panne : alerte « Enregistrement impossible » / « Enregistrement à vérifier » avec « Réessayer ». Un résultat inconnu reste aussi suivi par le panneau des demandes de la console.
- Revue : « Vérifier la préparation » et le bouton d'adoption sont désactivés tant que le brouillon de l'école n'est pas le brouillon local ou qu'un envoi est en vol, avec une raison courte liée par `aria-describedby` (`#setup-review-reason`). Le résumé est relu automatiquement dès que le brouillon est confirmé.
- Conflit de version : la saisie locale reste à l'écran, le brouillon de l'école est relu, l'étape concernée porte « À relire » et une alerte explique ; rien n'est renvoyé sans un geste explicite.
- « Enregistrer et quitter » reste attendu et n'annonce rien avant la confirmation ; il ne double pas un envoi déjà en vol.

## Preuve par critère

| Critère | Preuve |
| --- | --- |
| « Enregistrer et continuer » enregistre en arrière-plan et passe tout de suite ; un seul PUT en vol ; la dernière version part après la réponse avec la version renvoyée ; pas d'envoi pour une saisie inchangée | `setup-save-queue.test.ts` : « un seul PUT en vol… » (3 appuis pendant un envoi → 1 requête, puis une seconde avec `ifMatch: 2`), « aucune requête pour une saisie identique… » (même contenu, étape différente → 0 requête), « Enregistrer et quitter envoie la saisie plus récente après la réponse en vol ». Côté vue : `continueStep` remet le brouillon puis change d'étape ; `blocked` ne contient plus un envoi de brouillon simplement `sending`. |
| Statut discret ; rien de plus une fois confirmé ; erreur avec « Réessayer » ; jamais d'annonce avant la réponse vérifiée | `setup-guide.tsx` : le statut ne rend jamais « Enregistré », les alertes n'apparaissent qu'après un résultat de la file, le résultat de succès de la voie de commandes n'est jamais rendu. Le module ne repasse à `idle` qu'après un résultat `confirmed`, ou après un reçu dont la relecture montre exactement le brouillon envoyé (tests « un seul PUT en vol… », « un refus garde la saisie… »). Non mesuré dans un navigateur. |
| Revue et activation réservées au brouillon confirmé et à aucun envoi en vol ; activation inchangée | `finish()` exige `saveState.synced` en plus de `preview.draftVersion === document.version` ; les deux contrôles de la revue sont désactivés avec la raison. Le corps de `applySetupDraft` garde `reviewDigest`, `expectedSchoolVersion`, `expectedConfigurationVersion` : non modifié. Test du module : `synced` est faux pendant un envoi (`phase: 'saving'`) et faux tant que le contenu diffère. |
| « Enregistrer et quitter » explicite et attendu, sans relancer un envoi en vol | `save()` passe par `queue.flush` et ne navigue que si `settled.held` est exactement le brouillon remis. Tests : « attend l'envoi en vol au lieu de le doubler » (1 seule requête), « envoie la saisie plus récente après la réponse en vol » (2 requêtes, la seconde avec la version renvoyée). |
| Conflit : saisie gardée, brouillon de l'école relu, étape « à relire », aucune perte | Test « un conflit garde la saisie, relit l'école et marque l'étape “à relire” » : après un 412, `heldVersion` reste l'ancienne, `conflictStep` est l'étape visée, aucun envoi automatique ; après `adopt(5, …)` le nouveau brouillon est détenu et le prochain envoi part avec `ifMatch: 5` et le contenu local. Côté vue : la file ne touche jamais `content`, l'effet de version ne remplace le contenu que si la personne n'a rien saisi (`edited`), la relecture est déclenchée par `conflictedDraft`. |
| Changement d'école, de compte ou d'époque d'accès : envoi abandonné, rien rejoué ailleurs | Test « un changement de portée abandonne l'envoi » : `dispose()` remet la file à zéro, la réponse tardive est ignorée, un `enqueue` ultérieur n'envoie rien. Côté hook : la file est créée par `useMemo` sur `personId/schoolId/membershipId/accessEpoch` et détruite avec cette portée. |
| Aucun contenu de préparation dans le stockage du navigateur | Inchangé : la file ne garde rien hors mémoire, `drafts` de la console reste en mémoire, aucun appel à `localStorage`/`sessionStorage` n'est ajouté. |
| Logique de coalescence dans un module pur testable | `client/portal/setup/setup-save-queue.ts` : aucun import de React, du DOM ou du réseau (types seulement), 10 tests dédiés. |

## Vérifications exécutées (3 novembre 2026)

| Vérification | Résultat |
| --- | --- |
| `npm ci` dans `apps/web` (`node_modules` absent) | PASS, 153 paquets ajoutés ; avertissement `EBADENGINE` attendu (Node v26.8.1 alors que `engines` demande `>=24 <25`) |
| `npm run typecheck` | PASS (aucune sortie d'erreur, code 0) |
| `npm run test:unit` | PASS, 65 fichiers, 675 tests réussis et 1 échec attendu (`test.fails`, pas un échec). Référence mesurée avant modification, au même commit : 64 fichiers, 665 tests réussis et 1 échec attendu — l'énoncé annonçait 663 + 1, soit deux tests de plus déjà présents dans la base. |
| Tests ajoutés | `client/portal/setup/setup-save-queue.test.ts` : 10 tests (un seul envoi en vol ; dernière version après la réponse ; saisie inchangée ; refus puis « Réessayer » ; résultat non établi tranché par un reçu ; résultat non établi puis nouvel essai explicite ; conflit ; lecture en retard ignorée ; enregistrement explicite sans doublon et après l'envoi en vol ; changement de portée) |
| `npm run build` | PASS (construit en 813 ms) : le client se bundle avec la file et la vue |
| Tests `apps/api` et PostgreSQL | NOT_EXECUTED : base non fournie, `apps/api` non modifié |
| Parcours dans un navigateur (latence simulée, 412 réel, VoiceOver) | NOT_EXECUTED |
| Appareil, déploiement, homelab | NOT_EXECUTED |

## Ce qui n'est pas fait ou pas prouvé

- Aucun parcours navigateur : le comportement visuel (statut, alertes, marque « À relire », focus), la navigation sous 15 s de latence et l'annonce au lecteur d'écran ne sont pas mesurés. Seuls le module et le typage sont prouvés ; le hook n'est prouvé que par lecture du code.
- Le panneau global des demandes (`client/portal/runtime/pending-requests.tsx`, hors périmètre) affiche « Enregistrement en cours… » pendant chaque PUT de brouillon, en plus du statut de l'en-tête. C'est le mécanisme existant, honnête (aucun succès annoncé), mais redondant pendant quelques centaines de millisecondes ; le filtrer demanderait de toucher un fichier hors liste.
- L'étape mémorisée par l'école (`currentStep`) n'avance que lorsqu'une saisie change réellement : un simple changement d'étape n'envoie plus de requête, conformément à « pas d'envoi pour une saisie identique à la dernière confirmée ». Après un rechargement, la reprise peut donc se faire à l'étape du dernier contenu enregistré, pas à la dernière étape visitée.
- Aucun test de hook : sans environnement DOM ni bibliothèque de rendu (dépendances verrouillées), le câblage React n'est couvert ni par un test ni par un parcours.
- Deux administrateurs sur le même brouillon, la réponse perdue puis le reçu AP72 pour un brouillon : mécanisme commun seulement (`command-store.ts`, non modifié), jamais rejoué ici.
