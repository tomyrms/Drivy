# Replay : disponibilité et reprise du recalage (#91)

## Suite autorisée : fusion et déploiement

Après la livraison sur branche, le porteur a demandé la fusion et le déploiement, puis la clôture de #91. Le merge `36a3a70` a été poussé sur `master` avec `[skip ci]` pour respecter la campagne différée #84, sans modifier les workflows, les protections ou les contrôles de secrets. La branche principale n'avait pas de règle de protection imposant des checks. Le checkout des cours collectifs est resté sur sa branche.

Le 23 octobre 2026, sauvegarde de `drivy_refonte` dans CT113 avant changement : `/root/drivy_refonte-before-replay91-36a3a70-20261023T010832Z.dump`, mode 0600, 1 404 069 octets, synchronisation disque et catalogue `pg_restore --list` vérifiés. La base séparée `drivy_web` n'existe pas sur cet hôte. Le premier précontrôle s'était arrêté avant toute modification car le fichier facultatif `web-migration.env` n'existait pas ; la configuration réelle a été respectée, sans créer ce fichier.

L'installateur existant a compilé API et web avec dépendances verrouillées sous Node 24.21.0, contrôlé les rôles/RLS et basculé `current` de `d05ca595` vers `36a3a70`. Les 41 empreintes de migrations appliquées en base ont été comparées au nouveau snapshot avant installation et sont identiques. API et web redémarrés, identité laissée active ; configurations inchangées, aucun nouveau calcul sur un trajet réel lancé par les contrôles.

La revue parallèle `gpt-6-sol`, route `openai-oauth`, effort effectif `low`, a fait relever un défaut de protection dans le script opérateur temporaire : un échec de l'installateur après changement du lien devait aussi déclencher le retour arrière. Corrigé avant exécution, avec vérification de la release active pour ne pas écraser un autre déploiement. Aucun retour arrière n'a été nécessaire. L'ancienne release et la sauvegarde restent disponibles ; une restauration de base n'a pas été testée.

Contrôles réels après déploiement : répertoires des processus API/web et empreinte source conformes au commit, services actifs, readiness interne réussie ; HTTPS via curl donne web/OIDC 200, accès anonymes `/me` et `matched-route` 401, santé privée et administration identité 404. Un premier contrôle Python urllib avait reçu 403 du chemin public ; les mêmes contrôles curl et le web interne ont donné les statuts attendus, sans changement de configuration. [Observations structurées](proofs/deployment-replay91-20261023.json).

#91 clôturée à la demande explicite du porteur à 01:10 UTC, sans clôturer #88. Les sources applicatives iOS, dépendances et script IPA de `36a3a70` sont identiques à `cc72954` : l'IPA réussie `39880760958` reste valable, à signer et installer par le porteur. Cette clôture ne transforme pas les contrôles de déploiement en recette authentifiée du replay : les vérifications comportementales et physiques listées ci-dessous restent réservées à #84.

## Périmètre du 23 octobre 2026

Base : `master` à `26297dd`. Branche isolée : `openai/91-replay-finalisation-20261023`.

Le découpage récursif des lots mal recalés existe déjà. La correction de compatibilité `49121c0` conserve l'algorithme serveur à 2 et fait accepter OSRM >= 2 par l'app. Ces comportements, la migration 040 et le recalage direct ne sont pas réimplémentés. Le démarrage compact #95 reste inchangé.

Le travail porte sur les motifs de disponibilité, les erreurs de lecture et la récupération du résultat pendant l'ouverture du replay. Aucun changement de moteur, de sélection des points, de migration ou de données réelles. Aucun déploiement.

## Contrat additif

`GET /v1/schools/{schoolId}/captures/{captureId}/matched-route` conserve `status`, `provider`, `algorithmVersion`, `reconstructionVersion`, `spans` et `generatedAt`. L'OpenAPI canonique 3.11.0 n'est pas modifié. Deux champs facultatifs pour les anciens serveurs sont documentés dans `apps/api/contracts/matched-route.json` :

