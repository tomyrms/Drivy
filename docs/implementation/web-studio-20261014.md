# Portail web — Studio, référence Mercury

Décision de réalisation du 14 octobre 2026, après le rejet de Registre par le porteur et son choix explicite de la [démo Mercury](https://demo.mercury.com). Cette note remplace la direction visuelle web de la passe précédente pour les fichiers modifiés ; elle ne change ni le client Apple, ni les contrats métier. Le [benchmark](web-studio-benchmark-20261014.md) distingue les interactions réellement observées, les mesures DOM et les sources documentaires.

## Direction retenue

Deux voies ont été considérées pour traduire la référence choisie :

| Voie | Composition | Décision |
|---|---|---|
| **Studio proche de Mercury** | Rail calme, titre régulier, fond principal continu, menus ancrés, commandes en capsule, paramètres en lignes, fiche et éditeur à pleine largeur. | Retenue pour reprendre le rythme et les relations entre contenu et commandes appréciés dans la démo. |
| Studio éditorial | Grandes sections de présentation, accents de marque plus présents, cartes pour chaque groupe et formulaires visibles en permanence. | Écartée : les cartes et l’empilement de cadres éloignent les écrans denses de la référence explicitement choisie. |

Il ne s’agit pas d’une copie de banque : les comptes, montants, avatars, vues enregistrées, exports et actions en masse de Mercury ne deviennent pas des fonctions Drivy. La trace reste le symbole de Drivy, le cobalt reste son accent, le sombre reste anthracite. La police web évolue vers **Manrope**, auto-hébergée sous OFL, pour un dessin plus ouvert et proche du rythme observé. Elle remplace Source Sans 3 dans la feuille web principale ; l’audit des usages autorise le retrait des anciens actifs Source Sans 3 et du TTF de conversion inutilisé à l’exécution. Le WOFF2 Manrope, sa licence et sa provenance constituent les actifs de production.

La référence Mercury utilise Arcadia Display/Text et un sombre indigo. Ni ces polices ni cette teinte ne sont importées. Les captures réelles restent des artefacts locaux dans `artifacts/mercury-research-20261014/`, accompagnées du manifeste et d’une galerie ; elles ne sont pas ajoutées aux actifs du produit ou au dépôt public.

## Ce qui change depuis Registre

La passe précédente avait déjà livré des colonnes de données, une pagination locale, le retour au contexte, la protection des brouillons et le traitement des erreurs. Ces acquis ne sont pas présentés comme nouveaux. Studio recompose leur présentation : disparition des barres de navigation horizontales qui répétaient le rail, en-têtes plus simples, identité lisible dans les tables, menus de choix entièrement dessinés et passage des paramètres à la lecture avant édition.

La direction ne se résume pas à des rayons supplémentaires. Elle modifie simultanément l’enveloppe de la console, les proportions de texte, les destinations secondaires, les états ouverts des contrôles, la largeur des fiches et l’usage des formulaires dans les pages de paramètres et du catalogue.

## Fondations réellement déclarées

Les valeurs ci-dessous sont celles de `apps/web/client/styles.css` lors de la réalisation. Ce sont des valeurs CSS, pas des mesures universelles garanties dans tous les navigateurs.

| Usage | Valeur |
|---|---|
| Police | Manrope variable, système en repli ; 200–800 ; chargement local WOFF2 |
| Titre de page | 28 px / 36 px, graisse 450 |
| Titre secondaire | 20 px / 28 px, graisse 500 |
| Section | 16 px / 24 px, graisse 550 |
| Corps | 15 px / 24 px, graisse 400 |
| Texte secondaire et navigation | 14 px / 21 px ; graisse 400 ou 450 suivant le rôle |
| Métadonnées | 13 px / 19,5 px |
| Espacements | 4, 8, 12, 16, 24, 32 et 48 px |
| Rail / barre supérieure | 220 px / hauteur minimale 56 px |
| Champ / contenu / panneau | Rayons 8 / 12 / 14 px |
| Actions primaires et secondaires | Capsule, rayon 999 px ; hauteur de base 40 px |
| Choix dans un formulaire | Déclencheur de 42 px ; menu ancré, rayon 8 px |
| Liste d’élèves | Enveloppe de recherche et commandes proches de 36 px ; les grandes cibles tactiles sont traitées dans les règles responsives |
| Fiche | Contenu de détail borné à 58 rem ; formulaire courant à 36 rem |
| Coordonnées | Lignes libellé/valeur de proportion initiale 38/62 ; empilement sur petit écran |

| Rôle de couleur | Clair | Sombre |
|---|---|---|
| Fond | `#f7f8fa` | `#191b1e` |
| Surface | `#ffffff` | `#222428` |
| Surface atténuée | `#ebedf1` | `#303338` |
| Surface intérieure | `#f5f6f8` | `#1e2024` |
| Texte principal | `#272c36` | `#f2f3f5` |
| Texte secondaire | `#626977` | `#b3b7be` |
| Accent de texte | `#245bd6` | `#91b5ff` |
| Action remplie | `#245bd6` | `#3766d3` |
| Séparation | `#e5e7ec` | `#3c4047` |
| Bord de contrôle | `#858c98` | `#868c95` |

Les surfaces de succès, avertissement et erreur conservent des tokens distincts. Les ombres de superposition appartiennent aux menus ; les tables et sections de paramètres sont principalement séparées par l’espace et des traits. Les petites ombres de contrôle ne servent pas à encadrer chaque bloc de contenu.

Le thème effectif est porté par `html[data-theme='light'|'dark']`, initialisé avant l’affichage par le mécanisme existant. Le repli sans attribut suit `prefers-color-scheme`. Le choix Clair/Sombre/Système est personnel ; il ne change pas la configuration de l’école. Seule cette préférence d’interface est conservée en stockage local, sans dossier ni recherche nominative.

## Navigation et hiérarchie

Le rail garde les tâches Planning, Élèves, Équipe, Formations et tarifs, puis l’entrée Paramètres de l’école. Les destinations de la famille courante apparaissent sous celle-ci : disponibilités et absences, invitations et trajets, tarifs et conditions. Ces liens fonctionnent avec les routes existantes ; l’ouverture dans un autre onglet et les identifiants de contexte sont conservés.

Dans les paramètres, la navigation remplace les tâches métier par **Retour à la gestion**, les réglages de l’école et les préférences personnelles. Elle reprend ainsi la structure observée dans Mercury Company Settings sans reproduire ses rubriques bancaires. La recherche de paramètres reste indexée sur les destinations et champs connus ; elle attend le montage du champ, ouvre son éditeur si nécessaire, puis lui donne le focus.

Sur mobile, Menu déplie la navigation dans le flux. Échap la referme et rend le focus au déclencheur. Le bouton de retour à la liste reste explicite sur les fiches et éditeurs, y compris sur écran large. Les liens de contexte du catalogue conservent permis, origine et sélection utiles ; les valeurs personnelles recherchées ne sont pas inscrites dans l’URL.

`SectionHeading` gère le titre de page et son focus d’arrivée ; son icône optionnelle utilise le vocabulaire Drivy. Lorsqu’une fiche est ouverte, `DetailPanel` reçoit `headingLevel={1}` et le titre de la liste est retiré de la composition. Les sous-sections de cette fiche reprennent les niveaux inférieurs.

## Propriétaires des composants

| Composant | Responsabilité de présentation et de comportement |
|---|---|
| `SelectField`, `choice-field.tsx` | Choix unique avec déclencheur, liste ancrée et sélection explicite. `Select`/`Combobox` de Base UI 1.9.0 portent les comportements de choix. Une recherche temporaire ne change jamais la valeur métier. |
| `SegmentField` | Deux à quatre alternatives directement visibles avec de vrais radios, nom de groupe et clavier natif. Les informations demandées aux élèves et les choix courts du guide l’emploient. |
| `TextField`, `TextArea` | Labels permanents, formats de saisie, états désactivés et erreur associée au champ. |
| `CheckField` | État booléen, label distinct de l’aide et cible cohérente. La confirmation métier garde sa présentation explicite ; le contexte de revue du guide peut porter lui-même la conséquence. |
| `RecordSearch`, `FilterTabs`, `ListPagination` | Recherche nommée, vues réellement disponibles, décompte et navigation locale. Aucun export ou choix multiple de masse n’est ajouté pour imiter Mercury. |
| `SplitView mode='page'` | Maintient la liste et son contexte en mémoire, affiche la fiche ou l’éditeur dans la largeur de la page et restitue le focus au retour. |
| `DetailPanel` | Titre unique, métadonnées, contenu et actions contextuelles d’une fiche. |
| `ConfirmDialog` | Dialogue métier natif, focus et confirmation ; les menus de choix ouverts restent dans sa couche modale. Échap ferme d’abord le menu puis le dialogue. |
| `ThemeControl`, `AccountMenu` | Préférence personnelle, aperçu clair/sombre/système et accès au compte. Le menu de compte conserve des liens et des radios ordinaires. |
| `settings-studio.css` | Composition locale des coordonnées, de la confidentialité, des informations élèves et des aperçus de thème ; réutilise les couleurs et la police partagées. |

Les choix longs sont recherchables automatiquement au-delà de sept options, ou explicitement pour les personnes, formations et versions de catalogue. Le menu conserve l’option désactivée, le cas sans résultat et le cas sans choix. Les erreurs visent le vrai déclencheur ; un groupe désactivé ferme le menu et empêche la modification. Ces comportements doivent rester qualifiés après tout changement de primitive.

## Formulaires et données de l’école

**Coordonnées.** La page commence par des lignes de lecture. « Modifier les coordonnées » ouvre les trois champs dans un formulaire borné. La confirmation serveur garde l’éditeur ouvert ; Annuler restaure la dernière valeur durable même si une relecture scolaire est encore en attente. Terminer ferme un éditeur sans modification. Les identifiants `school-name`, `school-email` et `school-phone`, la validation, If-Match, l’opération idempotente et la garde de navigation ne changent pas.

**Confidentialité.** La lecture des textes, la date d’adoption, le contact et l’action de modification sont distincts. Le dialogue « Relire les textes » conserve la relecture et les conséquences sur les accords GPS et trajets en cours. Les champs demandés passent de la table de contrôles à des lignes avec choix directs ; leurs valeurs `none`, `optional`, `lesson` et `keep` ne changent pas. Aucun choix de présentation ne rend une photo obligatoire ou n’invente un consentement.

**Catalogue.** Référentiels, procédures, offres, conditions et prestations utilisent une table pleine largeur ; révision/version, durée, validité, type et prix sont répartis dans les colonnes utiles à chaque objet. Les éditeurs longs et les versions consultées passent dans `SplitView mode='page'`. Une fiche a son propre titre, ses références historiques et son retour. Les actions persistantes existantes des éditeurs restent désactivées sur petit écran ou faible hauteur pour laisser les champs visibles. Les dialogues de relecture, droits `CONFIGURE_CATALOG`, règles d’approbation et payloads sont conservés.

Les règles R74–R80/R95, les scénarios de configuration et collecte, `SchoolUpdateCommand`, les contrats de catalogue et leurs extensions documentées ont été relus. Les décisions du porteur du 13 octobre sur les textes, les informations demandées et le motif d’approbation priment sur les formulations plus anciennes du canon.

## Preuves disponibles et limites

La référence de comparaison comprend la démo Mercury réellement parcourue, son manifeste local avec URL et horodatage, les captures de menus ouverts et la [publication officielle du 16 mars 2026](https://mercury.com/blog/designing-in-the-open). Les captures Mercury comportent des données de démonstration ; elles ne prouvent pas les comportements d’un compte bancaire authentifié. Les surfaces Linear, Attio, Notion et Ramp restent des références documentaires secondaires, pas des sessions authentifiées observées.

Le typecheck web passe après les tranches paramètres et catalogue. Les premiers pilotes de coordonnées ont été lus en clair et sombre, à 1440 et 390 px ; les champs et actions sont visibles. La campagne de vérification signale les scénarios de coordonnées, refus, validation, conflit, relecture tardive, valeur durable et recherche profonde comme passants. Ces observations ne constituent pas le bilan final de toute la refonte.

Les résultats chiffrés de la campagne complète, les captures finales, le clavier, les contrastes et les limites de reflow sont à compléter par l’agent principal. Une fixture en navigateur ne qualifie ni OIDC/PostgreSQL réels, ni lecteur d’écran physique, ni l’acceptation esthétique du porteur. Aucun résultat Apple, GPS ou batterie n’est revendiqué par cette passe web.
