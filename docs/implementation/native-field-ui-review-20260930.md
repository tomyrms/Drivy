# Revue des écrans natifs de terrain — 30 septembre 2026

## Périmètre et sources

Cette passe épure les écrans Swift de séance, accord GPS, signalement, observations, replay et bilan sur iPhone/iPad. Elle conserve l’identité native « Cartographie native », les contrôleurs GPS, la journalisation chiffrée, les autorisations serveur et les règles de partage. Aucun endpoint, modèle métier ou contrat n’est modifié.

Références relues : `AGENTS.md`, `COMMENCER_ICI.md`, R46, E23, `gps-replay.md`, contrats AP161–164/AP49 dans `api.md`, scénarios T407–T410. La décision de partage automatique du 28 septembre prime sur les descriptions historiques de publication privée du dossier de conception.

Captures inspectées avant intervention : fichiers synthétiques `iPhone-lesson-light-synthetic.png` du run 36645747154 ; `iPhone-live-signal-light-portrait-synthetic.png` et `iPhone-observations-light-portrait-synthetic.png` du run 36645752884 ; `iPhone-gps-choice-light-portrait-synthetic.png`, `iPhone-live-light-portrait-synthetic.png` et `iPad-replay-light-landscape-synthetic.png` dans `artifacts/review-20260930-p3/trajet/v`. Ces captures précèdent certains correctifs déjà présents : le compteur de positions et l’ancien affichage des cadenas ne sont pas attribués à la version actuelle.

## Guides effectivement appliqués

Le routeur `ui-skills-root` et son catalogue `visual` ont été consultés. Le mandat utilisateur d’utiliser les guides utiles prime sur la limite de trois guides du routeur.

| Guide lu | Application concrète |
| --- | --- |
| `swiftui-ui-patterns`, référence `sheets.md` | État local conservé, routes de feuilles existantes réutilisées, aucune recréation du collecteur pendant une adaptation. |
| `better-layout` | Bilan prioritaire dans la colonne compacte ; contexte parallèle maintenu sur iPad ; action Signaler hors défilement ; grille selon largeur utile. |
| `better-ui` | Surface native et tokens conservés ; appréciations en rangées, symbole et texte explicites ; aucun ajout d’animation décorative. |
| `better-typography` | Suppression de la réduction de police des thèmes ; titres contextuels moins dominants ; texte long replié seulement lorsque sa lecture intégrale reste accessible. |
| `better-accessibility` | Commandes de chronologie 44 pt, séparation des cibles voisines, annonce d’enregistrement, retour à une composition verticale en Dynamic Type, conservation d’un motif non soumis. |

Les recettes CSS/DOM de ces guides ne sont pas transposées littéralement à SwiftUI. Les contrôles natifs, les tailles de texte sémantiques et les animations du projet sont conservés.

## Corrections

| Priorité | Écran / constat confirmé dans la source | Correction |
| --- | --- | --- |
| P2 | Leçon terminée : en compact, trajet et observations précèdent le bilan à rédiger ; aperçu fixe 260 pt. | En-tête et erreurs, puis bilan, puis trajet/observations. La composition parallèle iPad reste identique. Aperçu ramené au token existant 176 pt. |
| P2 | En-tête de leçon : un lieu vide laisse un pictogramme isolé ; avatar consomme de la largeur en texte d’accessibilité. | Lieu absent non rendu ; avatar 44 pt et retiré uniquement aux tailles d’accessibilité. Nom et horaires restent lisibles. |
| P2 | Préparation GPS : un blocage ne propose que des tentatives de GPS ou Fermer. | Action explicite « Continuer sans GPS » réutilisant exactement invalidation puis fermeture. Absente durant un départ et tant qu’un démarrage journalisé attend sa réconciliation. Elle ne prétend pas arrêter un GPS déjà démarré. |
| P2 | Accord GPS : grandes illustrations et hauteur minimale 144 pt de chaque réponse. | Deux choix toujours égaux, icône 44 pt et hauteur minimale 104 pt ; mêmes commandes, accès aux notices et protection du refus élève. |
| P2 | Signalement : trois colonnes fixes et réduction du texte, même avec de grands caractères ; appréciations en trois tuiles massives. | Colonnes adaptatives, une colonne aux tailles d’accessibilité, aucun minimumScaleFactor. Emblèmes 48 pt ; appréciations sur trois rangées d’au moins 64 pt, sans statut présélectionné. Le VoiceOver hint précise que le choix enregistre. |
| P2 | Observations sans GPS : action principale avant la liste et titre élève très dominant. | Liste immédiatement après le contexte ; action Signaler dans la barre inférieure sûre ; titre contextuel au niveau de la leçon ; titre de section redondant retiré. |
| P2 | Chronologie : zones de repères 34 pt / piste 36 pt et superposition des boutons à des instants proches. | Deux zones de 44 pt et retrait de 22 pt. Les boutons qui se chevaucheraient sont regroupés dans un Menu natif avec un choix par observation. Les offsets, IDs et ticks exacts restent inchangés ; les centres des groupes sont distants d’au moins 48 pt. |
| P2 | Replay : commentaire de repère très long peut agrandir le dock au point d’en repousser les commandes. | Résumé du commentaire limité à trois lignes dans le dock standard ; texte intégral toujours dans la liste et en présentation d’accessibilité défilante. Liste ouverte en grande feuille avec texte d’accessibilité. |
| P2 | Fin de leçon : Annuler ou glisser peut perdre le motif du permis non soumis. | Confirmation d’abandon sur Annuler ; glissement désactivé tant qu’un motif existe. La réussite et ses effets durables suivent toujours les commandes existantes. |
| P2 | Historique des envois : nom et bouton Envoyer restent sur une même ligne en Dynamic Type. | Rangée verticale aux tailles d’accessibilité ; bouton non comprimé aux tailles ordinaires. |

Les vues live, contrôles de carte et styles d’observation déjà corrects n’ont pas été réécrits. L’instant du signalement, la création uniquement après choix explicite, la confirmation après écriture durable, les droits, confirmations destructives et commandes GPS sont conservés.

## Vérification et limites

- `git diff --check` exécuté sur les fichiers de cette passe : aucune erreur d’espacement.
- Ajout de trois tests purs dans `DrivyTimelineMarkGroupTests.swift` : regroupement des instants voisins avec conservation de tous les choix ; redimensionnement sans changement d’offset ; instants identiques et durée nulle.
- Les identifiants UI existants sont conservés. Nouvel identifiant : `capture-continue-without-gps`.
- Swift/Xcode indisponibles sur cet hôte Windows : compilation, tests et nouvelles captures restent à exécuter par la campagne Apple pilotée par l’agent racine. Les captures anciennes ne qualifient pas les changements de cette passe.
- À vérifier sur les nouveaux rendus : iPhone compact et grands caractères, iPad portrait/paysage et fenêtre étroite ; long commentaire de replay ; menu de repères rapprochés ; motif permis Annuler/Continuer/abandon ; accès au bilan et à Signaler après défilement.
- Aucun résultat physique GPS, batterie, usage en circulation ou VoiceOver réel n’est revendiqué.

Validation visuelle finale en attente des nouveaux rendus Apple ; pas d’approbation globale depuis la seule lecture du code.
