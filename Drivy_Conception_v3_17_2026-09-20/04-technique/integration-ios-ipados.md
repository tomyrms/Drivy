# Intégration Swift native : iOS et iPadOS 26 / 27

> Référence 3.10 · [Index](../README.md). Swift natif confirmé par le porteur. Guide de réalisation à qualifier ; aucun build ni appareil n’a été testé dans cette passe. [Architecture Apple de référence](architecture-client-swift.md).

## Indicateur système et fermeture : ne pas surpromettre

Le profil `CLBackgroundActivitySession` garde la localisation de fond visible au système ; son indicateur exact dépend de l’environnement et doit être constaté sur appareil [S138](../06-gouvernance/sources.md#s138). Une application en arrière-plan n’est pas une application terminée ou forcée à quitter. Ne jamais écrire « enregistre même application fermée » comme garantie de continuité. L’indicateur de l’OS n’est ni une preuve de point persisté ni une preuve de synchronisation. E23 montre l’état connu du collecteur et la qualité réelle ; conserver les scénarios de rupture et le mode sans GPS.

## 1. Support et outillage

La cible d’étude reste **iOS/iPadOS 26 et 27**. Le tableau Apple consulté liste Xcode 27, SDK iOS 27 et macOS Tahoe 26.6 ou ultérieur pour cet outil [S63](../06-gouvernance/sources.md#s63). Cela ne prouve ni le support de l’ancien ordinateur de développement ni la qualification de Drivy.

Distinguer SDK de compilation, deployment target, version du compilateur, mode de langage Swift, modèle d’appareil et version exacte d’OS. La [matrice V3.6](../annexes/matrice-build-mobile-v3-4.json) ne contient aucun résultat de build. Le minimum commercial reste à choisir avec les appareils des premières écoles ; une API nouvelle est protégée par disponibilité et repli explicite. Ne pas exiger une capacité propre à 27 pour réaliser une leçon ordinaire sur un système supporté.

Figer Xcode/macOS, dépendances SwiftPM et `Package.resolved` après essai. iPhone et iPad partagent le projet Apple et ses services, pas nécessairement la même composition. Les branches bêta et les SDK de test restent distincts d’un support public annoncé.

## 2. Présentation et cycle applicatif

**Recommandation : SwiftUI**, UIKit seulement pour les besoins documentés qui ne sont pas correctement couverts ou performants avec la présentation choisie [S97](../06-gouvernance/sources.md#s97). Aucun runtime JavaScript, couche d’interface partagée ou pipeline mobile TypeScript n’est requis.

L’application possède les services de session, capture, synchronisation et stockage à sa racine. Les modèles d’écran exposent des projections sur `MainActor`. Une tâche liée à la vue peut être annulée pour un chargement visuel ; elle ne possède pas le service GPS ni la clé d’une commande déjà envoyée. Une API native ou un acteur n’est pas une dispense de gestion des erreurs et de concurrence. [Règles du coordinateur](architecture-client-swift.md#capture).

## 3. Liquid Glass et lisibilité

Employer les matériaux Apple pour la navigation et certaines commandes, sans rendre tous les contenus translucides [S65](../06-gouvernance/sources.md#s65), [S66](../06-gouvernance/sources.md#s66). Les bilans, données administratives, montants et erreurs conservent une surface stable. Contrôles de disponibilité natifs, état du système et préférences d’accessibilité déterminent le rendu.

Prévoir une présentation opaque offrant les mêmes actions, avec Réduire la transparence ou lorsqu’un fond cartographique rend le contenu peu lisible. Les rayons des composants personnalisés n’imposent pas de redessiner les contrôles système. Vérifier contraste, texte agrandi, VoiceOver et Réduire les animations sur les fonds réels ; les ratios de couleurs opaques du dossier ne certifient pas un matériau translucide.

## 4. iPad à part entière

Adapter à la taille effective de fenêtre, au clavier et à la taille de texte, pas seulement à un nom de modèle. Recommandation : `NavigationSplitView` lorsque la place permet liste/détail, puis une pile cohérente en fenêtre étroite. Sur la carte, le panneau de contexte ne doit pas cacher arrêt et état de capture. La sélection et le brouillon restent identiques lors du changement de composition.

Les scènes détiennent leur navigation ; le service applicatif conserve un seul propriétaire local de collecte. Une seconde scène, une rotation ou la fermeture d’une feuille ne crée pas un autre `captureId`. Le lancement d’une fenêtre depuis un lien n’autorise aucune capture. Les raccourcis annoncés aident recherche et navigation ; aucun raccourci caché ne publie un bilan ou n’arrête une leçon.

Le diagnostic de matériel distingue capacité de localisation, précision disponible et réseau. L’agenda, le bilan et la consultation fonctionnent sans diagnostic GPS réussi ; la qualification de capture requiert les appareils réels. [Compositions et limites](../02-experience/plateformes-tablette-web.md).

## 5. Core Location : profil natif proposé

Trois conditions restent indépendantes : choix pédagogique de la personne, droit serveur sur leçon/appareil et permission OS. Les [états GPS](../03-fonctionnel/gps-replay.md) et les preuves de collecte/transfert restent canoniques. Ne pas créer une autre machine à états dans Swift.

**Profil à éprouver d’abord :** séance commencée volontairement au premier plan, objectif d’autorisation `whenInUse` avec `CLServiceSession` lorsque disponible, flux `CLLocationUpdate.liveUpdates` et session `CLBackgroundActivitySession` conservée pendant le suivi. Apple décrit les sessions d’autorisation [S73](../06-gouvernance/sources.md#s73) et le suivi visible en arrière-plan, nécessitant notamment la déclaration `location` dans `UIBackgroundModes` [S99](../06-gouvernance/sources.md#s99).

Ce profil est une recommandation minimale à qualifier, pas une garantie de continuité ni une obligation universelle de demander Always. Un recours à une autorisation plus large devrait être justifié par un besoin et des essais, avec textes et finalités adaptés. Une alternative basée sur `CLLocationManager` reste possible si qualifiée ; ne jamais activer deux sources en parallèle pour la même capture.

Avant le départ : expliquer l’usage, offrir « Continuer sans enregistrement », puis demander la permission au moment utile. Distinguer refus, précision réduite, localisation système désactivée, absence de point et restriction. Ne pas interpréter une autorisation ponctuelle comme permanente ; relire au retour des Réglages. Aucun harcèlement par demandes successives.

Ne pas faire dépendre une capture de Live Activities, de l’acceptation du push ou d’un accès aux contacts. Aucun mode audio ou autre détournement n’est ajouté pour maintenir l’app en vie. Le choix exact de précision et la configuration automobile se mesurent avant fixation, sans promesse de batterie inventée.

## 6. Durabilité sous verrouillage et interruptions

La source accepte un point uniquement sous le contexte autorisé ; le magasin confirme sa persistance avant l’affichage « sauvegardé ». Les éventuelles mesures sans position et les pertes de qualité ne deviennent pas des coordonnées fabriquées. L’état stationnaire du système ne clôt pas la leçon métier.

L’arrêt coupe la source, exclut les callbacks tardifs et scelle le manifeste après les écritures déjà admises. Il fonctionne sans serveur. L’expiration de collecte ne se décale pas au démarrage tardif ; les règles de budget et de réconciliation restent celles de la [synchronisation](synchronisation.md). L’envoi différé ne prolonge pas la permission de recueillir des points.

La base, ses fichiers annexes et sa clé doivent rester utilisables sous verrouillage dans le profil autorisé. La classe Keychain après premier déverrouillage limitée à l’appareil est une option documentée, avec compromis à valider [S100](../06-gouvernance/sources.md#s100). Une clé inaccessible produit un incident explicite ; aucune copie en clair, aucun trajet vide présenté comme complet. [Persistance de référence](architecture-client-swift.md#persistance).

Une suspension, terminaison système, fermeture forcée et un redémarrage ne sont pas des événements équivalents. Le pilote ne promet aucune relance automatique après arrêt forcé. Une reprise système ne réutilise pas aveuglément un consentement ou un budget devenu invalide ; elle doit être qualifiée avec les autorisations encore valables et le journal durable. Sans preuve suffisante, conserver une trace partielle et demander une action explicite au retour. Les morceaux absents restent absents.

## 7. MapKit et replay

**MapKit direct est la référence recommandée pour Apple.** Le candidat d’affichage est `Map` et ses superpositions SwiftUI ; un adaptateur `MKMapView` ne s’ajoute que pour un besoin constaté. MapKit sait présenter des polylignes [S98](../06-gouvernance/sources.md#s98) ; cela ne garantit pas les performances d’un long trajet Drivy, à mesurer.

La carte présente des géométries autorisées provenant du magasin/API ; elle n’enregistre pas. Le replay historique n’a pas besoin de la localisation actuelle de l’élève. Le curseur et les fragments gardent leur segment logique ; une pause GPS n’est pas inventée à chaque page. Le retrait de partage et l’effacement purgent les projections, pas seulement l’affichage de carte.

Respecter les attributions et conditions du fournisseur. Aucun téléchargement arbitraire de tuiles ni navigation guidée, CarPlay, miroir live inter-appareils ou notation automatique n’est ajouté à ce périmètre. Si le fond n’est pas disponible hors ligne, l’UI le dit ; les observations déjà autorisées restent distinguées du fond cartographique.

## 8. Connexion, liens, notifications et import

OIDC/PKCE utilise l’authentification système, avec `ASWebAuthenticationSession` et une implémentation maintenue à qualifier ; valider le protocole, pas seulement la fermeture de la fenêtre [S77](../06-gouvernance/sources.md#s77). Les jetons vont dans Keychain, pas dans la navigation ou les logs.

Universal Links : domaine, AASA et Associated Domains concordants [S78](../06-gouvernance/sources.md#s78). Après connexion, revalider compte, école, destination et droits. Le repli web conserve l’accès possible sans installation ; l’ouverture d’un cours ne réserve rien.

Notifications : `UserNotifications`, inscription APNs native et adaptation serveur de l’installation [S105](../06-gouvernance/sources.md#s105). Séparer sandbox/production, gérer un jeton renouvelé et conserver le centre in-app sans push. Le message de verrouillage reste minimal. Ni le consentement push ni la réception d’un avis ne sont une confirmation métier.

Photo et documents : sélecteur système, photo de profil facultative, caméra demandée pour une capture volontaire. La quarantaine et le statut READY restent ceux de F09. Le calendrier interne n’exige pas EventKit ; l’accès aux contacts n’est pas demandé par défaut. [Intégration transverse](integration-mobile-transverse.md).

## 9. Distribution native, confidentialité et limites de publication

Le pipeline produit un binaire signé avec identifiants de bundle et configurations d’environnement cohérents. Qualification sur appareil et TestFlight avant la diffusion publique retenue. La version d’app, le numéro de build, le schéma local et le contrat API sont distincts. Pas de téléchargement d’une interface ou logique métier JavaScript pour remplacer une mise à jour native.

L’app n’interrompt pas volontairement une capture pour se mettre à jour. Elle ne prétend pas contrôler tous les remplacements de processus décidés par le système. Réconciliation et migrations doivent préserver les états durables après changement de binaire ; un downgrade de schéma n’est jamais présumé sûr.

App Privacy, manifeste `PrivacyInfo.xcprivacy`, textes de permissions et notice doivent correspondre aux flux effectifs [S93](../06-gouvernance/sources.md#s93), [S95](../06-gouvernance/sources.md#s95). Une localisation pédagogique ne déclenche pas automatiquement une permission publicitaire ; analyser les tiers réellement embarqués, sans annoncer « aucune collecte » si le serveur reçoit des traces nominatives.

**DM06 reste un blocage de publication publique :** la [clôture globale du compte](integration-mobile-transverse.md#cloture-compte) nécessite encore une extension de contrat. L’archive scolaire ne la remplace pas [S91](../06-gouvernance/sources.md#s91). Les leçons physiques et futurs achats numériques demandent des traitements commerciaux distincts [S94](../06-gouvernance/sources.md#s94) ; le journal de paiements ne constitue pas un système d’encaissement.

## 10. Preuves requises

Build reproductible, versions/entitlements relevés, tests Swift de contrats et de concurrence, tests UI XCTest, scénarios réseau et migrations, puis GPS/batterie sur iPhone et iPad réels. Les simulateurs et previews servent à l’interface, pas à certifier capteur et autonomie. [Qualification et scénarios MOB](../05-realisation/qualification-mobile-ui-ux.md).

Les sources montrent des capacités Apple. Les recommandations définissent leur emploi dans Drivy. Les statuts de compatibilité ne deviennent « qualifiés » qu’après les preuves associées au binaire précis. Aucun résultat natif n’est revendiqué ici.

## Revalidation datée de l’outillage

La relecture du 19 septembre 2026 distingue iOS/iPadOS 27.0 publics listés le 14 septembre des bêtas ultérieures, et vérifie le tableau d’hôte Xcode 27 [S109](../06-gouvernance/sources.md#s109). Elle confirme une disponibilité d’éditeur, pas la qualification de Drivy. Aucun Mac, SDK ou appareil n’a été exécuté ici. Le choix Swift reste acquis ; minimum commercial, profil Core Location et dépendances exactes sont ouverts.

## Mesures initiales et distribution sans GPS obligatoire

Apple documente dans son guide archivé des positions pouvant provenir du cache et leur date de mesure [S113](../06-gouvernance/sources.md#s113). Ce document historique n’est pas la référence des autorisations de fond iOS 26/27 : ses constantes d’exemple ne deviennent pas des paramètres Drivy. Le collecteur applique R111 et teste anciennes positions, livraison en lot, horloge modifiée et segment fermé. Un replay ne demande jamais une nouvelle autorisation de position.

**Décision Drivy :** ne pas déclarer `gps` comme matériel obligatoire global dans `UIRequiredDeviceCapabilities`, puisque l’app conserve des usages sans capture. La clé filtre l’installation, pas seulement le bouton GPS [S113](../06-gouvernance/sources.md#s113). Le diagnostic existant décide si cet appareil peut collecter ; un iPad non qualifié peut garder les cours, bilans et autres fonctions autorisées. Cela ne promet pas une localisation précise sur tout matériel.

APNs : enregistrer auprès du système et transmettre le token sous identité courante ; ne pas utiliser une copie persistée comme référence permanente [S111](../06-gouvernance/sources.md#s111). Associer le profil d’entitlement effectif au `deliveryEnvironment`, puis tester build de développement et distribution avec les environnements concordants. La liaison compte/école et la protection d’une notification déjà en transit suivent R112, pas le seul état d’un bouton.

<a id="revue-v310-contenu-sensible-hors-de-la-vue-courante"></a>
## Contenu sensible hors de la vue courante
Appliquer le [profil de scènes et de sessions URLSession](architecture-client-swift.md#confidentialite-transports) : séparation des credentials, inspection des caches et des fichiers temporaires, couverture avant snapshot et retour sous génération d’identité correcte. Aucun framework supplémentaire n’est imposé. Le comportement de snapshot s’appuie sur une source Apple archivée et exige une nouvelle qualification sur iOS/iPadOS ciblés ; il ne justifie pas de recopier un callback Objective-C ancien comme preuve de fonctionnement SwiftUI.
