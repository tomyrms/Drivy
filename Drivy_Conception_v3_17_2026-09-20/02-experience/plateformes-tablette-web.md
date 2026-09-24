# Une expérience cohérente sur téléphone, tablette et web

> Drivy · Référence de conception 3.14 · 20 septembre 2026
> Exigences du porteur intégrées ; choix détaillés proposés, à valider. [Index](../README.md).

## Décision de produit

**Un produit, deux clients, plusieurs compositions.** L’app native sert la séance et la mobilité ; le web sert le travail détaillé au bureau. Le dossier, les offres, les inscriptions, les droits et les règles sont communs. La tablette a sa propre composition dans l’app, pas une seconde base ni un abonnement fonctionnel distinct supposé.

Le pilote recommandé comprend **iPhone, iPad et web**. Android téléphone/tablette est prévu dans les contrats et l’UX, mais sa disponibilité dépend d’une qualification propre et des ressources confirmées. Le choix de commencer sur Apple est une recommandation de lancement, pas une nouvelle restriction de la vision produit. La tablette Apple doit franchir les gates en même temps que l’iPhone, et non après le pilote.

## Répartition fonctionnelle

| Travail | App téléphone | App tablette | Web connecté |
|---|---|---|---|
| Accueil élève, informations et documents | Parcours progressif | Même parcours, largeur limitée de formulaire | Même progression et mêmes validations ; installation non obligatoire. |
| Configuration de l’école | Étapes essentielles accessibles | Parcours complet au toucher/clavier | Support recommandé pour la configuration détaillée. |
| Agenda et cours collectifs | Jour/liste et inscriptions | Semaine + détail, présences lisibles | Vue détaillée, édition de série et gestion des inscrits. |
| Préparer/réaliser une leçon | Cœur | Cœur, ergonomie spécifique | Préparation, résultat et bilan ; pas de capture de fond. |
| Capture GPS | Appareil qualifié du moniteur | Appareil qualifié du moniteur | Hors périmètre de collecte ; pas de bouton trompeur. |
| Replay et bilan | Lecture et édition autorisées | Carte + observations, utile à deux à l’arrêt | Consultation/édition autorisées, pas de suivi live de l’équipe. |
| Gestion des élèves | Recherche et actions unitaires | Liste + fiche, actions unitaires | Recherche avancée, fiche détaillée et archivage par sélection. |
| Statistiques | Synthèse autorisée et lien web | Synthèse et détail tactile | Filtres, définitions, détails et export autorisé. |
| Archivage | Un dossier après prévisualisation | Un dossier après prévisualisation | Un dossier ou sélection bornée avec résultats par ligne. |
| Données sans réseau | Cache/brouillons/capture déjà autorisée selon F12/F15 | Identique, sans promesse de carte entièrement offline | Pas de persistance de dossier hors ligne. |

« Web admin » est le nom d’usage du poste de gestion, pas un rôle technique accordé à tous les moniteurs. Le moniteur non administrateur ne voit que ses périmètres. L’élève peut accéder à son onboarding et aux fonctions personnelles web sans entrer dans l’espace du personnel.

## Compositions selon la fenêtre, pas selon l’étiquette de l’appareil

Seuils proposés en unités logiques : **compact < 600**, **intermédiaire 600–1023**, **large ≥ 1024**. Ce sont des variables ajustables après tests, pas des normes réglementaires. Une police agrandie ou une fenêtre courte peut forcer une composition plus simple même au-dessus d’un seuil.

