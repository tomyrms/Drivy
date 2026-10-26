# Passe native — compte, dossier et accès à l’école

Cette passe conserve l’identité native de Drivy. Elle améliore la place des actions, la densité et l’adaptation aux grandes tailles de texte. Les changements concernent dix fichiers de vues ; ni l’API ni les règles de partage ou de persistance ne sont modifiées.

## Références et méthode

`AGENTS.md` et `COMMENCER_ICI.md` ont été lus, ainsi que les règles de profils et de dossier R05–R06 et R17–R20, les dispositions applicables des contrats AP01–AP20, et les scénarios liés aux profils, invitations et lectures de progression. La décision de partage automatique du 28 septembre prévaut sur les anciennes mentions de publication manuelle.

Guides appliqués : `ui-skills-root` et son catalogue SwiftUI, `swiftui-ui-patterns` avec les références Form, List, NavigationStack, split views et theming ; `better-layout` avec regroupement et adaptation ; `better-typography`, `better-writing`, `better-accessibility` et les principes de hiérarchie de `refactoring-ui`. Les contrôles système, les couleurs sémantiques et les composants Drivy sont conservés.

Les captures suivantes ont été ouvertes réellement, sans retouche :

- Dossier iPhone clair, dossier iPad clair et progression iPhone sombre du run `36722303236`, source `9c77dd64298f5417845a042d1c0e1f88961fa2e0`, sous `artifacts/retours-20260930/visual/36722303236/`.
- Profil, saisie du code d’école et accueil d’onboarding iPad clair des preuves `artifacts/review-20260929/gallery-proofs/ui-account-orientation-e720-20260929.json`, source `e720c4579d8e12c6d0aedb7d0ada6f2f529f30a0`.

Ces images documentent des versions précédentes. Le diagnostic a été confronté au code courant ; elles ne qualifient pas le rendu des modifications de cette passe.

## Changements

| Écran | Fichiers | Modification et objectif |
| --- | --- | --- |
| Profil et trajets | `SchoolUI/SchoolProfileTabView.swift`, `SchoolTripsUI/SchoolTripsView.swift` | Le profil regroupe le compte et les destinations utiles. Une entrée « Trajets » ouvre la liste dédiée, avec ses filtres, sa pagination, son actualisation et la réouverture des trajets conservés. Les préférences de leçon sont placées dans le même groupe. Le titre n’est plus répété dans le contenu de la destination. |
| Compte et édition du profil | `SchoolUI/SchoolAccountComponents.swift`, `SchoolProfileUI/SchoolProfileView.swift` | Avatar ramené de 72 à 52 points, masqué aux tailles d’accessibilité. La barre Enregistrer paraît lorsqu’une modification est présente ou pendant l’écriture. Suppression du doublon du libellé de naissance et du placeholder « Facultatif » du téléphone, qui pouvait contredire une règle d’école. Ligne biométrique de 52 points minimum. |
| Onboarding | `SchoolProfileUI/SchoolOnboardingView.swift` | Colonne de formulaire adaptée à l’iPad ; icône et titre réunis sur une rangée. L’illustration prend 44 points au lieu de 88. Les étapes, refus, consentements et demandes de permission restent identiques. |
| Rejoindre une école | `SchoolJoinUI/SchoolCodeJoinView.swift`, `SchoolJoinUI/SchoolJoinView.swift` | Champ du code réduit de 80 à 64 points minimum, police de base de 36 à 28. Dans la confirmation, emblème de l’école et nom sont alignés ensemble, puis les informations suivent. Les choix et accusés de lecture restent inchangés. |
| Code d’invitation | `SchoolInvitationsUI/SchoolInvitationsView.swift` | Le code utilise une ou deux rangées de quatre caractères selon la place disponible. Suppression du rétrécissement de police à 40 % et du filet décoratif. Aux tailles d’accessibilité, police système body monospaced en gras, sans interlettrage ajouté. La valeur complète épelée pour VoiceOver, la copie avec expiration et le partage sont conservés. |
| Dossier d’un élève | `SchoolUI/SchoolBrowserView.swift` | Démarrer et Planifier occupent une barre commune de 52 points minimum, côte à côte puis empilés aux tailles d’accessibilité. La même barre existe pour un dossier à une ou plusieurs formations. Les actions gardent les conditions de rôle, d’école active et d’archivage existantes ; le démarrage passe par le sélecteur de formation existant. Les contacts placent leurs actions sous la valeur aux grandes tailles de texte. |
| Leçons et progression | `SchoolTrainingUI/SchoolTrainingView.swift` | Réduction des espacements entre groupes et de l’avatar. Les filtres et la période forment un libellé qui peut revenir à la ligne. Leur valeur d’accessibilité inclut le tri. Dans les compétences, texte et indicateur passent en disposition verticale aux tailles d’accessibilité ; les niveaux et liens vers la leçon source sont conservés. |

