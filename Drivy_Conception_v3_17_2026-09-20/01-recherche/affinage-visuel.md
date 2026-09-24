# Drivy : recherche visuelle 02 et affinage de la V3.15

Date de consultation : 20 septembre 2026.

**Statut de la recherche d’origine : propositions sur la V3.15 appréciée par le porteur. Le porteur a ensuite demandé leur application. La V3.16 matérialise VIS-01 à VIS-04 ; VIS-05 est seulement préparé par une fiction plus dense, pas exécuté sur MapKit. Les sources web ci-dessous sont héritées de la recherche, sans nouvelle consultation dans cette passe. [Application et limites](../06-gouvernance/audit-corrections-v3-16.md).**

## 1. Ce que cette passe cherche à améliorer

Conserver la carte dominante, le bleu Drivy, le signalement rapide, les surfaces calmes et le faible volume de texte simultané. Chercher une meilleure précision visuelle et une meilleure correspondance entre ce que montre un contrôle et ce qu'il fait, plutôt qu'une nouvelle direction artistique.

Le parcours reste : carte de leçon, signalement, choix du statut, observation privée, replay puis bilan. Ni publication ni notation automatiques. Les contraintes de GPS, de confidentialité, d'accessibilité et de synchronisation ne disparaissent pas pour simplifier une capture d'écran.

### Matériaux examinés et limites

La planche claire `Drivy_apercus_v3_15/00_parcours_light.png`, le prototype `Drivy_Maquettes_v3_15.html` et son résumé de livraison ont été examinés. Les constats ci-dessous sur les chevrons, marqueurs et textes reposent sur ces fichiers, pas sur l'ancien audit V3.13.

La recherche externe utilise les présentations officielles et les visuels accessibles des éditeurs. Les images de Halide, Crouton, Lumy et une composition cartographique de Tripsy ont été consultées. Pour Clear, l'analyse porte principalement sur le guide officiel de gestes, pas sur une session installée. Certaines autres images de Tripsy et stoic n'ont pas pu être rendues ; aucune conclusion visuelle ne repose sur elles.

Aucune application n'a été installée pour cette passe, aucune animation native n'a été mesurée, aucun entretien ou essai sur appareil n'a été effectué. Une capture promotionnelle ne garantit pas le rendu exact de la dernière version distribuée. Les emprunts proposés ci-dessous sont des hypothèses de conception, pas des preuves d'efficacité pédagogique.

## 2. Cinq références supplémentaires

### Halide Mark III : le contenu avant les outils

Le lancement documenté par l'éditeur le 27 mai 2026 expose une hiérarchie volontaire : outils principaux visibles, réglages secondaires accessibles ensuite. Certains réglages manuels activés réapparaissent dans la barre afin que leur état ne soit pas oublié. Le visuel consulté garde la photographie au centre. [S1]

**Pour Drivy :** maintenir Signaler comme action dominante ; laisser visibles les états qui changent l'interprétation de la séance. La simplicité ne doit pas rendre une pause GPS invisible. Ne pas transposer mécaniquement le rangement d'un réglage photo au rangement d'une commande critique de leçon.

**Ne pas reprendre :** le volume d'outils photographiques, l'accent jaune, ou une personnalisation des styles qui détournerait la première livraison de son métier.

### Crouton : distinguer consulter et agir

La capture officielle distingue titre, action de démarrage et contenu de recette. Apple décrit également son guidage étape par étape et la hiérarchie de l'information dans sa présentation des Design Awards 2024. Une recette détaillée n'est pas sans texte : ce qui importe est sa répartition selon la tâche. [S2, S3]

**Pour Drivy :** traiter séparément la leçon active, le signalement et la lecture du bilan. L'écran d'action peut être très léger tandis que le bilan conserve les explications pédagogiques nécessaires. Ne pas transformer toutes les données en cartes identiques pour imiter une bibliothèque de recettes.

### Tripsy : relier les objets de la carte à ceux de la liste

La composition officielle examinée juxtapose carte et panneau de lieux. Les pictogrammes de lieux participent à l'identification des éléments ; les lignes rassemblent titre et informations secondaires sans un gros encadré pour chaque ligne. [S4, S5]

**Pour Drivy :** essayer un lien visuel plus fort entre l'observation sélectionnée sur le trajet et son thème dans le panneau. Pour les futurs écrans d'agenda et d'élève, tester des lignes alignées plutôt qu'une mosaïque de cartes.

**Ne pas reprendre :** une couleur par catégorie, toutes les métadonnées touristiques ni un grand panneau couvrant la carte pendant la leçon. Cette référence sert surtout la consultation.

### Lumy : faire de la chronologie une commande visuelle

La planche officielle intitulée « Lumy New 2025 » montre un curseur temporel, une représentation de la course du soleil et un panneau de détail. Ce visuel est daté par son intitulé ; il ne prouve pas une nouvelle interface publiée en septembre 2026. [S6]

