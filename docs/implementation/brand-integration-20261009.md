# Intégration de La trace — 9 octobre 2026

Le porteur a demandé de reprendre le chantier Claude et de le poursuivre en corrigeant les points restants. Cette passe part de la proposition du 6 octobre (`3353900`) et conserve le kit, la palette et la navigation existante.

## Réalisation

- **Primitives Apple** : `DrivyTraceLine`, `DrivyMarker`, `DrivyThreadItem`, parcours de compétence à trois stations et quatre états. Le rail est décoratif ; niveaux, statuts et actions gardent leur texte. Les stations suivent la première ligne réelle du contenu, sans hauteur de rangée imposée.
- **Agenda / Aujourd’hui** : fil chronologique dans les listes de la journée, état courant en cobalt, parcours passé à l’encre, suite en rail gris. Les leçons annulées conservent leur texte et leurs horaires barrés.
- **Progression / bilan** : dernière leçon et prochaine étape reliées ; compétences non vues distinctes des niveaux évalués ; observations avec anneau et glyphe sémantiques, actions et restrictions de visibilité conservées.
- **Cartographie** : fond atténué, mêmes traits et repères en live, replay et aperçu. Aucun raccord n’est déduit des seuls points décimés : un véhicule arrêté peut ne produire aucun nouveau point affiché sans que le GPS soit perdu. Les pauses et les fragments ne deviennent pas des trajets inventés.
- **Marque** : symbole transparent dans l’app et le web, AppIcon dédiée dans ses trois variantes, favicon/manifest web et cobalt commun. Les éléments historiques de la proposition restent consultables dans le dossier de marque.

La relecture a corrigé quatre détails d’intégration : le rail couvre aussi la hauteur minimale des lignes courtes, ses statuts ordinaires ont une valeur accessible, un élément unique termine le fil et sélectionner une observation passée ne transforme pas son segment suivant en « à venir ». Le manifeste web est explicitement autorisé depuis la même origine par la CSP.

## Périmètre des données

Les DTO de liste des leçons ne contiennent aucune polyligne autorisée. Les vignettes de trajet ne sont donc pas simulées ni téléchargées en ouvrant toutes les captures en arrière-plan. Cette partie demande un contrat serveur séparé avec les mêmes droits et règles de retrait que le trajet ; elle reste à réaliser.

Aucune migration, commande métier ou modification de droits n’est introduite. Le dossier de conception canonique reste intact. Aucun service du homelab n’est déployé par cette passe.

## Vérification

La compilation et la recette Apple sont exécutées via les workflows existants. Les résultats et liens de preuve sont consignés dans [STATUS](STATUS.md). Les captures de revue emploient exclusivement les jeux fictifs du simulateur.

- API/PostgreSQL : **238 tests** ; web : **104 tests**, types et build réussis sur `aecdac1` puis `bb75ae5`.
- Tests natifs et parcours iPhone/iPad : étape réussie sur `aecdac1` dans la [campagne Apple](https://github.com/tomyrms/Drivy/actions/runs/37857755974). La suite complète précède les deux corrections de rendu de `bb75ae5` ; la version finale a ensuite été compilée en Release et simulateur et capturée, sans répéter les tests métier.
- Web : quatre captures inspectées (agenda bureau et connexion 320 px, clair/sombre) ; **52 couples de contraste** passent les seuils mesurés, voir [la preuve](proofs/brand-web-contrast-20261009.json).
- IPA finale : **0.7.0, build 120**, source `bb75ae5`, [compilation Release](https://github.com/tomyrms/Drivy/actions/runs/37858824190) réussie. Archive téléchargée et SHA-256 confirmé : `f1d4309a8fe19f49a2de85c3f38c9b6f9e4c897c0316ecaad6c184a669408f3f`. Paquet non signé, pour signature locale avec iLoader.
- Grands caractères : **28 captures** de `aecdac1`, sur iPhone 17 Pro et iPad Pro 13 pouces (M5), clair/sombre, taille système `accessibility-extra-large` confirmée par `simctl`. [Campagne réussie](https://github.com/tomyrms/Drivy/actions/runs/37857758496), toutes les images ouvertes pour inspection. Les blocs métier entièrement visibles ne débordent pas horizontalement ; les fils visibles de l’agenda et de la progression suivent les retours à la ligne. Ces images précèdent les deux ajustements de trait de `bb75ae5` et ne montrent ni le singleton ni l’observation sélectionnée.
- Taille normale : **28 captures** de `bb75ae5`, mêmes appareils/thèmes, taille système `large` confirmée. [Campagne réussie](https://github.com/tomyrms/Drivy/actions/runs/37858834138), toutes ouvertes pour inspection. Symbole transparent clair/sombre, quatre états de compétence, rails et adaptation des colonnes visibles. [Manifeste des 56 images et limites](proofs/brand-native-visual-20261009.json) ; [six captures originales conservées](assets/brand-integration-20261009).

### Limites des captures

La revue concerne les zones visibles, sans défilement ni interactions. En grands caractères, les cartes et observations de la fiche de leçon, certaines compétences et une partie des leçons de l’agenda sont sous le viewport. Le logo de connexion est masqué par sa composition à cette taille ; son dessin a été vérifié à taille normale. La galerie de développement conserve des colonnes de couleurs trop étroites pour certains noms techniques sur iPad, surtout à la taille AX (mots fortement fragmentés) ; cette section existante n’est pas un écran métier.

Le live iPad montre le départ annelé, la position et le trait sur MapKit. Le replay de démonstration commence aux coordonnées synthétiques `(0, 0)` ; dans les captures, ses annotations de départ et de position à `t = 0` ne sont pas visibles bien que la donnée et les annotations soient présentes dans le code. La cause du rendu n’est pas établie, ce détail n’est donc pas qualifié. La fin du trajet et les lacunes cartographiques sont hors cadrage initial ; les tests logiques des lacunes sont distincts de leur inspection visuelle.

À qualifier sur appareil : carte réelle en plein soleil, VoiceOver, Dynamic Type, animation avec Réduire les animations, variantes de l’icône et rendu iOS. La géométrie et l’apparence simulées ne constituent pas un essai physique.
