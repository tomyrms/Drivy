# Dossier de formation : lecture et création

Les maquettes `04_dossier_light`, `14_mes_lecons_light` et `16_parcours_light` ont été inspectées. Cette passe suit les parcours de lecture des leçons, bilans partagés et appréciations, sans modifier les API ni les workspaces.

Les listes emploient des séparateurs et des intitulés directs. Les onglets deviennent un sélecteur natif, remplacé par un menu aux tailles de texte d’accessibilité. Les appréciations gardent date et contexte ; les compétences non observées restent nommées comme telles, sans note ni score. Leurs descriptions se déplient.

Les bilans publiés utilisent les mêmes intitulés que la relecture du rédacteur : Travail réalisé, À retenir, Prochaine étape. Le texte reste sélectionnable, dans une largeur de lecture bornée sur iPad. La publication actuelle est repérée par `currentPublishedRevisionId`, et non par la position supposée du premier résultat.

La création affiche catégorie, référence, durée et prix réels dès la sélection d’une offre. La validation reste au workspace. Le booléen de retour de `create()` est maintenant respecté : une erreur garde la relecture ouverte ; une demande en attente se vérifie ou se renvoie au même endroit. Le succès reste une confirmation textuelle, sans mise en scène décorative.

## Vérification et point de parcours

Relecture ciblée et `git diff --check` effectués. Les trois vues sont destinées à la prochaine compilation Apple groupée ; aucune capture ou exécution sur appareil n’est revendiquée ici.

Signalement traité avec l’intégration : l’accès aux bilans et au suivi dépendait de `progress != nil`, donc une panne de AP58 masquait des parcours AP55/56. L’intégration ajoute `canOpenPedagogicalContent`, fondé sur rôle, formation chargée sous les droits courants et absence de révocation/invalidation/chargement. Les deux gardes de présentation utilisent cette propriété ; chaque destination garde ses vérifications serveur. Le parcours lui-même exige toujours son résultat AP58 pour afficher des appréciations.