| Motif `reason` | Statut historique | Sens |
| --- | --- | --- |
| `WAITING_FOR_SYNC` | `UNAVAILABLE` | Capture pas encore finalisée ou synchronisée |
| `PROCESSING` | `PENDING` | Calcul réservé ou résultat à relire |
| `MATCHED` | `READY` | Au moins un tronçon disponible, sans promesse de couverture complète |
| `NO_RELIABLE_MATCH` | `READY` | Résultat vide, sans diagnostic inventé de faible vitesse |
| `MATCHING_DISABLED` | `UNAVAILABLE` | OSRM privé non configuré pour ce service |
| `PROVIDER_UNAVAILABLE`, `RATE_LIMITED` | `UNAVAILABLE` | Moteur indisponible ou délai imposé |
| `PROVIDER_REFUSED`, `INVALID_RESPONSE`, `MATCHING_FAILED`, `ROUTE_TOO_LARGE` | `UNAVAILABLE` | Calcul en échec, motif borné |
| `CACHE_UNREADABLE` | `UNAVAILABLE` | Dérivé illisible, distinct d'une absence de correspondance |

`retryAfterSeconds` est un entier de 1 à 604800 ou `null`. Il indique le délai minimal avant nouvelle lecture automatique, pas une autorisation de contourner le bail ou le délai de recalcul. L'attente de synchronisation propose 5 secondes, le calcul 3 secondes, l'échec reprend le délai stocké en base. Un code d'échec inconnu est ramené à `MATCHING_FAILED`. Aucune URL de moteur, position ou réponse OSRM n'est exposée comme diagnostic.

Les motifs et le résultat restent soumis aux mêmes droits serveur que le replay. Les fonctions SQL de réservation/complétion, les protections de fournisseur et de reconstruction restent inchangées. Un cache illisible est signalé sans boucle de recalcul ni remplacement du stockage chiffré par du clair.

## Client iOS

La lecture de `matched-route` propage les erreurs au lieu de les convertir en `nil`. Le replay mesuré reste accessible lors d'une panne de recalage. Les refus d'accès suppriment en revanche le contenu privé déjà chargé.

Une ouverture prévoit au plus six reprises automatiques. Les délais augmentent de 2 à 30 secondes et respectent tout délai serveur plus long. Le budget de 120 secondes borne la planification des reprises, pas la durée d'une requête réseau déjà engagée. À épuisement, une action permet une nouvelle tentative sans fermer le replay. Un conseil serveur explicitement `null` arrête les reprises automatiques. Sur ancien serveur sans conseil, `PENDING` et `UNAVAILABLE` utilisent une reprise générique bornée, sans cause inventée.

La fermeture annule la tâche, y compris lorsqu'elle vient du bouton de relance. La génération de chargement et l'annulation sont vérifiées après les attentes. Le client refuse une réponse portant une autre capture ; l'invalidation d'accès vide les données et empêche une réponse tardive de les réintroduire.

Après synchronisation ou changement de reconstruction, le client recharge les mesures. Une actualisation remplace toutes les pages ensemble, sans publier un préfixe plus court qui réduirait la durée du lecteur. Des lectures de recalage encadrent cette actualisation ; une reconstruction plus ancienne que celle déjà observée est refusée. Le lecteur conserve sa base temporelle, sa vitesse et son état lecture/pause. La sélection repose sur l'identifiant de l'observation, conservé lorsqu'il existe encore.

La couverture se calcule sur les intervalles effectivement acceptés et dessinés, pas sur le nombre de tronçons reçus. Les lacunes et points isolés ne sont pas comptés comme intervalles de trajet. La mention discrète « Recalage partiel » est indépendante de la qualité de synchronisation `PARTIAL`. Un résultat vide ou sans géométrie admise n'est pas présenté comme un recalage complet. Aucune faible vitesse n'est déduite de cet état.

## Répartition et coordination

