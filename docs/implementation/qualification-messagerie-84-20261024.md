# Qualification #84 : messagerie et candidat de branche

Campagne commencée le 23 octobre 2026 à 22:10 UTC (24 octobre, heure locale UTC+02). Branche `openai/65-messagerie`, PR #96 toujours en brouillon. Le porteur a demandé l'exécution des tests puis l'affichage de Messages une fois qualifié.

## Périmètre réellement testé

Candidat initial : `e2657c493029153d46f2ca4ae034ebe8d01304bd`. Les trois workflows ont résolu ce même SHA, relevé après leur lancement. Les corrections suivantes devront être requalifiées sur un nouveau SHA.

L'issue #84 porte aussi sur les cours collectifs. Cinq commits propres à `vague/cours-collectifs` ne sont pas présents dans ce candidat. Le checkout des cours contient du travail local en cours : aucun changement, stash, nettoyage ni fusion de ce travail n'a été effectué. Le manifeste conserve ces critères comme non qualifiés, pas comme des exclusions implicites.

## Première exécution

| Domaine | Preuve | Résultat observé |
| --- | --- | --- |
| API, PostgreSQL 17, Node 24 | Actions `40031983397` | FAIL : 596 tests réussis, 21 échoués sur 617, quatre fichiers en échec. Tests web de ce job non exécutés après l'échec API. |
| Intégrité documentaire | Job indépendant du run `40031983397` | PASS, ne qualifie pas le produit. |
| Navigateur, OIDC, BFF, API, PostgreSQL | Actions `40031985954` | PASS sur le candidat initial. |
| Swift et UI iPhone/iPad | Actions `40031925552` | FAIL à la compilation des tests : optionnel non déballé et captures MainActor dans des closures Sendable. Aucun test natif exécuté. Correctif committé `d11301b`, reprise métier ciblée `40032779482` en cours. |
| Web local | `npm run typecheck --prefix apps/web`, `npm test --prefix apps/web`, `npm run build --prefix apps/web` | PASS : 320 tests, 28 fichiers. Windows, Node 26.8.1 hors cible Node 24 : preuve complémentaire, pas substitution à la CI cible. |
| Sélection des tests Apple | `python -B scripts/ios/test_test_selection.py` | PASS : 14 tests de scripts, sans exécution Apple. |
| Orchestration des captures | `python -B scripts/ios/test_visual_capture.py` | Première exécution en échec : Bash WSL absent, décodage UTF-8 Windows et listes shell/Swift divergentes. Après correction du harnais et de la liste Swift : 11 tests réussis. Commandes Apple simulées uniquement. |
| Provisionnement opérateur | `node --test scripts/dev/provision-school.test.mjs` | BLOCKED : dépendances installées puis refus d'authentification du laboratoire PostgreSQL codé en dur, avant toute écriture. Un garde-fou réussi, test parent échoué. Le laboratoire Keycloak/Edge requis n'est pas celui de la CI navigateur. |

L'installation verrouillée web signale cinq vulnérabilités de dépendances (une basse, deux modérées, deux hautes). Aucun `npm audit fix --force`, changement de dépendance ou verdict d'exploitabilité n'en a été déduit.

## Conditions d'affichage

Les décisions du 23 octobre ont fixé le SDK Matrix, les règles d'accès, les sondages, la modération et les interactions enrichies. Photos et fichiers sont différés vers #97. La conservation et l'export restent à décider, sans délai inventé.

Les routes serveur acceptent uniquement `mode: test-synthetic` avec `NODE_ENV=test`. Une compilation ou un test synthétique réussi ne suffit pas à rendre une IPA utilisable contre le service actuel. L'activation devra être cohérente entre le client et un serveur qualifié, sans utiliser `NODE_ENV=test` en production.

Restent distincts des suites automatisées : recette VoiceOver et arrière-plan sur appareils physiques, preuve du périmètre d'hébergement et de restauration, et parcours E2EE intégré de plusieurs appareils via le relais Drivy. Aucun de ces résultats ne peut être déduit d'un simulateur ou des scénarios SDK isolés.

Aucun déploiement, fusion ou clôture d'issue effectué par cette campagne. Les gardes d'activation ne sont pas levées tant que les preuves nécessaires manquent.
