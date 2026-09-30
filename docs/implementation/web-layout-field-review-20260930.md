# Disposition des parcours web — deuxième passe du 30 septembre 2026

Périmètre : Agenda, Élèves, Équipe, Invitations, Disponibilités et Trajets. L’identité visuelle web livrée est conservée. Aucun changement natif, API, autorisation serveur ou contrat. Les styles restent sous la responsabilité de l’agent chargé du système visuel.

## Éléments examinés

Lecture des sources et des captures antérieures sous `artifacts/retours-20260930/web-craft/` : agenda desktop/mobile, élèves desktop/mobile, équipe desktop/mobile, invitations desktop/mobile, disponibilités desktop/mobile, trajets desktop/mobile et dossier/bilan mobile. Ces captures montrent l’état avant cette deuxième passe ; elles ne qualifient pas son résultat.

Guides relus : UI Skills root, `better-layout`, `better-writing`, `better-accessibility`. Catégorie interaction du registre inspectée. Application : rapprocher identité et informations utiles ; limiter les contrôles sans effet ; préserver les cibles de 44 px, la sémantique native et les retours de focus. Aucun fichier sous `.claude` modifié.

## Changements

| Gravité | Écran | Problème observé | Réorganisation |
|---|---|---|---|
| Moyenne | Élèves et Équipe | Deux colonnes dispersées sur desktop ; seul le nom est une cible alors que la ligne représente une personne. | Annuaire sémantique `ul/li`, une ligne native `button` par personne. Identité, rôle/formation et statut restent lisibles dans la même ligne. Le composant `DirectoryRow` est partagé. |
| Moyenne | Invitations | Identité, statut et expiration se compriment dans trois colonnes sur téléphone. | Identité et date d’expiration groupées ; statut distinct dans la même ligne sélectionnable. Les rôles du personnel restent affichés. Le code émis, sa copie et les commandes de renouvellement/révocation sont conservés. |
| Moyenne | Disponibilités | Sélecteur étiré sur toute la page et blocs hebdomadaires/absences empilés malgré la largeur disponible. | Barre de contexte compacte, accès au planning du moniteur et grille de deux zones lorsque le conteneur le permet. Le formulaire et les validations restent propres à chaque zone. |
| Moyenne | Trajets | Quatre colonnes trop étroites sur téléphone ; noms et départ se coupent de façon peu lisible. | Deux colonnes après le contrôle à 320 px : élève avec moniteur en information secondaire ; départ et durée regroupés. Le fuseau historique du trajet est conservé. |
| Basse | Agenda | Le bouton Aujourd’hui désactivé occupe une ligne tactile entière dans la semaine courante ; le jour et la date ont la même hiérarchie. | Retour Aujourd’hui uniquement après navigation, avec focus replacé sur la semaine affichée. Jour/date distingués. Navigation de semaine, filtres et liens vers le dossier inchangés. |
| Basse | Détail élève et membre | Les liens de consultation occupent des boutons pleine largeur aussi visibles que les opérations de gestion. | Groupe compact de liens de consultation, sans réduire leur cible tactile ni modifier leurs destinations. |

## Invariants conservés

- `aria-current="true"` reste porté par la ligne sélectionnée : le retour de `SplitView` retrouve la même cible et restitue le focus.
- Aucun bouton n’est imbriqué dans un autre ; les informations de la ligne font partie de son nom accessible. Les flèches décoratives sont masquées aux aides techniques.
- États inhabituels, erreurs, motifs, relectures et confirmations légales restent disponibles.
- Les identifiants, `routeQuery`, brouillons, commandes et liens de retour ne sont pas réécrits.
- L’absence d’une formation n’est plus représentée par un tiret ambigu ; elle est libellée « Sans formation en cours ».

## Vérification

- TypeScript client/serveur : réussi après les modifications.
- Vérification des espaces de fin de ligne : réussie sur les fichiers du lot.
- Inspection de l’ordre du DOM et des sélecteurs de retour de focus : effectuée.
- Nouveaux rendus navigateur, clavier, 200 % de zoom et lecture vocale : **non vérifiés par cet agent**. Root réalise la recette intégrée après application des styles partagés.

Pas de nouveau test métier pour cette réorganisation : les appels et règles restent identiques. Les tests existants et la construction globale sont exécutés lors de l’intégration.