| Contexte | Composition et comportement |
|---|---|
| Compact | Une tâche principale ; navigation basse dans l’app, menu replié sur le web ; formulaires centrés, jamais étirés sur une largeur inutile. |
| Intermédiaire | Rail si espace suffisant ; liste et détail alternés ou panneau temporaire. Priorité au contenu actif, pas au maintien de deux colonnes trop étroites. |
| Large | Rail latéral, liste/détail ou contenu/panneau ; tableau de gestion avec en-tête fixe dans son conteneur. |
| Clavier virtuel visible | Champ et erreur visibles ; pied d’action déplacé au-dessus du clavier ou dans le flux ; aucun bouton masqué. |
| Zoom ou texte agrandi | Redistribuer les blocs ; détails d’une ligne accessibles dans une fiche ; la page ne devient pas un vaste tableau horizontal. |

La règle canonique est [R82](../03-fonctionnel/regles-etats.md#r82). Les références externes sont [S49–S54](../06-gouvernance/sources.md#s49).

## GPS tablette : composition prioritaire

Les compositions utilisent les classes de taille horizontale et verticale et l’espace réellement disponible, jamais l’orientation comme condition d’entrée. En largeur régulière, carte et contexte sont côte à côte tant que la carte conserve environ 480 unités utiles. En largeur compacte ou hauteur contrainte, y compris Split View, le contexte devient un panneau temporaire. Fenêtre redimensionnable, rotation et changement de classe conservent capture, intention de signalement, observations et caméra manuelle. [Source Apple S135](../06-gouvernance/sources.md#s135).

L’en-tête contient identité de séance, durée de séance et **état de capture explicite**. Le réseau, la qualité de localisation et l’état d’envoi sont trois indicateurs distincts. L’arrêt demeure trouvable dans tous les formats, y compris en plein écran carte. Aucun enregistrement ne commence à l’apparition de la vue.

En largeur compacte ou hauteur contrainte, objectifs et détails deviennent un panneau temporaire. La carte et les commandes essentielles conservent leur accès, sans décision fondée sur l’orientation.

Le mode présentation du bilan montre **uniquement la révision publiée et ses éléments partagés**, avec absence de commandes administratives. Revenir à l’espace moniteur est explicite. Ce mode évite d’afficher une note privée quand la tablette est montrée à l’élève ; il ne transforme pas l’appareil en session authentifiée de l’élève.

## Tablette en dehors du GPS

**Agenda :** semaine à gauche et détail sélectionné à droite si la place le permet ; réservation/inscription toujours confirmée serveur. **Élèves :** recherche persistante et fiche ; changer d’élève ne conserve pas la note privée du précédent. **Cours :** série et toutes ses dates visibles, liste de présences avec zones tactiles suffisamment grandes. **Documents :** aperçu et métadonnées côte à côte, confirmation avant publication. **Bilan :** carte/timeline et éditeur sans masquer les objectifs. **Paramètres :** catégories regroupées et aide contextuelle, pas une colonne de boutons géants de téléphone.

Clavier et trackpad sont des moyens supplémentaires : toute action reste accessible au toucher. Le stylet peut servir de pointeur ou aux entrées système qualifiées ; aucun dessin libre, signature légale ou reconnaissance manuscrite métier n’est promis au pilote.

## Matériel et limites de capture

La fiche iPad Air distingue les modèles Wi-Fi et Wi-Fi + Cellular pour GPS/GNSS [S48](../06-gouvernance/sources.md#s48). Cette observation ne constitue pas une liste exhaustive des tablettes compatibles. Un appareil qui exécute bien Drivy peut rester non qualifié pour enregistrer une leçon.

Le diagnostic [E44](ecrans.md#e44) sépare : capacité de l’appareil/build, permission système, précision disponible, stockage, réseau et autorisation métier. Une localisation approximative n’est pas assimilée à une trace routière fiable. Un appareil non qualifié peut gérer l’agenda, afficher les bilans et servir à une leçon sans enregistrement.

Un partage de connexion n’est pas présenté comme transfert du récepteur GPS d’un téléphone. Le pilote n’inclut ni pont Bluetooth de positions, ni miroir live téléphone-tablette, ni bascule transparente d’enregistreur. Pour enregistrer depuis un téléphone, on démarre explicitement la séance dans ce téléphone ; la tablette relit les données après synchronisation. Voir [R83–R84](../03-fonctionnel/regles-etats.md#r83).

## Continuité et confidentialité

Une même personne peut être connectée sur téléphone, tablette et web. Elle retrouve les données **confirmées serveur** ; un brouillon uniquement local reste indiqué comme tel. La modification concurrente utilise If-Match et ne s’écrase pas silencieusement.

Une seule capture active par leçon, moniteur et appareil selon la contrainte précisée en R83. Ouvrir la séance ailleurs indique qu’une autorisation de capture est encore active sur un autre appareil, sans activer une seconde collecte. Cet état serveur ne prouve pas que le collecteur local enregistre à cet instant ; une pause ou un arrêt hors ligne peut ne pas être encore synchronisé. L’arrêt local reste possible même sans réseau ; une reprise sur un autre appareil exige clôture/autorisation serveur et crée une rupture explicite, jamais un raccord inventé.

Sur appareil partagé physiquement, chaque moniteur utilise son propre compte. À la déconnexion, la copie locale est verrouillée/purgée selon F12, et les données ne réapparaissent pas dans le compte suivant. Le navigateur ne mémorise pas de filtre contenant un nom, une naissance ou une adresse dans l’URL partageable.

## Matrice de qualification avant disponibilité

Tester au moins un iPhone qualifié, un iPad qualifié GPS, un iPad sans récepteur qualifié pour le mode sans capture, une tablette en fenêtre réduite, Safari iPad, et les navigateurs de bureau retenus. Android ajoute téléphone et tablette, avec essais de cycle de vie distincts avant annonce de support.

Pour chaque appareil, documenter modèle, OS, build, précision, arrière-plan, interruption forcée, verrouillage, batterie/chauffe, stockage et retour réseau. Les versions minimales seront choisies à G0 ; aucun numéro d’OS n’est déclaré compatible sans build et essai. Une capture d’écran d’un lecteur documentaire ne vaut pas un test de Drivy.

## Cohérence des reprises entre supports

Un changement d’écran ou de support ne convertit pas une opération PENDING en succès. Les mêmes enveloppes et identifiants servent à la reprise. Au retour réseau, la tablette invalide également cours, packs et publications GPS retirées, pas uniquement le planning individuel. Les règles de stockage du web restent inchangées ; la matrice des domaines ajoutés figure dans [synchronisation](../04-technique/synchronisation.md#domaines-incrementaux).

<a id="qualification-mobile-v34"></a>
## Qualification mobile par plateforme
La [politique iOS/iPadOS](../04-technique/integration-ios-ipados.md) couvre l’étude de 26 et 27. Android reste une disponibilité ultérieure : les contrats sont examinés dès G0 Apple et son [prototype natif distinct](../04-technique/preparation-android.md) est réalisé à GA0 avant le chantier Android. Aucune compilation Android n’est un prérequis implicite au pilote Apple. Les seuils de largeur ci-dessus sont internes à Drivy, non des constantes officielles Apple/Android.

Les [patterns](patterns-mobile-parcours.md) précisent caméra manuelle, replay accessible, choix avec/sans GPS et états d’inscription. Les préférences système de texte, mouvement/transparence, clavier et retour ont une adaptation native ; le web ne copie pas littéralement les matériaux Apple. Les [preuves MOB](../05-realisation/qualification-mobile-ui-ux.md) sont nécessaires avant déclarer ces supports qualifiés.

## Expression visuelle choisie

L’option A est déclinée dans [VIS01–VIS14](../DESIGN/04-ecrans-reference.md), dont une séance et un agenda iPad et trois compositions web. Les [règles de livraison](../DESIGN/06-livraison-validation.md) séparent point natif, pixel CSS, densité, police système et comportement de fenêtre. Aucun rendu de navigateur ne valide à lui seul SwiftUI ou Dynamic Type.