## Accès, interactions et qualification

Les commandes durables, la gestion de demande en attente, la validation de profil et les contrôles serveur restent en place. Les préférences ne s’affichent que pour les rôles déjà prévus. Les boutons de contact restent des liens natifs avec cibles de 44 × 44 points. Les détails du dossier et la visibilité des données privées ne sont pas modifiés.

Identifiants pour la vérification intégrée : `profile-list` reste la liste du profil ; `profile-open-trips` ouvre la destination dont la liste est `trips-list` ; `profile-planning-settings` ouvre les préférences. `learner-start-now`, `learner-plan-lesson` et `invitation-code-value` restent stables. La fixture d’édition doit effectuer une modification avant de chercher le bouton Enregistrer.

`git diff --check` sur les dix fichiers ne signale aucune erreur de contenu, seulement les avertissements de normalisation CRLF habituels. Les vues ont été relues avec leurs appelants. Aucun test Apple, rendu du nouveau code ou essai matériel n’est déclaré par ce lot à ce stade. L’agent principal centralise la compilation, les tests et les captures iPhone/iPad, dont les tailles d’accessibilité. VoiceOver physique, GPS et batterie restent hors de cette revue.

Une seconde lecture indépendante du lot agenda a vérifié les formulaires, prix, conditions de disponibilité et contrôles d’auteur. Un risque de sélection périmée au nouveau Réessayer du démarrage après échec de stockage a été signalé à son propriétaire : le rechargement doit revalider l’élève et ses formations. Ce point est traité dans le lot agenda, sans modification de ces fichiers par le présent lot.

## Revue complémentaire des capacités et raccourcis

Revue en lecture seule des sources après le lancement de la campagne Apple `bdec615`. Les constats ci-dessous ne décrivent pas de nouveaux boutons livrés. Ils séparent les corrections d’interface possibles des circuits métier encore absents.

| Nature | Constat étayé | Conséquence et périmètre de correction |
| --- | --- | --- |
| Défaut UI corrigeable localement | Dans `SchoolTrainingView.swift`, `months(of:)` concatène les groupes des leçons à venir et passées en mode Chronologique. `monthGroups` leur attribue dans les deux cas le même identifiant `année-mois`. `ForEach(months(of:))` et `training-month-…` réutilisent donc cet identifiant lorsqu’un mois contient une leçon future et une leçon réalisée. | Les identités SwiftUI ne sont pas uniques : réutilisation ou déplacement incohérent de vues possible lors d’une actualisation. Préfixer les identifiants par famille de groupe suffit ; aucune évolution serveur n’est nécessaire. Le défaut a été transmis au responsable d’intégration. |
| Raccourci de reprise absent, UI corrigeable avec la route existante | Le moniteur peut fermer son accueil avec « Plus tard » dans `SchoolOnboardingView`. Dans `SchoolRootView`, l’offre automatique est reportée par `SchoolOnboardingDeferral`, tandis que l’action de profil n’est construite que si `ownProfileLearner` existe, donc pour un rôle LEARNER. `SchoolAccountActions` ne contient pas d’action de reprise d’accueil autonome. La reprise dans `SchoolProfileView` ne peut ainsi pas être atteinte par un moniteur sans rôle élève. | Après avoir reporté l’accueil, ce moniteur n’a pas de reprise manuelle depuis le compte. La route `openOnboarding()` et le modèle `.staff` existent déjà. Une action conditionnelle de reprise doit utiliser cette route, sans prétendre ouvrir un profil administratif de moniteur inexistant. Elle nécessite une coordination avec le propriétaire de `SchoolRootView`, pas une nouvelle API. |
| Fonctionnalité future nécessitant le serveur | La photo de dossier est seulement signalée dans `SchoolProfileView`. `SchoolProfileWorkspace.editableFields` exclut explicitement `profilePhotoDocumentId`. Dans `apps/api/src/profiles.ts`, une valeur non nulle de ce champ est refusée par `DOCUMENT_NOT_READY`, avec le message indiquant que dépôt et vérification ne sont pas disponibles. | Ajouter un sélecteur photo seul produirait une action sans issue. L’ajout et le remplacement doivent attendre un circuit documentaire de dépôt et de vérification. La photo reste facultative ; aucun faux contrôle d’envoi n’a été ajouté. |

