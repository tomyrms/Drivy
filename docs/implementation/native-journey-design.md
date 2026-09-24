# Séance, trajet et replay — direction cartographique

Le 24 septembre 2026, les écrans natifs sont recomposés à partir des maquettes `application-v3-17/01_seance_light.png` et `parcours-v3-16-{clair,sombre}.png`, selon R45/R46 et le chapitre de saisie pédagogique de `gps-replay.md`.

- Séance : titre, date, carte du trajet courant, action principale et prochaines leçons réellement renvoyées par l’API. La carte d’exploration reste indépendante d’une capture.
- Trajet : carte dominante, bandeau compact, observations et grand bouton Signaler dans la zone sûre. Sans GPS, une composition temporelle remplace la carte vide. Avec texte d’accessibilité, Signaler reste fixe et les informations peuvent défiler.
- Signalement : six catégories en grille, puis trois statuts explicites ; le compteur et la fermeture suivent toujours l’écriture durable. La note facultative reste disponible dans le panneau développé. Aucun statut n’est choisi implicitement.
- Replay : carte dominante, chronologie et transport regroupés ; observations et bilan s’ouvrent séparément. Sur grande largeur, le panneau passe à gauche de la carte. Les positions absentes à un instant ne sont pas interpolées. Le bilan local reste privé, sans publication implicite.

Les séances locales gardent leur stockage SQLCipher et leur cycle existant ; cette reprise visuelle ne prétend pas implémenter le protocole scolaire serveur de capture.

## Revue visuelle ciblée

Le précédent rendu XCTest fondé sur `drawHierarchy` s’est bloqué autour des nouvelles vues cartographiques. Le script de capture lance désormais l’application simulateur et utilise le compositeur `simctl io screenshot`. L’entrée est exclue des builds Release et de tout appareil physique par `DEBUG && targetEnvironment(simulator)`. Elle est activée explicitement par `DRIVY_VISUAL_SCREEN`, ne se connecte à aucun serveur et conserve ses données synthétiques dans une base chiffrée temporaire distincte.

Captures iPhone/iPad clair/sombre : accueil, trajet, signalement, sans GPS, replay. Elles documentent une inspection de l’apparence de vues SwiftUI réelles ; elles ne qualifient ni GPS physique, ni autonomie, ni VoiceOver, ni sécurité en conduite. La compilation Apple et le résultat effectif de la capture doivent être reportés dans STATUS, sans déduire une qualification de la seule présence de ce script.
