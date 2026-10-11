# Direction artistique commune : Profil, Élèves, Agenda (11 octobre 2026)

Demande du porteur : que Profil, Élèves et Agenda « appartiennent clairement à la même application » sans devenir identiques. Aujourd’hui garde sa composition propre. On conserve le thème clair, la couleur principale et le thème sombre Soft Charcoal. Branche `claude/da-harmonisation-20261011`, posée sur la PR #12 (qui contient #10 et #11).

## Ce que l’audit a trouvé

Les fondations étaient déjà saines. Les couleurs, les rayons et les espacements passent tous par `DrivyTheme`, `DrivyRadius` et `DrivySpacing`. Il n’y a aucune couleur codée en dur, et les animations passent par `DrivyMotion` et respectent Réduire les animations. Les écarts visibles venaient d’ailleurs : les mêmes fonctions étaient dessinées de plusieurs façons selon l’écran.

| Écart | Où | Effet |
|---|---|---|
| Trois styles de ligne dans une même liste groupée | Profil du moniteur (« Leçons » en `NavigationLink` corps 44 pt, « Préférences de leçon » en bouton sans chevron, lignes du compte en `DrivyNavigationRow` titre 64 pt) ; Paramètres de l’élève (lignes du compte 64 pt, « Trajets » 44 pt) | Hauteurs, graisses et chevrons différents dans une même section |
| Deux composants pour « une ligne qui ouvre » | `SchoolProfileLinkRow` (Profil de l’élève) et `DrivyNavigationRow` | Chevron et détail placés différemment |
| En-tête du compte | Moniteur : posé sur le fond ; élève : dans une cellule | Les deux Profils ne se ressemblaient pas |
| Profil du moniteur et Paramètres de l’élève | Mêmes lignes de compte, mais rangées par sujet chez l’élève et en vrac chez le moniteur | Deux organisations pour le même compte |
| Action en texte refaite à la main | Neuf variantes de « sous-titre semi-gras accent + 44 pt » (Agenda, dossier, démarrage, bilan, progression) | Pressé, désactivé et alignement inégaux |
| Fermeture des feuilles | « Fermer » à gauche dans quinze feuilles, à droite dans six (Compte, Changer d’école, Formation, document, replay, accord GPS) | Le pouce ne sait pas où chercher |
| États | Historique : `ContentUnavailableView` dans une section, à côté d’un `DrivyEmptyState` ; planification : `ProgressView` nus | Vide et attente n’avaient pas la même voix |
| Identité d’une personne en tête de page | Dossier : avatar 48 et espacement 12 ; Profil : avatar 52 et espacement 16 | Deux en-têtes presque identiques |
| Doublons morts | `InlineErrorView` (doublon de `SchoolErrorNotice`, utilisé seulement dans la galerie), `DrivyDestructiveRow` (jamais utilisé) | Deux façons de faire la même chose |
| Valeurs magiques | 97 occurrences de `44` dans les cadres | La cible tactile n’était pas un token |

Ce qui fonctionne et reste tel quel :
- l’Agenda, bande de la semaine et liste du jour sur une page de lecture ;
- la liste des élèves, pleine largeur, avec recherche toujours visible ;
- le dossier, avec l’identité, les gestes fréquents, Leçons et Progression sur place, et la barre d’action en bas ;
- Aujourd’hui, carte et dock, l’exception éditoriale voulue ;
- le partage en deux familles de pages (lecture et liste groupée).

## Règles communes retenues

1. **Deux familles de pages, chacune avec son rythme.** Page de lecture (`ScrollView` + `drivyPageContent`, fond `surface`) : Agenda, Élèves, dossier, trajets. Liste groupée native (`List(.insetGrouped)`/`Form`, fond `canvas`) : Profil, Paramètres, détail d’un permis, historique, formulaires. Aujourd’hui reste à part, sur la carte.
2. **Une ligne s’adapte à sa famille.** `drivyFormRows()` pose `drivyRowContext = .grouped`. Dans une liste groupée, `DrivyNavigationRow`, la déconnexion et Face ID prennent le rythme des Réglages : corps de texte, 44 pt, surbrillance et chevron du système, identiques à un `NavigationLink` voisin. Sur une page de lecture, ils gardent le rythme aéré de Drivy (titre de ligne, 64 pt, surbrillance Drivy). Le chevron est `DrivyRowChevron`.
3. **Graisse d’une ligne.** Une chose (personne, permis, leçon) a un titre de ligne `.headline` et une méta `.subheadline`. Une destination ou un réglage est en `.body`.
4. **Une seule action en texte.** `.buttonStyle(.drivyText)` : encre d’accent, sous-titre semi-gras, 44 pt, pressé estompé, désactivé grisé. Elle sert dans les en-têtes de section, les états vides, « Planifier une leçon », « Aujourd’hui », « Modifier les informations », « Changer », « Voir la leçon ».
5. **Un statut qui attend une réponse est un badge** (`DrivyStatusBadge`, ton alerte) sur la ligne qui y mène. C’est le cas de « Accord GPS · À donner ». Le badge n’est jamais un texte gris à droite.
6. **Une personne en tête de page** a un avatar `DrivyAvatar.pageSize` (52), un espacement `s` et un nom en `.drivyTitle`, aussi bien dans le dossier que dans les deux Profils.
7. **Feuilles.** « Fermer » (ou « Annuler » quand il y a une saisie à abandonner) toujours en `.cancellationAction`, en haut à gauche. Le côté droit est réservé à la confirmation (« Afficher », « Enregistrer », « Fermer » d’un code d’invitation émis).
8. **États.** Un vide dans une page ou une section passe par `DrivyEmptyState`. `ContentUnavailableView` reste réservé à une colonne entière vide (iPad sans sélection, pas d’école). Une attente nommée passe par `DrivyLoadingState` ou un squelette, jamais par un `ProgressView` nu dans une section.
9. **Cible tactile.** `DrivyLayout.tapTarget` (44) remplace tous les littéraux.
10. **Mouvement et haptique.** Rien de nouveau n’est inventé. Les styles partagés portent l’appui (`DrivyMotion.press`, `feedback`), et la bande de la semaine de l’Agenda, qui est un sélecteur, donne un retour de sélection comme les roues du système.

