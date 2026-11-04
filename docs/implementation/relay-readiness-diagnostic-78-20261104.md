# Diagnostic fermé de la readiness du relais Apple — #78

Date : 4 novembre 2026. Tâche d'instrumentation, pas de correction du relais.
Base : `883581ad321b67ae3b7efe15ef2c6b89970b1e20`, branche de travail
`tomyrms/issues-relais-diagnostic-78`. Aucun push, aucune CI, aucun redéploiement.

Correction 1/2 (candidat `412d2475`) : la preuve hôte vérifie désormais la chaîne et
l'identité TLS par OpenSSL (`-verify_hostname localhost`, `-verify_ip 127.0.0.1`) au lieu
d'une recherche de préfixe dans le texte du certificat ; les tests hôtes sont autonomes en
répertoire temporaire et s'exécutent avec Node 24.22.2. Le test Swift et le relais restent
inchangés.

## 1. Ce qui est établi et ce qui ne l'est pas

Le run Apple `41861281984` (job `126683437419`, SHA `883581ad`) est réellement rouge :
`MatrixMessagingRelayIntegrationTests/testRealRelayExchangeIdempotenceRecoveryAndContextRefusal`
échoue à `MatrixMessagingRelayIntegrationTests.swift:39` après 25,022 s avec
`étape=READINESS, diagnostic=NONE`. Aucune conversation n'a commencé.

Les artefacts du run établissent seulement que :

- le port `18443` écoutait et `curl` répondait avant et après `xcodebuild` ;
- `xcrun simctl keychain … add-root-cert` a rendu `trust_status=0` ;
- le test a échoué dans la requête HTTPS de readiness, avant toute conversation.

Ils n'établissent **pas** la cause : TLS, ATS ou réseau restent indiscernables.
La cause n'est pas devinée ici et aucun correctif du relais n'est annoncé.

## 2. Instrumentation livrée

### 2.1 Test Swift — `apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift`

Le nom et le sens du scénario FFI attendu par
`scripts/messaging-relay-qualification.py` ne changent pas :
`MatrixMessagingRelayIntegrationTests.testRealRelayExchangeIdempotenceRecoveryAndContextRefusal`.
Le test échoue toujours en cas de panne : aucun `skip`, `expectedFailure` ni succès de
remplacement.

Types et fonctions privés au fichier, sans module produit :

| Élément | Rôle |
|---|---|
| `RelayTransportCategory` (`String`) | `TLS`, `ATS`, `CONNECT`, `TIMEOUT`, `CANCELLED`, `OTHER` |
| `RelayTransportDiagnostic` | catégorie + code borné optionnel, rendu `TLS code=-1202` |
| `relayTransportDiagnostic(for:)` | classifie `any Error` par `NSError.domain`/`code` uniquement |
| `RelayReadinessMismatch` | statut HTTP borné + champ divergent optionnel |
| `RelayReadinessMismatch.Field` | `type`, `fixture`, `schoolId`, `instructorId`, `learnerId` |
| `relayReadinessMismatch(status:data:schoolID:instructorID:learnerID:)` | évalue la readiness sans exposer de valeur |
| `RelayReadinessDiagnosticTests` | 8 tests locaux du vocabulaire fermé, sans relais |

Mapping de transport, fermé :

| Codes `NSURLErrorDomain` | Catégorie | Code affiché |
|---|---|---|
| `-1206…-1200` | `TLS` | oui, code connu |
| `-1022` | `ATS` | oui |
| `-1004`, `-1005` | `CONNECT` | oui |
| `-1001` | `TIMEOUT` | oui |
| `-999` | `CANCELLED` | oui |
| `CancellationError` | `CANCELLED` | non |
| tout autre domaine ou code | `OTHER` | non |

Le `catch` produit désormais :
`Relais interrompu : étape=READINESS, diagnostic=NONE, transport=TLS code=-1202.`
Il n'appelle ni `String(describing:)`, ni `localizedDescription`, ni une sérialisation de
`userInfo` ; il ne lit ni URL, ni corps, ni en-tête, ni certificat.

