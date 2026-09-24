# Système de design, états et accessibilité

**Application visuelle courante :** [atelier unifié](../DESIGN/APPLICATION.html), incluant la [leçon](../DESIGN/LECON.html). Le même répertoire sert la carte, les agendas, dossiers, bilans, documents et préférences. La direction appréciée reste carte dominante en leçon, bleu, texte simultané limité, surfaces calmes et détails à la demande. Les états critiques restent explicites. Aucun thème de couleur propre à une page n’est ajouté.


> Drivy · Dossier de conception 3.17 · 20 septembre 2026
> Statut : **direction A choisie par le porteur** ; valeurs et détails de rendu de référence à vérifier sur maquettes puis dans Swift. [Index](../README.md).

## Réutilisation contrôlée

Le [répertoire DS01–DS25](../DESIGN/02-composants.md) est la référence d’anatomie ; le [registre par écran](../DESIGN/composants-usage.json) fixe les usages et exceptions. Une nouvelle vue commence par composer ce répertoire. Une nouvelle implémentation d’une fonction déjà couverte nécessite une raison vérifiable, puis une variante réutilisable ou la suppression de l’ancienne implémentation.

La cohérence sémantique prime sur la copie de pixels. Ouvrir un détail, sélectionner une observation et enregistrer immédiatement un statut sont trois conséquences différentes : chevron, sélection explicite ou action sans chevron. Un champ multiligne a la même variante d’édition dans la carte et le bilan. La même ligne de leçon alimente accueil et agenda. Les menus de choix de formation restent cohérents entre dossier et parcours.

La navigation n’est pas un ensemble de raccourcis d’action. Les quatre destinations personnel et les trois destinations élève sont celles de l’[architecture d’information](architecture-information.md). Chaque onglet conserve son contexte ; la carte immersive revient à Séance sans arrêter la capture. L’iPad réutilise destinations et données dans un espace adapté. Les administrateurs ne gagnent pas de droits pédagogiques par une variante visuelle.

## Fondations et statut

Direction de référence : **A · Cartographie native**, choisie par le porteur dans la conversation. Elle remplace la recommandation ivoire/pétrole. Le [dossier DESIGN](../DESIGN/README.md) rassemble les spécifications visuelles et les maquettes. Les valeurs ci-dessous concrétisent cette direction ; elles ne sont ni héritées de l’ancienne app, ni toutes approuvées pixel par pixel. Les règles métier restent dans [Règles métier](../03-fonctionnel/regles-etats.md). Une couleur ne doit jamais modifier le sens d’un statut.

