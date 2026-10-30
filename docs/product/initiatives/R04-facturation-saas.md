# R04 — Abonnements et facturation SaaS de Drivy

[← Roadmap produit](../ROADMAP.md)

| Maturité | Horizon | Décision de développement |
| --- | --- | --- |
| Idée | À définir | Non prise |

## L'idée

Gérer ce que les auto-écoles paient à Drivy : offre souscrite, abonnement, factures, règlements, renouvellement et changement de plan. Le panneau administrateur pourrait s'appuyer sur ces informations pour suivre les comptes clients.

**Ce chantier est distinct des paiements que les élèves versent à leur auto-école.** La gestion financière des cours, packs et régularisations reste le sujet existant [#45](https://github.com/tomyrms/Drivy/issues/45), sans être lancée par cette initiative.

## Périmètre à examiner

Abonnements mensuels ou annuels, essai éventuel, factures et avoirs, renouvellement, résiliation, changement d'offre, incidents de paiement et rapprochement des événements du prestataire retenu.

Le suivi doit distinguer une facture émise, un paiement en attente et un règlement réellement confirmé. Un retour de page de paiement ne suffit pas comme preuve d'encaissement.

## Décisions ouvertes

| Sujet | À définir |
| --- | --- |
| Modèle économique | Prix par école, moniteur, module ou autre unité. |
| Offres | Contenu du socle et options, en coordination avec R03. |
| Paiement | Prestataire, moyens acceptés, devise et traitement des frais. |
| Documents | Facturation, taxes à faire vérifier et conservation des documents. |
| Transitions | Prorata, montée/baisse de gamme, résiliation et éventuel remboursement. |
| Incidents | Relance, délai de grâce, litige et conséquences d'un impayé. |
| Essai | Durée, accompagnement, passage vers une offre payante et fin d'essai. |

Aucune valeur chiffrée ni aucun prestataire ne sont sélectionnés à ce stade.

## Points de vigilance

Les événements répétés ou reçus en retard ne doivent pas produire de double effet. L'accès aux données et aux leçons ne doit pas être retiré brutalement à partir d'un événement non confirmé. Les états commerciaux, les droits aux modules et l'historique devront rester cohérents pendant les transitions.

Les indicateurs de revenu de Drivy devront reposer sur des faits disponibles, non sur des données de démonstration ou les revenus supposés des écoles.

## Relations et prochaine étape

Commencer par les offres de [R03](R03-modules-et-offres.md). Définir ensuite les règles commerciales et les responsabilités avant de choisir une solution de paiement. [R01](R01-administration-plateforme.md) affichera les états ; [R05](R05-site-vitrine.md) présentera seulement les offres effectivement retenues.

**Aucun encaissement, abonnement réel, mécanisme de suspension ou modification de données n'est autorisé par cette fiche.**