Si la readiness répond mais diverge, le message devient :
`… : statut=200 champ=learnerId.` (ou `type`, `fixture`, `schoolId`, `instructorId`).
Le statut est borné à `100…599`, sinon `0`. Aucune valeur de champ ni corps JSON n'est
affichée. Le contrôle HTTPS loopback (`https`, hôte `localhost`/`127.0.0.1`, port
`1024…65535`, sans identifiants, requête, fragment ni chemin) est conservé tel quel ; le
transport réel n'est pas remplacé par un mock.

### 2.2 Hôte — `scripts/ios/relay-qualification.sh`

Nouvelle fonction `relay_verify_chain`, appelée en tête de `relay_start_server` (donc au
démarrage initial et lors de `relay_reset_fixture`) :

1. chaîne : `openssl verify -CAfile "$relay_directory/ca.crt" "$relay_directory/server.crt"` ;
2. nom exact : `openssl verify -CAfile … -purpose sslserver -verify_hostname localhost
   "$relay_directory/server.crt"` ;
3. IP exacte : `openssl verify -CAfile … -purpose sslserver -verify_ip 127.0.0.1
   "$relay_directory/server.crt"` ;
4. marqueurs `chain=ok|ko` et `loopback_identity=ok|ko` dans `relay-probe.txt` ;
5. en cas d'échec : `RELAY_TLS_CHAIN_INVALID` sur `stderr`, puis `return 1`.

Le nom et l'IP sont vérifiés par OpenSSL, pas par une recherche de préfixe dans le texte
du certificat : `localhost.evil` et `127.0.0.10` ne satisfont pas l'identité. Les options
`-verify_hostname` et `-verify_ip` sont celles d'OpenSSL 3.x, déjà employées par
`scripts/qualification/test_relay_plan.py`.

Comportement exact en cas d'échec : `relay_start_server` retourne 1 **avant** de lancer
Node ; sous `set -euo pipefail`, la qualification s'arrête. Ce n'est pas un
`continue-on-error` et la panne n'est pas masquée. Les sorties brutes d'`openssl` sont
redirigées ; aucun sujet, chemin, certificat ni clé n'est publié.

L'ajout de la CA au simulateur reste inchangé :
`xcrun simctl keychain "$1" add-root-cert "$relay_directory/ca.crt"`. Aucun contournement
TLS/ATS, aucune acceptation générale de certificat, aucun élargissement d'URL.

### 2.3 Test local de l'hôte — `scripts/ios/relay-diagnostics.test.mjs`

Neuf tests locaux, sans relais réel, sans service et sans dépendre d'un magasin de
confiance système :

- disponibilité de `bash` et `openssl` ; syntaxe `bash -n` du script ;
- absence de `NODE_TLS_REJECT_UNAUTHORIZED`, `--insecure`, `curl -k`, conservation de la
  ligne de confiance simulateur et présence des vérifications OpenSSL exactes ;
- chaîne valide, SAN `DNS:localhost,IP:127.0.0.1` : exit 0, `chain=ok`,
  `loopback_identity=ok`, aucune fuite dans `stdout`/`stderr` ;
- SAN trompeur `DNS:localhost.evil` avec IP exacte : chaîne ok, identité ko, exit 1 ;
- SAN trompeur `IP:127.0.0.10` avec nom exact : chaîne ok, identité ko, exit 1 ;
- certificat signé par une autre autorité : chaîne ko, identité ko, exit 1 ;
- absence de preuve : chaîne ko, identité ko, exit 1 ;
- vocabulaire fermé de `relay_mark` (nom ou valeur hors motif refusé, aucune sentinelle).

Les certificats sont synthétiques et éphémères, générés par le test avec `openssl` dans un
répertoire créé par Node (`mkdtempSync` sous `os.tmpdir()`). Le test ne dépend plus de
`artifacts/relais-diagnostic-78` ni d'un artefact de session antérieure. Bash ne supprime
rien : le nettoyage est fait par Node dans le même runtime, après vérification du chemin
absolu résolu, de son inclusion sous `os.tmpdir()` et du préfixe de racine créé. Aucun
chemin n'est transmis à un `rm -rf` shell.

## 3. Garanties de confidentialité des diagnostics

Sorties autorisées, exhaustives :

