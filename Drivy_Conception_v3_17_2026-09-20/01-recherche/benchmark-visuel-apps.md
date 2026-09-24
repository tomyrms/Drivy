# Drivy : benchmark UI et direction visuelle proposée

Date de recherche : 20 septembre 2026.
Base du projet examinée : aperçu et prototype HTML Drivy V3.14.
Statut de la recherche d’origine : propositions de design. La recommandation de direction a ensuite été acceptée par le porteur dans cette conversation. Les détails des maquettes ne sont pas validés pour autant. Les descriptions des applications ci-dessous sont conservées depuis ce benchmark, sans nouvelle vérification de toutes ses sources dans la passe V3.15.

## Conclusion

Conserver la vision GPS de Drivy, mais concevoir des écrans qui permettent d'agir plutôt que d'expliquer constamment leur fonctionnement. La carte, la position, le trajet et les observations constituent le contenu principal. Les commandes doivent être compactes, lisibles, stables et immédiatement identifiables.

La cible n'est pas « aucun texte ». C'est « peu de texte simultanément, sans ambiguïté sur les actions et les états ».

## Méthode et limites

Sélection éditoriale de dix applications pertinentes pour les différentes parties de Drivy. Ce n'est pas le classement des téléchargements de l'App Store ni un palmarès officiel de sobriété. Les sources sont des pages d'éditeurs, des aides officielles, des captures publiques et les Apple Design Awards. Certaines applications sont anciennes mais restent des références proposées au moment de cette recherche ; certaines captures marketing présentes sur les sites peuvent provenir de versions antérieures.

Des captures officielles ont été examinées visuellement, notamment celles de Plans, Flighty, Things, Structured, Linear, Tide Guide et Moonlitt. Les aides officielles de Waze et AllTrails permettent de vérifier les parcours documentés. L'analyse de Gentler Streak repose sur sa présentation officielle et les aperçus publics disponibles. Les dix applications n'ont pas été installées et leurs interactions n'ont pas été mesurées sur iPhone. Les jugements esthétiques et les transferts à Drivy sont des propositions, pas des preuves d'efficacité ou de sécurité.

Moonlitt a remporté la catégorie Interaction et Tide Guide la catégorie Visuals and Graphics des Apple Design Awards 2026. Ces distinctions étayent l'intérêt de les étudier, sans démontrer que leurs choix conviennent à une leçon de conduite. [S1]

## Dix références, avec une fonction précise

| Application | Élément observé ou documenté | Transposition proposée pour Drivy | Ce qu'il ne faut pas reprendre automatiquement |
|---|---|---|---|
| Plans d'Apple | Carte structurante, informations de navigation mises en avant, commandes et fiches de contexte. [S2] | Carte continue derrière les commandes ; identité et temps de séance compacts ; détails dans un panneau. | Toutes les fonctions d'un navigateur routier, ni une promesse de navigation guidée. |
| Waze | Déclencheur de signalement, choix de catégorie puis précision ; la position est mémorisée lors de l'ouverture. [S3] | Bulle Signaler et choix pédagogiques courts ; préserver l'instant initial pendant la qualification. | Partage communautaire, mascottes, badges et envoi automatique par expiration d'un délai. |
| Flighty | Carte et liste de vols ; statuts, horaires et durées fortement hiérarchisés dans les captures. [S4] | État de séance compréhensible sans paragraphe ; une observation résumée sur une ligne avant ses détails. | Un tableau de métriques de vol transposé en faux indicateurs pédagogiques. |
| Things 3 | Listes aérées, faible présence des bordures, titres et métadonnées distingués. [S5] | Élèves, historique et bilans sous forme de listes sobres ; éviter une carte décorative autour de chaque donnée. | Transformer une leçon GPS en liste de tâches à cocher. |
| Structured | Journée organisée sur une ligne temporelle avec blocs dont la durée est visible. [S6] | Agenda du moniteur et vue temporelle des observations ; repérage de l'instant sans texte explicatif répété. | Multiplier les couleurs sans rôle stable, ou créer une seconde organisation concurrente de l'agenda. |
| AllTrails | Enregistrement GPS depuis Navigate, trace parcourue et panneau inférieur extensible. [S7] | Continuité trajet actif → historique → consultation ; commandes secondaires dans un panneau plutôt que sur toute la carte. | Fil social, découverte de randonnées et indicateurs qui ne servent pas l'enseignement. |
| Gentler Streak | Présentation de la progression personnelle autour d'Activity Path, plutôt que d'un objectif générique unique. [S8] | Après la leçon, rendre visibles acquis et points à travailler avec un ton non punitif. | Inférer une note de conduite ou ajouter des séries quotidiennes et récompenses sans besoin. |
| Tide Guide | Courbe temporelle explorée par glissement, donnée sélectionnée visible, visualisation centrale. [S9] | Dans le replay, déplacement sur une chronologie liée au point du trajet et à l'observation sélectionnée. | Courbes décoratives, fond changeant ou animation de marée transposée littéralement. |
| Moonlitt | Visualisation occupant l'écran et petits groupes de commandes ; interface de navigation de données spatiales. [S1, S10] | Carte immersive, commandes contenues, transitions reliant visuellement contrôle et contenu. | Écran sombre imposé, interface uniquement en icônes, effets translucides non qualifiés sur carte claire. |
| Linear mobile | Feuille de sélection de statut simple, icône + libellé ; présentation mobile distincte du bureau. [S11] | Choix Attention / À retravailler / Point positif en lignes courtes, sans sous-texte répété. | Vocabulaire de tickets ou complexité d'un gestionnaire de développement. |

