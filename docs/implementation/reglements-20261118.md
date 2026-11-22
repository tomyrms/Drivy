# R01-T06 — Règlements manuels et soldes par école (#458)

Branche `tomyrms/r01-t06-reglements`, issue de la tête de `tomyrms/r01-t05-factures`. Rien n'a été poussé, fusionné ni déployé.
Règle du porteur du 13 novembre : aucun test n'est exécuté avant la fin de l'épic R01.

## Périmètre

- Saisie par un opérateur d'un règlement reçu hors de Drivy : virement, espèces ou autre.
- Affectation à une ou plusieurs factures émises de la même école, libération, annulation et correction.
- Régularisation explicite du reste d'un règlement.
- Soldes, retard et dette par école, calculés à un seul endroit.
- Hors périmètre : prestataire d'encaissement, relances, PDF et QR-facture (#459), vue de l'école (#460), suspension en pause (#461).

## Unités et dates

- Montants : entiers en centimes de CHF, de 1 à 100 000 000. Une autre devise est refusée, sans conversion.
- La date de réception est un jour civil Europe/Zurich, jamais après aujourd'hui.

## Modèle

Migration `20261118_platform_payments.sql`. Aucune donnée n'est créée.

- `platform_payment` : le règlement reçu, son auteur, son état (`RECORDED`, `VOIDED`) et le lien vers l'original qu'il corrige.
- `platform_payment_allocation` : une part d'un règlement sur une facture, `ACTIVE` ou `RELEASED`, avec auteur, date et cause de la libération.
- `platform_payment_regularization` : une part du reste d'un règlement, de nature `REFUND_RECORDED` ou `OTHER`, avec un motif obligatoire.
- RLS forcée sur les trois tables, aucune suppression. Les écritures passent par des fonctions `SECURITY DEFINER` dont l'acteur est l'opérateur relu en base.
- Des gardes refusent toute réécriture d'un montant, d'une affectation ou d'une régularisation : on libère, on annule ou on corrige, et l'original reste lisible.

## Calcul unique

- `platform_payment_available` : montant moins affectations actives moins régularisations actives.
- `platform_invoice_settlement(facture, jour)` : `PAID`, `PARTIAL`, `UNPAID` ou `CREDITED`, montant réglé, avoir, solde et retard. Le solde vaut 0 pour une facture créditée, sinon total moins affectations actives.
- `platform_client_debt(école, jour)` : solde ouvert, montant et nombre de factures en retard, plus ancienne échéance due, reste non affecté.
- La fiche, la liste des factures et son filtre utilisent ces fonctions. L'écran n'en recalcule aucune. #460 et #461 devront les réutiliser.

## Règles des commandes

Toutes les commandes partent sous la version de facturation de la fiche (If-Match) avec une clé d'idempotence, et rendent la facturation relue. Elles prennent le verrou de l'école.

- Saisir (`POST .../payments`) :
  - sans affectation, avec répartition automatique sur les échéances les plus anciennes, ou avec des montants par facture ;
  - un trop-perçu reste « non affecté » sur le règlement ;
  - même montant pour la même école, à trois jours près ou avec la même référence : refus `PAYMENT_POSSIBLE_DUPLICATE` tant que l'opérateur ne confirme pas.
- Affecter : seulement une facture émise de la même école, dans la limite du reste du règlement et du solde de la facture.
- Libérer : motif obligatoire, l'affectation reste dans l'historique.
- Annuler : motif et confirmation. Les affectations sont libérées dans la même transaction. Refus si une régularisation est active.
- Corriger : l'original passe en `VOIDED` (cause `CORRECTED`) et garde son auteur. Un nouveau règlement reprend ses factures dans l'ordre, jusqu'à son montant et au solde de chacune. Refus si rien ne change ou si une régularisation est active.
- Régulariser : seulement sur le reste disponible. Drivy enregistre ce que l'opérateur déclare avoir fait. Il n'exécute et n'annonce aucun remboursement.
- Un avoir est refusé tant que des règlements sont affectés à la facture (`INVOICE_PAID`) : il faut d'abord les libérer.
- Un téléchargement, un QR ou une déclaration de l'école n'a aucune route vers ces commandes.

## Lecture

- `GET /v1/platform/clients/:id/billing` ajoute `debt`, `payments`, et pour chaque facture `settlement` et `allocations`.
- `GET /v1/platform/invoices` accepte le filtre `settlement`.
- Contrat `apps/api/contracts/platform-billing.json` régénéré. L'OpenAPI canonique 3.11.0 n'est pas modifié.

## Web

- Relais : liste fermée des sept commandes, schémas de réponse complets, identifiants mis en minuscules.
- Fiche de l'école : solde ouvert, retard, reste non affecté, rubrique « Règlements » et historique des règlements annulés ou corrigés.
- Boîtes : saisie, détail, affectation, libération, annulation, correction, régularisation et annulation de régularisation. Chacune relit le règlement dans la facturation à jour.
- Doublon probable : la confirmation est un bouton distinct, hors du pied de page, pour qu'un double clic sur « Enregistrer » ne la déclenche pas.
- Onglet Factures : état de règlement dans chaque ligne et filtre « Règlement ».
- Une écriture n'est affichée qu'après la réponse du serveur. Une réponse perdue se rejoue avec la même clé.

## Limites

- Aucun encaissement réel, aucun rapprochement bancaire.
- Un trop-perçu non affecté ne réduit pas la dette de lui-même : l'opérateur l'affecte ou le régularise.
- La régularisation ne porte que sur le reste d'un règlement.
- La correction reprend les affectations par `created_at, id` : entre deux affectations du même instant, l'ordre suit l'identifiant et n'a pas de sens métier.
- La suspension (#461) devra appeler `platform_client_debt` sous `platform_client_lock`, pour qu'un règlement concurrent soit vu ou attendu.

## Tests écrits, jamais exécutés

- `apps/api/test/platform-payments-model.test.ts` : bornes des saisies et projections.
- `apps/api/test/platform-billing-model.test.ts` : adapté au calcul de règlement.
- `apps/api/test/platform-billing.integration.test.ts` : bloc « Règlements (R01-T06, #458) » sur PostgreSQL. Ce fichier corrige aussi trois erreurs du test T05 lui-même, qui n'avait jamais tourné (réponse lue comme une facture, deux fiches pour une même école, enveloppe inutilisée).
- Aucun test web n'a été écrit pour cette tâche.

Contrôles exécutés le 22 novembre 2026 : `tsc` de l'API, `tsc` du client, des vérifications et du serveur web, `vite build`, génération du contrat (sans écart). L'interface n'a pas été ouverte dans un navigateur.
