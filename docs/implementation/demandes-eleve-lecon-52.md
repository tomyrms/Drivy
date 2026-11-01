# Demandes de l'élève sur sa leçon : déplacement et annulation (issue #52)

1er novembre 2026, branche `claude/eleve-demande-52`, base `master` `d4257f07`. Extension hors contrat canonique (OpenAPI 3.11.0 conservé) : [contracts/lesson-change-requests.json](../../apps/api/contracts/lesson-change-requests.json). Aucun test, typage ni compilation n'a été lancé pour ce lot, à la demande du porteur ; rien n'est déployé.

## 1. Règles retenues

Le porteur a validé ces règles par défaut le 1er novembre 2026 (« #52, recommandé »). Elles restent des choix de produit relisibles.

- **Une demande n'a aucun effet.** Elle ne modifie ni la leçon, ni ses occupations, ni son compte. Le créneau d'origine reste valable et occupé jusqu'à la réponse du personnel ; « Demande envoyée » n'est jamais présenté comme « Rendez-vous déplacé ».
- **Deux demandes possibles** : un déplacement (l'élève indique ses disponibilités ou une proposition, obligatoires) et une annulation (motif facultatif). Une seule demande en attente par leçon ; l'élève peut la retirer tant qu'elle est en attente, ce qui n'annule pas la leçon.
- **Pas d'annulation autonome.** Même avant l'échéance, l'élève demande : la procédure de l'école dit elle-même que « contacter l'école ne confirme pas l'annulation ». Le moniteur ou l'administration répond.
- **Aucun délai et aucun frais inventés.** L'échéance affichée est celle de la procédure approuvée de la leçon (`school_policy_version.cancellation_rules`, migration 20261028 : `cancellationHours`, `lateAction`). Sans délai fixé par l'école, rien n'est supposé (`deadlineAt` et `late` valent null). Une demande faite après l'échéance reste possible, porte un badge « Hors délai » côté personnel et n'est ni refusée ni facturée automatiquement.
- **Conditions figées.** La demande garde la version de procédure, le délai et l'état « hors délai » lus à sa création : changer la procédure ensuite ne la réécrit pas.
- **Réponse du personnel** (administration, ou moniteur de la leçon) : refuser (motif facultatif lu par l'élève), ou accepter en déplaçant / annulant la leçon par les commandes existantes. Ces commandes relisent tous leurs contrôles (créneau libre, ouverture du moniteur, version de la leçon) ; une annulation libère les occupations une seule fois, un refus ne les touche pas.
- **Caducité.** Si le personnel déplace ou annule la leçon sans désigner la demande, les demandes que ce changement rend caduques passent à `SUPERSEDED` (toutes si la leçon est annulée, les demandes de déplacement si elle est déplacée). Une demande d'annulation survit à un déplacement.

## 2. API

Migration `20261101_lesson_change_requests.sql` (additive) : table `lesson_change_request` (sécurité par ligne forcée), un index unique « une demande en attente par leçon », quatre fonctions de portée (`lesson_change_read`, `_staff`, `_learner`, `_conditions`), politiques de lecture (mêmes lecteurs que la leçon), d'insertion (élève de la leçon, en attente), de retrait (auteur) et de réponse (personnel), reçus d'opération et audit pour les trois nouvelles commandes.

| Route | Rôle | Effet |
| --- | --- | --- |
| `GET lessons/{id}/change-requests` | lecteurs de la leçon | conditions applicables, `canRequest` et `blockedReason`, vingt dernières demandes |
| `POST lessons/{id}/change-requests` (201) | `LEARNER`, élève de la leçon | crée la demande ; refuse leçon terminée, annulée, commencée, passée ou déjà demandée |
| `POST lesson-change-requests/{id}/withdraw` (If-Match) | auteur | retire la demande en attente |
| `POST lesson-change-requests/{id}/refuse` (If-Match) | `ADMIN`, moniteur de la leçon | refuse, motif facultatif |
| `GET lesson-change-requests` | `ADMIN`, `INSTRUCTOR` | boîte : demandes en attente sur des leçons planifiées, dans le périmètre de lecture |
| `POST lessons/{id}/move` et `/cancel` | inchangés | champ facultatif `changeRequestId` : la demande devient `ACCEPTED` dans la même transaction |

Les commandes passent par `schoolCommand` : clé d'idempotence, reçu `GET operations/{id}` lisible par l'auteur (`authorizeLessonChangeOperation`), audit. Code : `lesson-change-requests.ts` et `lesson-change-resolution.ts` (sans dépendance vers `lessons.ts`).

## 3. iOS

- `SchoolLessonChangeClient` : lecture de l'état, création, retrait, refus et boîte, sur le modèle du client des cours. Ces gestes passent directement par l'école, **sans file locale** : sans réseau, rien ne part et l'écran le dit. Le même identifiant d'opération sert à chaque nouvel essai d'un même geste, pour qu'une réponse perdue ne crée jamais une seconde demande.
- Fiche de la leçon : l'élève trouve « Demander un déplacement » et « Demander l'annulation » dans « Plus d'actions » (leçon planifiée, non commencée, sans demande en attente), puis une feuille avec le délai de l'école et la procédure à la demande. Une demande en attente se lit en tête de la fiche (« En attente de ton moniteur », « Retirer la demande ») ; la dernière demande refusée rappelle son motif.
- Moniteur ou administration : la demande de l'élève s'affiche en tête de la fiche avec « Déplacer » ou « Annuler la leçon » (feuille de planification existante, qui envoie `changeRequestId`) et « Refuser ».

## 4. Non fait, à qualifier

- **Aucune vérification exécutée** : ni typage, ni tests API sur PostgreSQL (`lesson-change-requests.integration.test.ts` écrit, jamais lancé), ni compilation Swift (pas de chaîne Swift sous Windows), ni tests Swift (`SchoolLessonChangeTests`), ni captures. La migration et ses politiques de sécurité par ligne n'ont jamais tourné.
- **Web** : aucune boîte de demandes dans la console d'administration ; l'administration répond depuis l'app, ou déplace / annule sans désigner la demande (elle devient alors caduque).
- **Notifications** : aucune alerte au moniteur à la demande, ni à l'élève à la réponse (#43/#44 : le push n'est pas activé). Les demandes se lisent en ouvrant la leçon.
- **Persistance** : les trois gestes de l'élève et le refus ne sont pas dans la file locale chiffrée ; la reprise après arrêt forcé n'existe pas pour eux. Accepter passe par la planification, qui a sa propre file.
- **Hors périmètre** : demande par l'élève d'un créneau précis réservé d'avance, modification directe du planning du moniteur, paiement, calcul de frais d'annulation tardive.
- **Réponse du moniteur** : la feuille de planification ne rappelle pas la proposition de l'élève ; elle reste lisible dans la fiche sous la feuille.
