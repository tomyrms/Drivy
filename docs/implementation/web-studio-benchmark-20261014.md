# Portail web — référence Mercury et adaptation Drivy

Étude du 14 octobre 2026. Le porteur rejette la direction Registre du 13 octobre, puis choisit explicitement la démo Mercury comme référence : « j’aime beaucoup la demo mercury […] reprendre le design en l’adaptant un peu aux couleurs de drivy ». Ce choix remplace l’exploration de directions concurrentes. La référence est désormais la composition et le comportement de Mercury ; La trace, le cobalt Drivy et le sombre anthracite restent les éléments de marque à adapter. Le premier cadrage conservait Source Sans 3 ; la réalisation Studio retient finalement Manrope auto-hébergée pour la police web, décision et provenance consignées dans la [note de réalisation](web-studio-20261014.md).

Ce document décrit les preuves disponibles et les décisions de présentation à réaliser. Il ne qualifie pas une implémentation et ne modifie ni les règles métier, ni les contrats, ni le client Apple.

## Ce qui a été observé et ce qui reste documentaire

La [démo publique Mercury](https://demo.mercury.com) a été parcourue avec CUA par l’agent principal le 14 octobre. Il s’agit d’une interface interactive avec données de démonstration, pas d’une session bancaire personnelle ni d’une maquette reconstruite. L’article officiel [Designing in the open](https://mercury.com/blog/designing-in-the-open), publié le **16 mars 2026** par Jonathan Simcoe, explique l’origine de cette démo publique issue d’un environnement interne. L’article ne donne pas un numéro de version de l’interface ; la date d’inspection sert de référence.

Le navigateur était indisponible dans la session du rédacteur de ce benchmark, malgré la documentation annonçant le navigateur 2. Les interactions et mesures Mercury ci-dessous sont donc celles transmises par l’agent principal, distinguées des pages lues avec l’outil Web. Le rédacteur a ensuite réellement inspecté les pixels des captures locales [Company Settings](../../artifacts/mercury-research-20261014/18-company-settings-light.png) et [Edit Company](../../artifacts/mercury-research-20261014/19-edit-company-modal-light.png), produites depuis la démo par l’agent principal : lignes espacées et séparées, libellé/valeur, navigation dédiée, formulaire court et actions en capsule y sont visibles. Aucun compte authentifié Linear, Attio, Notion ou Ramp n’a été ouvert. Les descriptions et liens d’images indexées de ces autres produits ne sont pas présentés comme des pixels effectivement vus par ce rédacteur.

| Surface Mercury | Observation transmise depuis la démo | Niveau de preuve |
|---|---|---|
| Structure | Rail de 220 px, en-tête compact, contenu distinct de la navigation. | Observation CUA et mesure DOM transmise. |
| Typographie | Titre Arcadia Display 28/36 px, graisse 380 ; corps Arcadia Text 15/24 px, graisse 400 ; navigation proche de 14 px. | Mesure DOM transmise ; ces polices propriétaires ne sont pas importées. |
| Commandes | Commandes de barre proches de 32 px ; action primaire en capsule. | Observation CUA ; hauteur de barre approximative. |
| Transactions | Rangée de vues, filtre, date, recherche de mot et montant ; tri et groupement compacts à droite. | Composition réellement observée. |
| Menu de filtre | Panneau ancré à deux colonnes : types de filtre à gauche, éditeur à droite, calendrier borné. | État ouvert réellement observé, plus utile qu’une capture de liste seule. |
| Sombre | Surfaces teintées indigo dans la démo. | Observé ; cette teinte n’est pas retenue pour Drivy. |
| Paramètres | La navigation de paramètres remplace les destinations métier, avec retour et groupes Company, Team, Security et Personal. Page Company en lignes séparées, libellés proches de 38 % et valeurs de 62 %. | Composition réellement observée. Les groupes Drivy restent adaptés à ses fonctions. |
| Modification d’entreprise | Dialogue de 448 px avec retrait de 40 px ; titre 19/28 px, graisse 400 ; enveloppe de champ de 42 px, rayon 8 px ; actions de 40 px en capsule, padding 8×32 px. | Mesures DOM transmises ; aucun formulaire soumis. |

Les dimensions proposées plus loin constituent des décisions Drivy à vérifier sur les écrans pilotes. La reprise de Mercury vise les relations entre éléments — taille du titre face aux outils, retrait du contenu, densité du menu, espace entre sections — et non l’ajout d’un décor bancaire ou de commandes sans équivalent métier.

### Couverture de la collecte finale

Le [manifeste local](../../artifacts/mercury-research-20261014/manifest.json) contient **35 captures d’états**, correspondant à **17 chemins de route distincts** et **18 URL distinctes** en comptant le paramètre qui ouvre la modification d’entreprise. Ces nombres sont calculés depuis le manifeste, pas extrapolés depuis la navigation. La [galerie locale](../../artifacts/mercury-research-20261014/index.html) utilise les PNG originaux ; le [manifest des empreintes SHA-256](../../artifacts/mercury-research-20261014/manifest-sha256.json) identifie chaque fichier et le manifeste source.

Les chemins observés sont `/transactions`, `/accounts`, `/cards`, `/cards/cardid-choice-0`, `/team-spend`, `/payments`, `/payments/recipients`, `/invoicing`, `/invoicing/catalog`, `/invoicing/catalog/add-item`, `/settings/company-profile`, `/settings/my-profile`, `/settings/users`, `/settings/users/team-id-9`, `/settings/notifications`, `/dashboard` et `/tasks`. Ils couvrent listes, fiche, formulaire de création, modification courte, préférences, menus de filtre, tri, présentation, recherche et état vide, dans les deux thèmes selon les captures disponibles. L’image 06 montre le menu des vues enregistrées, sans recherche dans ce menu. L’image 33 montre le menu de présentation (graphique, fuseau, catégories), pas une édition des colonnes de table. La capture sombre Company Settings a également été inspectée directement par le rédacteur.

La collecte est substantielle mais ciblée : elle ne couvre pas toutes les fonctions financières, tous les parcours de validation ou toutes les destinations de Mercury. Plusieurs captures d’une même route représentent des menus ouverts ou un changement de thème. Aucune couverture exhaustive de l’application, aucune session authentifiée et aucune transaction bancaire ne sont revendiquées.

## Lecture du rejet de Registre

Les essais de fonctionnement et les captures du 13 octobre avaient vérifié des propriétés techniques. Ils n’établissaient pas que la direction plaisait au porteur. Son retour invalide cette direction visuelle. Les acquits fonctionnels restent utiles : liens vers les dossiers, traitement des erreurs, recherche, filtres réels, pagination, retour au contexte et distinction entre données absentes et données non chargées.

Trois choix de présentation doivent changer ensemble : les filtres dessinés comme des champs de formulaire, la répétition de bandes titre/navigation/outils et la petitesse uniforme du texte. Remplacer seulement le chevron des sélecteurs ou augmenter les rayons ne répondrait pas à cette demande. La nouvelle passe doit revoir le cadre de travail, le dessin des composants fermés et ouverts, puis leur usage dans chaque famille de pages.

## Huit décisions de réalisation

### 1. Recomposer le cadre de travail autour du contenu

Reprendre la relation Mercury entre un rail calme de 220 px, un en-tête compact et une large zone de travail. Le contexte de l’école appartient au cadre ; le titre et l’action principale appartiennent à la page. Une page de liste ne doit plus empiler un titre de famille, un fil de contexte, un second titre puis une rangée de labels de champs avant d’afficher les données. Les paramètres disposent de leur propre navigation avec retour à l’espace métier, comme dans la démo. Le nom long d’une école est testé dans le cadre, sans repousser toutes les commandes.

**Application :** console principale, paramètres, catalogue, fiches et ouverture d’école. Les liens de navigation existants restent réels. La composition ne doit pas introduire de nouveau tableau de bord ni de statistiques décoratives.

### 2. Donner une hiérarchie plus accueillante au texte

Prendre le titre Mercury proche de 28 px comme point de départ ; employer une graisse 400–500 pour les titres de page, et réserver 550–600 à une identité ou une action qui doit ressortir. La réalisation retient Manrope après le cadrage initial en Source Sans 3. Garder le corps à 15–16 px et les métadonnées à 13–14 px. Le titre respire avec environ 24 px avant les outils ; les sections de formulaire se séparent par 24–32 px. Les valeurs finales sont déclarées dans la note de réalisation. Les écrans denses doivent rester lisibles sans obtenir leur densité par un texte partout minuscule.

**Application :** titre « Élèves », nom d’un dossier, libellés des sections de paramètres et titres du guide. Préserver le nom complet et les coordonnées utiles pour distinguer les personnes ; ne pas fabriquer de photo ni d’avatar.

### 3. Traiter les filtres comme des commandes de vue

Adopter une barre proche de Transactions : recherche, vues de dossier puis commandes compactes de filtre et de tri. Les valeurs actives apparaissent dans les commandes, par exemple « Profil : à compléter » ; elles ne sont pas cachées derrière un bouton générique sans état. Une enveloppe visuelle de 32–36 px est un point de départ pour les outils à la souris ; la cible tactile reste de 44 px. Ouvrir les choix dans un menu ancré, avec texte aligné, indicateur de sélection, séparation claire des groupes et fermeture prévisible. Le nombre de résultats appartient à la liste.

**Application :** élèves, équipe, invitations, trajets et catalogue. Les vues Actifs/Archivés/Tous et les filtres existants suffisent. La complexité du constructeur bancaire à deux colonnes n’est justifiée que si le contenu réel l’exige ; Drivy n’a pas besoin de reproduire ses filtres de montant, d’opérateurs avancés ou de vues partagées.

### 4. Dessiner les sélecteurs fermés et ouverts comme une même famille

Remplacer l’apparence de sélecteur système générique par un composant partagé, avec deux usages explicites : une commande compacte dans une barre, et un champ de choix dans un formulaire. Le choix sélectionné, le chevron, la zone de survol, la sélection du menu et le focus doivent appartenir à ce même dessin. Pour une longue liste de personnes ou de formations, ajouter une recherche dans le panneau ; pour trois états, montrer directement les trois options. Point de départ visuel : rayon 8 px, texte 15 px, menu opaque, ombre douce réservée à sa superposition.

**Application :** profil et tri des élèves, filtre d’accès, moniteur, catégorie de permis, école et choix du catalogue. Le composant doit gérer un libellé distinct de la valeur, les flèches, Entrée, Échap, l’état désactivé et la restitution du focus. La [référence APG du W3C sur les combobox](https://www.w3.org/WAI/ARIA/apg/patterns/combobox/) sert au comportement, pas à l’apparence. Le remplacement visuel ne peut pas être validé sur le seul état fermé.

### 5. Construire des tables lisibles avant de chercher une hauteur minimale

Reprendre la sobriété des tables Mercury : les noms et données utiles dominent, les commandes restent plus légères, les séparations servent à suivre les lignes. L’identité est en encre principale ; le bleu ne colore pas chaque cellule pour annoncer qu’une fiche existe. Garder un vrai lien sur le nom, un état de survol de ligne et un focus explicite. Les colonnes Contact, Formation, Dossier et Profil restent comparables sur écran large. Une ligne avec deux coordonnées peut respirer davantage qu’une ligne à une seule valeur ; ne pas forcer un nombre de lignes arbitraire dans le viewport.

**Application :** élèves, équipe, offres et conditions. Sur mobile, conserver l’identité et l’état utile en premier, puis présenter les autres valeurs avec leurs libellés. Ni checkbox de masse sans commande, ni bouton d’export décoratif, ni statuts normaux transformés en badges colorés.

### 6. Donner aux formulaires un rythme propre

Un formulaire de modification n’utilise pas la même échelle qu’une barre de filtres : champs de 40–44 px, label permanent, contenu de saisie borné, sections compréhensibles et marge suffisante entre elles. Employer la surface et l’espace pour grouper les questions ; éviter l’empilement d’une carte, d’un cadre de section puis d’un cadre autour de chaque checkbox. Le bouton d’enregistrement principal peut reprendre la capsule Mercury en cobalt Drivy. Un état de saisie modifiée reste adjacent à l’action ; l’aide n’apparaît que lorsqu’elle est utile ou demandée par le contrat métier.

**Application :** coordonnées, confidentialité, informations élèves, tarifs, référentiels et guide. Les paramètres reprennent la lecture en lignes de Mercury, avec un bouton Modifier et un formulaire limité au groupe concerné. Drivy peut afficher ce formulaire dans la page pour conserver ses mécanismes de brouillon et les cibles de recherche. Sauvegarde explicite, erreurs de champ, confirmations métier, protection des brouillons et succès après écriture durable restent inchangés.

### 7. Composer une fiche autour de la personne et de la tâche suivante

Dans la fiche d’élève, donner une place claire au nom, aux moyens de contact et à la formation en cours, puis aux sections de suivi. Le retour à la liste est discret mais permanent. Les actions sont groupées près du sujet qu’elles modifient ; les actions destructives ne concurrencent pas la commande principale. Le plein écran de fiche et le retour au contexte de liste restent conservés. Les formulaires de correction ne deviennent pas un long mur de champs placé avant toute information sur la personne.

**Application :** élèves et équipe ; détail du catalogue selon son contenu réel. Cette composition est une adaptation Drivy, non une copie de la fiche de transaction Mercury. Les champs privés, droits serveur et étapes de consentement ne sont pas déplacés hors de leur contexte métier.

### 8. Adapter les couleurs sans perdre la structure Mercury

Conserver le cobalt Drivy pour l’action principale, la sélection et le focus, et remplacer l’indigo sombre de Mercury par les neutres Soft Charcoal. Le menu doit se détacher de la page par une surface opaque légèrement plus claire, une bordure et une ombre de superposition ; un changement de couleur ne suffit pas à recréer la profondeur observée. Le clair et le sombre utilisent les mêmes espacements, tailles et rayons. Éviter les aplats bleus dans chaque rangée sélectionnée, les contours aussi forts partout et les thèmes différents selon les anciennes familles de composants.

**Application :** contrôler systématiquement recherche ouverte, sélection ouverte, menu du compte, calendrier, confirmation et erreur dans les deux thèmes. Le symbole La trace et le principe d’une police embarquée sont conservés. Aucune palette concurrente n’est proposée par ce benchmark.

## Références secondaires déjà étudiées

Ces lectures ont précédé le choix Mercury. Elles documentent des comportements utiles ; elles ne définissent plus une autre direction esthétique. Les pages d’aide sans date ni numéro de version sont datées par leur consultation, **14 octobre 2026**.

| Source officielle | Date ou version connue | Ce qui est établi par la documentation |
|---|---|---|
| [Linear — refonte](https://linear.app/now/how-we-redesigned-the-linear-ui) | 28 mars 2024 ; article historique | Travail conjoint sur navigation, en-têtes, onglets et panneaux ; une refonte ne se réduit pas à changer une table. |
| [Linear — filtres](https://linear.app/docs/filters) et [options d’affichage](https://linear.app/docs/display-options) | Aide consultée le 14 octobre 2026 | Distinction entre filtrer les résultats et modifier leur présentation. Commandes dédiées, raccourcis et valeurs actives éditables. Les filtres dans l’URL de Linear ne se transposent pas aux recherches privées Drivy. |
| [Linear — filtres avancés](https://linear.app/changelog/2026-02-13-advanced-filters-and-share-issues-in-private-teams) | 13 février 2026 | Apparition de groupes AND/OR. Fonction documentée, non nécessaire à l’annuaire Drivy actuel. |
| [Linear — préférences](https://linear.app/docs/account-preferences) | Aide consultée le 14 octobre 2026 | Préférences personnelles séparées et choix clair/sombre/système. |
| [Attio — filtrer et trier](https://attio.com/help/reference/managing-your-data/views/filter-and-sort-views) | Aide consultée le 14 octobre 2026 | Choix d’un attribut, d’une condition puis d’une valeur ; distinction entre modification temporaire et vue enregistrée pour l’équipe. |
| [Attio — tables](https://attio.com/help/reference/managing-your-data/views/create-and-manage-table-views) et [fiches](https://attio.com/help/reference/attio-101/attios-data-model/understanding-records) | Aide consultée le 14 octobre 2026 | Colonnes réglables, recherche de propriété dans le filtre, aperçu et fiche avec identité/attributs. Les actions au seul survol et la grille éditable ne sont pas reprises sans besoin Drivy. |
| [Notion — vues et filtres](https://www.notion.com/help/views-filters-and-sorts) et [mise en page des fiches](https://www.notion.com/help/layouts) | Aide consultée le 14 octobre 2026 | Séparation entre vues, propriétés et contenu d’une fiche ; choix d’ouverture pleine page ou aperçu. Pas de constructeur de base de données à introduire dans Drivy. |
| [Ramp — filtres comptables](https://support.ramp.com/accounting-filters-and-custom-views/) | Aide consultée le 14 octobre 2026 | Recherche/filtre au-dessus de la table, vues enregistrées et barre d’actions seulement après une sélection. Les actions groupées sont liées à de vraies commandes métier. |

### Images officielles identifiées

Liens destinés à la comparaison visuelle, pas à une intégration dans le produit. Les pixels suivants n’ont pas été observés dans la session du rédacteur ; l’agent principal peut compléter la preuve après lecture dans son navigateur.

- [Linear — constructeur de filtre, publication du 13 février 2026](https://webassets.linear.app/images/ornj730p/production/76a0de66dd1198cee29f081030c7437c78098d41-3600x1434.png?auto=format&dpr=2&q=95).
- [Attio — filtre City ouvert](https://attio.com/_next/image?q=75&url=https%3A%2F%2Fa.storyblok.com%2Ff%2F234930%2F1506x936%2Fb3d66694e1%2Funderestanding_records_city.png&w=1920).
- [Attio — table Companies](https://attio.com/_next/image?q=75&url=https%3A%2F%2Fa.storyblok.com%2Ff%2F234930%2F2196x1478%2F7f9fe7f94d%2Fall-records-page.png&w=1920).
- [Ramp — filtre appliqué à la table](https://assets.ramp.com/help-center/accounting-filters-and-custom-views/_attachments/accounting-filter.png).

## Comment juger la prochaine passe

La comparaison doit porter sur une liste Drivy avec noms longs et plus de 25 personnes, un menu de choix ouvert, une fiche, un formulaire réel et une confirmation. Les captures doivent inclure les états fermés, ouverts, sélectionnés, vides, en erreur et au clavier. Les vues de préparation, d’entrée et d’opérateur doivent employer les mêmes propriétaires de composants.

L’évaluation visuelle et les essais fonctionnels restent deux preuves distinctes. Une absence de débordement ou de violation automatique ne valide pas l’adhésion esthétique. Les mesures DOM complémentaires de la démo, les captures de l’implémentation et ses résultats de tests seront consignés par l’agent principal après réalisation ; aucune qualification complète de cette passe n’est revendiquée ici.

## Réalisation des pages de paramètres

Les coordonnées passent en lecture structurée : nom, e-mail et téléphone occupent des lignes avec une proportion initiale 38/62 entre libellé et valeur. « Modifier les coordonnées » ouvre le formulaire dans la page ; la recherche de paramètres ouvre également ce formulaire lorsqu’elle vise un champ `school-*`. Les identifiants des champs, la validation, la garde de brouillon et la commande AP06 sont conservés. La confirmation serveur garde le formulaire ouvert ; Annuler restaure la dernière valeur confirmée même si la relecture scolaire est encore en attente. Terminer ferme un formulaire sans modification.

La confidentialité distingue l’en-tête de la section, l’action de modification, les textes consultables et le contact pour les données. Le dialogue d’adoption et son analyse des conséquences GPS ne changent pas. Les informations demandées utilisent des lignes et les radios du composant partagé `SegmentField` pour les choix courts ; les valeurs `none`, `optional`, `lesson` et `keep`, les explications, la photo facultative et la confirmation d’application sont conservées. Les préférences gardent leurs radios natives et leur persistance de thème ; les aperçus montrent désormais la relation entre rail, titre et lignes du contenu.

La composition locale est dans `settings-studio.css`, limitée à ces pages et aux préférences personnelles. Les couleurs, la police et les contrôles restent sous la responsabilité du système partagé. À petite largeur, les libellés passent au-dessus des valeurs et les options peuvent se répartir sur plusieurs lignes. Les formulaires restent dans le flux, sans action collante susceptible de masquer un champ.

Les règles R74, R76, R77, R80 et R95, les scénarios T163–T174, le contrat `SchoolUpdateCommand` et les décisions sur les textes du 13 octobre ont été relus avant cette tranche. Le typecheck du web passe après les changements de structure ; les essais de fonctionnement et l’inspection visuelle de la nouvelle composition restent à consigner par la campagne de vérification.
