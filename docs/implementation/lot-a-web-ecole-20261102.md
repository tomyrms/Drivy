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
