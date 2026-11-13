# R08 — Préférences de signalements liées au profil

**Cadrage validé le 11 novembre 2026.**  
**Suivi : [epic #465 — Signalements : préférences du compte et visibilité pilotée par l’école](https://github.com/tomyrms/Drivy/issues/465).**

Les décisions détaillées, les cinq tâches et leurs dépendances sont suivies dans l’epic. Ce document conserve le périmètre produit ; les tickets créés ne constituent pas une livraison.

## Intention

Chaque moniteur et administrateur retrouve avec son compte Drivy son ordre manuel, son choix d’activer ou non le classement intelligent et les habitudes apprises, sur le web, iPhone et iPad, et entre ses auto-écoles.

La visibilité combine une règle de l’école et la préférence du compte. L’administrateur décide si l’école impose les thèmes affichés ou autorise les moniteurs à les personnaliser. Même lorsque la visibilité est imposée, le moniteur conserve le choix de son ordre et de son algorithme.

## Décisions du porteur

| Sujet | Décision |
| --- | --- |
| Réglages personnels natifs | Profil → Paramètres → Signalements. |
| Réglages personnels web | Mon compte → Préférences → Signalements. |
| Utilisateurs | Moniteurs et administrateurs, pour leur propre compte ; pas de réglage d’un collègue ni d’écran chez un élève seul. |
| Politique scolaire | Option ADMIN autorisant ou interdisant la personnalisation de la visibilité. |
| Ordre manuel | Personnel et commun aux écoles, toujours modifiable par son propriétaire. |
| Classement intelligent | Activation, apprentissage et classement par compte ; le choix d’une personne ne s’impose pas aux autres. |
| Premier usage | Références proposées par l’école ; modification de visibilité selon sa politique. |
| Réinitialisation de présentation | Rétablir ensemble ordre et visibilité ; ADMIN, ou moniteur si la personnalisation est autorisée. |
| Réinitialisation d’apprentissage | Action séparée et discrète « Recommencer l’apprentissage du classement intelligent ». |

Un réglage de l’école reste nécessaire pour sa politique et ses références. Il est distinct de la page personnelle. La formulation de l’option doit éviter une double négation : « Autoriser les moniteurs à personnaliser les signalements » activée signifie que le choix personnel de visibilité est autorisé.

## Priorité des configurations

La palette affiche l’ordre personnel manuel ou intelligent, filtré par la visibilité effective :

- en mode imposé, utiliser la visibilité de l’école ;
- en mode libre, utiliser celle du compte, initialisée depuis l’école si elle n’existe pas.

Une école qui masque un thème ne l’efface pas des préférences ni de l’apprentissage du compte. Le passage imposé → libre restaure les choix personnels conservés. Les références de l’école n’écrasent pas les comptes déjà personnalisés.

## Reprise et réinitialisations

Les règles de transition détaillées dans l’epic préservent les configurations scolaires existantes et démarrent ces écoles en mode imposé. Une configuration héritée unique ou identique se reprend automatiquement ; plusieurs configurations divergentes donnent lieu à un choix unique de reprise lors de la personnalisation, jamais au milieu d’une leçon. Un nouveau compte reste en manuel tant qu’il n’active pas le classement intelligent.

Une réinitialisation personnelle reprend l’ordre et la visibilité de référence de l’école ouverte. Une réinitialisation scolaire ADMIN, dans l’éditeur de l’école, remet les références de cette école aux valeurs Drivy d’origine. Les deux portées doivent être claires ; elles ne réinitialisent pas l’apprentissage d’un compte.

« Recommencer l’apprentissage » reste personnel, y compris lorsque l’école impose la visibilité. L’action repart de l’ordre manuel et exclut réellement l’ancien historique des prochains calculs, sans supprimer observations, trajets, bilans ou compétences et sans changer l’activation de l’algorithme.

## Réalisation et limites

- Synchronisation cohérente entre web, iPhone et iPad ; caches isolés par compte et politique scolaire.
- Dernier état confirmé disponible hors ligne et ordre stable pendant une leçon.
- Autorisations vérifiées côté serveur ; une ancienne app ou un ancien droit de gestion scolaire ne doit pas contourner la politique.
- Catalogue métier et droits de saisie/lecture des observations conservés. Les préférences globales n’ouvrent pas un accès aux données d’une autre école.
- Interface sobre, composants existants, action d’apprentissage dans un menu secondaire ou une petite ligne avec confirmation courte.
- Coordination avec [#455](https://github.com/tomyrms/Drivy/issues/455) pour distinguer droits commerciaux, politique scolaire et préférences personnelles ; le lancement de la facturation n’est pas une dépendance de R08.

Voir l’[epic #465](https://github.com/tomyrms/Drivy/issues/465) pour les critères d’acceptation, l’ordre de réalisation et le suivi. Le développement, la qualification et le déploiement sont des étapes distinctes de ce cadrage.
