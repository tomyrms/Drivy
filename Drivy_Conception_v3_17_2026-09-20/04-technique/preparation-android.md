# Préparer Android : client futur distinct et contrats communs

> Référence 3.10 · [Index](../README.md). Android téléphone/tablette est prévu pour une disponibilité ultérieure ; aucune compatibilité de binaire n’est déclarée acquise.

## Ce qui commence maintenant

Swift natif est la décision pour Apple ; Android n’utilisera pas les vues SwiftUI. **Recommandation future : Kotlin et Jetpack Compose**, avec intégrations Android propres. Ce choix précis, les ressources et la date de disponibilité restent à approuver. Le client web élève peut couvrir certaines consultations en attendant ; ce n’est pas un collecteur Android natif.

G0 Apple vérifie que les contrats HTTP, fixtures, formats de dates/montants, états, traductions sources et tokens sémantiques sont indépendants d’objets Apple. Un `CLLocation`, une permission iOS ou un token APNs ne devient pas un DTO métier universel. Cette préparation ne demande pas de maintenir un projet Android générable depuis le code Swift.

**GA0, au démarrage du chantier Android :** produire un prototype natif distinct avec connexion, lecture d’une leçon, carte, capture volontaire bornée, arrêt et lecture du résultat. Qualifier téléphone et tablette avant d’engager les écrans complets et annoncer une disponibilité. Un prototype Android plus tôt est possible selon les moyens, mais ne bloque pas automatiquement le pilote Apple.

Chaque capacité de plateforme tient un inventaire d’équivalence, de repli ou de besoin ouvert. Cette séparation évite à la fois de repousser toute réflexion Android et de faire croire que la version Android sortira d’une compilation du projet Apple.

## Version minimale, cible et compilation

