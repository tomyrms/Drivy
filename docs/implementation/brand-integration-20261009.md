# Intégration de La trace — 9 octobre 2026

Le porteur a demandé de reprendre le chantier Claude et de le poursuivre en corrigeant les points restants. Cette passe part de la proposition du 6 octobre (`3353900`) et conserve le kit, la palette et la navigation existante.

## Réalisation

- **Primitives Apple** : `DrivyTraceLine`, `DrivyMarker`, `DrivyThreadItem`, parcours de compétence à trois stations et quatre états. Le rail est décoratif ; niveaux, statuts et actions gardent leur texte. Les stations suivent la première ligne réelle du contenu, sans hauteur de rangée imposée.
- **Agenda / Aujourd’hui** : fil chronologique dans les listes de la journée, état courant en cobalt, parcours passé à l’encre, suite en rail gris. Les leçons annulées conservent leur texte et leurs horaires barrés.
- **Progression / bilan** : dernière leçon et prochaine étape reliées ; compétences non vues distinctes des niveaux évalués ; observations avec anneau et glyphe sémantiques, actions et restrictions de visibilité conservées.
- **Cartographie** : fond atténué, mêmes traits et repères en live, replay et aperçu. Aucun raccord n’est déduit des seuls points décimés : un véhicule arrêté peut ne produire aucun nouveau point affiché sans que le GPS soit perdu. Les pauses et les fragments ne deviennent pas des trajets inventés.
- **Marque** : symbole transparent dans l’app et le web, AppIcon dédiée dans ses trois variantes, favicon/manifest web et cobalt commun. Les éléments historiques de la proposition restent consultables dans le dossier de marque.

## Périmètre des données

Les DTO de liste des leçons ne contiennent aucune polyligne autorisée. Les vignettes de trajet ne sont donc pas simulées ni téléchargées en ouvrant toutes les captures en arrière-plan. Cette partie demande un contrat serveur séparé avec les mêmes droits et règles de retrait que le trajet ; elle reste à réaliser.

Aucune migration, commande métier ou modification de droits n’est introduite. Le dossier de conception canonique reste intact. Aucun service du homelab n’est déployé par cette passe.

## Vérification

La compilation et la recette Apple sont exécutées via les workflows existants. Les résultats et liens de preuve sont consignés dans `STATUS.md` après leur retour. Les captures de revue emploient exclusivement les jeux fictifs du simulateur.

À qualifier sur appareil : carte réelle en plein soleil, VoiceOver, Dynamic Type, animation avec Réduire les animations, variantes de l’icône et rendu iOS. La géométrie et l’apparence simulées ne constituent pas un essai physique.