Les exigences de contraste s’appuient sur WCAG 2.2 : contraste du texte usuel 4,5:1 ; grands textes et éléments non textuels pertinents 3:1, avec leurs conditions d’application. Les minima internes proposés pour les contrôles tactiles personnalisés sont 44 points iOS, 48 dp Android et 44 pixels CSS web ; les commandes principales/critiques visent au moins 48 dans leur unité. Ces choix Drivy ne sont ni une citation universelle d’Apple ni une prétention de conformité globale. [S28](../06-gouvernance/sources.md#s28).

## Palette sémantique

| Variable | Clair | Sombre | Usage |
|---|---|---|---|
| `canvas` | `#F7F8FA` | `#10151C` | Fond général |
| `surface` | `#FFFFFF` | `#19222E` | Panneau de lecture opaque |
| `surfaceMuted` | `#EEF2F7` | `#222E3E` | Groupe secondaire |
| `text` | `#18212B` | `#F2F5FA` | Texte principal |
| `muted` | `#536174` | `#B0BCCC` | Métadonnées et aide lisibles |
| `accent` | `#245BD6` | `#91B5FF` | Action primaire, lien et sélection |
| `accentPressed` | `#1947AD` | `#B4CCFF` | Fond primaire pressé |
| `onAccent` | `#FFFFFF` | `#10264D` | Contenu sur action primaire |
| `accentSoft` | `#EAF0FE` | `#233859` | Fond de sélection secondaire |
| `successText` | `#17633D` | `#98DBB4` | Succès confirmé, avec texte |
| `successSurface` | `#E9F5EE` | `#18372A` | Surface de succès |
| `warningText` | `#7A4D00` | `#F2CB83` | Vigilance nécessitant attention |
| `warningSurface` | `#FFF3D6` | `#382D19` | Surface de vigilance |
| `dangerText` | `#B02B37` | `#FFADB4` | Erreur et action destructive |
| `dangerSurface` | `#FDECEF` | `#40252D` | Surface d’erreur |
| `border` | `#D9E0E9` | `#34445A` | Séparation décorative uniquement |
| `controlBorder` | `#78869A` | `#71849D` | Bord de contrôle custom identifiable |
| `disabledText` | `#5D6A7C` | `#B0BCCC` | Texte indisponible, raison séparée |
| `disabledSurface` | `#E8EDF3` | `#222E3E` | Fond indisponible |
| `route` | `#245BD6` | `#91B5FF` | Trait de trajet mesuré, rôle distinct de la marque |
| `routeHalo` | `#FFFFFF` | `#10151C` | Halo de contraste du trajet |
| `mapCanvas` | `#E8EDF2` | `#202A36` | Fond de la carte schématique du prototype uniquement |
| `mapPark` | `#DDEBDF` | `#263B35` | Parc schématique uniquement |
| `mapWater` | `#DCEBFA` | `#203A54` | Eau schématique uniquement |

Le bord clair est un séparateur, pas le contour unique d’un contrôle. Les champs interactifs utilisent le token `controlBorder` à contraste renforcé, et le focus utilise `accent` avec espace de séparation. Les états désactivés gardent un libellé lisible et une explication ; ne pas s’appuyer sur l’opacité seule pour expliquer un refus.

## Vérification calculée des paires prévues

Ces ratios ont été calculés sur les valeurs sRGB opaques du tableau. Ils ne valident pas une interface rendue, une image, une transparence, un dégradé ni tous les états de composants. Arrondis à deux décimales.

| Mode | Premier plan | Arrière-plan | Ratio | Cible interne |
|---|---|---|---|---|
| light | `text` | `canvas` | 15.30:1 | 4.5:1 |
| light | `text` | `surface` | 16.26:1 | 4.5:1 |
| light | `text` | `surfaceMuted` | 14.47:1 | 4.5:1 |
| light | `muted` | `canvas` | 5.93:1 | 4.5:1 |
| light | `muted` | `surface` | 6.31:1 | 4.5:1 |
| light | `muted` | `surfaceMuted` | 5.61:1 | 4.5:1 |
| light | `accent` | `surface` | 5.93:1 | 4.5:1 |
| light | `accent` | `accentSoft` | 5.19:1 | 4.5:1 |
| light | `onAccent` | `accent` | 5.93:1 | 4.5:1 |
| light | `onAccent` | `accentPressed` | 8.25:1 | 4.5:1 |
| light | `successText` | `successSurface` | 6.49:1 | 4.5:1 |
| light | `warningText` | `warningSurface` | 6.59:1 | 4.5:1 |
| light | `dangerText` | `dangerSurface` | 5.67:1 | 4.5:1 |
| light | `dangerText` | `surface` | 6.47:1 | 4.5:1 |
| light | `disabledText` | `disabledSurface` | 4.67:1 | 4.5:1 |
| light | `controlBorder` | `surface` | 3.70:1 | 3:1 |
| light | `controlBorder` | `canvas` | 3.48:1 | 3:1 |
| light | `route` | `routeHalo` | 5.93:1 | 3:1 |
| dark | `text` | `canvas` | 16.77:1 | 4.5:1 |
| dark | `text` | `surface` | 14.67:1 | 4.5:1 |
| dark | `text` | `surfaceMuted` | 12.57:1 | 4.5:1 |
| dark | `muted` | `canvas` | 9.52:1 | 4.5:1 |
| dark | `muted` | `surface` | 8.33:1 | 4.5:1 |
| dark | `muted` | `surfaceMuted` | 7.14:1 | 4.5:1 |
| dark | `accent` | `surface` | 7.83:1 | 4.5:1 |
| dark | `accent` | `accentSoft` | 5.76:1 | 4.5:1 |
| dark | `onAccent` | `accent` | 7.29:1 | 4.5:1 |
| dark | `onAccent` | `accentPressed` | 9.26:1 | 4.5:1 |
| dark | `successText` | `successSurface` | 8.11:1 | 4.5:1 |
| dark | `warningText` | `warningSurface` | 8.76:1 | 4.5:1 |
| dark | `dangerText` | `dangerSurface` | 7.82:1 | 4.5:1 |
| dark | `dangerText` | `surface` | 9.08:1 | 4.5:1 |
| dark | `disabledText` | `disabledSurface` | 7.14:1 | 4.5:1 |
| dark | `controlBorder` | `surface` | 4.19:1 | 3:1 |
| dark | `controlBorder` | `canvas` | 4.79:1 | 3:1 |
| dark | `route` | `routeHalo` | 8.95:1 | 3:1 |

Calcul sans arrondi avant décision ; les valeurs affichées sont arrondies. Le contrôle des textes désactivés est une exigence interne plus prudente, pas une obligation WCAG universelle. Les tokens `map*` illustrent seulement une carte fictive : MapKit conserve son propre fond, ses labels et ses attributions. [Méthode W3C](../06-gouvernance/sources.md#s121).

## Typographie et rythme

Police système : SF via les styles sémantiques SwiftUI sur iOS/iPadOS, police système de la future interface Android, pile `system-ui` sur web. Le corps Apple de référence est 17 pt ; le web démarre à 16 CSS px et les tableaux denses à 14 CSS px, avec zoom/reflow. Les nombres du tableau sont des repères et non des limites à Dynamic Type. [Typographie Apple](../06-gouvernance/sources.md#s120). Aucune police binaire n’est distribuée dans le dossier. Les interfaces utilisent les réglages de taille et de contraste de la plateforme, sans figer une police par écran.

| Rôle | Taille de départ | Interligne indicatif | Usage |
|---|---|---|---|
| Titre de page | 28 | 34 | Une fois par destination, pas dans chaque section. |
| Titre de section | 21 | 27 | Formation, bilan, règlement. |
| Corps | 17 | 25 | Contenu lu et saisie, priorité sur la densité. |
| Label de contrôle | 16 | 22 | Action, valeur de champ, état. |
| Métadonnée | 14 | 20 | Date, source, auteur ; jamais information critique minuscule. |

Ces valeurs sont des points logiques natifs ou pixels CSS selon plateforme, non des pixels physiques. Respecter Dynamic Type/font scaling ; hauteur des blocs liée au contenu. Ne pas tronquer un nom ou une prochaine étape à une ligne sans moyen de lire la totalité. Les horaires utilisent des chiffres tabulaires si disponibles ; le texte pédagogique reste proportionnel.

Échelle d’espacement : 4, 8, 12, 16, 24, 32, 48. Marges mobiles 16 ; section séparée de 24 ; titre et contenu de 12. Coins proposés 12 pour champs personnalisés, 16 pour panneaux de contenu et 24 pour grands panneaux cartographiques ; ces tokens ne remplacent pas la géométrie des contrôles natifs iOS/Android. Pas de gros arrondis ajoutés systématiquement aux contenus. Pas d’ombre sur chaque groupe : une séparation de surface et un espacement suffisent.

## Catalogue des composants

| ID | Composant et anatomie | Variantes | États et règles d’usage |
|---|---|---|---|
| DS01 | En-tête objet : école, titre, catégorie, retour | Compact, large | La catégorie ne disparaît pas dans un bilan multi-permis ; retour préserve brouillon. |
| DS02 | Bouton : texte, icône optionnelle | Primaire, secondaire, destructif | Normal, focus, pressé, en cours, indisponible avec raison. Une action primaire par zone de décision. |
| DS03 | Champ : label permanent, saisie, aide, erreur | Texte court, multiligne, email, montant | Label jamais remplacé par placeholder. Erreur liée au champ et annoncée. |
| DS04 | Ligne de rendez-vous : heure, élève, catégorie, lieu, état | Compacte, détaillée | L’état transport ne remplace pas l’état métier ; toute ligne ouvrable a un libellé complet. |
| DS05 | Badge d’état : symbole et texte | Information, vigilance, erreur, succès | Pas de couleur seule, pas de badge numérique sans signification. |
| DS06 | Sélecteur de formation : catégorie et libellé de cycle | Une formation, plusieurs | Sélection explicite ; aucune fusion des scores ou documents. |
| DS07 | Ligne d’observation : compétence, contexte, niveau, source | Lecture, édition | Trois niveaux textuels et Non observé ; radios/liste, pas de curseur de précision artificielle. |
| DS08 | Bandeau de synchronisation | Local, en attente, conflit, verrouillé | Persistant tant qu’action utile ; indique ce qui n’a pas été envoyé. |
| DS09 | État vide : situation et prochaine action | Première utilisation, filtre sans résultat | Distinguer zéro donnée, filtre restrictif et erreur serveur. |
| DS10 | Erreur de contenu : message et reprise | Champ, section, page | Identifiant technique copiable séparé ; pas de stack trace ni nom d’autre élève. |
| DS11 | Confirmation d’engagement | Réserver, déplacer, annuler, corriger | Récapitulatif avant/après ; bouton nommé par l’action, pas « Oui ». |
| DS12 | Pièce jointe : nom, finalité, taille, état | Permis, bilan, autre document utile | Transfert et contrôle séparés ; pas d’aperçu d’un fichier en quarantaine. |
| DS13 | Journal de règlement | Synthèse et mouvements | Alignement des montants, signe/type explicite, auteur et correction reliée. |
| DS14 | Grille de semaine | Desktop/tablette large | Alternative liste complète ; clavier ; aucun déplacement par drag seul. |
| DS15 | Dialogue/panneau de formulaire | Court modal, page dédiée | Focus initial pertinent, fermeture maîtrisée, piège clavier évité. Long bilan en page, pas petite feuille modale. |
| DS16 | Historique de révisions | Liste datée et comparaison | Lecture de la version courante par défaut ; correction jamais écrasée. |

## États de référence

**Chargement.** Montrer la structure sans données fictives et annoncer le chargement une seule fois. Si une projection valide existe, l’afficher avec date de dernière actualisation ; ne pas masquer une erreur de rafraîchissement derrière un squelette permanent.

**Succès.** Résultat placé dans le contexte, non toast éphémère seul. Une réservation confirmée présente son heure et sa version. Une sauvegarde locale dit « Sur cet appareil ». Une publication serveur dit « Bilan partagé ».

**Erreur.** Message indiquant ce qui n’a pas abouti et ce qui est conservé. Exemple : « Ce créneau vient d’être réservé. Tes autres informations sont conservées. » Ne pas annoncer à tort qu’un moniteur ou un élève est responsable d’une erreur technique.

**Permission refusée.** Expliquer le besoin au moment de l’action et proposer une alternative lorsqu’elle existe. Refuser les photos ne bloque pas la lecture de l’app. La géolocalisation est demandée uniquement au moment d’une capture volontaire, après information et vérification du choix de l’élève ; son refus ouvre la séance sans enregistrement (R41).

**Conflit.** Présenter versions et conséquences dans une page persistante. Le bouton de résolution a une action précise, pas « Forcer » ou « Écraser » sans contexte.

## Accessibilité et adaptation

Cibles principales et critiques personnalisées : au moins 48 points iOS / dp Android / pixels CSS web, avec espaces suffisants pour les actions destructives. Le web doit fonctionner au clavier, avoir des régions sémantiques, labels et ordre logique. Focus visible, replacé après fermeture d’un dialogue et jamais dissimulé sous un pied fixe. Les erreurs de validation sont résumées puis accessibles champ par champ.

À 200 % de texte et sur une largeur de 320 CSS px, les formulaires et bilans se réorganisent sans défilement horizontal de lecture. La grille du planning possède une liste équivalente. Sur grand écran, limiter la largeur du texte à environ 65 caractères moyens ; les panneaux utilitaires n’étirent pas le bilan sur toute la largeur.

Respecter réduction des animations ; transition proposée 120 à 180 ms uniquement lorsqu’elle clarifie un changement, sans effet décoratif continu. Haptique facultatif et jamais unique retour. Tester VoiceOver, TalkBack et lecteur d’écran web sur appareil réel ; les propriétés d’un framework ne valent pas validation.

## Personnalisation des écoles

Nom, logo et coordonnées sont autorisés au pilote. La marque Drivy garde navigation, typographie, contraste et sémantique des couleurs. Pas de CSS libre, fonds personnalisés ni remplacement de la couleur d’erreur. Un logo incompatible avec le fond est placé sur une surface neutre et peut être remplacé par le nom ; la lisibilité prime sur la reproduction de la marque scolaire.

## Microtextes de référence

| Situation | Texte proposé | Texte à éviter |
|---|---|---|
| Brouillon local | « Brouillon sur cet appareil. Pas encore partagé. » | « Enregistré » sans précision. |
| Conflit de réservation | « Ce créneau n’est plus disponible. Choisis un autre horaire. » | « Erreur inconnue ». |
| Pièce en cours d’analyse | « Document reçu, vérification technique en cours. » | « Permis validé ». |
| Contrôle humain en attente | « Ton permis doit encore être vérifié par l’école. » | « Tu peux conduire » déduit du dépôt. |
| Aucun bilan | « Ton premier bilan apparaîtra après une leçon partagée. » | « Progression : 0 % ». |
| Avis email échoué | « Rendez-vous enregistré. L’avis à l’élève n’a pas encore été envoyé. » | « Réservation échouée ». |

Le tutoiement ci-dessus est une proposition rédactionnelle à valider ; les contrats techniques ne dépendent pas de ce choix. Les traductions devront conserver les distinctions métier, pas seulement traduire mot à mot.

## Composants du GPS et des cours

**CaptureStatus** affiche un mot d’état, une icône et l’état de transport séparément. Le bouton d’arrêt reste identifiable sans animation clignotante. **MapTimeline** synchronise position, segment et chronologie ; après geste manuel, le suivi caméra est inactif jusqu’à recentrage explicite. Les transitions ne traversent pas visuellement une lacune comme un trajet mesuré. Réduction des animations : déplacement instantané contrôlé et accès à la liste des observations.

**CourseOffer** est visuellement non bloquant : contour discret/pointillé et libellé « Disponible · Non inscrit ». **CalendarCommitment** possède un rendu plein et « Inscrit ». **CapacityState** utilise « X places restantes » ou « Complet », pas une couleur seule. **SeriesSummary** énumère toutes les dates avant confirmation, y compris sur petit écran. **EntitlementBalance** sépare disponible, réservé et utilisé ; le montant payé reste un composant distinct.

Au pilote, l’identité scolaire personnalisable couvre le nom, le logo et les coordonnées définis par F13. L’accent de Drivy reste fixe ; une couleur propre à chaque école est différée jusqu’à un contrat de configuration et une qualification de contraste explicites. Les contrôles système ne sont pas recolorés arbitrairement.

Les cartes ont un contenu alternatif textuel : début/fin, segments disponibles et observations accessibles dans l’ordre temporel. Les gestes ne constituent jamais l’unique accès au replay. Le trajet enregistré ne doit pas occuper tout l’écran lorsque le texte agrandi requiert un panneau lisible. Le clavier conserve accès aux filtres d’offres et à la liste de dates.

## Carte, signalement et adaptation accessible

« Signaler » est la commande pédagogique primaire de la leçon. Elle reste hors défilement, à emplacement stable dans la zone sûre. Les informations secondaires se replient avant la commande ; taille proposée du prototype : 60 unités logiques minimum, à qualifier. L’ouverture fige l’instant et l’ancre candidate ; catégories puis statut explicite, sans note automatique. Les composants et états sont décrits par E23 et R46, sans nouveau référentiel métier.

Animation proposée : ouverture/fermeture reliée au déclencheur, retour de choix immédiat et repère discret après écriture réussie ; aucun délai réseau masqué par une animation, aucun mouvement récurrent gratuit. Réduire les animations supprime les mouvements décoratifs sans supprimer de contrôle. Réduire la transparence et Augmenter le contraste ont un repli opaque/lisible. [Apple Motion S136](../06-gouvernance/sources.md#s136).

Utiliser les effets système de bord de défilement (`scroll edge`) là où la couche de commandes rencontre effectivement un contenu défilant et où l’API est disponible. Ce n’est pas une consigne de rendre toute carte ou tout formulaire translucide : surfaces de lecture stables et repli opaque conservés. [Apple Layout S135](../06-gouvernance/sources.md#s135).

Les avatars/pastilles ne tronquent pas leurs initiales au texte agrandi : dimension liée à la police ou libellé complet. Montants, dates et nombres passent par les API de localisation avec locale résolue et fuseau métier ; pas de concaténation ni de format figé dans une traduction. Le socle commun E01–E49 couvre VoiceOver, clavier, focus, Dynamic Type et les préférences d’accessibilité ; aucun test navigateur ne valide ces comportements natifs.

Les classes de taille et dimensions utiles guident le natif, les dimensions du conteneur le web. Une fenêtre iPad partagée n’est pas un modèle d’iPhone : la continuité de séance reste identique.

## Adaptation V3 : pas d’interface agrandie artificiellement

Les seuils proposés de composition sont **compact <600, intermédiaire 600–1023, large ≥1024** unités logiques disponibles, non des modèles d’appareil. Le web utilise les pixels CSS, le natif ses unités de layout ; éviter toute conversion d’identité entre pixels physiques, points iOS et dp Android. Le texte agrandi peut imposer un repli avant le seuil.

Carte tablette large : panneau utile 320–400 unités, carte cible minimale 480 ; sinon passer au panneau superposé/repliable. Ne pas réduire les contrôles sous une taille tactile utile pour maintenir un split. Cibles proposées 44 au web/iOS et 48 sur Android, avec espace ; le minimum WCAG 2.2 de 24 CSS et ses exceptions ne doivent pas être confondus avec ces choix [S54](../06-gouvernance/sources.md#s54).

Le calendrier, les dossiers, présences, bilans, documents et paramètres disposent de compositions spécifiques. Une table large peut offrir sélection de colonnes et défilement contenu, mais le titre, les filtres et actions suivent le reflow [S51](../06-gouvernance/sources.md#s51). Les opérations clavier ont une alternative tactile ; aucune information essentielle au survol seulement. Orientation et fenêtrage conservent état et focus [S49](../06-gouvernance/sources.md#s49), [S50](../06-gouvernance/sources.md#s50).

**Composants supplémentaires proposés :** Stepper non bloquant, sauvegarde confirmée, checklist de readiness, FieldPurposeHint, profil photo facultative, table paginée à sélection explicite, ArchiveImpactPanel, BulkJobResults, MetricDefinitionPopover avec alternative clavier, FreshnessLabel, DeviceCapabilityPanel et présentation élève publiée. Chacun possède loading/empty/error/permission/success, pas un unique état visuel.

Couleur d’accent scolaire : non configurable au pilote. La palette de Drivy et les significations d’état restent communes ; voir [F13](../03-fonctionnel/identites-formations.md#f13).

## Application iOS 26/27 et prévention des effets gratuits

Les contrôles système gardent leur sémantique, leur géométrie et leurs adaptations d’accessibilité. Les tokens sont la politique des surfaces Drivy personnalisées ; les tailles minimales et cibles critiques sont distinctes dans [tokens-proposition.json](../annexes/tokens-proposition.json). Les anciennes valeurs génériques 48 et les valeurs par plateforme 44/48 ne sont plus deux normes concurrentes.

Les matériaux natifs sont réservés à une couche de navigation/commande justifiée. Les bilans et données administratives conservent des surfaces de lecture stables. Chaque usage translucide possède un repli opaque ; les ratios sRGB ci-dessus ne certifient pas son contraste sur une carte. [Guide iOS](../04-technique/integration-ios-ipados.md).

[AS01–AS10](qualite-ui-ux-anti-slop.md) et [PX01–PX06](patterns-mobile-parcours.md) complètent le catalogue : rôle du composant, données réelles, visibilité du statut et situations de refus. Aucun effet, chiffre fictif ou texte promotionnel n’est ajouté pour remplir un écran.


La densité du workspace n’impose pas celle de la carte pendant la leçon. Complet/Inscrit/Archivé ne sont jamais distingués par la couleur seule. Les wireframes textuels décrivent des intentions à tester, pas une validation d’ergonomie.

## Mise en œuvre de la direction A

Les [fiches DS](../DESIGN/02-composants.md) complètent l’anatomie et les interactions sans dupliquer les règles serveur. [Cartographie](../DESIGN/03-cartographie.md) fixe traits, interruptions et caméra. [Maquettes et couverture](../DESIGN/04-ecrans-reference.md) distinguent les écrans illustrés des écrans seulement spécifiés.

Ne pas recolorer les contrôles iOS dessinés par le système avec les valeurs de surface custom : les composants natifs, leur contraste accru et leur comportement sous Réduire la transparence priment. Liquid Glass est une couche de commandes, pas un thème de contenu intégral. Les maquettes HTML montrent une surface opaque de référence, pas une simulation fidèle du moteur Liquid Glass. [S118](../06-gouvernance/sources.md#s118), [S119](../06-gouvernance/sources.md#s119).

## Spécification visuelle et composants spécialisés

Le [catalogue détaillé](../DESIGN/02-composants.md) prolonge DS01–DS16 sans les renommer : DS17 état de capture, DS18 chronologie, DS19 offre collective, DS20 dates de série, DS21 droits de pack, DS22 navigation adaptative, DS23 étape d’accueil, DS24 indicateur défini. Les [15 compositions](../DESIGN/04-ecrans-reference.md) les mettent en situation. Les valeurs JSON de ce document sont leur seule palette canonique.

<a id="précisions-vérifiées-en-v39"></a>
## Rendu des états et contenu exact
L’agrandissement de texte de la galerie passe à 200 % pour le contenu, les champs, les labels de choix et les dialogues. Les tailles ne sont pas globalement réduites pour éviter un dépassement. Les erreurs de formulaire gardent une relation explicite au champ ; le retour d’action replace le focus dans le contexte utile. [Texte agrandi S126](../06-gouvernance/sources.md#s126), [dialogue S127](../06-gouvernance/sources.md#s127).

Le contrôle des 36 paires opaques reste inchangé ; aucun nouveau contraste matériel translucide n’est prétendu vérifié. La palette A n’est pas retouchée dans cette passe. Les modèles de saisie et leurs données demeurent distincts du rendu : un remplacement de vue ne réinitialise pas la capture ni une intention réseau durable. [Corrections détaillées](../06-gouvernance/audit-corrections-v3-9.md).

À la frontière d’un contenu réellement défilant, considérer l’effet de bord de défilement système (scroll edge) quand il est disponible dans la cible retenue ; ne pas le réinventer par des ombres décoratives. Une carte ou un panneau fixe n’est pas automatiquement un bord de défilement. Le repli opaque et les réglages d’accessibilité restent nécessaires. [S135](../06-gouvernance/sources.md#s135).
