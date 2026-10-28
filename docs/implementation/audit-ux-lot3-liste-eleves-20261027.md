# Lot 3 de l'audit UX : liste des élèves (#151, #152, #153)

27 octobre 2026, branche `claude/audit-ux-lots-2-4`, après le lot 2. Code iOS seulement. Le filtre utilise le paramètre `requiresAction=true` que `GET /v1/schools/{id}/learners` accepte déjà : aucun contrat, aucune migration, rien à déployer.

## Ce qui change

| Ticket | Avant | Après |
|---|---|---|
| #151 A22 | Initiales seulement dans la liste, photo dans le dossier. | Même photo que le dossier, lue par l'identifiant de la personne quand la ligne paraît (`GET /v1/people/{id}/photo`, droits du serveur inchangés). Initiales tant qu'elle manque, même hauteur de ligne. Une lecture à la fois par personne ; une réponse arrivée après un changement d'école est ignorée ; le cache des photos est vidé au changement d'école. |
| #152 A23 | Deux élèves du même nom indiscernables. | Seulement quand un homonyme est affiché : « Réf. A1B2 » sous le nom, la fin de l'identifiant (`HomonymReference`, même règle que la planification et le web). Aucune donnée personnelle ajoutée ; la navigation reste par identifiant. |
| #153 A24 | Badge « Profil à compléter » sans moyen de filtrer. | Menu de filtre de la barre : « Tous les élèves » ou « Profil à compléter ». Filtre du serveur, combiné à la recherche et à la pagination ; bandeau « Profil à compléter · Tout afficher » en tête ; « Aucun profil à compléter » quand il n'y en a pas. Le nombre n'est affiché que pour l'administration, qui lit les dossiers à compléter de toute l'école. Le filtre se retire au changement d'école et reste au retour du dossier. |

## Limites connues

- Une photo remplacée sur un autre appareil n'apparaît qu'au prochain changement d'école ou lancement : la liste ne connaît pas la version de la photo (comme le dossier aujourd'hui).
- Un dossier complété reste dans la liste filtrée jusqu'à la relecture suivante ; son badge disparaît aussitôt.

## Vérification

- Compilation par l'IPA d'essai ; aucun test lancé avant l'essai du porteur. La cible de tests compile avec l'implémentation par défaut de `incompleteLearners` (filtre sur place) pour les faux clients.
- À vérifier à l'œil : photos dans la liste et le dossier, deux homonymes, filtre avec et sans recherche, iPhone et iPad, VoiceOver.
