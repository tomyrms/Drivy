# Web — deuxième passe de composition

Le porteur apprécie la direction visuelle livrée, mais signale encore des espaces inutiles et des informations peu visibles. Cette passe porte sur les dispositions de tous les écrans web. La palette, la police et l’identité native restent conservées.

## Constats et choix

| Emplacement | Problème observé | Correction recherchée |
|---|---|---|
| Navigation et en-têtes | Fil d’Ariane, onglets, titre et barre de filtres cumulent des étages avant les données. | Garder le fil pour les véritables sous-pages, rapprocher les groupes, préserver les cibles interactives. |
| Listes et détails | À 1200 px, le détail remplace encore une liste qui pourrait rester visible ; sans sélection, le panneau vide réserve de la place. | Adapter les deux colonnes à leur conteneur et rendre la largeur à la liste sans sélection. |
| Élèves, équipe, invitations | Les seules cellules de nom sont cliquables, les métadonnées s’étirent loin de l’identité. | Une ligne de sélection entière, hiérarchie identité/métadonnées, repère explicite du détail. |
| Disponibilités | Un sélecteur pleine largeur puis deux grands panneaux empilés repoussent les absences. | Sélecteur près du titre et zones horaires/absences côte à côte quand elles tiennent. |
| Dossier sur téléphone | L’imbrication des cadres et marges réduit fortement la largeur du bilan et des compétences. | Aplatir les contenants secondaires tout en conservant leurs titres et leur ordre. |
| Catalogue et réglages | Des cartes imbriquées et des champs techniques prennent le pas sur les données métier. | Sections alignées, prix/durée avant références, présentation compacte des règles fixes. |
| Connexion et invitation reçue | Plusieurs titres et une grande icône répètent une seule action ; les faits d’invitation occupent trois grandes rangées. | Une seule entrée, identité regroupée, faits lisibles et notices conservées intégralement. |

## Guides et coordination

Trois agents se partagent les dispositions communes, les parcours planning/dossiers/équipe et les parcours catalogue/réglages. L’intégration principale traite l’entrée, les cas de textes longs et la revue navigateur.

`ui-skills-root` et le catalogue `craft` orientent le choix. `better-layout` et ses références de regroupement/adaptation guident les compositions ; `refactoring-ui` la hiérarchie et la densité ; `better-writing` la suppression des répétitions ; `better-accessibility` les cibles, libellés, repli et focus. `baseline-ui` sert à contrôler les effets décoratifs et la cohérence avec les primitives existantes. Les agents complètent avec `better-ui` et `better-typography`. Le système CSS existant prime sur les recettes imposant un nouveau framework. Les guides de suppression de tics rédactionnels ne sont pas présentés comme une qualification visuelle.

La compacité ne modifie ni les droits, ni les confirmations, ni les états de demande incertaine. Aucun contenu de notice, prix, état critique ou capacité n’est supprimé pour gagner de la place.

## Vérification et livraison

- TypeScript client/serveur, compilation et **104 tests web** réussis sur le lot final. L’avertissement Vite sur le bloc JavaScript de 508,42 kB reste présent, sans échec de construction.
- **18 destinations** inspectées en navigateur à 1200 et 390 px : entrée, compte, invitation reçue, agenda, élèves, équipe, disponibilités, trajets, invitations, formations, compétences, procédures, offres, tarifs, conditions, école, informations des élèves et préparation.
- Les mêmes destinations sont contrôlées à 320 px avec des noms et libellés longs ; aucun débordement de page ou de conteneur détecté après correction. Un jeu de vingt dossiers vérifie aussi la liste longue. Les variantes de détail et de formulaire sont inspectées sur tablette 834 px en sombre et sur ordinateur.
- Filtres mois/année et bilan, retours vers la même ligne élève/membre/invitation, retour à la semaine courante, menu au clavier, erreur de prix et confirmation de coordonnées sont exercés. Le dialogue boucle aux bornes Tab/Shift+Tab et restitue le focus à la fermeture. Les cibles des jours restent supérieures à 44 px dans le formulaire étroit.
- La revue a conduit à trois corrections complémentaires : identité d’invitation décomprimée sur mobile, faits des coordonnées en deux colonnes et trajets regroupés en deux colonnes avec durée indivisible. Les filtres élèves restent sur une même ligne lorsqu’ils disposent de 300 px utiles.

La [preuve de revue](proofs/web-layout-pass2-20260930.json) indexe 65 captures, 58 relevés et les empreintes des 17 fichiers de source. La revue indépendante des sources n’a trouvé aucune régression concrète des droits, confirmations ou données conservées. Les constats spécialisés figurent dans les revues [parcours quotidiens](web-layout-field-review-20260930.md) et [catalogue/réglages](web-layout-catalog-review-20260930.md).

Le banc utilise des réponses synthétiques : il ne qualifie ni une écriture durable ni une vraie session authentifiée. Le zoom à 200 %, les lecteurs d’écran, Safari et les appareils physiques restent non vérifiés. Le client natif et les essais GPS/batterie sont hors de cette passe.

Le lot `e30e4ea` est déployé sur le homelab après une nouvelle sauvegarde PostgreSQL vérifiée. Les trois services sont actifs, leurs chemins d’exécution correspondent à la release et les migrations 001–021 restent conformes. Les fichiers JavaScript, CSS et la police servis en HTTPS sont identiques au build local testé. La [CI sur ce commit](https://github.com/tomyrms/Drivy/actions/runs/36737761024) réussit avec **224 tests API et 104 tests web**. [Preuve de déploiement](proofs/deployment-web-layout-pass2-20260930.json).
