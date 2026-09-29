# iPad portrait et paysage — agenda, dossiers, leçons et invitations

## Portée et méthode

Revue du 29 septembre 2026 à la demande du porteur : adapter les compositions aux fenêtres iPad, puis les examiner en portrait **et** paysage. Cette note couvre Aujourd’hui, Agenda, départ immédiat, Planning, Élèves, Formation, Progression, Leçon et Invitations. Capture, signalement, replay, compte et onboarding sont suivis par les autres volets de la revue.

Sources relues avec `swiftui-ui-patterns/references/split-views.md`, `better-layout/SKILL.md` et les contrôles d’accessibilité de la passe précédente. Le split natif est conservé pour une sélection liste/détail ; des colonnes de contenu explicites sont utilisées lorsque deux contenus doivent rester visibles ensemble. Les espacements, surfaces et couleurs restent ceux de Drivy. Aucun identifiant de rôle, droit serveur, calcul métier ou contenu privé n’est modifié par cette passe.

Les rendus `ed56802` de la passe précédente prouvent seulement les écrans et dimensions qu’ils montrent. Les **32 captures** des nouvelles compositions sur la source `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0` ont été inspectées individuellement : Home `36584376304` et Office `36584383615`, iPad Pro 13, portrait et paysage réels, apparence claire. Les inventaires et limites figurent ci-dessous.

## Corrections de composition

| Gravité | Source | Avant | Après | Pourquoi |
| --- | --- | --- | --- | --- |
| MEDIUM | `apps/ios/Drivy/SchoolUI/SchoolTodayView.swift:47` | Carte et panneau inférieur identiques sur les fenêtres larges ; ouvrir toutes les leçons accroissait la hauteur du panneau. | Dès 960 pt disponibles, panneau de leçons défilant de 380 pt à côté de la carte. Sous ce seuil, hauteur du contenu mesurée, panneau inférieur défilant limité à 66 % de la hauteur disponible. | Garder la carte et les actions accessibles ; la composition dépend de l’espace disponible et non du nom de l’appareil. |
| MEDIUM | `apps/ios/Drivy/SchoolAgendaUI/SchoolAgendaView.swift:49` | Semaine, filtres et rendez-vous défilaient dans une seule colonne centrée sur toutes les largeurs. | Dès 1000 pt, semaine et filtre dans une colonne de 388 pt, contenu intérieur de 340 pt ; liste du jour à côté, défilement indépendant. Sinon, flux unique centré de 800 pt maximum. | Conserver le contexte du jour pendant la lecture des rendez-vous ; sept cibles de jour de 44 pt tiennent dans la colonne. |
| MEDIUM | `apps/ios/Drivy/SchoolUI/SchoolBrowserView.swift:15`, `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationsView.swift:17` | Navigation liste/détail automatique ; listes autorisées à prendre respectivement 440 et 460 pt. | Split équilibré ; listes plafonnées à 360 pt pour les élèves et 380 pt pour les invitations. Le système conserve la navigation compacte lorsqu’une fenêtre ne permet plus le split. | Réserver une vraie largeur au dossier ou au détail sans reconstruire le comportement de sélection natif. |
| MEDIUM | `apps/ios/Drivy/SchoolTrainingUI/SchoolTrainingView.swift:94` | Leçons et progression accessibles seulement par un sélecteur, même dans un détail très large. | Dès 1040 pt dans le contenu réel, leçons et progression côte à côte, chacune défilante. Dans un détail étroit, le sélecteur reste en place. Une section imposée par un onglet garde sa présentation dédiée. | Comparer l’historique et les compétences sans allonger les lignes de texte ni ajouter une deuxième navigation. |
| MEDIUM | `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonReportView.swift:182` | Le trajet et les observations repoussaient le bilan sous la ligne de flottaison sur les vues larges. | Leçon réalisée avec bilan : contexte/trajet dans 380 pt, bilan dans la largeur restante dès 900 pt disponibles. Les deux panneaux défilent. Sinon, formulaire unique de 820 pt maximum. | Garder le trajet à portée pendant la rédaction. Le seuil laisse au moins 520 pt au formulaire avant ses marges natives. |
| MEDIUM | `SchoolLessonReportView.swift:46`, `SchoolInvitationsView.swift:83`, `SchoolTrainingView.swift:21` | La présentation modale automatique pouvait conserver la largeur d’un petit formulaire. | Les fiches de leçon, invitations et formation demandent une présentation `.page`. La décision de passer en colonnes utilise ensuite la largeur réellement accordée par le système. | Rendre la composition large atteignable en usage réel, tout en respectant le fenêtrage iPad. La largeur finale doit être vérifiée en capture. |
| MEDIUM | `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningView.swift:60`, `apps/ios/Drivy/SchoolLessonReportUI/SchoolLessonCompletionSheet.swift:89` | Valeurs secondaires `LabeledContent` gris système ; défaut mesuré à environ 3,44:1 sur une capture originale de Tarif. | Les neuf valeurs concernées utilisent explicitement `DrivyTheme.muted`, comme les autres valeurs secondaires du produit. | Corriger la même cause dans Planning et Tarif sans changer leurs textes ou leur structure. Nouveau rendu du prix mesuré à 6,31:1 sur l’original e720 portrait. |
| MEDIUM | `apps/ios/Drivy/SchoolInvitationsUI/SchoolInvitationsView.swift:41` | Les captures `invitation-detail` e720 révèlent un titre sombre sur la sélection native bleue : 2,74:1 mesuré. | La sélection utilise le motif existant d’Élèves : fond `accentSoft` et `DrivyEntityRow(isSelected:)`. | Conserver la sélection native avec une paire de couleurs prévue pour celle-ci. Correction postérieure à e720 ; compilation et nouveau rendu non vérifiés ici. |