## Synthèse pour une identité cohérente

Ne pas mélanger dix styles. Je recommande d'utiliser Plans pour la composition cartographique, Waze pour le principe de signalement, Flighty pour les états, Things pour la sobriété des listes et Tide Guide pour le replay. Les autres servent de références ponctuelles.

La direction « Cartographie native » reste pertinente : bleu Drivy, surfaces claires et iconographie cohérente. L'amélioration porte sur la composition, l'usage de l'espace et la hiérarchie, pas sur l'ajout d'un thème différent. Les traits, cadres, ombres et effets doivent avoir une fonction. Une animation relie une action à son résultat ; elle ne doit pas retarder la prochaine action.

## Réduction de texte : modifications proposées à la V3.14

Les expressions ci-dessous ont été retrouvées dans le HTML fourni. Elles ne sont pas des extrapolations de l'audit V3.13.

| Présentation actuelle | Proposition | Condition à préserver |
|---|---|---|
| « L'instant est retenu. Aucun événement n'est ajouté avant votre choix d'enregistrement. » | Retirer le paragraphe permanent ; afficher l'heure du repère et permettre d'annuler. Réserver l'explication détaillée au premier usage ou à une aide accessible. | Aucun événement final n'est créé par la seule ouverture. |
| « Enregistrer l'observation » sous chacun des trois statuts | Supprimer la répétition ; garder les statuts explicites. Si nécessaire, une instruction commune « Choisis un statut pour enregistrer ». | Compréhension du fait que sélectionner un statut enregistre ; possibilité de correction. |
| « Pas de note automatique. Les précisions restent modifiables après l'enregistrement. » | Explication dans l'aide ou le détail ; pas sous chaque saisie. | Ne créer réellement aucune note automatique, même si l'explication n'est plus permanente. |
| « Démo · mémoire de cette visite », références au trajet fictif | Déplacer ces mentions dans le cadre extérieur de la démonstration, toujours visibles pour l'évaluateur mais hors de l'écran simulé. | Le prototype ne doit jamais être présenté comme un GPS ou une persistance réels. |
| Identité, durée, état GPS et longues commandes dans un grand panneau | Grouper en une zone compacte et réserver l'espace principal à la carte. | GPS actif, pause, absence de position et panne restent distinguables. |
| Grandes cases avec plusieurs lignes de qualification | Icône cohérente + nom explicite ; feuille de statut simple. | Garder « Priorité à droite », plutôt qu'un raccourci ambigu comme « Priorité ». |

La divulgation progressive consiste à placer les fonctions avancées ou rarement nécessaires au second niveau. Elle ne justifie pas de dissimuler les informations critiques. [S12]

Les pictogrammes seuls ne sont pas universellement compris : conserver de courts libellés pour les actions et les catégories dont le sens n'est pas évident. [S13] Les descriptions VoiceOver doivent rester complètes même lorsque le texte visible est court.

## Composition proposée du parcours

### Carte de leçon

Carte dominante. Zone compacte avec élève, durée et état de capture. Action Signaler fixe et lisible, distincte du recentrage et de la fin de leçon. Repère non qualifié toujours disponible sans ajouter une deuxième action aussi dominante. Observations accessibles avec compteur, pas avec un paragraphe.

L'espace de la carte cède à la lisibilité des commandes aux grandes tailles de texte. Ne pas rendre l'interface plus « légère » en réduisant les caractères ou les cibles tactiles.

### Signalement

Ouverture ancrée visuellement au déclencheur. Moment mémorisé. Catégories stables, icône + libellé, pas de clavier requis. Choix de statut puis retour carte après enregistrement local réussi. Aucun statut par défaut ne doit être ajouté pour gagner un appui sans arbitrage explicite.

### Confirmation et erreurs

