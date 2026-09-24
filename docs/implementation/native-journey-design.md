# Séance, trajet et replay — direction cartographique

Le 24 septembre 2026, les écrans natifs sont recomposés à partir des maquettes `application-v3-17/01_seance_light.png` et `parcours-v3-16-{clair,sombre}.png`, selon R45/R46 et le chapitre de saisie pédagogique de `gps-replay.md`.

- Séance : titre, date, carte du trajet courant, action principale et prochaines leçons réellement renvoyées par l’API. La carte d’exploration reste indépendante d’une capture.
- Trajet : carte dominante, bandeau compact, observations et grand bouton Signaler dans la zone sûre. Sans GPS, une composition temporelle remplace la carte vide. Avec texte d’accessibilité, Signaler reste fixe et les informations peuvent défiler.
- Signalement : six catégories en grille, puis trois statuts explicites ; le compteur et la fermeture suivent toujours l’écriture durable. La note facultative reste disponible dans le panneau développé. Aucun statut n’est choisi implicitement.
- Replay : carte dominante, chronologie et transport regroupés ; observations et bilan s’ouvrent séparément. Sur grande largeur, le panneau passe à gauche de la carte. Les positions absentes à un instant ne sont pas interpolées. Le bilan local reste privé, sans publication implicite.

Les séances locales gardent leur stockage SQLCipher et leur cycle existant ; cette reprise visuelle ne prétend pas implémenter le protocole scolaire serveur de capture.

## Revue visuelle ciblée

Le précédent rendu XCTest fondé sur `drawHierarchy` a pris plus de vingt minutes et son run a été annulé ; les journaux finalement disponibles montrent un passage réussi du cas iPad juste avant l’annulation, sans preuve de deadlock. Le script de capture lance désormais l’application simulateur et utilise directement le compositeur `simctl io screenshot`. L’entrée est exclue des builds Release et de tout appareil physique par `DEBUG && targetEnvironment(simulator)`. Elle est activée explicitement par `DRIVY_VISUAL_SCREEN`, ne se connecte à aucun serveur et conserve ses données synthétiques dans une base chiffrée temporaire distincte.

Captures iPhone/iPad clair/sombre : accueil, trajet, signalement, sans GPS, replay. Elles documentent une inspection de l’apparence de vues SwiftUI réelles ; elles ne qualifient ni GPS physique, ni autonomie, ni VoiceOver, ni sécurité en conduite. La compilation Apple et le résultat effectif de la capture doivent être reportés dans STATUS, sans déduire une qualification de la seule présence de ce script.

## Résultat exécuté et exemples demandés

Le build appareil `36049713595` réussit pour `072e724` : IPA 0.6.0/build 16, Release arm64, SHA-256 `2869dee158fa4779ee97200eeab65a177c648d1dcba1cddc417dd129e3288479`. La finition `a394825` compile aussi dans le run `36050985364`.

Le run ciblé `36049725920` compile le simulateur puis produit dix captures iPhone : les cinq vues en clair et sombre. L’inspection a confirmé la composition du Live, du signalement et du sans GPS, et a révélé deux corrections : cadrer le trajet dans la surface libre au-dessus du panneau Replay, et forcer la date française du bandeau. Le run a été annulé après huit minutes de capture ; aucune capture iPad n’a été produite avant cette limite. La variante iPad existe dans le code, sans preuve visuelle nouvelle sur ce run. Aucune campagne fonctionnelle n’a été exécutée.

À la demande suivante du porteur, les deux trajets fictifs Cernier → Neuchâtel reçoivent un accès direct depuis Séance. Ils restent dans un groupe Exemples dans l’historique et leur origine est visible dans le replay, le bilan et les détails. La carte les annonce comme positions d’exemple. Le cadrage tient compte des commandes flottantes, sans déplacer ni inventer de point d’un trajet réel. Leur création chiffrée et idempotente relève du module Core d’exemples ; l’UI lit l’origine persistée, elle ne reconnaît pas une fixture en comparant un prénom ou un identifiant codé en dur.
