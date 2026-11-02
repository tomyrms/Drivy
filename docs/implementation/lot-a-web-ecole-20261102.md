# Lot A web : invitations, école, catalogue, disponibilités, dossiers (2 novembre 2026)

Branche `claude/lot-a-web-ecole` (base `0312e768`). Web uniquement : `apps/api` et l'iOS ne sont pas touchés. Aucun déploiement, aucune PR. Les garanties restent : aucun succès avant la confirmation du serveur, droits relus au serveur, aucun accès, tarif ou code accordé par une projection locale, notifications et publications déclenchées par le serveur seulement.

## Socle ajouté (utilisé par les cinq issues)

Le moteur reste `command-store.ts` (clé d'idempotence, corps et version identiques à la reprise, reçu AP72). Ce lot ne le remplace pas ; il en lève trois limites qui obligeaient chaque section à un seul envoi à la fois.

| Fichier | Rôle |
| --- | --- |
| `client/command-conflicts.ts` | Les clés de conflit deviennent des chemins : `invitations:<id>`, `planning:availability:<moniteur>:rules`, `learners:<élève>`. Deux commandes se bloquent si leurs clés sont égales ou emboîtées. Un renvoi sur une invitation n'attend plus la révocation d'une autre ; la planification (leçons, cours) attend toujours tous les horaires. Une commande restaurée sans corps (page rechargée) et les opérations d'accès bloquent toujours tout. `wouldConflict` laisse un bouton se désactiver sans fabriquer de commande. |
| `client/command-core.ts` | `createCommand` accepte `scope` (agrégat nommé quand le corps ne le porte pas : le moniteur d'un retrait d'horaire, l'élève d'une affectation). En mémoire seulement, comme le corps. |
| `client/command-lane.ts` | Une voie suit plusieurs intentions indépendantes d'une section, une par étiquette : `sending`, `followed` (résultat inconnu, le magasin reste propriétaire de la reprise), résultat à montrer. Aucun corps de réponse n'entre dans son état ; elle est détruite avec le compte, l'école, le rattachement ou l'époque d'accès. |
| `client/command-families.ts` + `command-store.ts` | Compteurs de confirmations par type de commande. Une section ne relit que sa famille (`invitations`, `members`, `catalogue`, `availability`, `learners`, `school`) au lieu de toute l'école. |
| `console/context.ts` | `useCommandLane` (voie liée au contexte) ; `useCommandRunner` est inchangé pour les sections non migrées. |

Tests du socle : `test/command-conflicts.test.ts` (7), `test/command-lane.test.ts` (12) contre le vrai magasin de commandes, un faux `window` et un réseau scripté.

## #121 Invitations

### Ce qui existait déjà

- Lignes « Renvoi en cours » / « Révocation en cours » et « Création d'une invitation en cours » sans ligne ni code inventés : `console/context.ts` (`usePendingResources`, `usePendingCreations`), `portal/invitations/invitation-list.tsx`.
- Code à usage unique uniquement dans la réponse qui le crée, jamais dans la liste, jamais dans le stockage : `invitation-model.ts` (`parseInvitationResponse`, `issuedCodeOf`), `test/command-store-code.test.ts`, `test/invitation-model.test.ts`.
- Idempotence côté serveur, version `If-Match`, refus `INVITATION_USED` / `INVITATION_REVOKED`, renvoi sans code sur rejeu : `apps/api/src/invitations.ts`, `apps/api/test/g1c.integration.test.ts` (lignes 219 à 233, 340 à 365, 428, 575 à 579). Non relancés ici (PostgreSQL requis).

### Ce qui a changé

Le reste de l'issue était « un seul envoi à la fois dans la section » (`reactivite-lots-20261028.md`). `portal/invitations/use-invitations.ts` passe de `useCommandRunner` à `useCommandLane` :

- le dialogue se libère dès que la demande est conservée par le magasin ; un renvoi de l'invitation A suivi pendant 15 s laisse la révocation de B partir et se confirmer ;
- une même invitation reste ordonnée : « Nouveau code » et « Révoquer… » sont désactivés tant que la demande sur cette invitation est suivie ; un double appui sur la même opération n'envoie rien ;
- un refus définitif ne touche que son intention et rend la saisie : sur la liste, bandeau « Reprendre la saisie » (adresse, rôles, permis, moniteur ou motif repris tels quels) ; sur l'invitation concernée, le dialogue revient seul avec le refus ;
- le code d'une réponse est gardé par invitation (plusieurs peuvent être à copier), jamais pour un code appris par reçu ;
- relecture ciblée : invitations, membres et offres seulement ; un refus de version ou « utilisée / révoquée » relit la liste.

### Preuve par critère

| Critère | Preuve |
| --- | --- |
| Retour immédiat sous latence, sans faux membre ni code | `command-lane.test.ts` (« une demande lente de 15 s… », fake timers) ; Edge sur l'aperçu synthétique : dialogue fermé en moins de 0,5 s, ligne « Renvoi en cours », aucun code ni succès avant la réponse, code affiché une fois la réponse reçue (captures relues). |
| Réponse perdue et double appui : ni doublon ni second e-mail | `command-lane.test.ts` : réponse perdue puis reçu sans seconde écriture, reprise avec même `Idempotency-Key`, même corps, même `If-Match`, double appui à une seule requête ; Edge : création perdue suivie dans le panneau, vérification par reçu, aucune seconde création. Idempotence serveur : tests API existants cités ci-dessus (non relancés). |
| Acceptée/expirée pendant l'opération : état réel, lien révoqué non ressuscité | Edge : une révocation faite derrière l'interface, puis « Nouveau code » refusé (412), la page relit et affiche « Révoquée » sans « Nouveau code ». Le refus `INVITATION_USED` sur une intention n'arrête pas l'autre : `command-lane.test.ts`. Côté serveur : `g1c.integration.test.ts`. |
| Refus : formulaire et destinataire gardés, homonymes par identifiant | Edge : refus « déjà en attente », saisie rendue avec l'adresse ; les clés de conflit et les voies sont par identifiant (`command-conflicts.test.ts`), les libellés d'homonymes viennent de `person-reference.ts` (`test/person-reference.test.ts`). |
| Compte changé / relance : aucun secret d'une autre portée | `command-lane.test.ts` (compte changé : voie détruite, réponse tardive sans rappel ni code) ; aucune donnée ni code dans `sessionStorage`/`localStorage` (test + Edge : seul `drivy-gestion-demandes-v1` avec identifiants). `use-invitations.ts` vide codes et refus au changement d'école, de rattachement, d'époque ou de public. |

### Non prouvé ici

- Aucun envoi réel d'e-mail, aucun serveur réel : l'aperçu est un transport simulé, le serveur n'est pas lancé (Docker non démarré).
- Les cas « acceptée pendant l'opération » et « expirée » ne sont prouvés que par le refus de version et les tests API existants, pas par une recette intégrée.
- Côté iOS : inchangé, hors périmètre.

## #110 Disponibilités et absences

### Ce qui existait déjà

- Lectures indépendantes en `Promise.all`, version lue avec chaque ligne, retrait versionné, conversion heure civile/fuseau et refus d'une heure inexistante au passage été/hiver, détection locale de chevauchement, trois sémantiques séparées (horaire récurrent, absence, retrait) : `portal/availability/schedule-model.ts`, `client/availability-model.ts`, tests `portal/availability/schedule-model.test.ts` (dont `2026-03-29T02:30` refusé) et `test/availability-model.test.ts`.
- Serveur seul décideur : un retrait ou une modification d'horaire relit les rendez-vous (`EXISTING_BOOKINGS`), une absence aussi : `apps/api/src/lesson-setup.ts` (lignes 114 à 160), non relancé ici.
- Les préférences personnelles (durée, tampon, prestation par défaut) n'existent que côté natif : le web n'appelle pas `planning-defaults` (recherche dans `apps/web/client`, aucune occurrence). Rien n'est ajouté « par harmonisation ».

### Ce qui a changé

L'écart était un verrou global : `locked = runner.busy || runner.pending` bloquait filtres, boutons et formulaires pendant toute sauvegarde, et le formulaire ne se fermait qu'à la confirmation.

- `portal/availability/use-schedule-commands.ts` passe à `useCommandLane`. Le formulaire se libère dès que le magasin conserve la demande ; la ligne devient « À confirmer » (création), « Modification à confirmer » ou « Retrait à confirmer ».
- `portal/availability/schedule-projection.ts` (pur) : une création est une ligne provisoire sans identifiant de l'école (`pending:<opération>`, version 0, aucune action) ; une modification montre les valeurs voulues, l'horaire confirmé n'est pas touché ; un retrait laisse la ligne à l'écran, marquée. La semaine type et l'agenda lisent toujours les horaires de l'école : aucun créneau n'est ouvert ni proposé avant le reçu. Une intention confirmée reste projetée sans marqueur jusqu'à la relecture suivante (pas de ligne qui disparaît puis revient) ; un retrait confirmé disparaît aussitôt.
- Ordre : un moniteur et un type (horaires ou absences) à la fois, par clé de conflit `planning:availability:<moniteur>:rules|closures` ; la planification (leçons, cours) attend toujours tous les horaires. La modification suivante d'un même moniteur reste un brouillon (envoi désactivé, raison donnée) ; un autre moniteur, une absence, le choix du moniteur et la lecture de l'agenda ne sont jamais bloqués.
- Refus ou conflit : seule la ligne concernée est concernée, les autres horaires restent. La demande refusée revient par un bandeau « Reprendre la saisie » (formulaire rouvert avec la saisie et la raison, dont `EXISTING_BOOKINGS` et le lien vers l'agenda) ; un retrait refusé rouvre sa confirmation avec la raison.
- Lecture : relecture ciblée sur les seules commandes d'horaires/absences/membres (`command-families.ts`), avec cache de lecture (`useLoad`, clé `schedule`) : les données connues s'affichent pendant l'actualisation.
- Les intentions suivies sont gardées en mémoire dans `drafts` de la console (renouvelées avec compte, école, rattachement, époque) : elles survivent à un changement de rubrique, jamais au stockage du navigateur.

### Preuve par critère

| Critère | Preuve |
| --- | --- |
| Modification visible tout de suite avec statut ; aucune opération indépendante bloquée par une sauvegarde lente | Edge (aperçu synthétique, ajout d'horaire à 15 s) : ligne « À confirmer » immédiate, aucun succès annoncé, une absence du même moniteur partie et confirmée pendant ce temps, puis horaire confirmé et lu sans marqueur ; `schedule-projection.test.ts`, `command-conflicts.test.ts`. |
| Deux changements rapides et relecture concurrente : convergence, aucune saisie effacée | Edge : la modification suivante du même moniteur reste un brouillon (envoi désactivé, saisie `07:00` gardée) ; `command-lane.test.ts` (une même invitation ordonnée, relecture ciblée) ; `schedule-projection.test.ts` (projection retirée seulement par une relecture plus récente). |
| Créneau occupé, règle chevauchante, passage été/hiver, changement de moniteur corrects | Inchangés et déjà testés : `schedule-model.test.ts` ; la projection tient compte d'un horaire provisoire pour l'indice de chevauchement et ne projette pas une heure inexistante (`schedule-projection.test.ts`, heure d'hiver du 25 octobre 2026) ; moniteurs séparés (`command-conflicts.test.ts`). Créneau occupé : refus serveur affiché (Edge, scénario de refus), non rejoué contre le vrai serveur. |
| Reprise après coupure sans double absence ni clé accidentelle ; demandes périmées à réévaluer | Edge : création d'absence à réponse perdue, ligne « À confirmer », vérification par reçu, aucune deuxième création ; `command-lane.test.ts` (même clé, même corps, même version à la reprise) ; `command-store-code.test.ts` existant (changement d'accès : le corps n'est jamais rejoué). |
| Agenda et préremplissage cohérents, une intention n'est pas une disponibilité confirmée | Edge : la semaine type ne montre pas l'horaire provisoire ; un retrait garde la ligne (`schedule-projection.test.ts`). Aucun préremplissage côté web (préférences natives). |

### Non prouvé ici

- Préférences de durée, tampon, prestation par défaut : natives, hors périmètre web ; non traitées.
- Aucun serveur réel : l'aperçu est un transport simulé. Passage d'une saison à l'autre sur une règle récurrente : la règle est en heure civile, rien d'instant à convertir côté web ; aucune recette intégrée.
- iOS inchangé.