- transport : `TLS|ATS|CONNECT|TIMEOUT|CANCELLED|OTHER`, avec un code entier uniquement
  pour les codes URLError listés au §2.1 ;
- readiness : `statut=<0|100…599>` et `champ=type|fixture|schoolId|instructorId|learnerId` ;
- hôte : `chain=ok|ko`, `loopback_identity=ok|ko`, `RELAY_TLS_CHAIN_INVALID`, exit `0|1` ;
- étape et diagnostics de messagerie existants (`READINESS`, `CONVERSATION`, `NONE`,
  `D-*`, `H-*` bornés) inchangés.

Ne sortent jamais : URL, corps, en-têtes, jeton, nom de personne, identifiant de fixture,
valeur de champ, JSON, sujet ou SAN de certificat, chemin de certificat, clé, secret,
description localisée ou `userInfo`. Les tests Swift injectent des sentinelles
(`SENTINEL_TOKEN`, `SENTINEL_NAME`, `SENTINEL_CERTIFICATE`, valeurs de champs) et
vérifient leur absence. Le test hôte vérifie en plus qu'aucun chemin, nom de fichier,
sujet, SAN, marqueur `BEGIN` ou contenu de certificat n'apparaît dans `stdout`/`stderr`.
Les certificats de test sont exclusivement synthétiques et éphémères ; aucun certificat,
secret ou magasin de confiance réel n'est modifié. Les journaux de cette session
restent dans `artifacts/relais-diagnostic-78/`, ignorés par Git ; le test lui-même écrit
uniquement dans son répertoire temporaire puis le supprime.

## 4. Commandes et résultats réels

| Commande | Résultat | Exit |
|---|---|---|
| Node 24 `--test scripts/ios/relay-diagnostics.test.mjs` (avant correction de la preuve) | 5 passés, 4 échecs attendus : vérifications exactes absentes, SAN `localhost.evil`, SAN `127.0.0.10`, autre autorité | 1 |
| Node 24 `--test scripts/ios/relay-diagnostics.test.mjs` (après correction) | 9 tests passés, 0 échec, 0 ignoré | 0 |
| `bash -n scripts/ios/relay-qualification.sh` (Git Bash 5.2.37) | aucune erreur de syntaxe | 0 |
| `git diff --check` | aucune erreur d'espacement | 0 |
| validation synthétique de `scripts/messaging-relay-qualification.py` avec une suite relais à un cas et une seconde suite | `RELAY_SELECTOR_SYNTHETIC_OK` | 0 |
| `rg` sur `SUITE`/`METHOD`/nom du test | nom et sens du scénario inchangés | 0 |

Node utilisé : `v24.22.2`, binaire portable
`C:/Users/jtoma/AppData/Local/Temp/drivy-orchestration-20261104/node-v24.22.2-win-x64`,
exécuté par son chemin absolu, sans modification globale du `PATH`. OpenSSL local : 3.6.5
(MSYS2). Aucun paquet ajouté ; le test n'utilise que la bibliothèque standard et `openssl`
déjà installé. Les tests Swift n'ont pas été exécutés : aucun Xcode/Swift sur ce poste
Windows, et aucun changement Swift n'a été nécessaire pour cette correction.

## 5. Sources, skills et Codebase Memory

Sources lues directement :

- `Drivy_Conception_v3_17_2026-09-20/COMMENCER_ICI.md` et `AGENTS.md` ;
- `artifacts/apple-883581ad/RAPPORT.md` et `diagnostic-six-rouges.md` (cas 1) du worktree
  `issues-medias-crypto-97`, en lecture seule ;
- `apps/ios/DrivyTests/MatrixMessagingRelayIntegrationTests.swift` ;
- `scripts/ios/relay-qualification.sh`, `scripts/messaging-relay-qualification.py`,
  `scripts/ios/test-simulator.sh`, `scripts/qualification/test_relay_plan.py` ;
- `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift` (`SchoolURLSessionTransport`) ;
- `scripts/messaging-relay-qualification.mts` / `.test.mjs` pour les marqueurs existants.

Skills Superpowers réellement chargés :

- `systematic-debugging`
  (`C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\systematic-debugging\SKILL.md`) ;
