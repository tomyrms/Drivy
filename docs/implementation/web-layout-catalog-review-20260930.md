# Deuxième passe web — catalogue et réglages

La direction « encre et papier » est conservée. Cette passe réduit les niveaux de conteneurs, rapproche les informations liées et réserve les contrôles aux choix réellement modifiables. Elle ne change ni les commandes métier, ni l’API, ni l’app native.

## Références relues

- `COMMENCER_ICI.md`, règles R73–R77, contrat AP165–AP171 et précisions de versionnement ; scénarios T233–T235 et T241.
- UI Skills : `ui-skills-root` et catalogue `craft`, `better-layout` avec ses guides de regroupement et d’adaptation, `better-writing`, `better-typography`, `better-accessibility`, `refactoring-ui`.
- Le choix de plusieurs guides répond à la demande explicite du porteur. Les règles utiles sont appliquées au système existant ; aucune nouvelle palette, police ou collection de composants n’est introduite.

## Constats et changements

| Gravité | Emplacement | Avant | Après | Principe et effet |
| --- | --- | --- | --- | --- |
| Moyenne | `apps/web/client/console/configuration.tsx` | Trois grandes cartes, dont deux imbriquent des panneaux de détail ; beaucoup de marge avant la section suivante sur téléphone. | Sections alignées avec une zone d’intitulé et une zone de contenu. Suppression des cartes imbriquées et du pied d’actions vide d’une école déjà préparée. | Regroupement par proximité ; les coordonnées et les textes se repèrent sans accumuler les bordures. |
| Moyenne | `apps/web/client/console/formations.tsx` | Chaque permis consomme une rangée de titre et d’action avant ses deux colonnes. | Composition catégorie / enseignement / tarifs à largeur suffisante ; empilement resserré sur téléphone. Les autres prestations gardent leur disposition propre. | Hiérarchie par alignement, largeur adaptée au contenu plutôt qu’espace rempli par défaut. |
| Moyenne | `apps/web/client/console/profile-fields.tsx` | Tableau de règles à quatre colonnes et trois sélecteurs désactivés pour chaque nom et prénom. | Tableau à deux colonnes : information, finalité et explication / exigence et moment. Les règles fixes se lisent en texte ; seuls les choix possibles restent des contrôles. | Distinguer information et action ; garder une lecture utilisable dans un panneau étroit. |
| Moyenne | `apps/web/client/console/overview.tsx` | Titre, état et gros bouton de navigation répétés sur trois lignes pour chaque étape mobile. | Une rangée entière est un lien natif, avec titre, état et flèche. L’état courant « école active » n’est plus un badge supplémentaire. | Une destination, un contrôle ; cible large sans trois niveaux de chrome. |
| Moyenne | `apps/web/client/console/catalog.tsx` | Trois boutons de destination, puis les mêmes références dans une liste de faits. | Trois liens en rangées regroupant destination et version exacte, après la durée. | Une information à un seul endroit ; le lien conserve la version sélectionnée. |
| Faible | `apps/web/client/console/commerce.tsx` | Référence technique en premier, prix plus bas ; conditions répétées en fait et en bouton. | Libellé et prix en premier, référence secondaire ; le nom de la version des conditions devient directement le lien. | Ordre de lecture métier, suppression d’un contrôle redondant. |
| Faible | `catalog.tsx`, `commerce.tsx`, `configuration.tsx` | Grandes zones de texte vides et explications permanentes déjà présentes dans la relecture. | Hauteur initiale des textes réduite, contenu et limites inchangés ; explications de confirmation conservées dans les dialogues. | Divulgation progressive, pas de perte d’information ni d’acceptation implicite. |

## Garde-fous conservés

Les liens possèdent un `href` et conservent l’ouverture avec modificateur ou dans un autre onglet. Les titres, légendes et libellés de champs restent explicites. La photo reste facultative, les noms restent requis, et la finalité ainsi que l’explication de chaque information restent affichées. Les confirmations, motifs, dates d’effet, versions précédentes, états désactivés, droits et écritures durables restent inchangés.

Le CSS de ces compositions est coordonné avec la passe globale dans `styles.css`, afin de conserver les cibles tactiles et un seul système d’espacement. Les composants partagés de liste, détail et formulaire assurent aussi la densité des référentiels et conditions commerciales.

## Vérification de ce lot

- Sources et captures de la première passe inspectées : formations, référentiels, procédures, offres, tarifs, conditions, configuration, informations des élèves et préparation.
- `npm run typecheck` réussi le 30 septembre 2026 après les modifications.
- `git diff --check` sans erreur de contenu ; Git signale seulement la normalisation habituelle CRLF → LF.
- La revue navigateur après intégration du CSS, les mesures de reflow, les scénarios de sélection/retour, les grands libellés, le clavier et les tests consolidés sont réalisés par l’agent principal et consignés dans le suivi de la deuxième passe. Ce document ne les déclare pas exécutés à sa place.
- Lecteur d’écran et matériel physique : non vérifiés par ce lot.

Conclusion de revue des sources et captures examinées : **Approve** pour les changements listés, sous réserve de la revue navigateur intégrée. Aucun verdict global d’accessibilité n’est déduit de cette revue.