**Pour Drivy :** améliorer la relation entre curseur de replay, heure sélectionnée, point cartographique et observation. Le replay doit rester lisible lorsqu'une seule observation est mise en avant.

**Ne pas reprendre :** les dégradés astronomiques, les effets de verre partout ou une grosse visualisation sans rapport avec une donnée réelle du trajet.

### Clear : une référence partielle, avec une limite importante

Le guide officiel décrit une interface pilotée par des gestes : balayage, pincement, traction et maintien. Cette radicalité réduit les commandes visibles, mais elle impose aussi des conventions à apprendre. [S7]

**Pour Drivy :** retenir l'économie des listes et la réduction des éléments décoratifs. Ne pas supprimer les boutons explicites pour reproduire son principe gestuel. Signaler, Annuler, les commandes GPS et la fin de leçon ne doivent pas dépendre d'un geste secret.

**Ne pas reprendre :** les thèmes multicolores, les récompenses de collection et les sons répétés. Clear est un contrepoint utile, pas la nouvelle direction visuelle de Drivy.

## 3. Retouches proposées sur les quatre vues actuelles

### VIS-01. Corriger le signal visuel des lignes de statut

**Constat dans le fichier :** les trois lignes du panneau de statut portent un chevron droit. Le même bloc annonce « Le choix enregistre » et les boutons possèdent un libellé accessible décrivant l'enregistrement de l'observation privée.

**Risque interprétatif, non mesuré :** le chevron peut laisser attendre une étape suivante alors que le choix déclenche l'enregistrement.

**Proposition :** comparer la version actuelle à des lignes sans chevron de navigation, avec un état pressé net et une confirmation discrète après l'enregistrement. Conserver la possibilité de correction. Ne pas ajouter par défaut un bouton de confirmation supplémentaire, qui rallongerait le geste.

**Texte :** ne pas retirer immédiatement « Le choix enregistre ». Comparer sa présence en phrase commune à une explication limitée au premier usage. L'esthétique seule ne permet pas de décider que le comportement est suffisamment évident.

**Acceptation à vérifier :** l'utilisateur comprend la conséquence avant de toucher un statut, distingue sauvegarde locale et publication et peut corriger une sélection erronée. Aucun test utilisateur correspondant n'a été réalisé.

### VIS-02. Mieux identifier l'observation sélectionnée sur la carte

**Constat :** les marqueurs actuels affichent surtout le statut, sous la forme d'un point d'exclamation, d'une croix ou d'une coche. Le thème complet existe dans le panneau et le libellé accessible.

**Proposition :** essayer le pictogramme du thème sur le seul marqueur sélectionné, avec un état de sélection distinct. Conserver le statut explicite dans le panneau et dans l'accessibilité. Une autre variante peut garder les pictogrammes actuels mais afficher un intitulé bref uniquement à la sélection.

**Garde-fou :** ne pas déployer une étiquette textuelle sur chaque point, ni une nouvelle couleur par catégorie. Lorsque les événements sont rapprochés, leur accès par la liste doit rester possible. Ne pas fusionner pédagogiquement plusieurs observations simplement pour désencombrer le rendu.

**Acceptation à vérifier :** identifier quelle observation est sélectionnée et ce qu'elle concerne ; retrouver chacune des observations rapprochées ; conserver l'identification sans dépendre uniquement de la couleur.

### VIS-03. Donner une continuité aux panneaux

**Point de départ :** le prototype possède déjà des animations courtes d'apparition et une variante à mouvements réduits. Cette proposition ne consiste pas à ajouter des animations partout.

**Proposition :** traiter Catégories puis Statut comme deux étapes d'un même panneau : transition de son contenu et de sa hauteur, conservation du contexte temporel, retour vers les catégories sans recréer un instant. La carte et l'en-tête ne doivent pas changer de position sans nécessité.

**Acceptation à vérifier :** absence de saut de contexte ; nouvelle action possible sans attendre un effet décoratif ; interruption et retour gérés ; mêmes fonctions avec mouvements réduits. Une animation de succès suit l'enregistrement local, jamais un simple appui non persisté.

### VIS-04. Préciser la famille de pictogrammes, sans multiplier les couleurs

**Point de départ :** le prototype utilise déjà une épaisseur SVG commune. Il ne faut pas présenter une incohérence générale d'épaisseur comme un défaut constaté.

**Proposition :** vérifier maintenant l'équilibre optique et la compréhension métier : visibilité des flèches de priorité, reconnaissance du giratoire, distinction du repère non qualifié et du bouton de signalement. Garder les pictogrammes avec des libellés courts dans le panneau de catégories.

