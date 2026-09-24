# Architecture du client Apple en Swift natif

> Référence 3.10 · 19 septembre 2026 · [Index](../README.md). **Décision du porteur : Swift natif pour iPhone/iPad.** Les choix détaillés ci-dessous sont des recommandations d’implémentation. Aucun projet Xcode ni code de l’ancienne application n’est modifié ou compilé dans cette livraison.

<a id="decision"></a>
## Observations pendant la leçon

Le service de séance Swift conserve les observations indépendamment du cycle de vie de la vue et du collecteur Core Location. Le formulaire ne déclenche jamais une demande de position. Avant un accusé visuel, persister l’intention chiffrée ; un échec disque ne devient pas un succès UI. Réutiliser les stores/outbox existants, sans nouvelle dépendance multiplateforme. La liste native E23/E04 et le bilan E08 lisent les mêmes identifiants d’observation ; une rotation ne recrée pas les commandes. Les champs origin/observedAt/eventKind/eventStatus sont mappés explicitement dans les DTO ; le compte/école et le lease restent obligatoires. Tests T407–T422, ainsi que les scénarios mobiles de persistance, rotation et révocation déjà spécifiés.

**Composition du signalement.** Le coordinateur de séance possède le contexte stable ; l’ouverture du panneau copie un instant et une référence vers un point admissible déjà persisté. Le modèle de présentation contient la sélection temporaire sans créer de table « ReportBubble » ni un second collecteur. La confirmation appelle l’écriture transactionnelle locale via le service de domaine ; la vue n’accuse qu’un résultat réussi. Une reconstruction SwiftUI, rotation, présentation de feuille ou fenêtre partagée conserve le contexte tant que la scène existe. Le kill de processus avant persistance ne garantit pas la restauration. Les API de géolocalisation et le réseau ne sont pas appelés depuis les boutons de catégorie.

## 1. Décision, portée et invariants conservés