- Coordinateur : contrat, API, tests PostgreSQL, intégration et documentation.
- Agent A : comparaison ciblée en lecture seule.
- Agent B : client iOS, état asynchrone du replay et tests Swift associés.
- Agent C : revue des patches, sans écriture.

Modèles effectivement relevés dans les métadonnées de session : coordinateur `gpt-6-astra` via `openai-oauth`, effort hérité `high` ; A `gpt-5.6-terra`, B `gpt-6-astra` et C `gpt-6-sol`, tous via `openai-oauth`, effort `low`. L'outil de délégation expose le modèle mais aucun paramètre d'effort. Aucun compte ni réglage global n'a été modifié. A est arrêté après son repérage, B et C après livraison et revue. L'intégration finale reprend la propriété des fichiers, sans écriture concurrente.

Le chantier cours collectifs travaille séparément dans le checkout principal. Aucun fichier d'agenda, contrat de réservation, registre `app.ts` ou migration de ce chantier n'est modifié ici. Les sections de `STATUS.md` devront être conservées toutes les deux lors d'une intégration future.

## Vérifications et recette #84

Déclencheurs lus et stratégie confirmée avec le coordinateur des cours : les push automatiques des workflows actuels ciblent `master`, `codex/**` et `claude/**`, pas `openai/**`. Aucune PR vers `master` n'est ouverte pendant ce chantier, car elle déclencherait les campagnes. Aucune modification des workflows ni désactivation des contrôles de secrets. Seul `ipa-essai.yml` peut être lancé manuellement au point d'intégration utile.

Exécuté à ce stade : installation verrouillée `npm ci --ignore-scripts --no-audit --no-fund`, `npm run typecheck`, `npm run build`, `git diff --check`. Le Node local est 26.8.1, hors cible projet 24 : les compilations locales ne qualifient pas l'exécution sous le runtime cible. Aucun compilateur Swift local disponible sous Windows.

Commits : serveur `2be1783`, client iOS et scénarios `cc72954`, préparation des assertions mutantes hors macros Swift Testing `1d5127a`. Revue indépendante des patches API et iOS : aucun défaut P1/P2 confirmé. Cette lecture n'est pas une exécution de tests.

IPA légère demandée manuellement sur `cc72954` : run `39880760958` réussi le 23 octobre 2026 à 00:57 UTC. Compilation Release, archive Xcode et paquet IPA non signé terminés ; artefact `Drivy-essai-cc7295414671270c88ac152b1a554cac29ba47d1` publié. Ce workflow archive seulement l'application ; les fichiers de tests Swift ne sont ni compilés ni exécutés par cette commande. Le commit `1d5127a` ne change que les tests. Aucun essai sur appareil n'est revendiqué.

Tests préparés, non exécutés conformément à #84 : `apps/api/test/matched-route.integration.test.ts` vérifie les motifs attente/calcul/résultat vide/moteur désactivé, le délai des échecs, le refus d'accès aux motifs, les codes inconnus et le cache illisible avec conservation des chunks et du replay. Les scénarios existants de concurrence, d'anciens fournisseurs/versions, d'expiration de bail et de retrait restent en place.

Les tests Swift `SchoolCaptureReplayTests` et `SchoolTrackDisplayTests` préparent les cas attente puis résultat, panne transitoire, budget épuisé, conseil serveur, ancien serveur, réponse d'une autre capture, annulation pendant attente et pendant réponse, génération remplacée, compte invalidé, refus d'accès, versions de reconstruction successives, actualisation paginée et sélection, couverture complète/partielle/rejetée, conservation de la vitesse et de la lecture. Les fixtures sont synthétiques et passent par le vrai client HTTP avec un transport de test, sans réseau ni position réelle.

