# R10 — Gestion financière des cours et des leçons

Évolution future conservée à la demande du porteur (20 octobre 2026). Elle vient de l'ancienne issue [#45](https://github.com/tomyrms/Drivy/issues/45), fermée le 3 novembre 2026 au profit de cette fiche.

**Statut : hors périmètre actuel, sans priorité ni date fixée.** Liée aux cours collectifs (epic #37), mais elle ne bloque pas leur livraison : le suivi minimal « À régler / Payé sur place » est porté par #81, les présences par #42 et l'accomplissement par #82. Aucun de ces lots n'attend cette évolution.

À ne pas confondre avec [R04](R04-facturation-saas.md), qui concerne ce que Drivy facture aux écoles. R10 concerne l'argent entre une école et ses élèves.

## Situation de la première version

Paiement et questions financières traités sur place. Drivy conserve seulement les informations renseignées à la main par le personnel autorisé. Pas d'encaissement en ligne, de prélèvement, de remboursement automatique ni de consommation automatique de pack.

## Intention

Permettre une gestion financière intégrée des prestations, cohérente entre cours collectifs et leçons, sans confondre réservation, présence, accomplissement et paiement.

## Pistes à étudier, non validées

- Paiement en ligne, sur place, ou choix entre les deux ; paiement à l'inscription ou plus tard.
- Acompte, règlement partiel, montant restant et rapprochement des règlements.
- Packs comprenant des cours et des leçons : réservation du droit, consommation au bon événement, annulation et restitution explicites.
- Factures ou reçus, avoirs, remboursements et régularisations après annulation.
- Frais d'annulation selon la version des conditions réellement acceptée.
- Choix d'un éventuel prestataire et des moyens de paiement, comptes de destination des écoles, frais, droits et exigences de conformité.

Aucun prestataire, barème, moyen de paiement, délai ou règle de consommation de pack n'est imposé par cette fiche.

## Invariants à conserver

- Un paiement ne valide ni une présence ni l'accomplissement d'une formation.
- Un remboursement n'est affiché comme exécuté que lorsqu'il a réellement été confirmé.
- Les écritures et corrections restent auditables ; pas de réécriture silencieuse d'un historique payé sur place.
- Des événements de paiement répétés ou reçus en retard ne produisent ni double encaissement ni double remboursement.
- Les opérations financières respectent les droits et l'isolement des écoles.
- Un simple statut « Payé sur place » sans montant vérifié n'est jamais transformé après coup en transaction détaillée inventée.

## Conditions avant réalisation

- Valider le périmètre avec le porteur et les écoles concernées.
- Définir les règles de prix, d'annulation, de packs, de paiement partiel et de remboursement.
- Vérifier les contraintes contractuelles, de protection des données et de paiement applicables au moment de l'implémentation.
- Prévoir une reprise cohérente du suivi manuel existant (#81) sans altérer les faits enregistrés.
- Découper ensuite l'implémentation et ses critères de recette, sans intégrer ces fonctions par anticipation dans les lots actuels des cours.

Aucune issue de développement n'est créée automatiquement depuis cette fiche.