L’application Apple est un client Swift natif. SwiftUI constitue la présentation recommandée ; UIKit reste disponible pour une intégration ponctuelle justifiée, sans seconde interface complète. Apple documente leur interopérabilité [S97](../06-gouvernance/sources.md#s97). Ce choix ne reconduit pas l’architecture de l’ancienne app et ne garantit pas, à lui seul, précision GPS, autonomie ou absence de bugs.

Le backend TypeScript/Fastify, PostgreSQL et le web distinct restent les propositions de référence. La décision Swift ne transforme ni l’API ni le BFF en services Swift. Android sera un autre client ; Kotlin/Jetpack Compose est une recommandation future, pas une décision déjà validée ni un développement réalisé.

**Les autorités métier ne changent pas :** place de cours confirmée au serveur, financement distinct des présences, droits contrôlés par école, GPS facultatif, publications immuables mais accès révocables, suppression de données applicable aux dérivés. Le contrat OpenAPI courant est la référence ; l’adapter à Swift ne signifie pas réduire ses validations pour simplifier un générateur.

## 2. Composition recommandée, sans architecture disproportionnée

```text
DrivyApp / composition root
 ├─ SessionScope : identité, école, droits et génération de session
 ├─ UI SwiftUI : navigation et modèles d’écran MainActor
 ├─ LessonCaptureCoordinator : une capture locale, transitions bornées
 │   ├─ CoreLocationSource : API Apple et diagnostics
 │   └─ CaptureStore : journal, points et manifeste chiffrés
 ├─ SyncCoordinator : commandes durables et réconciliation des résultats
 ├─ DrivyAPIClient : URLSession, DTO et gestion HTTP explicite
 ├─ IdentitySession : OIDC via authentification système, coffre Keychain
 └─ SystemIntegration : liens, notifications, import et cycle applicatif
```

Ces noms désignent des responsabilités internes, pas des DTO supplémentaires ou des services distribués. Les isoler par dossiers puis par cibles SwiftPM seulement si la compilation, la réutilisation ou les tests le justifient. Une dépendance est injectée à la racine par initialiseur ; aucun conteneur d’injection complexe n’est requis au pilote.

| Couche | Possède | Ne décide pas |
|---|---|---|
| Vue SwiftUI | Présentation, focus, sélection et saisie transitoire | Confirmation de paiement, place, permission métier |
| Modèle d’écran | Projection observable, chargement/erreur, intention utilisateur | Persistance de la capture à la place du collecteur |
| Services locaux | Session, coordination, brouillons et commandes en attente | Transaction commerciale définitive |
| Adaptateurs Apple | Réseau, positions, coffre, notifications et import | Règles de prix ou d’éligibilité |
| Serveur Drivy | Droits, invariants et résultats autoritaires | Continuité d’un appareil suspendu hors de sa connaissance |

`MainActor` est réservé à l’état présenté et aux API qui l’exigent. Ne pas y faire tourner calculs de longues géométries, chiffrement de fichiers ou requêtes bloquantes. Une API `async` n’est pas une preuve que tout son travail s’exécute hors du thread de l’interface ; le profilage vérifiera les chemins effectifs.

<a id="capture"></a>
## 3. Capture : propriétaire stable, isolation et arrêt

Le collecteur est créé et détenu par la composition applicative, pas par une cellule, une feuille, un `onAppear` ou une tâche attachée à la durée de vie de l’écran. Les vues observent sa projection ; leurs tâches annulables servent à charger une page ou une image. Navigation et rotation n’annulent pas la séance.

**Proposition d’isolation :** un coordinateur protège les transitions locales ; un adaptateur respecte l’isolation exigée par Core Location ; le magasin sérialise les écritures. Les positions sont converties en valeurs internes immuables, transférables entre domaines d’isolation. Une référence d’objet système n’est pas déclarée arbitrairement `@unchecked Sendable` pour faire taire le compilateur.

Les acteurs Swift sont réentrants aux points de suspension [S101](../06-gouvernance/sources.md#s101). Par conséquent, le coordinateur doit recontrôler état, génération et périmètre après chaque `await` important. Deux appels concurrents à « Démarrer » ne donnent pas deux flux parce qu’ils ont tous deux vu l’ancien état avant un appel réseau.

### Séquence proposée pour démarrer

1. Vérifier l’action explicite, le choix de l’élève, le diagnostic appareil et la session scolaire courante. Ne pas demander une permission GPS pour lire un ancien trajet.
2. Passer localement à une intention de démarrage identifiée ; conserver l’identifiant d’opération avant l’appel autorisant la capture. Ne pas afficher « Enregistrement » pendant une réponse PENDING.
3. Obtenir et valider les autorisations existantes de collecte/transfert, leurs bornes, la leçon, l’installation et la génération de compte. Rejeter une réponse devenue obsolète après déconnexion.
4. Persister le contexte autorisé ; créer une seule source native après vérification du profil de permission. Un refus ou un échec du magasin produit un état explicite, pas une capture supposée active.
5. Accepter les points dans le journal durable, puis publier une projection de progression. Un point reçu mais non écrit n’est pas annoncé comme sauvegardé.

### Barrière d’arrêt proposée

L’action locale « Arrêter » interdit immédiatement l’admission de nouvelles mesures et invalide la source native ; elle ne dépend pas d’Internet. Un compteur de génération empêche les callbacks tardifs de rouvrir la capture. Une barrière sur le chemin d’écriture termine ou classe les écritures déjà admises, puis scelle le manifeste. Ne pas lancer des écritures détachées qui pourraient se produire après ce scellement.

Le transport peut continuer ensuite, sous les règles existantes. Un jeton d’envoi n’est pas un droit d’enregistrer davantage. Si l’écriture finale échoue, l’UI signale la sauvegarde incomplète et conserve une possibilité de diagnostic ; elle ne prétend pas que tous les points sont acquis.

Le traitement d’un événement « stationnaire » n’est pas assimilé à l’arrêt métier d’une leçon. Une autorisation OS, un consentement pédagogique et un bail serveur ne sont pas interchangeables. [Profil iOS](integration-ios-ipados.md) et [machines à états GPS](../03-fonctionnel/gps-replay.md) font référence.

<a id="persistance"></a>
## 4. Persistance chiffrée, clés et périmètres

**REC :** un magasin SQLite/SQLCipher natif dédié, intégration et édition choisies après qualification [S104](../06-gouvernance/sources.md#s104). Des modèles `Codable` ne remplacent pas une transaction locale. Une simple mention de SQLite, SwiftData ou Core Data ne prouve pas le chiffrement exigé par le dossier ; ne pas ajouter une synchronisation CloudKit concurrente au serveur métier.

Proposer des espaces logiques séparés : projections de lecture avec leur révision, commandes en attente avec leur clé d’opération, puis captures avec segments/manifeste/ack. Les clés de stockage incluent compte, école et identifiant d’objet lorsque nécessaire. Le passage à une autre école purge les projections incompatibles et ne réaffecte jamais une capture en attente à cette école.

### Invariants locaux à démontrer

| Invariant | Vérification attendue |
|---|---|
| Une intention durable conserve sa clé | Timeout puis reprise envoie la même intention, sans second achat ou inscription |
| Un point n’est jamais acquitté avant commit | Arrêt brutal avant/après commit donne un état récupérable et un nombre honnête |
| Un manifeste scellé est stable | Callback tardif rejeté ; aucune mutation silencieuse du jeu à transférer |
| Une purge touche les dérivés | Points, miniatures locales, index et caches de replay effacés selon leur portée |
| Une perte de clé ne provoque pas un repli en clair | Échec contrôlé, aucune copie temporaire non chiffrée |
| Un changement de compte invalide les anciennes réponses | Résultat retardé rejeté même si l’identifiant d’écran ressemble au nouveau |

Les clés et jetons sont dans Keychain, jamais dans `UserDefaults`, une constante, un log ou un fichier du dépôt. **Option à arbitrer en sécurité :** une accessibilité après premier déverrouillage, limitée à cet appareil, pour permettre les écritures autorisées écran verrouillé. Apple décrit cette classe et sa limite au redémarrage [S100](../06-gouvernance/sources.md#s100). Choisir aussi la protection des fichiers DB, WAL, journaux et pièces ; le coffre seul ne protège pas tout le répertoire.

Ne pas exiger une authentification biométrique pour chaque point. Le compromis entre accès sous verrouillage et protection doit être documenté, testé et approuvé. Après redémarrage avant premier déverrouillage ou indisponibilité de clé, ne pas inventer une continuité GPS. L’exclusion des sauvegardes et les limites de restauration restent celles de l’[intégration transverse](integration-mobile-transverse.md).

<a id="api-swift"></a>
## 5. Client HTTP Swift : contrat commun, implémentation propre

**REC :** `URLSession` derrière `DrivyAPIClient`. Un client généré par Swift OpenAPI Generator est candidat : le projet officiel génère des types et appels depuis le contrat, avec un transport choisi séparément [S103](../06-gouvernance/sources.md#s103). Cela ne démontre pas que toutes les constructions des schémas du contrat Drivy sont couvertes par la version retenue.

En G0, essayer un échantillon des opérations critiques, puis contrôler la couverture du contrat : nullabilité/omission, unions, discriminants, branches conditionnelles, champs requis, enums et erreurs. Si une construction n’est pas représentée correctement, garder le contrat canonique et écrire un adaptateur Swift limité avec tests. Ne pas affaiblir `if/then`, unicité ou permissions dans OpenAPI pour faire réussir la génération.

| Élément du contrat | Traduction à préserver en Swift |
|---|---|
| Montants entiers en centimes CHF | Entier suffisamment large, bornes vérifiées ; formatage local à l’affichage, pas `Double` pour les calculs comptables |
| Champs absents, `null` ou valeur | Différence conservée, notamment PATCH partiels ; un `Optional` naïf peut effacer cette distinction |
| ETag / If-Match / If-None-Match | Préconditions exactes par opération ; pas de version locale fabriquée |
| 202 / opération en cours | État de confirmation en cours, clé stable et reprise ; pas de toast de succès définitif |
| Pagination et fragments GPS | Curseur opaque, révision et continuité de segment respectées ; aucun raccord inventé |
| Snapshot retiré ou effacé | Aucun point ni curseur conservé dans une nouvelle projection interdite |
| Erreur inconnue / enum évolué | Message prudent et trace technique non sensible ; pas de valeur par défaut transformant un refus en succès |

L’annulation d’une tâche réseau liée à une vue ne signifie pas annulation de l’opération serveur. Une commande durable continue sa réconciliation même si l’utilisateur quitte l’écran. Un refresh d’identité est coordonné pour éviter les demandes concurrentes ; revalider périmètre et jetons avant le rejeu, sans fabriquer une nouvelle commande.

**Transport GPS de référence :** envoi des chunks JSON existants par URLSession lorsque le processus dispose d’exécution, avec reprise au premier plan. La file reste chiffrée au repos et la réception est confirmée par l’API, pas par l’indicateur d’octets envoyés. Ne pas introduire un fichier temporaire en clair pour obtenir un upload système en arrière-plan. Cette optimisation éventuelle demanderait un profil distinct prouvant protection, authentification expirée, redirection, annulation et compatibilité du contrat ; elle n’est pas une capacité acquise du pilote.

## 6. Carte, navigation et identité visuelle

**REC : MapKit direct.** Utiliser les présentations SwiftUI disponibles pour la carte et les tracés ; n’ajouter un adaptateur `MKMapView`/UIKit que si un comportement nécessaire ou une mesure le justifie. MapKit expose des superpositions de trajets [S98](../06-gouvernance/sources.md#s98). Le stockage canonique reste la géométrie Drivy, indépendante de la caméra et du fond cartographique.

La navigation conserve des destinations typées plutôt qu’une vue globale modifiée depuis chaque callback. Téléphone : pile et présentations adaptées. iPad : liste/détail ou carte/panneau selon la fenêtre ; même sélection et mêmes brouillons au changement de composition. La racine détient les services, chaque scène détient son état d’affichage. Le pilote propose un seul propriétaire local de collecte, même si une seconde scène peut consulter des données autorisées.

Les matériaux, menus et champs sont natifs autant que possible ; la charte [anti-slop](../02-experience/qualite-ui-ux-anti-slop.md) ne se réduit pas à une bibliothèque de composants. Dynamic Type, VoiceOver, Réduire les animations et Réduire la transparence font partie des essais. Une carte dispose d’une liste accessible des observations ; le replay ne demande pas la localisation actuelle de l’élève.

## 7. Intégrations Apple : choix et limites

| Capacité | Référence proposée | Limite essentielle |
|---|---|---|
| Authentification | OIDC/PKCE via session système `ASWebAuthenticationSession`, bibliothèque maintenue à qualifier | La session système ne valide pas seule tout le protocole OIDC [S77](../06-gouvernance/sources.md#s77) |
| Secrets | Security/Keychain | Politique d’accès et de purge indépendante des préférences UI |
| Notifications | UserNotifications, inscription APNs native, transport serveur qualifié | Jeton lié à une installation/environnement ; push jamais confirmation métier [S105](../06-gouvernance/sources.md#s105) |
| Liens | Universal Links et routage après connexion | Destination et compte relus sous droits ; aucun démarrage GPS depuis un lien |
| Photos et documents | Sélecteurs système, import volontaire et pipeline existant | Une photo choisie n’est pas immédiatement READY au serveur |
| Calendrier | Calendrier interne Drivy | Pas d’accès EventKit demandé pour consulter les cours internes |
| Journaux | Identifiants techniques et événements limités | Pas de tokens, noms, positions ou contenu pédagogique dans les logs |

Les API précises, entitlements et déclarations sont à compiler et tester sur les SDK retenus. Les sources de plateforme expliquent des mécanismes, pas une conformité ou une réussite d’intégration de Drivy.

<a id="tests-swift"></a>
## 8. Tests et build : nouvelle chaîne Apple

La chaîne Apple emploie Xcode et Swift Package Manager, avec configurations de développement/recette/production séparées et secrets de signature hors dépôt. `Package.resolved`, version du compilateur, mode de langage, SDK, deployment targets et hash de binaire alimentent la matrice. iOS/iPadOS 26 et 27 restent des cibles à qualifier, pas une obligation que toutes les écoles possèdent le même OS.

Swift Testing est proposé pour les tests unitaires et d’intégration Swift ; XCTest pour l’interface et les mesures adaptées. Apple distingue ces usages [S102](../06-gouvernance/sources.md#s102). Les doubles de source GPS, horloge, magasin et API servent à reproduire les cas difficiles ; ils ne remplacent pas les essais physiques sous verrouillage.

Parcours de qualification : compilation avec diagnostics de concurrence traités ; tests de décodage sur fixtures ; migrations interrompues ; capture simultanément sollicitée/arrêtée ; interface avec grand texte et rotation ; build signé distribué au groupe de recette ; mesure sur iPhone et iPad réels. Instruments peut documenter mémoire, blocages et consommation, sans fixer une promesse de batterie à partir d’un simulateur.

Les scénarios [MOB041–MOB052](../05-realisation/qualification-mobile-ui-ux.md#mob041) rendent ces choix testables. Ils restent **NOT_EXECUTED**, comme les autres MOB et T. Un vérificateur Python de liens/contrats n’est pas un compilateur Swift, un test Xcode ou une recette GPS.

## 9. Android, mutualisation et conditions de suite

G0 Apple fige les interfaces stables et les règles multi-clients. GA0 porte le premier prototype Android quand les moyens de cette plateforme sont engagés. Kotlin/Compose, ses adaptateurs de localisation et son stockage ont leurs propres versions et leur propre cycle de vie ; ne pas fabriquer une couche abstraite pour partager les vues Apple.

Réutiliser fixtures, montants attendus, cas de refus, états de confirmation, vocabulaire et contrat HTTP. Prévoir une comparaison des clients sur les mêmes jeux, pas l’identité des widgets. Le lancement Android requiert ses tests de fond, sécurité, accessibilité et contraintes de publication. Une compilation Apple ne remplit aucune cellule Android de la matrice.

Les critères restant ouverts sont : appareils/minimum d’OS, implémentation précise des permissions, fournisseur d’identité et de cartes web/Android, politique locale de clés, bibliothèque SQLCipher/édition, budget Android et clôture globale de compte. La décision **Swift natif** n’est plus une question ouverte ; ces choix de réalisation le restent.


<a id="contrat-courant-v37-et-apports-hérités"></a>
## Contrat courant et séparation des couches
Le contrat API n’est plus le fichier 3.2 hérité inchangé : il porte 3.10.0. Les adaptations Swift doivent couvrir plannedWaypoints (omission / [] / remplacement), teachingLanguage, la validation des permis et AP193–AP201, les observations textuelles autonomes, la nullabilité des segments vides et les nouveaux snapshots tarifaires. La navigation Compte et le reçu après suppression ne dépendent pas d’un SessionScope scolaire actif. Le reçu a une clé Keychain et un transport strictement séparés des access tokens ; il ne participe pas au refresh OIDC. Aucun build du client généré n’est revendiqué dans cette revue.

<a id="contrats-de-publication-remise-et-clôture-v36"></a>
## Publication, remise et clôture
Encoder `textObservationSelection` explicitement, même vide, et afficher les `textObservations` sans demander Core Location. Distinguer `SegmentManifest.lastSequence == nil` parce que le segment est vide d’une erreur de décodage. Le tableau de remise et les prix de pack utilisent les snapshots reçus, pas une somme locale définitive. Une clôture collective possède sa revue des droits inutilisés ; un 202 laisse l’opération en attente. Les pages d’aperçu de suppression sont rattachées à la même version, sans état de sélection d’école ajouté à une demande globale.

<a id="compléments-de-qualification-v37"></a>
## Qualification des sources et des interruptions
Le collecteur applique la [provenance des mesures R111](../03-fonctionnel/regles-etats.md#r111), avec source mesurée et horloge de réception distinctes. Les doubles de source doivent livrer une ancienne position, plusieurs mesures en lot et un callback après scellement ; la vue n’utilise jamais une coordonnée par défaut comme premier point. Swift `Date` ne remplace pas l’horloge monotone du bail.

Le client API décode `rightSettlement=null`, REVIEW_REQUIRED et les résolutions sans transformer une régularisation en paiement. Une attendance confirmée peut exiger la relecture d’exigences invalidées ; un écran quitté n’annule pas cette transaction. Le profil d’application fournit l’environnement APNs de manière contrôlée, sans convertir arbitrairement WEB ou une valeur inconnue en IOS. Les champs de preuve côté serveur ne sont pas générés par l’UI Swift pour accélérer une validation.

## Référence graphique choisie

L’option A Cartographie native est choisie. Utiliser les [tokens canoniques](../annexes/tokens-proposition.json), la [spécification des composants](../DESIGN/02-composants.md) et la [livraison Swift](../DESIGN/06-livraison-validation.md). Le prototype HTML illustre composition et microtextes ; **il ne doit pas être embarqué dans une WebView pour remplacer le client Swift**. Les composants et classes CSS ne deviennent ni DTO ni sources de vérité métier.

<a id="traduction-des-corrections-de-maquettes-v39"></a>
## Correspondance entre maquettes et composants natifs
Les valeurs de formulaire appartiennent au modèle de brouillon identifié par compte/école/leçon, pas à une reconstruction à partir de valeurs initiales dans `body` ou `onAppear`. Les effets de mutation et la capture demeurent hors de la durée de vie d’une vue. Le retour vers une capture ouverte observe le même coordinateur ; la scène ne demande pas une nouvelle session.

Préserver les trois champs de bilan et `ObservationInput.context` ; l’absence de niveau omet l’observation. Contrôler les longueurs dans la convention du contrat plutôt que de supposer que `String.count`, UTF-16 et le comptage Unicode d’un validateur JSON sont interchangeables. Le client effectue une aide à la saisie, le serveur valide les bornes. L’aperçu ne remplace pas les préconditions de PublishCommand.

La fixture temporelle de la galerie n’est pas une bibliothèque Swift à recopier : le replay natif utilise les timestamps et identifiants de segments autorisés de l’API. Les nouveaux scénarios UX de [livraison design](../DESIGN/06-livraison-validation.md) doivent être reproduits avec l’état applicatif réel, VoiceOver et les modes de fenêtre ; les résultats Chromium ne les marquent pas exécutés.

<a id="confidentialite-transports"></a>
## 10. Transports de fichiers et confidentialité des scènes

Créer deux configurations URLSession distinctes : client Drivy authentifié vers les origines API connues, et PUT de staging sans bearer Drivy ni cookies applicatifs. Ne pas mutualiser un intercepteur qui ajoute Authorization à toute URL. Sur ces sessions, désactiver les caches HTTP persistants et le stockage automatique de cookies non requis ; une configuration éphémère et `urlCache=nil` sont des candidates d’implémentation à compiler et tester sur le SDK retenu. Ne pas mettre de réponse sensible dans URLCache en remplacement du magasin SQLCipher. Les projections hors ligne restent autorisées uniquement dans le stockage chiffré délibéré de F12. Les exports et médias temporaires suivent la même politique de fichiers/clés, sans cache disque en clair ajouté par un moteur d’aperçu.

Les en-têtes `private, no-store` ne suppriment pas rétroactivement des copies faites ailleurs [S131](../06-gouvernance/sources.md#s131). Origine exacte, méthode, en-têtes et politique de redirect sont ceux du [transport canonique](fichiers-temps-communications.md#transport-fichiers). L’expiration d’une URL signée n’est pas une permission d’inventer un nouveau dépôt : appliquer la réconciliation de [reprise](fichiers-temps-communications.md#reprise-depot).

**Scènes et sélecteur d’applications.** Avant qu’une scène sensible passe en arrière-plan, masquer son contenu par une surface opaque neutre, sans identité, carte ni aperçu pédagogique. Apple décrit le snapshot utilisé par le sélecteur d’apps dans une note archivée [S132](../06-gouvernance/sources.md#s132) ; cette note n’est pas une recette SwiftUI/iOS 27. Le hook précis de cycle de vie UIKit/SwiftUI, son ordre et le cas multi-fenêtres doivent être testés sur les appareils qualifiés. Ne pas attendre un appel réseau ni animer cette couverture.

La couverture appartient à la scène et ne détruit ni le service GPS ni le brouillon. Au retour, retrouver le contenu seulement après vérification de la génération de session/école et du droit de lecture local encore valide ; pas de nouvelle biométrie imposée ni de connexion obligatoire si la lecture hors ligne autorisée reste valide. Une révocation connue garde un écran neutre et purge les projections selon F12/F14. L’indicateur système de localisation n’est pas masqué. Cette protection ne prétend pas empêcher les captures d’écran volontaires, la photographie de l’écran ou une copie explicitement exportée.