Restent à exécuter dans #84 : tests API sur vraie PostgreSQL isolée et runtime cible, tests Swift/UI sur runner Apple, reprise après synchronisation/erreur et absence de résultat avant épuisement du budget, conservation de la lecture et de la sélection lors d'une géométrie tardive, changement de compte/capture/droits, compatibilité ancien serveur et ancienne app. Les essais physiques GPS, iPad, VoiceOver, autonomie et géométrie réelle ne sont pas déduits d'une compilation.

## Contrôle supplémentaire de sélection et traçabilité

La cible XcodeGen inclut le dossier `DrivyTests`, mais la liste explicite du mode GPS omettait `SchoolCaptureReplayTests`. Le contrôle existant `TestSelection.test_explicit_gps_matches_default`, avec l'attente corrigée, a échoué sur cette omission. Après ajout de la suite au vrai script `scripts/ios/test-selection.sh` dans `bb7d0fc`, `python -B scripts/ios/test_test_selection.py TestSelection` passe : sept contrôles de sélection, sans commandes Apple. Cette exécution vérifie les arguments réellement produits par le script de production. Elle ne simule pas une réussite de compilation ou d'exécution Swift. Les cas utilisant de fausses commandes Apple (`SimulatorArguments`) n'ont pas été lancés.

La sélection GPS par défaut et explicite inclut désormais la nouvelle suite. Les sélections `all`, UI et visuelle restent inchangées ; les modes et entrées invalides sont refusés. Ce complément a été signalé au coordinateur des cours. Aucun workflow ni déclencheur n'a changé.

| Exigence / sortie modifiée | Vérification prévue | Observation obtenue |
| --- | --- | --- |
| Régressions replay découvertes par la future recette GPS | Script de sélection réel et présence des noms de suites dans les sources | Échec reproduit, corrigé, contrôles ciblés réussis |
| Budget, espacement et conseil serveur | `retryBudgetBacksOffAndNeverShortensServerAdvice`, `pendingForeverStopsAfterSixAutomaticRetries`, `serverDelayBeyondBudgetDefersWithoutAnotherRequest` | Code applicatif compilé dans l'IPA ; assertions Swift non exécutées |
| Attente, erreur et résultat disponible sans réouverture | `pendingThenReadyKeepsMeasuredReplayAndAddsGeometry`, `transientFailureBetweenPendingAndReadyDoesNotEndPolling`, `waitingForSyncReloadsMeasurementsBeforeApplyingNewReconstruction` | Non observé en exécution |
| Anciens serveurs, absence fiable et réponse invalide | `matchingAdviceDistinguishesLegacyPendingExplicitStopAndUnavailable`, cas legacy UNAVAILABLE, `readyWithNoReliableGeometryIsTerminalNotAnOutage`, `invalidMatchingResponseKeepsMeasurementsWithoutAutomaticRetry` | Non observé en exécution |
| Arrêt et réponses périmées, autre compte/capture, refus d'accès | Tests d'annulation pendant attente/réponse, génération remplacée, compte invalidé, autre capture et refus 403 dans `SchoolCaptureReplayTests` | Non observé en exécution |
| Remplacement atomique des pages et sélection | `refreshKeepsTheOldCompleteReplayUntilEveryNewPageArrives`, cas de reconstruction successive/régressive | Non observé en exécution |
| Couverture complète, partielle, rejetée et raccords | Assertions `matchingCoverage` et deux nouveaux cas de tronçons rejetés/adjacents dans `SchoolTrackDisplayTests` | Code de couverture compilé dans l'IPA ; rendu non observé sur simulateur/appareil |
| Vitesse, instant et lecture/pause après géométrie tardive | `lateMatchedGeometryPreservesPlaybackInstantSpeedAndPlayState` puis recette UI réelle | Non observé en exécution |

Limite vérifiée : pas de compilateur Swift local. Le workflow Apple existant n'expose pas de mode « compiler seulement les tests » ; ses modes GPS/all exécutent des tests, son mode visuel lance des captures. Aucun de ces modes n'a été détourné ou lancé pour contourner #84. Les contrôles de sélection ci-dessus ne ferment donc pas la boucle de validation comportementale du replay.
