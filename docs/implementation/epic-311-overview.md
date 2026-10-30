# #311 — Accueil et préparation de l’école (#321, R10)

Reconstruit par le coordinateur le 29 octobre 2026, dans `portal/overview/`, section `apercu`.

- Entrée quotidienne d’une école active : redirection vers l’agenda en remplaçant l’entrée d’historique, contexte d’agenda transmis (comme la console).
- Préparation volontaire (`from=configuration`, onglet « Préparation » de Réglages) : prochaines actions décidées par le serveur (`setup-draft/next-actions`), « Planifier une leçon » vers la planification, autres actions vers leur section ; formations mises de côté comptées depuis `setup-draft` (schéma réduit au seul champ utile) ; école prête annoncée sans autre texte.
- École archivée : préparation fermée, planning et informations consultables.
- École en préparation et préparation d’un permis (`from=formations`) passent par le guide unique #320, pas encore reconstruit : la page le dit et propose l’ancienne présentation (composant partagé `portal/components/not-rebuilt.tsx`, désormais aussi utilisé par la console).
- Non repris ici : bandeau « Pour planifier une leçon » et carte « Votre premier rendez-vous » affichés en tête de l’agenda par la console historique — à intégrer côté Agenda (propriétaire Planning).

Exécuté : typage, 472 tests web, deux builds, captures 1440/390 clair et sombre. Non exécuté : écoles archivée et en préparation en navigateur (l’aperçu n’a qu’une école active), vraie BFF.