Les branches larges sont désactivées pour les tailles Dynamic Type d’accessibilité. Les modèles, sélections de jour, sélection d’élève, contenus du bilan et routes de présentation restent possédés au-dessus des branches de composition. Une rotation ne crée pas un nouveau modèle et ne constitue pas un motif de relecture ou d’abandon d’une commande.

Apple décrit `.page` comme une taille adaptée au contenu de consultation et de composition, avec un minimum défini par la plateforme. Ce n’est pas une garantie de largeur de 900 pt : [PagePresentationSizing](https://developer.apple.com/documentation/swiftui/pagepresentationsizing). Si une feuille reste plus étroite, le formulaire vertical demeure fonctionnel ; les captures doivent établir quelles compositions sont effectivement atteintes.

## Écrans conservés en une colonne

| Écran / variante | Décision fondée sur les sources | Vérification requise |
| --- | --- | --- |
| Démarrer une leçon | Petit formulaire Élève / Formation éventuelle / Lieu, largeur maximale 820 pt ; action dans une zone fixe tenant compte de la safe area. Une deuxième colonne n’apporte pas d’information utile. | Fenêtre étroite, clavier et absence d’affectation ; pas de fixture dédiée dans ce lot. |
| Planifier / déplacer | Séquence dépendante élève → formation → prestation → rendez-vous ; conserver le `Form` centré, maximum 820 pt et action fixe. | `planning` dans les deux orientations ; le déplacement et ses motifs ne sont pas exercés par cette fixture. |
| Annuler une leçon | Motif et action destructive dans le même formulaire court. | Présentation réelle, clavier et confirmation ; non couverts par `planning`. |
| Progression seule | Niveaux et contextes dans une colonne de lecture de 720 pt maximum. La page Formation peut la mettre à côté des leçons ; l’onglet Progression garde sa propre liste. | `progression` dans les deux orientations ; vérifier les longs contextes et la plus grande police séparément. |
| Leçon planifiée | Objectifs, notes privées et souhait dans un formulaire unique de 820 pt maximum ; bouton principal fixe. | `lesson-planned`, portrait/paysage ; absence de clavier dans la capture statique. |
| Permis manquant à la clôture | Formulaire court dédié à l’exception, largeur maximum 820 pt. Aucune deuxième colonne, aucune nouvelle saisie d’heure. | Exception non couverte par `lesson-finish`, dont le permis est validé. |
| Tarif | Deux valeurs, présentation secondaire et largeur bornée. | `lesson-tariff`, portrait/paysage et contrôle du contraste corrigé. |
| Dossier avec plusieurs formations | En-tête, choix de formation et coordonnées secondaires dans le détail du split ; largeur de lecture maximale 720 pt. | La fixture `learner` couvre une formation. Plusieurs formations et coordonnées longues restent à exercer. |
| Création d’un code | Choix de permis et du moniteur dans un formulaire unique, maximum 820 pt ; action fixe. | `invitation-create`, portrait/paysage et dépendances absentes séparément. |
| Code créé | Code et deux actions centrés, largeur maximum 560 pt ; défilement disponible. | `invitation-code`, portrait/paysage ; copie, partage et restitution vocale restent des interactions distinctes. |
| Révocation d’invitation | Conséquence et motif dans un formulaire unique, maximum 820 pt ; confirmation destructive. | Non couverte par la capture du détail ; exercer la présentation et le clavier séparément. |

## Matrice de capture et interaction

Chaque ligne doit être rendue sur le simulateur iPad en orientation effective portrait et paysage. Un nom de fichier contenant une orientation ne remplace pas son contrôle par dimensions et affichage réel. Les captures restent originales, sans recadrage destiné à masquer un défaut.

| Fixture | Surface réelle examinée | Point à vérifier dans les deux orientations |
| --- | --- | --- |
| `home-tabs` | Aujourd’hui dans les vrais onglets | Carte + panneau côte à côte quand la largeur le permet ; aucune action cachée sous les barres. Ouvrir « Leçons du jour » dans une interaction supplémentaire. |
| `agenda` | Agenda dans les vrais onglets | Sept jours entiers, filtre accessible, liste suffisamment large, date et Planifier sans collision. |
| `learners` | Liste Élèves + état de détail initial | Équilibre liste/détail, recherche et commandes de barre sans troncature bloquante. |
| `learner` | Élève sélectionné dans le split | Historique lisible dans la largeur restante et sélection conservée à la rotation. |
| `dossier` | Formation ouverte séparément | Leçons et progression côte à côte si le contenu dépasse 1040 pt ; sinon sélecteur complet. |
| `progression` | Progression dédiée | Colonne de lecture bornée, niveau et contexte entiers, accès à la leçon source. |
| `planning` | Formulaire de planification | Valeurs contrastées, calendrier et champ de lieu sans coupe, action accessible. |
| `lesson` | Leçon réalisée et bilan auteur | Répartition contexte / rédaction dès 900 pt ; carte et les trois textes accessibles ; barre d’enregistrement complète. |
| `lesson-planned` | Objectifs avant la leçon | Formulaire centré, action du bas accessible. |
| `lesson-finish` | Leçon présentée dans une vraie feuille | Largeur effective de `.page`, fermeture après bilan vide par le test interactif distinct. |
| `lesson-modal` | Leçon déjà réalisée présentée dans la même vraie feuille | Fixture ajoutée après `e720c45`, sans commande : largeur effective de `.page` pour le bilan, seuil des deux colonnes dans la présentation modale et non uniquement dans le harnais plein écran. |
| `lesson-tariff` | Tarif secondaire | Prix et solde lisibles et contrastés, bouton Fermer accessible. |
| `invitations` | Liste d’invitations | Liste et détail vide équilibrés ; accès création. |
| `invitation-detail` | Invitation choisie dans le vrai split | Nouveau fixture : sélection d’une invitation synthétique après chargement. Détail, échéance, Nouveau code et Révoquer visibles ou accessibles par défilement. |
| `invitation-create` | Créer un code | Permis, moniteur, message d’indisponibilité et action accessible. |
| `invitation-code` | Résultat code synthétique | Code entier, actions Partager/Copier et marges cohérentes. |

`SchoolOfficeVisualReview.swift` utilise uniquement le transport `visual.drivy.invalid` sous `DEBUG && targetEnvironment(simulator)`. Le nouveau détail ne génère pas de commande ni de véritable invitation. Aucun nouvel échantillon GPS n’est ajouté.

## État de vérification de ce lot

- Relecture des sources des écrans ci-dessus effectuée ; modèle d’état, propriété de la sélection et accès aux actions vérifiés par inspection.
- `git diff --check` exécuté sans erreur de whitespace sur le lot.
- Test `LayoutContinuityTests.testUnsavedReportTextSurvivesPortraitLandscapeAndBack` ajouté après le snapshot `e720c45` : saisie dans le champ accessible « Travail réalisé », portrait → paysage → portrait, comparaison exacte du texte à chaque rotation, sans sauvegarde. Il utilise la vraie fixture `lesson` et la vraie orientation de fenêtre, sans état produit de test. Exécution Apple **non vérifiée** à ce stade. Un iPad de 11 pouces est nécessaire pour garantir le franchissement du seuil de 900 pt ; le 13 pouces plein écran peut rester en deux colonnes dans les deux orientations.
- Compilation de l’application et des cibles de tests sur Apple passée pour `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0`, étape 5 du run `36584364280`, terminée le 29 septembre à 14:42:09 UTC. Ce résultat ne dit pas encore que les tests ou les captures sont passés.
- Contrelecture de l’attachement Apple `artifacts/review-20260929/native-field-tests/e720/test-reports/iPadTests/attachments/33CE8B64-B601-4ADD-A40F-B3DB7FB02541.png` (2064 × 2752) : vraie feuille `.page` après « Terminer » sur iPad Pro 13 portrait. Deux colonnes effectives, trois textes facultatifs, cinq compétences dont Anticipation et bouton d’enregistrement complets. Aucun défaut de composition bloquant sur cet état précis. Le message de solde indisponible appartient aux données synthétiques de cette fixture. Cette image ne qualifie pas encore le paysage ni l’iPad 11 pouces.
- Les nouvelles compositions Pro 13 sont examinées dans les 32 captures ci-dessous ; le contraste corrigé de Tarif est mesuré. Tailles Dynamic Type d’accessibilité, clavier, fenêtre iPad étroite et rotation pendant une saisie restent des vérifications distinctes, **non qualifiées par ces captures**.
- GPS, batterie, VoiceOver et matériel physique : **non vérifiés** et hors portée d’une capture simulateur.

## Inspection des 14 rendus Home sur Pro 13

Run `36584376304`, source `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0`, apparence claire : les **14 originaux** du dossier `artifacts/review-20260929/ipad-oriented/36584376304/test-reports/Visual-iPad-light/attachments/` ont été ouverts et inspectés individuellement. Sept écrans, chacun en portrait et paysage. L’association nom lisible / fichier UUID vient du `manifest.json` Apple du même dossier.

Inventaire vérifiable : [preuve Home iPad](proofs/ui-ipad-home-e720-20260929.json), avec SHA-256, dimensions de stockage et d’affichage, tag d’orientation et verdict par fichier. Le `summary.json` Apple confirme un test passé, zéro échec et zéro test ignoré.

Le test XCTest de capture est passé (un test, zéro échec, 322,112 secondes) et a produit ses 14 attachements. Le job global est en échec **après** cette capture : le premier exporteur comparait uniquement les dimensions IHDR du PNG. Les PNG paysage conservent un stockage de 2064 × 2752 pixels et un tag TIFF `eXIf` d’orientation 8 ; les dimensions d’affichage sont donc 2752 × 2064. `view_image` présente les originaux en paysage avec du texte horizontal. Ce diagnostic a été transmis au propriétaire du script ; aucune rotation de fichier ni aucun réencodage n’a été appliqué. L’échec d’export ne constitue pas un défaut de mise en page de l’app.

| Écran | Portrait inspecté | Paysage inspecté | Résultat observé |
| --- | --- | --- | --- |
| Aujourd’hui | Oui | Oui | Carte visible à côté du panneau de leçon ; action Terminer et ouverture des leçons du jour complètes. Le volet déplié n’est pas montré dans ces deux captures. |
| Agenda | Oui | Oui | Sept jours entiers, mois/flèches/filtre complets ; rendez-vous et action Planifier lisibles dans la colonne voisine. |
| Liste Élèves | Oui | Oui | Recherche et quatre élèves lisibles ; détail sans sélection correctement présenté dans sa propre colonne. |
| Élève sélectionné | Oui | Oui | Portrait : sélecteur Leçons/Progression dans le détail. Paysage : historique et progression côte à côte à côté de la liste. Action Planifier entière dans les deux cas. |
| Formation | Oui | Oui | Portrait : colonne centrée et sélecteur. Paysage : deux colonnes, niveaux et contextes lisibles. |
| Progression seule | Oui | Oui | Colonne de lecture centrée ; contexte, date, niveaux et lien à la leçon source visibles. |
| Trajets | Oui | Oui | Trois états de capture lisibles avec les actions de ligne disponibles ; aucune troncature bloquante constatée. Surface relue visuellement sans modification de son code dans ce lot. |

Aucun défaut de composition bloquant n’a été observé sur ces 14 états. Les fenêtres plus étroites, les grandes tailles de texte et le clavier restent des vérifications distinctes : ce résultat n’est pas une approbation générale de tous les écrans iPad.

## Inspection des 18 rendus Office sur Pro 13

Run `36584383615`, même source e720 et apparence claire : les **18 originaux** du dossier `artifacts/review-20260929/ipad-oriented/36584383615/test-reports/Visual-iPad-light/attachments/` ont été ouverts et inspectés individuellement. Neuf écrans, chacun en portrait et paysage. Le `summary.json` Apple confirme un test passé, zéro échec et zéro ignoré ; le job a échoué dans l’export pour la même lecture incomplète de l’orientation EXIF que Home. Les 18 images sont exploitables dans leur orientation d’affichage, sans modification de leurs octets.

Inventaire : [preuve Office iPad](proofs/ui-ipad-office-e720-20260929.json), dimensions de stockage/d’affichage, orientation, SHA-256, défaut constaté et mesure de contraste du tarif.

| Écran | Portrait inspecté | Paysage inspecté | Résultat observé |
| --- | --- | --- | --- |
| Bilan de leçon | Oui | Oui | Contexte et rédaction en deux colonnes sur les deux orientations du Pro 13 ; les trois textes, cinq compétences dont Anticipation, replay et bouton d’enregistrement sont lisibles. |
| Leçon prévue | Oui | Oui | Formulaire centré ; objectifs, notes privées et souhait visibles ; Terminer reste entier. |
| Leçon dans une vraie feuille | Oui | Oui | Présentation `.page` effective avant la clôture, formulaire et action complets. L’état après Terminer est confirmé par la capture FieldFlow portrait citée plus haut, pas par cette fixture statique. |
| Tarif | Oui | Oui | Deux valeurs et Fermer entiers. Couleur `#536174` sur blanc mesurée pour Prix convenu dans le PNG portrait : 6,31:1. |
| Planning | Oui | Oui | Formulaire borné ; valeurs et dates lisibles, bouton et motif de désactivation complets. En paysage, la suite du formulaire demande un défilement natif ; cette interaction n’est pas exercée par l’image. |
| Liste Invitations | Oui | Oui | Liste, création et état de détail sans sélection complets ; états Utilisé et Expiré distingués par texte et symbole. |
| Détail Invitation | Oui | Oui | Échéance, Nouveau code et Révoquer sont accessibles. Défaut de contraste de la ligne sélectionnée confirmé ; correction ciblée décrite ci-dessous. |
| Création Invitation | Oui | Oui | Permis et moniteur dans une colonne bornée, action Créer le code complète. |
| Code créé | Oui | Oui | Code synthétique entier et actions Partager/Copier centrées dans une largeur de lecture adaptée. |

Le seul défaut supplémentaire vérifié est la ligne sélectionnée dans `invitation-detail` : pixels de texte `#18212B` sur fond `#245BD6` dans le portrait `0D58943F-9216-4007-8955-C8C7E9B51D50.png`, zone de stockage x170–620, y280–380, contraste 2,74:1. `SchoolInvitationsView` passe désormais la sélection au composant et utilise `accentSoft`, comme la liste Élèves déjà inspectée. Cette correction n’ajoute aucun état métier ni changement de navigation. Son nouveau rendu doit être recapturé ; les PNG e720 restent la preuve du défaut avant correction.

Le tarif a été mesuré sans modifier son fichier : `5E1C748B-5A4E-4F62-95EE-85B66EBE822D.png`, zone de stockage x1580–1780, y260–320. Les pixels intérieurs du texte sont `#536174`, le fond `#FFFFFF`, rapport 6,3066:1. Cette mesure confirme la correction ciblée du prix ; elle ne représente pas une certification de tous les contrastes de l’application.

## Contrôle ciblé de la sélection d’invitation

Correction intégrée à `be768134ddaaada0b437cfd8cbd4558542c25b5a`. Recapture ciblée lancée dans le run `36588826160` : uniquement `invitation-detail`, iPad Air 11 demandé par `visual_compact_ipad=true`, portrait et paysage, apparences claire et sombre, soit quatre PNG attendus. Inspection et mesure du rendu **en attente** ; aucune nouvelle campagne globale déclenchée.
