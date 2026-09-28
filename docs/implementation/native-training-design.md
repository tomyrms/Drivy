# Dossier de formation : lecture et création

Les maquettes `04_dossier_light`, `14_mes_lecons_light` et `16_parcours_light` ont été inspectées. Cette passe suit les parcours de lecture des leçons, bilans partagés et appréciations, sans modifier les API ni les workspaces.

Les listes emploient des séparateurs et des intitulés directs. Les onglets deviennent un sélecteur natif, remplacé par un menu aux tailles de texte d’accessibilité. Les appréciations gardent date et contexte ; les compétences non observées restent nommées comme telles, sans note ni score. Leurs descriptions se déplient.

Les bilans publiés utilisent les mêmes intitulés que la relecture du rédacteur : Travail réalisé, À retenir, Prochaine étape. Le texte reste sélectionnable, dans une largeur de lecture bornée sur iPad. La publication actuelle est repérée par `currentPublishedRevisionId`, et non par la position supposée du premier résultat.

La création affiche catégorie, référence, durée et prix réels dès la sélection d’une offre. La validation reste au workspace. Le booléen de retour de `create()` est maintenant respecté : une erreur garde la relecture ouverte ; une demande en attente se vérifie ou se renvoie au même endroit. Le succès reste une confirmation textuelle, sans mise en scène décorative.

## Vérification et point de parcours

Relecture ciblée et `git diff --check` effectués. Les trois vues sont destinées à la prochaine compilation Apple groupée ; aucune capture ou exécution sur appareil n’est revendiquée ici.

Signalement traité avec l’intégration : l’accès aux bilans et au suivi dépendait de `progress != nil`, donc une panne de AP58 masquait des parcours AP55/56. L’intégration ajoute `canOpenPedagogicalContent`, fondé sur rôle, formation chargée sous les droits courants et absence de révocation/invalidation/chargement. Les deux gardes de présentation utilisent cette propriété ; chaque destination garde ses vérifications serveur. Le parcours lui-même exige toujours son résultat AP58 pour afficher des appréciations.

La revue métier suivante distingue aussi la liste de leçons effectivement chargée (`lessonsLoaded`) et l’erreur de lecture des révisions (`revisionsError`). Le dossier n’annonce une liste vide qu’après une lecture réussie. Une erreur de bilans se présente dans cette section ; son actualisation conserve le dialogue existant protégeant une saisie non enregistrée.

## Rendu natif ciblé

`JourneyVisualReview` accepte les entrées `catalog`, `dossier` et `bilan`, qui instancient les vraies vues natives du catalogue, de la formation et d’une révision publiée. `SchoolVisualReview` est compilé uniquement en DEBUG sur simulateur, avec la mention visible « Rendu de contrôle · données fictives ».

Les trois captures iPad claires du run `36057849015`, source `e60e7d9`, ont été ouvertes et inspectées. Rendez-vous/historique, texte du bilan et appréciation sont lisibles dans leur colonne ; le catalogue présente correctement ses deux offres et leurs états. Le bandeau de contrôle recouvre toutefois une partie des barres de navigation : cette limite interdit de qualifier leur rendu à partir de ces images. Le bandeau est déplacé dans l’inset inférieur pour la prochaine revue. Ce correctif n’a pas encore été recapturé. Ni mode sombre ni taille d’accessibilité ne sont prouvés par ces trois images.

Les clients habituels reçoivent un transport en mémoire limité aux GET explicitement définis sur `visual.drivy.invalid`. Aucun transport réseau n’est créé et une route inconnue échoue. La file de commandes de cette fixture refuse l’écriture ; elle n’utilise ni les données scolaires locales ni le service hébergé. Les identités, conditions tarifaires et textes du bilan sont synthétiques.

`DRIVY_VISUAL_LARGE_TEXT=1` permet de rendre ces mêmes vues à la taille d’accessibilité 3. Le workflow et son déclenchement restent sous la responsabilité de l’intégration. La préparation du harness ne vaut pas une preuve de rendu : les images devront être inspectées après l’exécution Apple.