Les parcours déjà présents ne sont pas comptés comme des manques : retour de la progression vers sa leçon source, filtres mensuels et annuels, renouvellement/révocation d’invitation, copie/partage du code, reprise de demande incertaine et réouverture des trajets disposent d’actions reliées à leurs modèles. L’ouverture administrative d’une formation reste volontairement sur le web (`SchoolBrowserView`, état « Aucune formation »), conformément au partage terrain/bureau. Les observations de cette section sont issues du code ; aucune anomalie d’exécution n’est affirmée sans reproduction.

### Corrections consécutives à la revue

Les deux défauts locaux ont été corrigés après la source Apple `bdec615` :

- Les identifiants de groupe de leçons portent désormais les préfixes `upcoming`, `past` ou `all`. Un mois présent à la fois dans les leçons futures et réalisées ne partage plus son identité SwiftUI ni son identifiant d’accessibilité.
- `SchoolRootView` vérifie l’état de l’accueil avant d’appliquer le report de l’offre automatique. Si le serveur confirme un accueil inachevé pour la personne, l’école, l’appartenance et le type STAFF attendus, « Reprendre l’accueil » apparaît dans le compte du moniteur d’une école active, sans rôle élève. L’action passe par `AccountFollowUp` puis `openOnboarding()`, donc conserve la fermeture préalable de la feuille de compte et les contrôles d’accès. Elle disparaît à la fin de l’accueil et à la déconnexion. Les réponses tardives sont rejetées après changement d’identité ou d’accès ; la portée est vérifiée à nouveau après l’attente d’une présentation modale.

Le test `staffWelcomeResumeRequiresAnUnfinishedResponseForTheCurrentAccount` couvre la réponse STAFF inachevée, la réponse terminée, le mauvais type, une autre appartenance et l’erreur réseau, sans émission de commande. L’agent principal a relié la fixture `profile-tab` à un vrai écran d’accueil STAFF et étendu le test UI retour de Trajets → reprise d’accueil. Ces tests sont ajoutés à la prochaine campagne Apple ; ils ne sont pas déclarés passés par cette mise à jour. Captures ciblées à reprendre : `profile-tab`, `dossier`, `onboarding-staff`. Le champ photo demeure sans contrôle d’envoi.

## Relecture visuelle de la campagne journeys

Seize PNG originaux ont été ouverts individuellement avec `view_image` dans `artifacts/native-ui-20260930/journeys/`. Aucun assemblage ni retouche n’a remplacé leur lecture. Cette campagne précède les deux dernières corrections de raccourci et d’identité mensuelle. Elle est partielle : le job a été interrompu après 42 captures sur 48 ; cette revue ne transforme pas les images présentes en réussite globale du job.

| Fichiers effectivement vus | Constat visible |
| --- | --- |
| `iPhone-learners-light-synthetic.png`, `iPad-learners-light-synthetic.png` | Quatre élèves lisibles, recherche et invitation visibles. Sur iPad, liste et état de sélection vide sont distincts. Aucun nom coupé dans ces données courtes. |
| `iPhone-learner-light-synthetic.png` | Dossier chargé, sélecteur Leçons/Progression, filtre et deux leçons lisibles. Démarrer et Planifier sont côte à côte, alignés à la même hauteur, au-dessus des onglets. |
| `iPad-learner-light-synthetic.png` | La capture s’arrête sur « Chargement de la formation… ». La sélection de l’élève et la barre d’actions sont visibles, mais le dossier chargé n’est pas qualifié. Reprise demandée avec attente explicite d’une leçon ou du filtre. |
| `iPhone-dossier-light-synthetic.png`, `iPad-dossier-light-synthetic.png` | Détail de formation chargé ; groupe À terminer et groupe Septembre lisibles. Aucun recouvrement entre heures, date, lieu, badge et flèche. La fixture ne comporte pas de groupe futur : elle ne démontre pas la correction des IDs identiques d’un même mois. |
| `iPhone-progression-light-synthetic.png`, `iPad-progression-light-synthetic.png` | Compétence observée avec niveau, contexte et date, suivie de deux compétences Pas encore vu. Les trois points et le chevron restent distincts. Sur iPad, l’indicateur est éloigné du texte par la largeur de la liste ; réserve de densité, sans collision visible. |
| `iPhone-learner-home-light-synthetic.png`, `iPad-learner-home-light-synthetic.png` | Onglet Leçons et bouton de compte visibles ; les heures, dates et états restent lisibles. Aucun bouton de démarrage du moniteur n’est montré à l’élève. Le menu de filtre n’est pas ouvert par la capture. |
| `iPhone-learner-progress-light-synthetic.png`, `iPad-learner-progress-light-synthetic.png` | Onglet Progression actif, mêmes niveaux et détails visibles que dans la formation. Aucune anomalie d’alignement certaine avec la barre des onglets. Le lien vers la leçon n’a pas été actionné pendant cette lecture de PNG. |
| `iPhone-profile-tab-light-synthetic.png`, `iPad-profile-tab-light-synthetic.png` | Identité, école, rôles, Trajets, Préférences de leçon et actions du compte sont visibles. Les liens du groupe Leçons sont en graisse normale avec icônes bleues, ceux du compte en gras avec icônes grises : différence de traitement mineure encore visible. La nouvelle reprise d’accueil est postérieure à ces images et doit être recapturée. |
| `iPhone-trips-light-synthetic.png`, `iPad-trips-light-synthetic.png` | Filtre et trois trajets visibles. Le trajet partiel conserve son chevron, le trajet supprimé n’en affiche pas. Titres, durées et badges restent séparés ; aucun recouvrement identifié. |

