# Cohérence de l’application : recherche visuelle et décisions de composition

> Recherche du 20 septembre 2026. Référence de fabrication : V3.17. Les sources publiques ne démontrent pas l’efficacité de Drivy. Pas d’applications installées ni de mesure sur iPhone.

## Mandat

Étendre la direction appréciée en V3.15 puis affinée en V3.16 aux parcours hors carte. La demande du porteur est explicite : pas de composants concurrents pour la même fonction, peu de texte simultané et une cohérence tout au long de l’application. Le bleu, la carte centrale pendant la leçon, Swift natif et les règles de confidentialité sont conservés.

## Références effectivement consultées

| Source primaire | Ce qui a été examiné | Transposition proposée pour Drivy | Limite |
|---|---|---|---|
| [Fantastical, Calendar Views](https://flexibits.com/fantastical-ios/help/calendar-views), [capture DayTicker](https://flexibits.com/img/help/fantastical-ios/en/f3-ios-dayticker.png) | Guide et capture : sélection du jour reliée à une liste chronologique, heure et intitulé séparés | Agenda par jours, colonne d’heures, détail à l’appui ; même ligne de leçon dans l’accueil et l’agenda | La capture affiche octobre 2025. Ce n’est pas une preuve du dernier binaire 2026. Ne pas reprendre les couleurs de calendriers ni le changement par orientation comme règle native Drivy |
| [Cardhop](https://flexibits.com/cardhop), capture « My Card » liée à la page | Présentation de la recherche de contacts et visuel de liste/carte d’identité | Recherche visible dans les élèves, identité claire au dossier, détails au second niveau | Pas d’essai de recherche installé. Ne pas reprendre le moteur de langage naturel, le graphe relationnel ou l’envoi de messages |
| [Bear](https://bear.app/), [capture iPhone](https://bear.app/images/home/hero_iphone.jpg) | Composition de lecture et rédaction avec titres, paragraphes et détails disponibles selon le contexte | Bilan lisible comme un document, non comme une mosaïque de cartes ; trois rubriques métier conservées | L’édition Markdown n’est pas un besoin ajouté à Drivy. Une page de bilan peut légitimement contenir davantage de texte qu’un signalement |
| [Linear mobile](https://linear.app/mobile), illustration Project Update de cette page | Présentation et capture d’une rédaction centrée sur le contenu, avec commandes de sortie/publication distinguées | Séparer sauvegarde, aperçu et publication, notifications ouvrant un objet précis | Ni gain de rapidité ni sécurité établis pour Drivy ; ne pas ajouter tâches, commentaires ou chat |
| [Things](https://culturedcode.com/things/), [planche officielle](https://culturedcode.com/things/2024-01-20/images/whatsnew-collage-io60.png) | Planche de listes, sections et informations secondaires | Lignes aérées, groupes titrés, détails utiles seulement ; conserver la direction déjà appréciée | Illustration de présentation, pas test de la version installée ni nouveau classement d’applications |
| [Apple HIG, Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) ; [contenu JSON officiel consulté](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/tab-bars.json) | Navigation entre sections, conservation de leur état, libellés et adaptation tablette | Les onglets canoniques ne deviennent pas des boutons d’action ; une pile de navigation par section ; adaptation à la largeur disponible | Recommandation plateforme ; la barre CSS n’est pas une implémentation TabView ni une preuve du rendu système |
| [Apple HIG, Lists and tables](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables) ; [contenu JSON officiel consulté](https://developer.apple.com/tutorials/data/design/human-interface-guidelines/lists-and-tables.json) | Texte court, détail au second niveau, distinction retour de sélection/navigation | Une anatomie partagée de ligne d’objet, accessoires différents seulement selon la conséquence | La source permet des variantes sémantiques, pas une obligation de rendre toutes les lignes identiques |

La page HTML Apple dépend de JavaScript ; son contenu éditorial JSON public a été lu. Une requête sur le JSON Search fields a échoué : aucune recommandation ne repose sur cette page non lue. Certains visuels mobiles Cardhop étaient inaccessibles ; la capture « My Card » a pu être examinée. Les galeries promotionnelles ne sont pas assimilées à des tests d’usage.

## Corrections réalisées et origine de la décision

### COH-01 · Une navigation commune, deux espaces de rôle

**Source locale :** `02-experience/architecture-information.md` fixe déjà Séance, Agenda, Élèves, École pour le personnel, et Mes leçons, Agenda, Mon parcours pour l’élève. Ce choix n’est pas réinventé à partir du benchmark.

**Application :** DS22 utilise un seul moteur de navigation et deux jeux de destinations. Les recherches, filtres, sélection et pile de détail sont conservés en changeant d’onglet. Compte et notifications restent dans l’en-tête ; aucune commande Signaler n’est ajoutée comme onglet. La carte est une présentation immersive de séance dont la fermeture n’arrête pas la capture. La sidebar iPad provient des mêmes destinations, pas d’un second menu métier.

### COH-02 · Une seule ligne de leçon

**Constat de travail :** la carte et les parcours hors carte étaient encore décrits par deux générations de prototypes. Il fallait étendre la direction, pas ajouter une nouvelle esthétique par écran.

**Application :** `UI.lessonRow` / DS04 alimente accueil, agenda, liste de détail iPad et engagements de l’élève. Heure, durée, personne/objet et lieu viennent de la même fixture. La pause de midi s’insère chronologiquement. Pas de cartes séparées pour chaque métadonnée. Une offre non réservée ne devient pas une leçon par proximité visuelle ; les offres collectives restent hors de cette nouvelle composition.

### COH-03 · Recherche, dossier et formation

**Application :** le même champ de recherche DS03.search, filtre en feuille DS15 et ligne DS25 sont utilisés selon le rôle. DS06 affiche une formation simple lorsqu’il n’y en a qu’une, un choix explicite sinon. Les leçons, pièces et bilans de B ne remplissent jamais les états vides de A. Les noms sont lisibles au détail ; les filtres restent visibles et effaçables.

### COH-04 · Des observations communes, sans fusion des sens

**Application :** `UI.observationRow` est effectivement appelée par la liste privée de la carte, la sélection du bilan et le contenu partagé prévisualisé. Le thème, le statut et le moment gardent la même anatomie. Trois accessoires sont autorisés : chevron pour ouvrir, case cochée pour sélectionner un texte à inclure, aucun accessoire pour lire.

Les statuts LIVE `ATTENTION`, `TO_REWORK`, `POSITIVE` ne deviennent pas des niveaux de compétence. Le parcours pédagogique garde la date et le contexte de sa source, sans moyenne ni note inventée. La sélection d’observations du bilan du 18 septembre utilise ses propres fixtures, pas celles de la capture du 21.

### COH-05 · Rédiger, prévisualiser, publier

**Source locale :** E08/E09 et `03-fonctionnel/bilans-documents.md` imposent les trois rubriques, la publication explicite et la distinction entre observation privée, projection partagée et trajet.

**Application :** un éditeur de texte composé avec DS03.multiline, un aperçu issu des seuls champs autorisés et une confirmation DS11/DS15. Le brouillon peut être incomplet ; une publication incomplète ou hors ligne est refusée. Une copie publiée simulée n’est pas modifiée par les nouvelles frappes dans le brouillon. La publication du trajet n’est pas ajoutée à cette passe : l’aperçu précise qu’aucun trajet ne sera partagé.

### COH-06 · L’apparence ne remplace pas le comportement

Documents, compte, notifications et écran École réutilisent les mêmes actions, lignes, champs, états et feuilles. Un document en analyse n’a ni aperçu ni validation humaine automatique. L’espace École du moniteur n’est pas une console d’administrateur. L’accès à la suppression de compte est illustré, mais le parcours de réauthentification et DM06 ne sont pas prétendus exécutés.

## Garde-fous transversaux

Même intention et même contexte donnent le même composant. Une différence de rôle, de sélection, de densité ou de longueur peut justifier une **variante documentée**, pas une copie par écran. La cohérence n’est pas l’uniformisation de conséquences différentes : enregistrer un brouillon, publier un bilan et réserver un créneau ne doivent pas devenir trois boutons « OK ».

La bibliothèque source du prototype est `DESIGN/atelier/ui.js`. Les couleurs restent issues du JSON de tokens 3.8. Les classes CSS ne doivent pas permettre une palette différente par page. Les tailles proposées ne sont pas des résultats ergonomiques validés. Une variante grand texte utilise la place disponible ou le défilement vertical, pas une réduction forcée de police.

## Couverture et travail restant

Le [registre de couverture](../DESIGN/couverture-ecrans.json) distingue le nouvel atelier, les illustrations antérieures et les écrans non dessinés. Les 49 fiches E disposent d’une affectation de composants, mais cela ne signifie pas 49 parcours reconstruits ou testés. La gestion de bureau, les cours, packs, configuration complète, journal financier, onboarding, export et procédures sensibles restent à reprendre sur cette bibliothèque. Une adaptation Android ne consiste pas à copier le CSS.

Les limites de capture, de calendrier, de document, de persistence et de publication restent explicites dans la [revue de livraison](../06-gouvernance/audit-corrections-v3-17.md). Aucun essai utilisateur, appareil, serveur ou Swift n’est exécuté par cette recherche.
