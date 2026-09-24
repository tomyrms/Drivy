# V3.4 : Swift natif devient la référence Apple

> 19 septembre 2026 · [Index](../README.md). Dossier complet corrigé à partir de V3.3. **Le porteur confirme Swift natif pour iPhone et iPad.** Le code de l’application et les archives sources ne sont pas modifiés.

<a id="apports"></a>
## Ce qui change réellement

La V3.3 conservait une proposition React Native/Expo, alors que le porteur souhaite une réalisation Apple native. La V3.4 remplace cette proposition dans les références actives. Il ne s’agit pas de rebaptiser un wrapper ni de faire passer une préférence pour une garantie de qualité. Le choix Swift est accepté ; les bibliothèques, modèles de code et paramètres précis restent des recommandations à qualifier.

| Domaine | Référence V3.4 | Documents principaux |
|---|---|---|
| Décision technique | Swift natif iPhone/iPad accepté ; SwiftUI et UIKit ponctuel recommandés | [ADR01/18/19](../04-technique/architecture-decisions.md), [client Swift](../04-technique/architecture-client-swift.md) |
| GPS | Core Location direct, profil minimal à qualifier, service possédé hors des vues | [iOS/iPadOS](../04-technique/integration-ios-ipados.md), [GPS fonctionnel](../03-fonctionnel/gps-replay.md) |
| Carte | MapKit direct proposé, UIKit seulement si nécessité démontrée | [architecture Swift](../04-technique/architecture-client-swift.md) |
| Concurrence | Isolation, génération de session, réentrance après await et barrière d’arrêt | [coordinateur](../04-technique/architecture-client-swift.md#capture) |
| Persistance | SQLCipher natif proposé, Keychain et fichiers qualifiés sous verrouillage | [persistance](../04-technique/architecture-client-swift.md#persistance) |
| Réseau | URLSession et adaptateurs/génération Swift à éprouver contre OpenAPI | [client HTTP](../04-technique/architecture-client-swift.md#api-swift) |
| Authentification et push | Session système, OIDC/PKCE, Keychain, notifications/APNs natifs | [transverse](../04-technique/integration-mobile-transverse.md) |
| Builds et tests | Xcode/SwiftPM, binaire signé, Swift Testing et XCTest selon le type de test | [qualification](../05-realisation/qualification-mobile-ui-ux.md) |
| Android | Client futur distinct ; Kotlin/Compose proposé, GA0 dédié | [préparation Android](../04-technique/preparation-android.md), [roadmap](../05-realisation/roadmap-backlog.md) |
| Références communes | Même backend, OpenAPI, fixtures et règles serveur ; pas d’UI universelle | [architecture](../04-technique/architecture-decisions.md) |

Le dossier contient **60 fichiers Markdown**, dont deux nouveaux : architecture-client-swift et ce journal. Les descriptions fonctionnelles existantes restent en place. Les changements sont intégrés à l’index, à la synthèse, aux recherches concernées, aux décisions, à la synchronisation, à l’exploitation et aux tests, pas laissés dans un addendum concurrent.

## Ce qui ne change pas

GPS et apprentissage restent centraux, capture volontaire, inscription collective jamais automatique, packs configurables et indépendants du temps GPS, web détaillé, tablette et onboarding progressif. Le backend proposé demeure TypeScript/Fastify avec PostgreSQL/worker ; le frontend web reste distinct.

**Le contrat OpenAPI est conservé octet pour octet.** Son `info.version` 3.2 désigne le contrat hérité, tandis que le dossier est en 3.4. Les 192 opérations, 344 schémas et 284 scénarios métier T ne sont pas augmentés pour un changement de client. Les 109 cas de validation de schéma restent des contrôles de forme, pas des tests Xcode.

## Précisions de conception à connaître

**Concurrence Swift.** Une isolation par acteur ne rend pas toutes les opérations contenant `await` atomiques. Le démarrage, l’arrêt, les callbacks retardés et le changement de compte ont donc une stratégie explicite. C’est une exigence d’implémentation, pas la correction d’un crash observé dans l’ancienne app.

**Arrière-plan.** La collecte et le transfert sont séparés. Le profil Core Location est à éprouver sur appareils. L’envoi de chunks JSON est repris quand le processus peut travailler, au minimum au retour au premier plan. Un upload système de fichier ne devient pas obligatoire si cela introduit un fichier GPS temporaire en clair ou contourne les droits actuels.

**Distribution.** Le dossier ne prévoit plus de code mobile mis à jour par bundle JavaScript distant. Il ne promet pas non plus qu’une application peut bloquer toute mise à jour ou terminaison décidée par le système. Le journal et les migrations doivent tolérer ces interruptions ; aucun rollback de binaire n’inverse magiquement les données.

**Android.** L’ancien prototype Android obligatoire en G0 est remplacé par l’analyse des contrats dès G0 Apple, puis GA0 pour le prototype Android avant son chantier complet. Cette proposition de séquençage reflète deux clients séparés et des moyens non établis ; elle ne retire pas Android de la vision. Un lancement simultané exigerait un autre engagement de ressources.

**Historique.** Les journaux V2/V3/V3.1/V3.2/V3.3, anciennes annexes et références à Expo/React Native restent conservés comme preuves datées, avec statut historique. Ils ne sont pas des instructions actuelles. Un moteur de recherche peut les retrouver ; la lecture de développement doit partir de l’index V3.4 et des registres V3.4.

<a id="decisions"></a>
## Décisions encore à qualifier

| ID conservé | État V3.4 | Sortie attendue |
|---|---|---|
| D11 | **ACCEPTÉ : Swift natif Apple** | Ne plus demander de choisir Expo pour réaliser iPhone/iPad. |
| DM01 | Minimum commercial et appareils ouverts | Matrice iOS/iPadOS 26/27 par binaire/appareil, minimum approuvé selon écoles pilotes. |
| DM02 | Framework Apple décidé ; détails de build ouverts | Xcode/macOS, compilateur/mode Swift, SwiftPM, profil Core Location et tests conformes. |
| DM03 | MapKit direct proposé pour Apple | Prototype replay/caméra/performance ; fournisseurs web/Android et conditions séparés. |
| DM04 | Android futur distinct | Ressources et pile Android approuvées, prototype GA0 puis qualification avant lancement. |
| DM05 | Persistance et clés à qualifier | Édition/version/licence SQLCipher, politique Keychain/fichiers, migrations et perte de clé. |
| DM06 | **Blocage avant publication publique** | Contrat et parcours de suppression globale du compte, pas simple archivage scolaire. |
| DM07 | Budgets et UX à mesurer | Seuils fixés avec preuves appareil et observation des parcours, sans métriques inventées. |
| DM08 | Modèle économique et distribution ouverts | Traitement des prestations et règles de store correspondant aux flux réellement proposés. |

Les autres questions de responsabilités, durée de conservation, réglementation, fournisseurs et migration restent dans le [registre général](glossaire-decisions-questions.md). Le choix Swift ne les résout pas par lui-même.

## Recherche complémentaire et limites

Neuf nouvelles références primaires S97–S105 ont été consultées pour SwiftUI, MapKit, Core Location, Keychain, acteurs Swift, tests Xcode, génération OpenAPI, SQLCipher et APNs. S63 sur Xcode a été reconsultée. Les références anciennes ne sont pas présentées comme toutes revalidées ; le guide APNs ajouté est explicitement archivé et n’atteste pas de signatures de SDK actuelles. [Registre des sources](sources.md).

La lecture source V3.3 a précédé la correction et les contrôles antérieurs ont été relancés sur cette base. Les différences techniques sont issues de la décision du porteur et de recommandations explicites ; les prix des dix écoles et les réglementations scolaires ne sont pas recherchés à nouveau dans cette passe.

## Contrôles et essais

Les registres contiennent désormais **16 exigences MX et 52 scénarios MOB**, dont 12 nouveaux cas Swift. Les cas MOB001, MOB006, MOB031, MOB033 et MOB034 ont aussi été réalignés sans changer leur identifiant. Tous sont **NOT_EXECUTED**, de même que T001–T284. Six lignes de matrice demeurent **NOT_QUALIFIED**.

Le [rapport documentaire](../annexes/verification-documentaire.json), le [rapport mobile V3.4](../annexes/verification-mobile-v3-4.json) et le [contrôle de cohérence Swift](../annexes/verification-swift-v3-4.json) décrivent les résultats exécutés. Le contrôle Swift cherche les anciennes dépendances dans les références actives, vérifie la décision et la traçabilité des nouveaux cas ; il ne prouve pas toutes les propriétés sémantiques possibles.

Le lecteur HTML est régénéré depuis les textes et vérifié séparément. Le [diff V3.3→V3.4](../annexes/corrections-v3-3-vers-v3-4.patch) et la [provenance](../annexes/provenance-v3-4.json) identifient les changements. Les empreintes des sept ZIP sources permettent de vérifier leur conservation.

**Limite de livraison :** aucun build Swift, aucun test d’application, aucune qualification GPS/batterie/appareil et aucun audit juridique ne sont exécutés. La chaîne documentaire vérifie des fichiers et contrats ; la prochaine preuve de fonctionnement reste le parcours vertical natif réellement compilé et testé.
