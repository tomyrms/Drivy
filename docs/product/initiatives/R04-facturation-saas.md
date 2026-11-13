# R04 — Abonnements et facturation SaaS de Drivy

[← Roadmap produit](../ROADMAP.md)

| Maturité | Horizon | Décision de développement |
| --- | --- | --- |
| Cadré | Volet V1 dans R01 | [Epic #452](https://github.com/tomyrms/Drivy/issues/452) |

## Volet retenu le 11 novembre 2026

Le porteur a choisi une première version avec **confirmation manuelle des règlements**, intégrée à [l’epic R01 #452](https://github.com/tomyrms/Drivy/issues/452) : montant initial unique puis abonnement mensuel par école, tarifs/remises particuliers, essais configurables, factures PDF avec QR suisse et consultation des documents par l’école.

L’école peut demander un changement ou une résiliation. L’opérateur confirme la résiliation et sa date d’effet. Relances et alertes précèdent une suspension configurable ; l’epic propose deux mois calendaires depuis l’échéance du plus ancien solde impayé. Les prix, l’émetteur, la fiscalité, le compte bancaire et les délais se configurent à la mise en service.

Les lots [#456](https://github.com/tomyrms/Drivy/issues/456) à [#461](https://github.com/tomyrms/Drivy/issues/461) portent ce volet. L’encaissement automatique et les formules annuelles restent des extensions à cadrer ; les tableaux de réflexion ci-dessous ne rouvrent pas les choix déjà retenus. Les tickets n’émettent aucune facture ou prélèvement réel.

## L'idée

Gérer ce que les auto-écoles paient à Drivy : offre souscrite, abonnement, factures, règlements, renouvellement et changement de plan. Le panneau administrateur pourrait s'appuyer sur ces informations pour suivre les comptes clients.

**Ce chantier est distinct des paiements que les élèves versent à leur auto-école.** La gestion financière des cours, packs et régularisations reste [R10](R10-gestion-financiere-cours-lecons.md), issue de l’ancienne #45, sans être lancée par cette initiative.

## Périmètre à examiner

Abonnements mensuels ou annuels, essai éventuel, factures et avoirs, renouvellement, résiliation, changement d'offre, incidents de paiement et rapprochement des événements du prestataire retenu.

Le suivi doit distinguer une facture émise, un paiement en attente et un règlement réellement confirmé. Un retour de page de paiement ne suffit pas comme preuve d'encaissement.

## Paramètres et extensions à préciser

| Sujet | À définir |
| --- | --- |
| Modèle économique | Prix par école, moniteur, module ou autre unité. |
| Offres | Contenu du socle et options, en coordination avec R03. |
| Paiement | Prestataire, moyens acceptés, devise et traitement des frais. |
| Documents | Facturation, taxes à faire vérifier et conservation des documents. |
| Transitions | Prorata, montée/baisse de gamme, résiliation et éventuel remboursement. |
| Incidents | Relance, délai de grâce, litige et conséquences d'un impayé. |
| Essai | Durée, accompagnement, passage vers une offre payante et fin d'essai. |

Aucun tarif chiffré ni prestataire d’encaissement n’est sélectionné. Pour le volet de #452, les règlements sont saisis manuellement ; les options de paiement automatisé restent différées.

## Points de vigilance

Les événements répétés ou reçus en retard ne doivent pas produire de double effet. L'accès aux données et aux leçons ne doit pas être retiré brutalement à partir d'un événement non confirmé. Les états commerciaux, les droits aux modules et l'historique devront rester cohérents pendant les transitions.

Les indicateurs de revenu de Drivy devront reposer sur des faits disponibles, non sur des données de démonstration ou les revenus supposés des écoles.

## Relations et prochaine étape

Commencer par les offres de [R03](R03-modules-et-offres.md). Définir ensuite les règles commerciales et les responsabilités avant de choisir une solution de paiement. [R01](R01-administration-plateforme.md) affichera les états ; [R05](R05-site-vitrine.md) présentera seulement les offres effectivement retenues.

**Aucun encaissement, abonnement réel, mécanisme de suspension ou modification de données n'est autorisé par cette fiche.**
