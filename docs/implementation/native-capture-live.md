# Séance scolaire : carte et commandes GPS

`SchoolCaptureLiveView(controller:learnerName:closeSaved:returnToLesson:)` présente le `SchoolCaptureSessionController` détenu par l’application. L’écran ne crée ni source, ni autorisation, ni segment. Son ouverture ou sa fermeture ne change pas l’état du GPS ; la racine garde le contrôleur vivant. Le callback facultatif `returnToLesson` permet de quitter la vue lorsqu’elle est directement dans l’onglet Séance ; sinon la vue utilise le retour natif. Le callback facultatif `closeSaved` reste un raccord réservé à la racine, sans effacement implicite du contrôleur. L’intégration courante le laisse vide pour conserver l’accès au trajet et à son envoi après un retour à l’Agenda.

Références : E23, GPS/replay, R111 et AS03–AS07 de la conception 3.17. Le collecteur, le journal, les droits et les commandes réseau appartiennent aux modules déjà documentés ; cette vue ne les remplace pas.

## Ce que présente la vue

- Carte MapKit des seules `measurements` fournies après écriture confirmée. Chaque segment reste une polyligne distincte ; une pause ne crée pas une liaison artificielle. Un segment d’un seul point reste visible. Le dernier repère est nommé « Dernière position enregistrée », sans prétendre être une mesure en direct.
- Élève, état textuel du GPS, temps écoulé depuis le départ et nombre de positions. Le temps inclut les pauses : ce n’est pas un compteur de durée de collecte ni une attestation de durée de leçon. Avant le premier point, l’attente est explicite et aucune position n’est créée.
- Pause et reprise liées à `canPause` / `canResume`. Arrêt confirmé séparément, toujours nommé « Arrêter le GPS » : il ne termine pas la leçon. Le refus de reprise explique que la leçon peut continuer sans GPS. Un échec de sauvegarde conserve son erreur et propose uniquement la vraie commande `retrySaving`.
- Après sauvegarde, envoi explicite des positions puis vérification du trajet complet via AP158. `allowPartial: true` n’est appelé qu’après sa propre confirmation. L’écran n’annonce ni synchronisation ni publication avant réponse ; les résultats s’appuient sur `finalizedSyncState`, pas sur l’interprétation d’un texte. Les actions de finalisation disparaissent une fois le résultat reçu.

Les intentions de confirmation portent l’identifiant de la capture affichée. Chaque tâche vérifie encore cet identifiant avant d’appeler le contrôleur ; un changement de contexte ne réemploie pas un clic pour un autre trajet. Un retour à l’état inactif montre une entrée vide sans ancien nom ni tracé. Fermer pendant un échange réseau est désactivé ; aucune nouvelle commande n’est créée pour faire disparaître une erreur.

## Composition et limites

Sur iPhone : carte, bandeau compact et panneau de commandes. Sur largeur iPad : panneau défilant à gauche, carte à droite. Au texte d’accessibilité, la carte et les informations défilent séparément des commandes ; leur zone est bornée pour garder les actions atteignables. Les textes utilisent les tailles système et les commandes ont une cible d’au moins 44 points. La vue n’ajoute pas d’annonce continue des positions au lecteur d’écran.

Le bouton Signaler n’est pas affiché : le raccord scolaire AP161–AP164 est une tranche distincte, et le stockage des observations personnelles n’est pas réutilisé comme substitut. Aucun bouton fictif ni publication implicite. La carte vide utilise seulement une vue géographique générale, sans annotation de localisation.

Contrôle de diff effectué. Compilation Apple groupée, rendu iPhone/iPad de ce nouvel écran, GPS physique, interruptions système et VoiceOver restent à exécuter ; aucun résultat de ces vérifications n’est déduit du code ou des captures des trajets personnels.