Confirmation courte : « Observation ajoutée » ou thème + statut. Garder un accès à la correction. Ne pas utiliser « Synchronisé » pour une écriture uniquement locale. Une connexion absente ou un envoi en échec reste visible au niveau approprié.

### Replay

Trajet dominant, chronologie avec repères, fiche de l'observation sélectionnée. Les informations détaillées apparaissent à la sélection. L'exploration manuelle de la carte n'est pas annulée arbitrairement par un recentrage. Les transitions doivent également fonctionner avec Réduire les animations.

### Arrêt et clôture

Ne pas raccourcir « Arrêter le GPS » et « Terminer la leçon » en un même « Arrêter ». Peu de texte n'est pas une raison de rendre une conséquence ambiguë.

## HTML, Figma et SwiftUI

Le HTML reste utile comme prototype de parcours et pour les états interactifs. Il ne fixe pas un plafond de qualité esthétique : la densité actuelle vient de choix de conception, pas de son format.

Figma est pertinent pour comparer les compositions, travailler avec des calques éditables, des composants, des variantes et Auto Layout. Celui-ci permet notamment de faire suivre un conteneur au contenu. [S14, S15] Importer des calques ne garantit toutefois pas la qualité de la structure, des composants ou de l'adaptation : une reprise peut être nécessaire.

Le parcours recommandé est : valider quelques écrans visuels dans Figma, conserver les scénarios du prototype HTML utiles, puis éprouver le rendu et les interactions du client natif SwiftUI sur les appareils cibles. Figma ne constitue pas un test GPS, batterie, accessibilité native ou ergonomie en véhicule.

État des outils au moment de la recherche : intégration Figma trouvée et proposée dans la conversation, pas encore connectée. Aucun document Figma n'a été créé. Les possibilités précises de création devront être confirmées dans les actions disponibles après connexion.

## Critères de revue de la prochaine maquette

- Un nouveau lecteur reconnaît l'élève, l'état de capture et l'action principale sans lire une explication.
- Il distingue signalement, repère non qualifié et fin de leçon.
- Le thème et le statut sont compréhensibles sans deviner un pictogramme.
- Les paragraphes documentaires ne sont plus présents dans le parcours courant ; les explications restent consultables.
- Les états sans GPS, hors ligne, erreur d'envoi, pause et texte agrandi sont représentés, pas seulement l'état idéal.
- Les changements de disposition et les animations ne sont pas qualifiés comme sûrs en mouvement par une simple revue visuelle. Aucun test terrain n'a été réalisé.

## Sources

Toutes les pages ci-dessous ont été consultées le 20 septembre 2026. La date de consultation ne signifie pas que chaque capture illustre la dernière version commercialisée.

- **S1. Apple**, Apple Design Awards 2026, publié le 2 juin 2026 : https://www.apple.com/newsroom/2026/06/apple-reveals-winners-of-the-2026-apple-design-awards/
- **S2. Apple**, Plans, page produit et captures : https://www.apple.com/maps/
- **S3. Waze**, Report road hazards, aide officielle : https://support.google.com/waze/answer/13739290?hl=en-GB
- **S4. Flighty**, présentation et captures publiques : https://flighty.com/
- **S5. Cultured Code**, Things, présentation et captures : https://culturedcode.com/things/
- **S6. Structured**, présentation et capture de la chronologie : https://structured.app/
- **S7. AllTrails**, How to track and record an activity : https://support.alltrails.com/hc/en-gb/articles/360019244391-How-to-track-and-record-an-activity ; Using the Navigate feature : https://support.alltrails.com/hc/en-gb/articles/37228358315668-Using-the-Navigate-feature
- **S8. Gentler Stories**, Gentler Streak : https://gentlerstories.com/gentlerstreak
- **S9. Condor Digital**, Tide Guide : https://tideguide.com/
- **S10. Apple Developer**, ADA Q&A: What a little Moonlitt can do, publié le 16 mai 2026 : https://developer.apple.com/news/?id=v1nphz91
- **S11. Linear**, application mobile et capture de sélection des statuts : https://linear.app/mobile
- **S12. Nielsen Norman Group**, Progressive Disclosure, publié le 3 décembre 2006 : https://www.nngroup.com/articles/progressive-disclosure/
- **S13. Nielsen Norman Group**, Icon Usability, publié le 27 juillet 2014 : https://www.nngroup.com/articles/icon-usability/
- **S14. Figma**, Guide to auto layout : https://help.figma.com/hc/en-us/articles/360040451373-Guide-to-auto-layout
- **S15. Figma**, Design an interactive button component : https://help.figma.com/hc/en-us/articles/20953528101783-Design-an-interactive-button-component

Les recommandations pour Drivy constituent la synthèse de cette recherche et de l'examen de sa maquette ; elles ne sont pas des recommandations émises par ces éditeurs pour Drivy.