Le **minSdk** définit les appareils capables d’installer, le **targetSdk** les comportements ciblés, et le **compileSdk** les APIs disponibles à la compilation. La page Google Play consultée indique **API 36/Android 16 ou ultérieur à partir du 31 août 2026** pour nouvelles apps et mises à jour ordinaires téléphone/tablette ; les exigences futures seront relues avant publication. [S88](../06-gouvernance/sources.md#s88).

Ne pas transformer ce target en obligation que tous les élèves possèdent Android 16. Fixer le minimum après croisement des besoins des SDK choisis, appareils pilotes et effort de support. Enregistrer Gradle, Android Gradle Plugin, JDK, Kotlin, Compose, NDK éventuel, ABI et bibliothèques natives dans la matrice propre à Android. Éviter les versions `latest` non verrouillées dans les builds diffusés.

## Contrats partagés et points natifs

| Partager | Adapter / tester spécifiquement |
|---|---|
| Contrat OpenAPI et fixtures ; clients générés/écrits séparément en Swift et Kotlin, identifiants d’opération | Authentification système, association de liens, cycle des activités |
| Sémantique des états, progression et règles de formulaire documentées | Navigation retour, contrôles, accessibilité TalkBack, clavier et insets |
| Formats de capture et synchronisation autorisée | Collecteur, foreground service, stockage/Keystore, arrêt et restrictions OS |
| Intention de notification et cible métier | Canaux Android, permissions, jetons et reprise du lien |
| Palette sémantique et termes français | Composants Material ou natifs équivalents, densité suivant la fenêtre |

Les interfaces de [l’intégration transverse](integration-mobile-transverse.md) empêchent un objet MapKit, un jeton APNs ou une permission Apple de devenir une donnée métier universelle. La référence Android sera une application distincte : ne pas compter sur un pont Kotlin dans le client Apple. Les ressemblances métier ne rendent pas les vues ou les services de cycle de vie interchangeables.

## Collecte de localisation : parcours visible et borné

Android sépare localisation approximative/précise et autorisation au premier plan/en arrière-plan. [S81](../06-gouvernance/sources.md#s81). Pour Drivy, la préparation visible de la leçon est le point de démarrage. La source est arrêtée par une action locale explicite ou les limites de la capture, sans dépendre de la connectivité.

Un foreground service de type `location` requiert les déclarations et permissions adaptées, notamment les contraintes spécifiques des versions récentes. Son démarrage depuis l’arrière-plan est restreint. [S82](../06-gouvernance/sources.md#s82). **Ne pas confondre** un service lancé pendant que l’app est visible et poursuivi ensuite avec le besoin de démarrer librement depuis le fond. Ne pas lancer le suivi depuis un push, au démarrage du téléphone ou parce qu’un cours figure au calendrier.

Le profil natif Kotlin devra sélectionner les API et autorisations réellement nécessaires à une séance commencée visiblement. Aucune permission de fond n’est demandée uniquement pour imiter une intégration Apple. Documenter la justification, les états de refus et les contraintes selon chaque OS avant le pilote Android [S81](../06-gouvernance/sources.md#s81), [S82](../06-gouvernance/sources.md#s82).

La qualité des positions est évaluée séparément du droit d’accès. Une position approximative ne permet pas de promettre une observation au bon carrefour. La séance et le bilan restent accessibles si la capture ne peut pas répondre au niveau de qualité demandé. Le produit explique la limite, sans contourner le choix système.

### Notifications et service ne sont pas le même consentement

Depuis Android 13, `POST_NOTIFICATIONS` concerne les notifications ; Android précise que cette autorisation n’est pas nécessaire pour démarrer un foreground service, qui doit néanmoins fournir sa notification. Quand l’autorisation est refusée, la visibilité système diffère. [S83](../06-gouvernance/sources.md#s83).

Drivy distingue donc annonces de cours et indicateur de collecte. Le refus des annonces ne bloque pas l’inscription ni ne devient automatiquement un refus de GPS. Le binaire doit rester transparent sur la collecte dans son UI et dans les mécanismes système applicables. L’action « Arrêter » dans une notification éventuelle arrête seulement la capture autorisée concernée ; elle ne publie pas de bilan.

### Arrêt, restrictions constructeur et reprise

Tester téléphone verrouillé, économie d’énergie, absence réseau, processus terminé, arrêt utilisateur du service et redémarrage. Le comportement peut varier selon version, profil de service et constructeur : l’app ne doit pas afficher RECORDING sans source effectivement active. Une interruption identifiée conduit à un état local cohérent, un segment incomplet et une explication ; elle ne relance pas automatiquement une collecte non autorisée.

Ne pas présenter une demande globale d’exemption batterie comme une étape obligatoire pour tous les élèves. Mesurer d’abord le comportement du profil retenu, vérifier les règles Play et proposer une aide ciblée au moniteur si nécessaire. Aucun « keep alive » audio ou cycle de relancement caché n’est accepté.

## Interface Android véritable

Les layouts suivent la fenêtre disponible, y compris tablette, multi-fenêtre et changement de posture sur appareil concerné. Les références Compose de Google nourrissent la proposition native ; elles ne sont pas des vues SwiftUI réutilisables. [S84](../06-gouvernance/sources.md#s84). Utiliser un composant équivalent exposant les bons comportements, avec essais de réduction de largeur pendant une capture.

Respecter les insets système et du clavier ; l’edge-to-edge des cibles récentes n’autorise pas un bouton sous la barre de navigation. [S85](../06-gouvernance/sources.md#s85). Le retour prédictif doit conserver sa destination réelle. [S86](../06-gouvernance/sources.md#s86). Fermer un panneau ou revenir à l’agenda n’arrête pas la collecte ; quitter un brouillon non protégé déclenche la règle de sauvegarde ou d’abandon explicite, sans piéger le retour système.

TalkBack reçoit noms, rôles, états et ordre de focus testés. La carte a une liste d’observations utilisable. Le grand texte ne se réduit pas automatiquement pour correspondre à une capture iPhone. Les barres, sélecteurs et états pressés sont natifs ou qualifiés Android ; aucune obligation de reproduire Liquid Glass.

## Liens, fichiers, cartes et sécurité

Les App Links HTTPS sont associés au domaine contrôlé avec le bon certificat de signature, y compris celui du binaire distribué par Google Play. [S79](../06-gouvernance/sources.md#s79). Tester une invitation quand l’app est absente, installée, fermée ou connectée au mauvais compte. Un lien ne fournit jamais les droits sur son objet.

Clés, cache chiffré et sauvegardes suivent la [politique transverse](integration-mobile-transverse.md). Restaurer une base sans sa clé doit mener à une reprise sûre, pas à un mode non chiffré. Les fichiers choisis avec le système sont copiés ou lus selon la durée réelle d’accès accordée ; une référence temporaire n’est pas un fichier envoyé. Les permissions de stockage global ne sont pas une solution de facilité.

La carte choisie doit fonctionner sans dépendre de MapKit. Le modèle de trace reste indépendant du fournisseur ; vérifier attribution, quotas, clés, licences et données transmises avant configuration de production. La disponibilité d’un SDK de cartes ne garantit pas le GPS sur tous les appareils.

## Binaire et publication

Les bibliothèques natives doivent être vérifiées pour les pages mémoire **16 Ko**, notamment lorsque le paquet contient une bibliothèque de base chiffrée ou de carte. La compatibilité ne se déduit pas de l’absence de code C++ écrit par l’équipe : les dépendances peuvent en embarquer. [S87](../06-gouvernance/sources.md#s87).

Séparer clés d’upload et signature de distribution, identifiants dev/test/production et configurations de liens. Le binaire release, pas uniquement debug, passe les tests de login, carte, capture et stockage. Les permissions du manifeste fusionné sont relues pour détecter celles ajoutées par un SDK.

Avant Play : cible à jour, déclarations sur les données et localisation cohérentes, chemin de suppression de compte dans l’app et ressource web applicable, fiche et accès de revue. [S88](../06-gouvernance/sources.md#s88), [S92](../06-gouvernance/sources.md#s92). La demande web reste possible sans réinstaller l’app. Les règles de confidentialité communes ne sont pas remplacées par une notice générique Google.

## Jalons Android

**Maintenant, G0/G1 Apple :** conserver contrats, fixtures et interfaces sans dépendance d’objets Apple. **GA0 Android :** budget, prototype natif, build reproductible et première exécution connexion/capture/arrêt sur appareil Android, avant la réalisation complète.

**Pendant les tranches métier :** documenter les équivalences Android et les limites ; fixtures sémantiques communes. Une fois son chantier ouvert à GA0, compiler régulièrement le projet Android distinct et tester ses intégrations. La compilation seule ne suffit pas à qualifier GPS, clavier, batterie ou notifications.

**Avant lancement Android :** finir téléphone/tablette, tester appareils de constructeurs différents, profils de permissions et release, remplir les preuves [MOB](../05-realisation/qualification-mobile-ui-ux.md). Si les ressources ne permettent pas ces essais, conserver le statut prévu/non disponible ; ne pas afficher « Android pris en charge ».

<a id="contrats-v37-partagés-sans-disponibilité-android-implicite"></a>
## Contrats partagés sans disponibilité Android implicite
Le futur client conserve sourceEnrollmentCycle, la basis serveur, le suivi des droits et les invalidations ; il ne ramène pas une valeur inconnue à COMPLETED. AP148 réserve ANDROID/FCM_PRODUCTION, mais renvoie PUSH_PLATFORM_NOT_CONFIGURED tant que ce fournisseur n’est pas retenu et qualifié. Les mêmes invariants R111 de provenance GPS seront testés contre la source Android, sans transposer les cycles de vie Apple ni partager les widgets SwiftUI.