## Profil : décisions

- **Moniteur.** L’en-tête est posé sur le fond. Viennent ensuite Leçons et Préférences de leçon, puis le compte rangé par sujet comme dans les Paramètres de l’élève : « Compte », « Sécurité » (Face ID), puis « Se déconnecter » seul. « Préférences de leçon » ouvre une feuille ; la ligne porte désormais le même chevron que les autres destinations.
- **Élève.** L’en-tête est posé sur le fond, comme chez le moniteur. « Mes informations » forme sa propre section. L’accord GPS en attente est un badge d’alerte.
- Les identifiants d’accessibilité ne changent pas.

## Vérification

- IPA d’essai compilée sur GitHub Actions à chaque lot (runs `38167048200`, `38168268907`, `38168704308`, `38169054910`, tous réussis). La cible de tests n’est pas compilée par ce workflow.
- Captures simulateur iPhone, clair et sombre : avant (run `38166545247`, 12 écrans) et après (runs `38167461062` et `38168706137`). Relues à l’œil : dans le Profil du moniteur, les lignes ont la même graisse et la même hauteur, et chaque destination a son chevron. Les deux Profils posent l’en-tête sur le fond. Les volets « Informations personnelles » et « Mes informations » ont un chevron vers le bas. Dans l’historique, les chevrons sont ceux du système.
- `python scripts/ios/theme-contrast.py` : 141/141 couples sombres conformes, clair inchangé. Le nouveau token `listChevron` est la couleur système `tertiaryLabel`.
- Non exécuté : tests Swift et parcours UI. Restent à qualifier sur appareil : VoiceOver, grand texte, iPad, la surbrillance native des lignes du Profil et l’animation du volet dépliable.

## Ajouts après la première passe

- **Volets dépliables** : `DrivyDisclosureStyle` (`.disclosureGroupStyle(.drivy)`), un chevron vers le bas qui pivote, le même glyphe qu’une compétence de Progression. Le chevron vers l’avant reste réservé à « ouvre ailleurs ». Appliqué au dossier et au Profil de l’élève.
- **Liens natifs** : un `NavigationLink` de liste groupée ne reçoit plus de hauteur minimale, la cellule assure déjà ses 44 pt.
- **Ligne de leçon** : son chevron passe par `DrivyRowChevron`. Dans l’historique, il devient celui du système.

## À valider par le porteur

- Profil du moniteur : le compte est rangé en trois sections (Compte, Sécurité, déconnexion) au lieu d’une.
- Lignes du Profil et des Paramètres plus compactes : 44 pt et corps de texte au lieu de 64 pt et titre de ligne.
- « Fermer » à gauche dans les feuilles Compte, Changer d’école et Formation.

## Dossier en blocs (11 octobre 2026, soir)

Retour du porteur : le dossier « est différent des autres ». La première passe l’avait laissé tel quel, à plat sur fond blanc, avec « Informations personnelles » en lien bleu. Il rejoint la famille des listes groupées, sans devenir une `List` : il garde son défilement, son sélecteur et sa barre d’action.

- Fond `canvas`, identité et gestes de contact posés sur le fond, comme l’en-tête des deux Profils.
- « Informations personnelles » : une ligne blanche qui se déplie sur place, en corps de texte, comme « Mes informations » chez l’élève.
- Leçons : chaque mois dans un bloc blanc sous son titre, comme l’historique des leçons. Progression : en blocs, comme chez l’élève.
- Un seul modificateur pour ces blocs hors `List` : `drivyGroupedBlock()`.

Captures après : [clair](assets/dossier-blocs-20261011/iPhone-dossier-light-synthetic.png), [sombre, plusieurs permis](assets/dossier-blocs-20261011/iPhone-dossier-multi-dark-synthetic.png) (run `38173292134`). IPA d’essai compilée (run `38173288632`). Non exécuté : tests Swift et parcours UI. Non vu : l’onglet Progression du dossier et le volet déplié, que les captures ne montrent pas ; VoiceOver et grand texte.

