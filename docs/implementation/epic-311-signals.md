# #311 — Signalements (#331, R20)

Reconstruit par le coordinateur le 29 octobre 2026, dans `portal/signals/`, section `signalements` (espace Réglages).

- Logique : `console/observation-themes-model.ts` réutilisé tel quel (module pur, déjà testé par `test/observation-themes-model.test.ts`). Lecture `readObservationThemes`, enregistrement `saveObservationThemes` avec `If-Match`, brouillon protégé par `useSectionDraft` et jamais rejoué sur une version plus récente.
- Rendu : liste ordonnée avec poignée (glisser au pointeur, flèches, Début/Fin, Échap annule), boutons Monter/Descendre gardés en mobile, interrupteur d’affichage (le dernier thème affiché ne se masque pas, explication liée), menu Réinitialiser (ordre d’origine, configuration d’origine), aperçu moniteur dépliable, barre d’enregistrement collante. Annonces de déplacement pour les lecteurs d’écran conservées.
- Conflit de version : rechargement et message court ; refus d’accès : passage en lecture seule. Aucun succès avant reçu.
- Pictogrammes : copie du chargeur `theme-icons` dans la famille (la vue historique `.tsx` n’est pas importable par le portail).
- Données fictives : `preview/families/signals.ts`, 18 clés stables, 12 affichées par défaut.

Socle au passage : `portal/components/feedback.tsx` (lecture et retour de commande partagés ; Élèves et Équipe gardent pour l’instant leurs copies), bouton fantôme désactivé sans bordure, barre basse à cinq espaces sans libellé tronqué.

Exécuté : typage client, 472 tests web (dont la frontière du portail), build d’aperçu, captures 1440 et 390 en clair et sombre : lecture, déplacement + masquage, aperçu mobile déplié, scénario Refus (erreur affichée, saisie conservée). Non exécuté : glisser-déposer réel au doigt, lecteur d’écran, conflit de version et réponse perdue en navigateur, console authentifiée.
