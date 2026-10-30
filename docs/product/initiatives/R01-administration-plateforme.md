# R01 — Administration de la plateforme Drivy

[← Roadmap produit](../ROADMAP.md)

| Maturité | Horizon | Décision de développement |
| --- | --- | --- |
| Idée | À définir | Non prise |

## L'idée

Un espace privé pour l'exploitant de Drivy, distinct du portail utilisé par les auto-écoles. L'objectif est de gérer les établissements clients et leur relation avec Drivy sans devoir intervenir manuellement dans la base de données.

## Ce que cet espace pourrait permettre

- Retrouver les auto-écoles clientes et leurs interlocuteurs autorisés.
- Consulter leur offre, les modules disponibles et l'état de leur abonnement.
- Savoir quelles factures Drivy sont réglées, en attente ou en incident de paiement.
- Gérer les opérations nécessaires à une école pilote, active ou archivée.
- Consulter des indicateurs utiles dont la finalité et la source auront été définies.

Ce sont des pistes de cadrage, pas une liste de fonctionnalités promises.

## Les distinctions à conserver

**Administrer un client n'est pas consulter ses élèves.** L'accès aux dossiers, aux trajets, aux notes ou aux messages ne découle pas du droit de gérer un abonnement. L'assistance dans le contexte d'une école est un chantier distinct : [R02](R02-assistance-autorisee.md).

**Le revenu de Drivy n'est pas le chiffre d'affaires des auto-écoles.** Le panneau peut être conçu autour de ce que les écoles paient à Drivy. Les revenus propres d'une école ne sont ni présumés disponibles ni autorisés à la consultation par cette idée.

## Questions à trancher

Quels rôles auront les membres de l'équipe Drivy ? Quelles opérations seront possibles en lecture seule ? Lesquelles nécessiteront une confirmation renforcée ? Quelles métadonnées sont réellement nécessaires et comment tracer les actions de l'opérateur ? Comment traiter une fermeture d'école, un litige ou un compte pilote ?

Le périmètre minimal avant facturation automatisée reste à définir. Les concepts d'école et d'opérateur déjà présents devront être examinés avant de créer une seconde administration.

## Relations avec les autres initiatives

[R03 — Modules et offres](R03-modules-et-offres.md) définit ce qui est accessible commercialement. [R04 — Facturation SaaS](R04-facturation-saas.md) fournit les états de facturation. Un panneau minimal peut précéder leur version complète.

## Avant de créer une epic

Définir les opérations indispensables, les données visibles par rôle et leurs limites. Vérifier ensuite l'existant et les dépendances, puis faire valider le périmètre par le porteur.

**Aucun accès supplémentaire, développement ou déploiement n'est autorisé par cette fiche.**