« Observation » peut être ambigu puisqu'il désigne aussi l'objet enregistré. « Contrôles visuels » est une piste uniquement si le thème recouvre réellement rétroviseurs, regard et angles morts. Un changement de libellé n'est pas un changement silencieux de taxonomie.

**Acceptation à vérifier :** les moniteurs comprennent les catégories sans une légende permanente ; le plus grand texte ne coupe pas leurs intitulés ; les catégories restent au même endroit d'une utilisation à l'autre.

### VIS-05. Éprouver la sobriété sur une carte réaliste

**Constat :** la carte actuelle est volontairement schématique. Le résumé de livraison ne la présente pas comme MapKit.

**Proposition :** pour la prochaine validation native, essayer les mêmes panneaux sur une carte urbaine dense et avec plusieurs observations proches. Vérifier routes, toponymes, signal de position, halo du trajet et lisibilité des commandes superposées.

**Garde-fou :** ne pas conclure qu'il faut masquer les noms de rues ou rendre toute la carte très pâle. Ne pas confondre un fond de démonstration élégant et les options réellement disponibles auprès du fournisseur cartographique.

**Acceptation à vérifier :** priorité visuelle du trajet et de l'observation sélectionnée, lecture des informations utiles, contraste des panneaux, distinction entre position connue et absence de position. Aucune qualification de sécurité en mouvement n'en découle.

## 4. Décliner ensuite, sans redessiner tout le produit maintenant

Pour l'agenda, tester une journée structurée par les heures : horaire en colonne stable, nom d'élève dominant et une ligne secondaire utile. Une leçon courante n'a pas besoin d'un paragraphe ni d'un panneau autonome pour sa durée, son permis et son statut.

Pour la fiche élève, conserver un nom, la formation sélectionnée et une prochaine action pertinente au premier niveau. Placer coordonnées, pièces et historique derrière des sections identifiables. Ne pas créer un tableau de bord de chiffres uniquement pour remplir l'écran.

Pour le bilan, proposer une synthèse lisible, puis les observations et leurs explications. « Très peu de texte » vaut pour ce qu'on affiche simultanément, pas pour la suppression du contenu pédagogique rédigé. Les critères « à travailler » doivent provenir des observations et de l'évaluation, pas d'un score inventé.

Ces trois déclinaisons ne sont pas de nouveaux écrans livrés par cette note. Le premier travail reste la finition du parcours cartographique approuvé.

## 5. Ordre conseillé et invariants

Première retouche : sens des lignes de statut, effort réduit et conséquence directe sur le geste. Deuxième : marqueur sélectionné et relation avec le replay. Troisième : continuité des panneaux et iconographie. Valider ensuite la lisibilité sur fond cartographique réel, puis étendre les composants aux écrans adjacents.

Ne pas supprimer les informations hors ligne, les erreurs d'enregistrement, l'absence de GPS ou le caractère privé d'un bilan pour gagner de la place. Ne pas rendre le texte plus petit ou moins contrasté pour paraître sobre. Ne pas cacher une commande critique pour obtenir une capture plus vide. Aucune norme de nombre maximal de mots, aucun gain de temps chiffré et aucune sécurité d'usage ne sont établis par ce benchmark.

La recherche ne justifie ni changement d'outil obligatoire, ni nouvelle couleur de marque, ni nouvelle route API, ni table supplémentaire. La source V3.15 est laissée intacte. L’application des retouches se trouve dans une livraison distincte V3.16.

## Sources effectivement utilisées

Toutes consultées le 20 septembre 2026. Les références donnent accès aux preuves publiques, pas à une certification des applications.

- [S1 : Lux, Halide Mark III, 27 mai 2026](https://www.lux.camera/halide-mark-iii/), sections « The Photo Lab » et « The New Design », et capture de l'interface associée.
- [S2 : Crouton, présentation officielle](https://crouton.app/) et sa [capture officielle](https://crouton.app/images/hero.png).
- [S3 : Apple Design Awards 2024](https://developer.apple.com/design/awards/2024/), section Interaction, Crouton.
- [S4 : Tripsy, présentation officielle](https://tripsy.app/), section des activités et cartes.
- [S5 : Tripsy, composition cartographique officielle](https://framerusercontent.com/images/OvHE2UJ4Isy24z8roiNfi2kr90.png?height=3378&width=3770), visuel effectivement consulté. Les autres images inaccessibles ne sont pas des preuves.
- [S6 : Lumy, présentation officielle](https://lumy.app/) et [planche « Lumy New 2025 »](https://lumy.app/images/lumy_new_2025.png).
- [S7 : Clear, guide officiel](https://www.useclear.com/guide/), description des gestes et de l'organisation de l'interface.

Sources locales : `Drivy_Maquettes_v3_15.html`, `Drivy_apercus_v3_15/00_parcours_light.png` et `Drivy_v3_15_resume_corrections.md`. Cette passe ne reprend pas comme actuels les défauts historiques du dossier V3.13.
