# #311 — Trajets (#332, R21)

Reconstruit par le coordinateur le 29 octobre 2026, dans `portal/trips/`, section `trajets` (espace Élèves).

- Lecture identique à la console : `readPage` paginé par curseur pour l’inventaire, `readAll` filtré pour un élève (`learner` dans la requête), avec l’avertissement d’historique partiel quand la lecture est tronquée. La recherche ne porte que sur la page lue et le dit. Retour au dossier avec le contexte d’agenda conservé, lien « Tous les trajets ».
- Modèle pur `trip-model.ts` réutilisé (durée, état en cours ou interrompu). Aucun replay, carte, export ni position affichée : la reconstruction n’ajoute rien au contrat.
- Tableau sémantique en ordinateur, même tableau empilé en lignes en mobile (un seul arbre).
- Données fictives : `preview/families/trips.ts`, 14 trajets dont un en cours et un interrompu.

Exécuté : typage, tests web, build d’aperçu, captures 1440/390 clair et sombre, filtre par élève, recherche. Non exécuté : pagination réelle (l’aperçu renvoie une seule page), console authentifiée.