Bilan limité aux images chargées : aucun texte tronqué ni chevauchement certain identifié dans leur cadrage. Quinze captures permettent une lecture du contenu attendu ; `iPad-learner` prouve seulement l’état de chargement. Les tailles d’accessibilité, le sombre, le paysage, les longs noms, le clavier et les interactions ne sont pas couverts par ces seize PNG. Les fonds vides sous les petites listes ne prouvent pas à eux seuls un défaut de disposition et n’appellent pas d’information de remplissage. Aucun fichier produit n’a été modifié pendant cette relecture.

## Relecture visuelle de la campagne account — iPhone

Les 24 fichiers suivants de `artifacts/native-ui-20260930/account/` ont été ouverts individuellement avec `view_image`. La campagne s’est interrompue après l’iPhone, avant les captures iPad ; ces dernières restent à relire dans leur reprise. `join-link-preview` a également été rouvert seul pour vérifier le rôle et l’intégralité de la notice.

| Fichiers effectivement vus | Constat visible |
| --- | --- |
| `iPhone-sign-in-light-synthetic.png`, `iPhone-sign-in-error-light-synthetic.png`, `iPhone-sign-in-unconfigured-light-synthetic.png` | Message principal et illustrations contenus dans la page. État d’erreur explicite ; absence de connexion annoncée dans la variante non configurée. La présence des contrôles n’est pas une preuve d’authentification réelle. |
| `iPhone-app-lock-light-synthetic.png` | État verrouillé et bouton Déverrouiller lisibles. La capture ne valide ni Face ID ni Touch ID. |
| `iPhone-account-light-synthetic.png`, `iPhone-school-choice-light-synthetic.png`, `iPhone-no-school-light-synthetic.png` | Identité et destinations lisibles ; l’école actuelle a une marque de sélection ; absence d’école avec accès au code. Les actions fictives de la fixture Compte ne prouvent pas les droits ou la navigation du compte réel. |
| `iPhone-profile-light-synthetic.png`, `iPhone-profile-error-light-synthetic.png` | Champs Identité/Contacts et explications visibles sans barre Enregistrer inactive. En erreur, l’avis et Réessayer occupent un groupe distinct. Le clavier, les saisies et le retour après sauvegarde ne sont pas montrés. |
| `iPhone-join-code-light-synthetic.png`, `iPhone-join-code-preview-light-synthetic.png`, `iPhone-join-code-pending-light-synthetic.png`, `iPhone-join-code-confirmed-light-synthetic.png` | Saisie, aperçu école/rôle/permis, demande à vérifier puis confirmation ont chacun un état lisible. Le champ vide désactive Continuer ; la demande incertaine propose une vérification ; la confirmation propose d’ouvrir l’école. Aucun succès réel n’est déduit des données synthétiques. |
| `iPhone-join-link-preview-light-synthetic.png` | École, rôle Élève, adresse masquée, validité, notice, conservation, contact et acquittement sont lisibles. Le bouton Rejoindre reste désactivé avant acquittement. Aucun recouvrement du bouton et de la notice. |
| `iPhone-onboarding-welcome-light-synthetic.png`, `iPhone-onboarding-information-light-synthetic.png` | Titre d’accueil compact, étapes annoncées et sortie Plus tard visibles. Les quatre champs d’information et le lien de notice tiennent dans le cadrage, au-dessus de Continuer. |
| `iPhone-onboarding-formation-light-synthetic.png`, `iPhone-onboarding-gps-light-synthetic.png`, `iPhone-onboarding-review-light-synthetic.png`, `iPhone-onboarding-ready-light-synthetic.png` | Formation à ouvrir, explication GPS de l’élève, relecture puis état terminé sont distincts. Les actions de bas de page n’empiètent pas sur le contenu visible. Ces images de parcours élève ne remplacent pas la capture STAFF attendue après ajout de la reprise. |
| `iPhone-invitations-light-synthetic.png`, `iPhone-invitation-detail-light-synthetic.png` | Les codes valables, utilisés et expirés sont affichés sans chevauchement ; détail avec échéance et actions distinctes de renouvellement/révocation. Réserve UX : les trois intitulés sont identiques « Code élève · Permis B » ; seul l’état les distingue dans cette fixture. Plusieurs codes valables d’un même permis manquent d’un repère secondaire dans la liste. |
| `iPhone-invitation-create-light-synthetic.png`, `iPhone-invitation-code-light-synthetic.png` | Permis et moniteur lisibles ; Créer le code est visible. Le code émis apparaît en entier, avec validité, Partager et Copier. Aucun partage ou presse-papiers réel n’a été exécuté par la lecture. |

