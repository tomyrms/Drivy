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

- IPA d’essai compilée sur GitHub Actions (voir STATUS.md).
- Captures simulateur iPhone clair et sombre, avant (run `38166545247`) et après : voir STATUS.md.
- `python scripts/ios/theme-contrast.py` : aucune valeur claire ne bouge. Le nouveau token `listChevron` est la couleur système `tertiaryLabel`.
- Reste à qualifier sur appareil : VoiceOver, grand texte, iPad, et la surbrillance native des lignes du Profil.

## À valider par le porteur

- Profil du moniteur : le compte est rangé en trois sections (Compte, Sécurité, déconnexion) au lieu d’une.
- Lignes du Profil et des Paramètres plus compactes : 44 pt et corps de texte au lieu de 64 pt et titre de ligne.
- « Fermer » à gauche dans les feuilles Compte, Changer d’école et Formation.