- `test-driven-development`
  (`C:\Users\jtoma\.config\opencode\node_modules\superpowers\skills\test-driven-development\SKILL.md`) ;
- `verification-before-completion` avant la livraison.

Codebase Memory, projet unique dans ce worktree :

- projet `drivy-r7-relais-78-20261104`, racine
  `C:/Users/jtoma/orca/workspaces/Drivy/issues-relais-diagnostic-78`, mode `fast` ;
- réindexé au HEAD `412d2475` pendant cette correction : 39 017 nœuds, 165 411 arêtes,
  `status: ready`, `indexed_at 2026-11-04T18:25:49Z` ;
- recherche `search_graph` sur `SchoolURLSessionTransport` : classe
  `apps/ios/Drivy/SchoolAPI/DrivyAPIClient.swift:36-75` et méthode `send:51-74` ;
- couverture : `scripts/` et `docs/` sont exclus par défaut de l'index et ont été lus
  directement ; le fichier Swift de test est indexé et inchangé dans cette correction ;
  `DrivyAPIClient.swift` est `parse_partial` (`53-57`, `319-319`), sans incidence sur la
  ligne 51-74 utilisée ;
- aucun index d'un autre worktree n'a été utilisé ; les rapports du worktree #97 ont été
  lus comme fichiers, pas via son index.

## 6. Limites

- Aucune exécution Swift, aucun simulateur, aucun `simctl keychain`, aucun test de
  confiance réelle sur ce poste Windows. Les 8 tests Swift sont **préparés, non exécutés** ;
  aucun changement Swift n'a été nécessaire pour cette correction.
- Aucun RED de compilation n'est forgé. Le seul échec empirique reste le run
  `41861281984` ; sa cause TLS/ATS/réseau n'est pas déterminée.
- La preuve `openssl` de l'hôte ne s'exécutera sur le runner Apple que lors d'une
  prochaine CI autorisée. Localement, les cas comportementaux prouvent la chaîne, le nom
  exact et l'IP exacte avec OpenSSL 3.6.5 et des certificats synthétiques ; ils ne
  prouvent ni le trust simulateur ni le comportement d'iOS 26.4.1.
- OpenSSL 3.5.9 est déclaré par les artefacts du run Apple ; `-verify_hostname` et
  `-verify_ip` sont déjà utilisés par `scripts/qualification/test_relay_plan.py`. Leur
  disponibilité sur le runner n'est pas revérifiée ici.
- Les répertoires temporaires du test sont supprimés par Node avec garde de racine ;
  contrôle après exécution : 0 répertoire `drivy-relay-diag-*` résiduel.
- Une prochaine exécution Apple autorisée est nécessaire pour lire `transport=…` et
  `champ=…`. Cette tâche n'autorise ni push, ni rerun, ni CI, ni PR, ni fusion, ni
  déploiement, ni fermeture d'issue.
- **Instrumentation livrée, relais non réparé** : aucun changement de transport produit,
  de sécurité, de fixture métier ou de workflow.

## 7. Lecture d'une prochaine exécution

| Observation | Ce qu'elle établira | Ce qu'elle n'établira pas |
|---|---|---|
| `transport=TLS code=-1201/-1202/-1203/-1204` | le processus de l'app refuse la chaîne ou sa validité | la correction à appliquer |
| `transport=ATS code=-1022` | ATS bloque la connexion loopback | si un réglage produit est acceptable |
| `transport=CONNECT code=-1004/-1005` | le simulateur n'atteint pas le relais | la cause réseau exacte |
| `transport=TIMEOUT` / `CANCELLED` | délai ou annulation | la cause amont |
| `transport=OTHER` | erreur hors du vocabulaire connu | toute conclusion TLS/ATS/réseau |
| `statut=<200-599> champ=<champ>` | le relais a répondu, le contenu diverge | la valeur ou la cause du contenu |
| `chain=ko` ou `loopback_identity=ko` + `RELAY_TLS_CHAIN_INVALID` | la preuve hôte échoue avant l'app | un défaut ATS ou réseau |

Aucune de ces lignes ne doit être transformée en cause certaine sans la prochaine
exécution correspondante.