Aucun défaut certain de chevauchement ou de texte coupé n’a été relevé sur ces 24 écrans en taille standard. Le blanc des parcours courts est disponible pour le contenu et ne constitue pas une perte de données. Les textes plus longs, le défilement avec clavier, les dialogues système, les grandes tailles de texte et l’iPad ne sont pas qualifiés par cette série. Aucun fichier produit n’a été modifié pendant cette relecture ; la réserve sur les invitations a été transmise au responsable d’intégration.

## Relecture des six captures à grande taille de texte

Six PNG de `artifacts/native-ui-20260930/large-text/` ont été ouverts individuellement avec `view_image`. Les fichiers `visual-device-iPhone.json` et `visual-device-iPad.json` rapportent `accessibility-extra-large` demandé et effectivement configuré. Les appareils annoncés sont iPhone 17 Pro et iPad Air 11 pouces M4 ; la demande de présentation compacte iPad est activée.

| Fichier effectivement vu | Rendu et limite |
| --- | --- |
| `iPhone-learner-dark-synthetic.png` | **Apparence claire malgré le nom du fichier.** Nom et permis lisibles ; les sélecteurs deviennent des menus. Démarrer et Planifier s’empilent et restent entièrement visibles au-dessus des onglets. La leçon continue sous la barre fixe et nécessite un défilement non vérifié par ce PNG. |
| `iPad-learner-dark-synthetic.png` | Apparence sombre, mais dossier capturé pendant « Chargement du dossier… ». Noms de la liste sur plusieurs lignes et boutons empilés lisibles. Les contacts présents ne remplacent pas la qualification du dossier chargé. Nouvelle capture demandée. |
| `iPhone-progression-dark-synthetic.png` | **Apparence claire malgré le nom du fichier.** Niveau, contexte et date reviennent à la ligne ; indicateur et chevron passent sous le texte. Le bas de la liste est hors du cadrage et la légende de fixture occupe le pied de page. Aucun texte horizontalement coupé dans la zone visible. |
| `iPad-progression-dark-synthetic.png` | Apparence sombre effective. Trois compétences, niveaux, contexte, date et points lisibles en disposition verticale. Aucun chevauchement identifié. |
| `iPhone-profile-tab-dark-synthetic.png` | **Apparence claire malgré le nom du fichier.** Identité et école reviennent à la ligne, liens Trajets et Préférences de leçon complets. Les actions du compte commencent sous le cadrage et demandent de faire défiler. La légende « Administration · Moniteur » se coupe avant le point médian ; défaut de finition mineur, sans perte de texte. |
| `iPhone-invitation-code-dark-synthetic.png` | **Apparence claire malgré le nom du fichier.** Code `EXEM-PLE1` entièrement visible sur une ligne. Partager se répartit sur deux lignes ; Copier et la validité restent entiers et dans le cadre. Le repli du code en deux groupes n’est pas exercé par cette largeur et ce code. |

Pas de défaut certain de troncature ou d’action inaccessible identifié dans le cadrage de ces six images. Le sombre n’est établi que sur les deux PNG iPad, dont un état de chargement ; les quatre images iPhone qualifient seulement la grande taille de texte en clair. Cette différence de thème et l’état de chargement ont été signalés immédiatement au responsable d’intégration avant le gel des sources. Les essais de défilement et de lecteur d’écran ne sont pas remplacés par cette lecture. Aucun fichier produit n’a été modifié.
