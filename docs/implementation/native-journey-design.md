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

## Trajets personnels : états et commandes

La passe suivante applique AS03–AS07 à Live, Historique et Replay, sans modifier le collecteur ni le stockage. L’historique vide montre désormais l’erreur de lecture et son action Réessayer lorsque le contrôleur autorise cette lecture. Le replay indisponible conserve aussi le message d’erreur. Une liste vide n’est plus présentée comme un historique confirmé après une panne.

Sans GPS, le texte dit directement que les observations gardent leur heure sans position. Pendant une sauvegarde ou après un arrêt, le bandeau n’annonce plus un trajet en cours. Une interruption du replay apparaît dans son panneau principal. Les listes de trajets sont plus compactes et leur pictogramme disparaît au texte d’accessibilité. Les exemples restent nommés comme données fictives ; aucun symbole décoratif ne remplace leur origine.

Le replay garde un seul accès à la liste d’observations, quatre commandes de lecture et une action Bilan personnel d’au moins 44 points. Sans point ni observation, il n’offre plus une lecture sans contenu. Précédent/suivant parcourent chaque identifiant dans l’ordre sauvegardé, y compris à heure identique ; sélectionner un repère conserve l’état de lecture selon E24. Le curseur temporel, l’ouverture d’une feuille et la demande de suppression mettent explicitement la lecture en pause. Aucun calcul de géométrie ni comblement de lacune n’est ajouté.

Le bilan personnel indique qu’il reste sur cet appareil et n’est pas partagé avec l’école. Les confirmations, la limite de texte et la fermeture après écriture réussie restent inchangées. Cette dénomination distingue ce parcours du bilan scolaire publié.

### Libellés à reprendre dans les racines, hors de ce lot

- Entrée `Essais locaux` → `Trajets personnels` ; `Revenir à l’essai en cours` → `Revenir au trajet en cours`.
- Explication proposée : `Les trajets et bilans personnels restent sur cet appareil. Ils ne sont pas partagés dans les dossiers de l’école.`
- Racine locale `Séance d’essai` → `Trajets personnels`, `Nouvelle séance` → `Nouveau trajet` ; remplacer le panneau générique « Prendre des repères » par l’action et le choix réel avec ou sans GPS. La limite de deux heures reste visible, sans la présenter comme une leçon scolaire.

Ces propositions ne sont pas appliquées aux fichiers Root/Home, réservés à l’intégration. Contrôle de diff effectué ; aucune nouvelle capture ou compilation Apple n’est revendiquée par cette passe. Les effets du texte agrandi, des observations simultanées et de l’interruption restent à confirmer dans le binaire groupé.

## Signalement personnel : choix et interruption

Le retour aux catégories reçoit une cible de 44 × 44 points. L’en-tête conserve l’instant figé et écrit « Sans position » ou « Sur le trajet » ; il ne s’appuie plus sur le seul pictogramme pour cette différence. L’instruction « Choisissez le moment à retenir » est retirée, car le moment a déjà été figé à l’ouverture. Le changement de catégorie/statut cible le titre pour la lecture d’accessibilité, sans choisir de statut ni écrire une observation.

L’arrêt du trajet est expliqué même depuis la grille des catégories. Une note saisie reste disponible après arrêt ou échec ; le panneau se développe et retire le clavier automatique pour permettre sa relecture/copie. Le dépassement de 1 000 caractères est signalé près des statuts désactivés, avec un compteur à l’approche de la limite. La fermeture avec texte non enregistré garde sa confirmation. La liste d’un trajet d’exemple affiche son origine fictive.

Cette passe ne change ni `ObservationContext`, ni validation du contrôleur, ni moment d’écriture ou de fermeture après succès. Contrôle de diff seulement ; le focus VoiceOver est implémenté mais reste à vérifier sur Apple, sans résultat d’usage physique revendiqué.

## Carte et replay : recherche ciblée demandée par le porteur

Sources primaires consultées le 24 septembre 2026, puis décisions appliquées aux vues natives :

- [Uber Design — Navigation, 2023](https://medium.com/uber-design/designing-the-latest-generation-of-uber-navigation-maps-built-for-ridesharing-de3ede031ce1) motive une information lisible rapidement et un tracé contrasté. Drivy conserve ses couleurs, réduit les repères non sélectionnés et distingue thème et statut sur le repère choisi. Il n’adopte ni guidage routier, ni branding Uber, ni résultat de sûreté déduit de cet article.
- [Uber Engineering — interface de carte, 2019](https://www.uber.com/au/en/blog/building-a-scalable-and-reliable-map-interface-for-drivers/) décrit la gestion des surfaces recouvertes et des conflits de caméra. [MapKit pour SwiftUI, Apple](https://developer.apple.com/videos/play/wwdc2023/10043/) donne le raccord natif `safeAreaInset`. Les cartes personnelles utilisent désormais ces zones sûres réelles : retrait des hauteurs de panneau codées en dur et des `ignoresSafeArea` qui contournaient ces insets. MapKit cadre un rectangle géographique, avec marge autour des points, dans l’espace disponible.
- [Apple — MapCameraPosition](https://developer.apple.com/documentation/mapkit/mapcameraposition) distingue une caméra déplacée manuellement. Le suivi explicite de la position enregistrée s’interrompt sur pan/zoom, sans changer la collecte ni la lecture. « Voir tout le trajet » reste séparé du suivi. Une sélection d’observation ne réinitialise plus un cadrage manuel. Le GPS scolaire reçoit le même geste, depuis ses propres mesures persistées.
- [Plans — aperçu d’itinéraire](https://support.apple.com/fr-fr/guide/iphone/iph1b3553719/ios) distingue également aperçu et consultation détaillée. Le replay affiche une ligne temporelle marquée par les observations, un seul accès à leur liste et un bouton Bilan directement dans le bandeau. Le panneau de lecture est plus court ; sélectionner une observation montre sa note et ouvrir la liste la place au centre. Les marques de temps complètent les boutons précédent/suivant, sans devenir de petites cibles tactiles obligatoires.

Ces choix sont une adaptation à Drivy, pas une reproduction d’un écran externe. Sur iPad large, le Live personnel passe en panneau latéral pour laisser la carte utiliser toute la hauteur. Les lacunes restent sans position et sans interpolation. Contrôle de diff effectué ; deux rendus iPhone ciblés Replay/Live sont proposés à l’intégration pour vérifier la surface utile, sans lancer une matrice générale ou annoncer une qualification physique.
