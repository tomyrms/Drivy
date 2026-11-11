# R01 — Administration de la plateforme Drivy

[← Roadmap produit](../ROADMAP.md)

| Maturité | Horizon | Suivi |
| --- | --- | --- |
| Cadré | À planifier | [Epic #452](https://github.com/tomyrms/Drivy/issues/452) et 11 sous-tâches ouvertes |

## Décision du 11 novembre 2026

Le porteur a précisé son besoin et autorisé la création de l’epic et de ses sous-tâches. Le suivi est désormais [#452](https://github.com/tomyrms/Drivy/issues/452). Le cadrage couvre R01 et les parties de [R03](R03-modules-et-offres.md) et [R04](R04-facturation-saas.md) nécessaires à une gestion commerciale utilisable.

## Périmètre retenu

- Deux opérateurs au démarrage, mêmes droits commerciaux complets, puis invitation/révocation d’autres opérateurs.
- Génération et **copie d’un code** transmis manuellement, notamment par WhatsApp. Le responsable installe l’app, saisit ce code, s’authentifie et crée lui-même son école.
- Réutilisation de l’ouverture et de la préparation existantes : création iPhone/iPad, continuité explicite et reprenable vers la préparation web.
- Portefeuille d’écoles, fiches clientes, contacts/responsables, suivi de préparation et historique commercial.
- Offres/modules attribués par école, avec droits contrôlés côté serveur et cohérents entre clients.
- Montant initial unique puis abonnement mensuel ; tarifs particuliers et remises par école.
- Essais de durée configurable, prolongeables ou terminables par l’opérateur.
- Factures PDF avec QR suisse, envoi et consultation par l’école ; confirmation **manuelle** des règlements, paiements partiels et corrections traçables.
- Espace école : offre, modules, échéances, documents et demandes de changement/résiliation. La résiliation requiert une confirmation opérateur et une date d’effet visible.
- Alertes, relances et suspension pour impayé selon une règle configurable, puis reprise après régularisation.
- Tableau de bord et actions à traiter : facturé, encaissé, dû et revenu mensuel contractuel distincts.

## Paramètres et précisions

Portail prévu en français, responsive et en CHF. Montants, durées d’essai, remises, échéances, rappels et coordonnées de facturation restent configurables ; aucun tarif réel ni IBAN n’est fixé dans ces documents.

L’epic propose deux mois calendaires depuis l’échéance de la plus ancienne somme encore due avant suspension, avec réglage et exceptions par école. Un essai expiré ne crée pas automatiquement un abonnement payant ou une dette. Les changements de conditions sont proposés à la prochaine période mensuelle, sans prorata automatique ; les exceptions sont explicites.

Les conditions et factures émises sont historisées. La facturation pendant suspension est un choix explicite avant activation des traitements. Les écoles pilotes existantes ne reçoivent aucune dette, facture rétroactive ou restriction par défaut.

## Limites conservées

L’administration commerciale ne donne pas accès aux élèves, trajets, notes ou messages. L’assistance reste [R02](R02-assistance-autorisee.md). Les paiements des élèves restent [R10](R10-gestion-financiere-cours-lecons.md) ; ils ne constituent pas le revenu de Drivy.

Désactivation, fin d’essai et suspension ne suppriment pas l’historique et préservent la finalisation sûre d’une leçon engagée. L’accès aux factures et au contact Drivy reste disponible selon une autorisation commerciale adaptée.

Le paiement automatique, le site vitrine et les extensions d’offres non retenues restent distincts.

## Suivi et preuve

Les 11 lots, dépendances et critères de clôture sont dans [l’epic #452](https://github.com/tomyrms/Drivy/issues/452) ; ne pas dupliquer son index ici.

L’existant a été examiné en lecture statique sur master ff79607a, avec contrôle des issues, PR et branches. Les tickets ne valent pas réalisation : aucun nouvel opérateur, facture, règlement, relance, suspension ou déploiement n’a été activé. L’avancement et les preuves seront consignés dans les issues, PR et [STATUS.md](../../implementation/STATUS.md).
