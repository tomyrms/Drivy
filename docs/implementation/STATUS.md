# État de la réalisation

## 1er novembre 2026 — release `bdcf1faf` déployée sur le homelab (API + web), IPA d'essai lancée (`claude/deploy-20261101`)

- **Déployé** : `bdcf1fafa676494eac6c02af6ef0cacf7ed68a03` (master après #385 à #393 et le lot iOS #337 à #339), accord du porteur (« si il faut déployer, fais-le »). API, web et course-worker tournent dans `releases/bdcf1faf…` (précédente : `be8a0245`), répertoires réels vérifiés, zéro redémarrage automatique, identité inchangée, fichiers de configuration privés inchangés. Le drop-in `95-epic311-web.conf`, qui figeait le web sur `web-releases/f0aa7dce`, est retiré (copie dans `/root/` sur CT114) : le BFF est recompilé (route d'export du pilotage) et suit `current`.
- **Migrations 57 → 60** : `20261031_messaging_message_push`, `20261031_messaging_report_moderation_77`, `20261031_pilotage_metrics`. Noms et empreintes des 60 fichiers égaux à ceux de la base. Installeur inchangé ; seule la variable `DRIVY_BUILD_SHA` est fournie à son sous-processus (la configuration Vite l'exige depuis le portail unique, l'archive n'a pas de dépôt git).
- **Sauvegardes** (CT113, `0600`, `pg_restore --list` et lecture de tous les blocs, restauration répétée sur une base jetable puis supprimée) : `/root/drivy_refonte-before-bdcf1faf-20261101T135144Z.dump` (2 310 481 octets, 57 migrations, point de retour d'avant la release) et `/root/drivy_refonte-before-bdcf1faf-20261101T135615Z.dump` (2 397 038 octets, 60 migrations, avant le second essai). Copies locales dans `.local/backups/`. Un troisième dump valide (`…T135047Z`) vient d'un premier tir que ma comparaison de tables a refusé à tort (mauvaise base interrogée) ; rien n'a été déployé à ce moment.
- **Premier essai, 13:52 UTC** : release installée et services redémarrés, puis retour arrière automatique. Mon contrôle des routes de la boîte des signalements (#77) attendait 401 pour une école inconnue ; la garde de configuration de la messagerie répond 503 `MESSAGING_NOT_ENABLED` avant toute authentification. Défaut du contrôle, non du produit. Code revenu à `be8a0245`, web revenu sur `web-releases/f0aa7dce`, base gardée à 60 migrations additives (version précédente prête dessus), aucune restauration. Pendant ces quatre minutes la base était donc en avance sur le code.
- **Second essai, 13:56 UTC** : contrôle corrigé (école réelle, en-têtes factices) et sauvegarde fraîche. Tout est vert : readiness API ; 60 migrations ; HTML public identique octet pour octet au build de la release et portant le SHA ; 4 fichiers d'entrée servis ; OIDC (session anonyme, démarrage de connexion avec callback exact et PKCE S256, page de connexion du fournisseur, document de découverte, 2 clés publiées) ; sans jeton : export du pilotage API et BFF 401 (404 avant), préférences de messagerie 401, liste des signalements 401, changement de statut d'un signalement 401 (404 avant) ; aucun message d'erreur dans les journaux depuis le redémarrage.
- **IPA** : `gh workflow run "IPA d'essai · iLoader" --ref master -f messaging_qualification=true`, run 41313723110, succès, artefact `Drivy-essai-bdcf1fafa676494eac6c02af6ef0cacf7ed68a03`. Non téléchargée ni installée.
- **Retour arrière** : `.local/deploy-20261101.py --rollback` (lien `current`, drop-in du web, services ; la base n'est restaurée que si la version précédente ne tourne pas sur le schéma). Restauration complète seulement depuis le dump `…T135144Z`.
- **Non prouvé** : aucune connexion avec identifiants réels, aucun export du pilotage ni signalement avec jeton, aucun parcours authentifié ; un 401 anonyme prouve que la route existe, pas son comportement métier. Aucun résultat physique GPS, batterie ou VoiceOver.

## 1er novembre 2026 — qualification de la messagerie #77 (`claude/qualif-77-20261101`)

- **Code de l'app modifié** : entrée « Signalements » de Messages (`MessagingViews`, forme de toucher : un appui au centre de la ligne n'ouvrait rien), sélection des messages à signaler (`MessagingConversationView.selectable`, rond superposé dans la marge de la bulle au lieu d'un voisin qui rétrécissait la ligne et faisait couper les messages courts), boîte des signalements (`MessagingReportInboxViews`, date sur sa propre ligne). Aucun changement d'API, de contrat OpenAPI ni de migration ; un fichier de test API ajouté.
- **Exécuté** : 6 tests API sur PostgreSQL réel (vérifications, run 41260549546) ; scellement et lecture par l'administrateur contre le SDK Matrix réel et le relais jetable, tests métier iPhone « messaging » (runs 41260562839 et 41305480743, 91 tests, 0 échec, sur un code d'app identique à la tête) ; parcours d'interface sur fixture, trois tests (runs 41301709973, 41302920798 pour la boîte, 41309165061 pour la sélection et la confirmation sur la tête `15d8f8fb`). Huit captures iPhone clair, hors dépôt : `.local/captures-77/final/`.
- **Pourquoi le toucher du run 41260808224 échouait** : défaut de l'app (pas de forme de toucher), non de la fixture ni d'un délai ; corrigé et revérifié (section 11 de [messaging-reports-77.md](messaging-reports-77.md)).
- **Test de sélection** (`MessagingReportScreensUITests/testConfirmationBeforeSendingAReport`) : vert sur `0991774f`, puis cinq runs rouges (41302920798, 41304132896, 41305459276, 41306677916, 41307996593) quand j'ai voulu choisir des messages hors de la pastille épinglée (lignes sous l'écran, ligne de réponse sans libellé propre), vert sur `15d8f8fb` (41309165061). Il choisit désormais des lignes entièrement visibles ; il peut rester sensible à la position initiale du fil.
- **Défauts encore vus** : rond d'un message reçu centré sur la ligne entière (auteur compris), environ 25 pt au-dessus de la bulle ; bouton « Revenir en bas » devant le rond du sondage.
- **Non prouvé** : aucun essai sur deux appareils réels, E2EE réel de la fixture, sombre, iPad, grandes tailles, VoiceOver ; la conservation des preuves attend #68.
## 1er novembre 2026 — défauts Messages (`claude/messages-defauts-20261101`)

- **Code de l'app modifié** : `MessagingConversationView.statusLine` et `MessagingWorkspace.hasPendingMutation`. La ligne d'état sous une bulle garde sa hauteur tant que le message porte ma réaction ou une intention en cours : « Synchronisation… » ne fait plus remonter la bulle de 13 pt à la cinquième seconde. Arbitrage à valider à l'œil : ~16 pt d'espace sous les messages réagis.
- Bouton « Charger les messages précédents » : défaut absent sur master (vidéo du run 41262108155), aucun correctif ; la branche `claude/cles-messagerie-169-170-141` n'a aucun commit non fusionné.
- **Exécuté** : contrôle ciblé réussi (runs 41268464654, 41268473463), test des cinq secondes réussi deux fois, tests métier de messagerie réussis (run 41268482749). Détail et limites : [messages-defauts-20261101.md](messages-defauts-20261101.md).
- **Non prouvé** : le lien direct entre le décalage de 13 pt et l'appui perdu reste une hypothèse ; aucun résultat physique.

## 1er novembre 2026 — tests UI instables (`claude/tests-ui-stables-20261101`)

- Analyse de 173 runs iOS (journaux, deux artefacts, historique git) : sur les douze tests suivis, dix n'échouent plus depuis leur dernière correction (0 échec sur 8 à 41 exécutions de la version actuelle) ; deux échouaient encore sur master. Notes par test : [tests-ui-instables-20261101.md](tests-ui-instables-20261101.md).
- Corrigés : `SchoolAgendaUITests/testRefreshFailure…` (séance de 14:00 amenée à l'écran avant le compte final, `702865be`) et `MessagingLatencyUITests/testFiveSecond…` (retrait attendu dans l'état stable : un appui tombant sur la bascule « en cours de synchronisation » à 5 s est perdu ; réponse à l'ajout retardée de 15 s, `1dc697f5`). Code de test seul ; aucun fichier produit, aucune assertion retirée.
- **Exécuté** : agenda, runs 41254020521 et 41254915339, réussis ; cinq secondes sur le code final, runs 41257979928 et 41257987154, réussis. Trois essais intermédiaires abandonnés (8 s, 15 s sans attente : 41256319407 et 41257019945 rouges, appui perdu).
- **Défauts de l'app décrits, non corrigés** : bouton « Charger les messages précédents » derrière la barre de navigation sur iPhone ; appui perdu sur les réactions pendant la bascule « en cours de synchronisation ».
- **Limites** : les échecs de lancement du simulateur ne relèvent pas des tests ; deux passages ne prouvent pas une stabilité durable.
## 31 octobre 2026 — CI allégée (`claude/ci-allegee-20261031`)

- Mesures sur 600 runs (21 au 31 octobre) : 5 235 min macOS, dont 41 % en parcours UI iPhone + iPad (62 % en échec), 20 % en tests métier (compilation 6,3 min pour 959 tests en 77 s) et 19 % en IPA. Les « 59 minutes d'attente » du run 41234908420 sont une relance (tentative 2) ; les vraies attentes (28 runs, 303 min, jusqu'à 51 min) venaient du groupe de concurrence par branche. L'allongement depuis le 11/10 suit le dépôt : code ×1,8, tests UI 13 → 82, paquets Swift 2 → 9.
- Changé : « Refonte · iOS » refuse un lancement sans mode, ne rejoue l'iPad que sur demande (`ui_ipad=true`) ou en campagne complète (`full_campaign=true`), ne construit plus d'IPA sans `build_ipa=true`, et ne fait plus attendre ni annuler un lancement par un autre ; compilation arm64 seule ; API et web ne tournent que si les fichiers modifiés les concernent (tout tourne pour workflows, dépendances verrouillées, contrat OpenAPI, migrations ou doute) ; push et pull request dépassés annulés, master compris, sans jamais annuler un lancement manuel ni une qualification.
- **Exécuté** : tests Python (66), tests de structure des workflows (8), actionlint ; vérifications dispensées 41247626704, état final 41249234890, navigateur 41249234791, IPA 41249234793, iOS UI 41247640168 (`LaunchTests`, iPhone seul, sans IPA), iOS métier 41250320040 (`profile`) : tous en succès.
- **Limites** : gain macOS estimé à ≈ 14 % à usage égal (jambe iPad et IPA de campagne), gain de l'arm64 non établi ; campagne complète et `unit_test_scope=all` non redispatchés ; un démarrage anticipé du simulateur a été essayé et retiré (il bloque `xcodebuild`). Reste à trancher : iPad par défaut, relance des seuls tests en échec, tests UI instables, IPA sur master. Voir `docs/implementation/ci-20261031.md`.
<!-- reprise-372-20261030 -->
## 30 octobre 2026 — reprise #372 : pile iOS à jour de master, IPA 447 retenue, plan web prêt

Master `f0aa7dce17372ece43e7626346db21ae79221230` contient #347. Chaîne iOS vérifiée linéaire (#337 ⊂ #338 ⊂ #339) ; `master` intégré par fusions additives sans force-push : `74436ffd` (#337), `35ed4546` (#338), `0f8e33c7` (#339). Seul conflit : ce fichier, deux historiques conservés, contrôle automatique des lignes. Master avait remplacé un octet invalide de la ligne « alerte de mention » par un caractère valide : édition acceptée.

**IPA candidate : Drivy 0.7.0 (447), non signée**, [artefact](https://github.com/tomyrms/Drivy/actions/runs/40959499844/artifacts/12935631882) valable jusqu'au 12 novembre 2026, run 40959499844 sur `633f20d3b6893f66151ea95d266ac0fb5ceef1bf`, SHA-256 `92be049a68418aea3fc5994e01c23d5c62c1cf2533a5ac7f84c00f41c99ff2cc`. Réutilisée sans recompilation : aucune différence entre `633f20d3` et `0f8e33c7` sur `apps/ios/Drivy`, `project.yml`, `Package.resolved`, `build-ipa.sh`, `messaging-qualification.sh`, `ipa-essai.yml` ; seuls deux fichiers de `DrivyTests` diffèrent. Essai du porteur attendu : `NOT_EXECUTED`. Fusions #337 → #338 → #339 et tests iOS en attente de ce retour.

**Web : candidat `f0aa7dce`**, servi `4af4b0e6` (lu publiquement). Delta de 10 fichiers sous `apps/web/client`, trois de test compris ; aucun changement de BFF, dépendances, API, contrat, migration ni infra. Typage et 16 tests des fichiers modifiés réussis ; build Node 24.22.1, 105 fichiers, identité de build contrôlée. Plan `deploy-web-311.py` exécuté en lecture seule : `deployment-plan`, frontend seul, sans migration, cinq services sains. **Aucune écriture sur le serveur** ; `--execute` attend l'accord du porteur. Depuis Windows, lancer ce script en PowerShell : Git Bash réécrit `/opt/...`.

**Suites `--extended` : non exécutées**, après l'essai web. Sélecteurs recoupés au portail sans exécution : récupération de compte 6/6 présents ; saisie par code 15/16, le seizième étant un gabarit dynamique bien présent dans `.entry-facts` ; formations et tarifs à réécrire en partie (onglets au lieu de la navigation par liens, `.cat-competency-*`, déplacement par menu, messages de tarif et de reprise changés). Ce recoupement ne vaut pas résultat de test. La note précédente surestimait donc l'écart des deux premières.

### 30 octobre 2026, 18:05 Europe/Zurich — web `f0aa7dce` déployé après accord du porteur

Accord explicite du porteur sur `f0aa7dce17372ece43e7626346db21ae79221230`. Master était entre-temps à `028211d6` (#383), documentation de la roadmap seulement : code web identique, SHA autorisé conservé.

- URL : <https://drivy.shulker.ch/app/>. Reçu et identifiant de rollback : `20261030T170449Z-f0aa7dce1737`. Release précédente conservée : `4af4b0e6`.
- Sauvegarde CT113 : `/root/drivy_refonte-before-web311-20261030T170449Z.dump`, 2 232 328 octets, catalogue et blocs relus. Aucune restauration réelle : l'archive lisible n'est pas une répétition de restauration.
- Seul `drivy-refonte-web` a redémarré ; API, worker et identité gardent leur PID, ingress inchangé. Aucune migration, BFF compilée identique entre les deux releases (`diff -rq`), configuration privée inchangée selon le contrôle du script.
- PASS après bascule : SHA servi, HTML exact sur sept adresses, 104 fichiers statiques à l'empreinte, CSP `default-src 'none'` sans `unsafe-eval`, session anonyme `no-store`, 401 sur `/app/bff/me`, plan de rollback valide, zéro erreur `journalctl` du web sur dix minutes, Edge 1440 et 390 sans débordement ni erreur JavaScript sur quatre pages publiques. Seul 401 console : préférences sans connexion, comportement documenté.
- NOT_EXECUTED : parcours connecté, données réelles, essai du porteur, suites `--extended`, restauration de la sauvegarde. Rollback non exécuté.

### 30 octobre 2026, 18:30 Europe/Zurich — essai web validé, trois suites étendues vertes

Essai web validé par le porteur sur `f0aa7dce`. Suites `--extended` exécutées après ce retour, sur la PR #384.

- PASS : [run 41098462805](https://github.com/tomyrms/Drivy/actions/runs/41098462805), `fca6a78e`, 164 contrôles, Chromium, OIDC, BFF, API et PostgreSQL isolés, données synthétiques. Formations et tarifs, saisie par code, récupération de compte réunis dans le même run. Le code applicatif est identique à `f0aa7dce`, la version déployée.
- Saisie par code et récupération n'ont demandé aucune adaptation : la limite notée le 30 octobre était fausse pour ces deux suites. Formations et tarifs a été réaligné sur le portail : 29 assertions conservées, dont quatre adaptées à des comportements changés par #311 et listées dans la PR. Aucun défaut applicatif trouvé.
- Les trois suites sont raccordées à `validation-finale.yml`. Le parcours de base reste inchangé par défaut.
- Typage du harnais sans erreur dans les fichiers modifiés ; 3 erreurs préexistantes sur master dans d'autres scripts.
- PR #384 fusionnée sur décision du porteur : master `2a376c39`, identique à `fca6a78e`. Sur ce SHA, `Refonte · ouverture école navigateur` (41100489556, parcours de base) et `Refonte · vérifications` (41100488932) réussis. Code applicatif toujours identique à `f0aa7dce`, aucun redéploiement.
- NOT_EXECUTED : navigateur physique, lecteur d'écran, compte réel. Récupération par e-mail toujours désactivée en production.

<!-- ios-batch-15-20261029 -->
## 29 octobre 2026 — IPA 447 : 15 issues supplémentaires, 40 réalisées et fermées

Nouveau lot natif : #113, #117, #118, #125, #196, #200, #208, #209, #210, #214, #220, #227, #231, #238, #246. Les 25 issues de l'IPA 446 restent incluses. Les 40 clôtures GitHub sont confirmées sur demande explicite du porteur ; elles ne constituent pas une validation de recette physique. PR #337/#338/#339 en brouillon, retour d'essai attendu avant tests pertinents puis fusion dans master.

Branche `codex/ios-batch-15-20261029`, trois branches spécialisées séparées, base `2d9a5f64`. Les restes des issues déjà partiellement livrées ont été rapprochés de leurs commentaires/PR, sans recompter leurs anciennes réalisations. Aucun changement web/API/contrat/migration/homelab, aucun déploiement. EPIC #311 exclue ; seule cette entrée additive concerne le suivi partagé.

Compilation Release réussie : Drivy 0.7.0 (447), code produit `633f20d3b6893f66151ea95d266ac0fb5ceef1bf`, [IPA](https://github.com/tomyrms/Drivy/actions/runs/40959499844/artifacts/12935631882). Paquet non signé copié dans `C:/Users/jtoma/Downloads/Drivy-0.7.0-447.ipa` ; manifeste, SHA-256, CRC ZIP, plist, dépendances et copie vérifiés. Empreinte `92be049a68418aea3fc5994e01c23d5c62c1cf2533a5ac7f84c00f41c99ff2cc`.

Contrôles ciblés Apple réussis : agenda 73 tests (78 exécutions paramétrées, run 40954007339), consentement 20 (40957419205), profil 10 (40960532711), brouillons 49 (40961435005). SHA et limites documentés dans le guide ; les corrections ultérieures de garde d'agenda ne sont pas assimilées au SHA testé. Les échecs intermédiaires profil/brouillon provenaient du code de test et sont corrigés sans changer le produit de l'IPA. Vingt captures comparables avant/après inspectées pour #196/#220/#227/#231. Revues croisées et `git diff --check` effectués. Grandes suites, tests UI préparés, recette physique, GPS/batterie/VoiceOver : non exécutés.

[Livraison, preuves et recette de chacune des 40 issues](ios-batch-15-delivery-20261029.md). Les anciennes mentions d'attente de clôture ci-dessous sont remplacées par la demande explicite du porteur ; l'attente de validation et de fusion demeure.

<!-- ios-suite-19-20261029 -->
## 29 octobre 2026 — suite iOS : 19 nouvelles issues, 25 avec le premier lot

Branche `codex/ios-suite-19-20261029`, hors EPIC #311 et web de Claude. Implémentations : #201, #202, #203, #204, #206, #207, #211, #212, #213, #215, #216, #217, #218, #219, #228, #229, #230, #232, #240. Les six précédentes (#195, #197, #198, #199, #237, #241) sont incluses dans la même candidature.

Relectures croisées et `git diff --check` effectués. Compilation Release/IPA finale PASS : Drivy 0.7.0 (446), SHA `9e1769494f0d55e3eaf6cf9d1a6dca60d9d1cb55`, [IPA](https://github.com/tomyrms/Drivy/actions/runs/40947705309/artifacts/12931460123). Artefact téléchargé : SHA-256, CRC ZIP, plist, plateforme iPhoneOS et paquet non signé vérifiés. Tests ciblés préparés mais non exécutés ; grandes suites et essais physiques NOT_EXECUTED. Aucun déploiement, fusion dans master ou clôture. Retour du porteur attendu avant tests pertinents puis fusion/clôture. Détail et preuves : [livraison des 19 issues](ios-suite-19-delivery-20261029.md).


## 29 octobre 2026 — lot iOS indépendant de #311, avant essai

- Inventaire des 155 issues ouvertes et rapprochement commentaires/branches/commits/PR : [triage](ios-independent-triage-20261029.md). #311, sa reprise de #280 et les disponibilités web #248–252 sont exclus.
- Intégration `codex/ios-independent-20261029` depuis `master c94ec2bb` : connexion/récupération #195/#197/#198/#199 ([détail](ios-auth-195-199.md)), états d’envoi/épingles Messages #237/#241 ([détail](ios-messages-237-241.md)). Aucun changement web, API, contrat, migration, dépendance ou workflow ; aucun déploiement requis.
- Exécuté : revue de source, revue indépendante de l’authentification, contrôle de périmètre et `git diff --check`. Compilation Release/IPA réussie : build 445, SHA eb4a5aae, run 40941417787 ; paquet téléchargé et empreintes vérifiées. [IPA et reçu](ios-independent-delivery-20261029.md). Tests ciblés préparés, aucune suite exécutée pendant le développement.
- Attente du retour du porteur sur l’IPA avant tests pertinents, fusion et clôture. #50 non activée. Rendu/VoiceOver physiques, réseau dégradé réel, GPS/batterie : aucune qualification revendiquée.
- Entrée additive sur la branche iOS ; documents et worktrees du chantier #311 intacts.
## 30 octobre 2026 — intégration de la refonte, corrections et limites de recette

- Fusion de `origin/master` (README, roadmap et organisation du Project issus de #371) dans `codex/epic-311-rebuild` : aucun conflit ; les fichiers documentaires sont conservés et l'ancien frontend reste retiré.
- Entrée : après un refus de création de compte (adresse différente de l'invitation), le mot de passe saisi n'est plus effacé ; une seule alerte est affichée et la saisie reste corrigeable.
- Portail : le moniteur et la période sont conservés entre Agenda, Disponibilités et Absences ; la préparation d'une formation reste dans son espace ; l'onglet parent d'une fiche reste navigable ; une version ancienne de prestation n'ouvre plus le tarif courant ; le retour des préférences conserve la requête d'origine.
- Harnais navigateur « ouverture école » aligné sur l'éditeur de disponibilités et les parcours reconstruits, sans retirer d'assertion.
- **Exécuté** : typage API/web, builds, 523 tests web, vérificateur documentaire, 106 contrôles navigateur (ouverture d'école, invitations, préparation, disponibilités, première leçon, agenda, confirmation d'identité et réglage GPS), contrôles GitHub du dépôt.
- **Limites** : les suites navigateur étendues « formations/tarifs », « saisie par code » et « récupération de compte » ciblent encore l'ancienne présentation ; elles restent dans le dépôt et s'exécutent avec `--extended`, mais ne sont pas déclarées vertes par ce parcours. Déploiement homelab non effectué (build servi `4af4b0e6748081f90201169132cccd5c9fd6cfdb`), tests iOS et campagne exhaustive non exécutés. Project, labels et issues inchangés.

## 29 octobre 2026 — refonte web acceptée et tickets clôturés à la demande du porteur

- Retour explicite du porteur : « c’est parfait », puis demande de fermer tous les tickets concernant la refonte web. Les 56 tickets des deux epics sont CLOSED, état relu sur GitHub : #311 et #312–#336 ; #280 et #281–#309. #247/#255 étaient déjà fermés.
- #311 et #312–#334 clôturés sur livraison et acceptation produit. Ancienne direction #280/#281–#309 fermée comme remplacée. #335/#336 fermés administrativement comme non poursuivis dans ce jalon, avec limites de qualification explicites ; aucune case de test cochée sans preuve. L’historique et les critères initiaux sont conservés dans chaque ticket.
- Build homelab toujours `4af4b0e6748081f90201169132cccd5c9fd6cfdb`, Tomy School remplie. Cette opération de suivi ne réalise ni la campagne exhaustive, ni la fusion dans master ; elles ne sont pas présentées comme exécutées. [Livraison](epic-311-livraison-essai.md), [contenu de l’école](tomy-school-content-20261029.md).

## 29 octobre 2026, 22:47 — Tomy School remplie pour l’essai du porteur

- À sa demande explicite, ajout de 24 élèves et 3 moniteurs, 36 leçons, 16 bilans, 48 observations sans GPS, 8 cours/18 séances, 32 inscriptions, appels et règlements. Catalogue à 4 catégories/14 prestations, disponibilités et absences. Libellés naturels, aucun suffixe test dans l’UI. [Résultat et vérifications](tomy-school-content-20261029.md).
- Sauvegarde PostgreSQL vérifiée avant population atomique ; contraintes et conservation de l’existant contrôlées avant commit, lecture sous RLS après commit et rejeu annulé sans doublon. Aucun compte OIDC, invitation, message, position ou notification créés. Aucun changement du build web déployé.
- Essai et retour du porteur attendus ; campagnes complètes, fusion et clôtures restent différées.

## 29 octobre 2026, 22:25 — #311 déployé pour essai du porteur

- Nouvelle web app active sur https://drivy.shulker.ch/app/ au commit `4af4b0e6748081f90201169132cccd5c9fd6cfdb`. Sauvegarde PostgreSQL créée et archive relue avant bascule ; configuration sauvegardée, BFF et autres services inchangés ; plan de rollback vérifié après bascule.
- 34 contrôles navigateur synthétiques réussis, compilation/typage et tests ciblés réussis ; six routes publiques et 104 assets comparés au build, entrée réelle chargée dans le navigateur. [Reçu, limites et parcours à essayer](epic-311-livraison-essai.md#déploiement-effectif--29-octobre-2225-europezurich).
- **En attente du retour utilisateur** : essai authentifié personnel, corrections, campagnes complètes et qualification, performances/sécurité, fusion master et clôtures. Récupération e-mail désactivée dans la configuration existante ; fallback 404 hors routes connues reste celui de la BFF. Aucune qualification exhaustive revendiquée.

## 29 octobre 2026, soir — #311, reprise intégrée avant essai homelab

- Reprise de `codex/epic-311-rebuild` à `33232416`, sans réinitialisation. Sauvegardes récupérées dans trois worktrees isolés ; Équipe déjà intégrée vérifiée par équivalence de patch. [Livraison d’essai](epic-311-livraison-essai.md).
- #319/#320/#326/#327/#329/#330 raccordés : entrée et récupération, ouverture et préparation, catalogue et textes, participants/appel/règlements, recherche et réglages. Pages secondaires et blocages de planification conservés. Nouveau portail rendu unique ; 60 fichiers historiques retirés, garde du graphe d’imports et du bundle renforcée.
- **Exécuté** : typage client/serveur, compilation de production ; 91 tests ciblés d’intégration et contrôles ciblés des agents documentés. Recette navigateur synthétique 390 sombre/1440 clair avec recherche et focus ; recette finale consignée dans la livraison.
- **À suivre** : essai personnel sur données réelles après sauvegarde et déploiement web uniquement. Matrices complètes R24, PostgreSQL, performance, sécurité, accessibilité réelle et régression Apple différées au retour du porteur. Aucune fusion dans master, aucune clôture d’issue. L’inventaire des 110 vues indique l’intégration, pas une qualification exhaustive.

## 29 octobre 2026, après-midi — #311, cinq familles de plus, aperçu publié

- Reconstruits par le coordinateur pendant la limite d’usage des agents : Signalements (#331), Trajets (#332), Préférences personnelles (#333), Accueil et préparation (#321), fiche École (#330, coordonnées et fuseau). Retours de page et message « pas encore reconstruite » mutualisés dans `portal/components`. Socle : bouton fantôme désactivé sans bordure, barre basse à cinq espaces.
- Aperçu publié au SHA `ce3b3559` avec en plus les cours collectifs (#328). **Exécuté** : typage client et serveur, 472 tests web, deux builds, captures 1440/390 par famille, chargement public. **Reste** : #329 (participants, en cours chez Planning), fin de #326/#327, #330 confidentialité/GPS/informations élèves, #319 entrée et invitation, #320 ouverture et guide, puis raccord réel, retrait de l’ancien rendu et qualification. Aucune sous-issue clôturée.

## 29 octobre 2026 — #311, cours collectifs intégrés, branche sauvegardée

- Intégrés : cours collectifs (#328 : ajout depuis l’agenda, brouillon de série, séances, revue et publication, fiche, capacité, dates, annulation de la série, politique) et finitions Formations et tarifs (#326/#327 partiels). Pas encore publiés dans l’aperçu.
- **Exécuté** sur la branche intégrée : typage client et serveur, 472 tests web, build de production, build d’aperçu ; l’agent a joué Refus, Conflit et Réponse perdue sur les cours à 1440/390 en clair et sombre. **Non exécuté** : module de cours désactivé en navigateur, clavier et lecteur d’écran réels.
- En cours : #329 (participants), fin de #326/#327. Branche `codex/epic-311-rebuild` envoyée sur GitHub pour sauvegarde, sans CI ni PR. Aucune sous-issue clôturée.

## 28 octobre 2026, soir — #311, trois familles intégrées et publiées en aperçu

- Intégrés : Équipe (#325 annuaire, fiche membre, retrait d’accès, invitations), Disponibilités et Absences (#323), Formations et tarifs (#326/#327, partiels). Publiés sur l’aperçu isolé au SHA `e2a0d5e6`, données fictives. [Publication](epic-311-preview-publication.md#publication-avec-équipe-disponibilitésabsences-formations-et-tarifs).
- **Exécuté** : typage client et serveur, 465 tests web, deux builds, captures 1440/1024/390 clair/sombre, chargement public. **Non exécuté** : édition, refus et réponse perdue sur ces nouvelles pages par le coordinateur (les agents les ont exercés dans leurs worktrees selon leurs commits), console authentifiée contre une vraie BFF. **Reste** : #328 cours collectifs, fin de #326/#327, vague 2. Aucune sous-issue clôturée.

## 28 octobre 2026 — #311, généralisation lancée et console authentifiée raccordée

- Après « continue » du porteur sur les trois pilotes : shell à cinq espaces (seules les sections reconstruites sont proposées), registre des pages, données fictives par famille, primitives shadcn complémentaires. Correctif dossier élève : formation et affectation restent ouvertes après un refus.
- Console authentifiée reconstruite (#316) sur le même runtime que la console historique, activable par navigateur (`?presentation=nouvelle`). Défaut inchangé pour tous.
- **Exécuté** : typage client et serveur, 430 tests web (dont frontière du portail, vérifiée par injection volontaire), build de production, build d’aperçu, captures 1440/390. **Non exécuté** : la console reconstruite contre une vraie BFF. Rien de publié ni déployé dans ce lot.
- Agents Équipe (#325), Planning (#323/#328), Catalogue (#326/#327) arrêtés par la limite d’usage, travaux partiels non intégrés. [Reprise](reprise-epic-311.md).

## 28 octobre 2026 — #311, aperçu des trois pilotes publié

- À la demande du porteur, Agenda et Élèves intégrés à l’aperçu à côté de « Modifier les accès », navigation commune protégée par la saisie, choix du scénario d’essai. Publié sur l’aperçu isolé au SHA `0688868d`, données fictives. [Publication et retour arrière](epic-311-preview-publication.md#publication-des-trois-pilotes).
- **Exécuté** : typage client et serveur/tests, build d’aperçu (garde des imports hérités à 0), contrôle navigateur local de l’artefact sur les trois pages en largeur mobile et sombre, puis chargement public d’Élèves et d’Agenda au bon SHA. Corrigé à l’intégration : les onglets Base UI (variantes `data-horizontal`/`data-vertical` absentes du socle) plaçaient la liste et le contenu du dossier élève côte à côte.
- **Non exécuté** : bureau, thème clair, édition/refus/lenteur/réponse perdue sur Agenda et Élèves, tests du calendrier après intégration. **Connu, non corrigé** : les dialogues de formation et d’affectation se ferment après un refus (saisie conservée, erreur affichée). Inventaire de 125 sous-vues toujours non relu. Aucune sous-issue clôturée ; suite en attente du retour du porteur.

## 28 octobre 2026 — #311, premier aperçu limité à une page

- À la demande du porteur, priorité à « Modifier les accès » pour juger la DA. Nouveau rendu shadcn/Base UI, rôles cumulés, autorisations, relecture/confirmation, lecture, erreur conservant le brouillon, clair/sombre et mobile.
- Typage et essai navigateur ciblé réussis ; jeu de données fictif et entrée isolée. Compilation et publication consignées après exécution. [Détail et limites](epic-311-access-preview.md).
- Agents Agenda et Élève arrêtés à ce jalon, travaux conservés séparément. Suite de #311 et grandes campagnes en attente du retour visuel ; aucune sous-issue déclarée terminée sur cet aperçu.

## 28 octobre 2026 — audit UX, lot 9 : fil de discussion (#142, #168, #177)

- Branche `claude/audit-ux-lot9-fil`, sur master avec le fil Exyte. Zones d'appui des réactions et des reprises, menu de sourdine selon l'état réel avec l'heure de fin, erreurs qui s'expliquent avant de se masquer et sans renvoi aveugle. [Détail](audit-ux-lot9-fil-20261028.md).
- Validé à l'essai par le porteur (IPA build 431). Tests UI `MessagingLatencyUITests`, `MessagingThreadUITests`, `MessagingFeatureCheckUITests` : iPad réussis sauf deux lancements d'app ratés par le simulateur ; iPhone réussis sauf un retrait rapide de réaction, réussi à la relance ciblée sur cette branche et sur master (runs 40684982359, 40693720605, 40693724801). iOS seulement, rien à déployer.

## 28 octobre 2026 — audit UX, lots 5 à 8 (#148-#150, #159-#161, #164-#165, #166/#167/#171/#176)

- Branche `claude/audit-ux-lots-5-8`, sur les lots 2 à 4. Agenda : aller à une date, choisir soi-même l'horaire, sorties des blocages. Cours : langue, type avec description, suivi toujours visible. Bilan : trajets nommés par leur horaire, « Ce que verra l'élève ». Messages : état vide avec le général, recherche au-delà de la page, recherche des membres, école en sous-titre. [Détail](audit-ux-lots5-8-20261028.md).
- iOS seulement, rien à déployer. Tests non lancés avant l'essai du porteur.

## 27 octobre 2026 — audit UX, lot 4 : Mon profil (#155 à #158)

- Branche `claude/audit-ux-lots-2-4`. Résultat de la photo près d'elle et alerte de sortie exacte, cadrage avant envoi (ImageIO, 512 px, sans métadonnées), aperçu du nom affiché, « E-mail de contact », explications à la demande. [Détail](audit-ux-lot4-mon-profil-20261027.md).
- iOS seulement, rien à déployer. Nouveau test `SchoolProfilePhotoCropTests` écrit, pas encore exécuté.

## 27 octobre 2026 — audit UX, lot 3 : liste des élèves (#151, #152, #153)

- Branche `claude/audit-ux-lots-2-4`. Photos autorisées dans la liste, repère « Réf. » pour les homonymes, filtre serveur « Profil à compléter » combiné à la recherche. [Détail](audit-ux-lot3-liste-eleves-20261027.md).
- iOS seulement, paramètre d'API existant, rien à déployer. Tests non lancés avant l'essai du porteur.

## 27 octobre 2026 — audit UX, lot 2 : écrans vides et dossier (#139, #140, #154)

- Branche `claude/audit-ux-lots-2-4`, sur le lot 1. États d'attente de l'élève avec contact de l'école et « Actualiser », une seule ligne d'écran vide et de recherche sans résultat, contacts qui distinguent attente, panne et absence, en-tête de dossier sans faux bouton. [Détail](audit-ux-lot2-etats-vides-20261027.md).
- iOS seulement, rien à déployer. Tests non lancés avant l'essai du porteur.

## 27 octobre 2026 — audit UX, lot 1 : navigation et paramètres (#133 à #138)

- Branche `claude/lot1-navigation-parametres`. Onglet Messages stable pendant un trajet, même sélecteur pour « Changer d'école », engrenage direct « Paramètres de Messages », « Historique des leçons », Notifications dans Paramètres. Règles de vocabulaire et d'ouverture des pages écrites. [Détail](navigation-parametres-lot1-20261027.md).
- iOS seulement, rien à déployer. IPA d'essai à compiler ; tests non lancés avant l'essai du porteur. Aucun résultat VoiceOver ou appareil revendiqué.

## 26 octobre 2026 — récupération intégrée et reçus Messages

- #50 : [158 contrôles navigateur réussis](https://github.com/tomyrms/Drivy/actions/runs/40334928759) sur `9105617`, dont les huit scénarios de récupération avec Keycloak/Mailpit isolés. [Preuve et limites](account-recovery-20261026.md). SMTP cible reporté à la demande du porteur ; activation réelle désactivée.
- Agenda/cours : [65 tests métier réussis, 69 exécutions avec paramètres, zéro échec/ignoré](https://github.com/tomyrms/Drivy/actions/runs/40332817407) sur `bd5cbdc`. [Résumé Apple](proofs/parcours-20261026/agenda-bd5cbdc/summary.json). UI cours/profil/récupération en cours ; reprise UI bilan encore attendue.
- #104 : reçus serveur atomiques en `103c3a8`, journal natif avec identité stable et contrôle de reçu en `828e284`, reprise d'une écriture locale interrompue en `14ba07c`. Neuf tests PostgreSQL de mutations plus 22 régressions messagerie réussis. [Installation future API avant IPA et limites](messaging-mutation-receipts-104-20261026.md). Nouveaux tests UI synthétiques 1/5/15 secondes préparés, pas encore exécutés.
- #51 : revue finale en cours ; frontière bureau ADMIN conservée. Campagne complète, PR et IPA finales à venir. Aucun déploiement ni validation physique annoncé.


## 26 octobre 2026 — socle réactivité qualifié sur Apple

- Socle natif #106/#107/#119 : [79 tests réussis, zéro échec/ignoré](https://github.com/tomyrms/Drivy/actions/runs/40331345770) sur `0c3a712`, et IPA compilée. [Détail et preuve](reactivite-native-106-107-119-20261026.md#exécution-apple-du-socle).
- Web : socle et pilote réglages en `dbd868b`, 84 tests ciblés, concurrence des préférences vérifiée sur PostgreSQL17.11 isolé, quatre parcours navigateur synthétiques. Revalidation du compte actif après verrou ajoutée en `120f24a`.
- Cours/formulaires en `50cd527`, entrée récupération native en `bd5cbdc`, intégration serveur/web #50 en `cc85d22` et correctifs de recette suivants. Apple ciblé et recette réelle Keycloak/Mailpit encore en cours ; SMTP réel non activé.
- Les deux nouveaux tests UI du bilan ont échoué sur un sélecteur XCTest ambigu (boutons imbriqués). Ciblage corrigé en `ab9a2d3`, reprise programmée ; pas de validation UI revendiquée.
- Messagerie durable en `fcc3c35` ; reçu serveur contre les anciennes requêtes retardées en réalisation. Planification web #51 en réalisation. Aucun déploiement.


## 26 octobre 2026 — vague parcours, première preuve bilan

- #162/#163 : 101 tests Swift réussis (105 cas paramétrés), zéro échec/ignoré, sur Apple au commit `2b0c952` : [run 40328492050](https://github.com/tomyrms/Drivy/actions/runs/40328492050). UI iPhone/iPad encore en cours. [Détail](bilan-brouillon-162-163-20261026.md).
- Socle natif #106/#107/#119 intégré en `d85bd00`/`d88757f` ; tests Apple à lancer. Le bilan adopte le domaine pédagogique ; test de coexistence avec une invitation préparé.
- #50 : le porteur demande de préparer l'intégration et de choisir le relais e-mail plus tard. Aucune activation ni annonce d'envoi réel avant configuration et qualification.
- Les lots messagerie, cours/formulaires et web restent en réalisation. Aucun déploiement ni validation physique revendiqués.


## 26 octobre 2026 : vague parcours, bilan #162/#163 prêt pour qualification ciblée

- Worktree isolé, branche `codex/bilans-reactivite-parcours-20261026` : correctifs Messages jusqu'à `da7f8f3` conservés et agenda `71390e9` intégré. [Périmètre demandé](vague-parcours-20261026.md).
- Bilan : conservation locale proposée avant sortie, fermeture après écriture réussie seulement, erreur réessayable sans perte de saisie. Suppression locale refusée signalée ; commande déjà partie jamais annulée fictivement. Action « Enregistrer et fermer » et variantes privées/vides. [Détail](bilan-brouillon-162-163-20261026.md).
- Tests Swift et UI préparés, pas encore exécutés sur Apple. Mode ciblé `reports` ajouté sans réduire la campagne complète. Aucun déploiement ni résultat physique annoncé.

## 26 octobre 2026 à 13:25 UTC : agenda web et BFF déployés

Version `71390e97d3c3ac313673635fe06c40c2f8e98c46` activée sur CT114. La [PR #178](https://github.com/tomyrms/Drivy/pull/178) est fusionnée et les issues #144/#145/#146/#147/#172/#173/#175 sont fermées.

- Sauvegarde préalable CT113 : 2 276 844 octets, catalogue et blocs vérifiés. Registre de 53 migrations ; aucune migration exécutée.
- Web seul redémarré, actif avec son répertoire réel vérifié. API, identité, ingress et worker de cours conservent leurs PID et répertoires ; environnements privés inchangés.
- Override actif `90-qa84-web-anchor.conf`, sauvegarde de retour dédiée à cette bascule ; retour vers `5888f03` documenté dans le [compte rendu de déploiement](web-agenda-deployment-20261026.md).
- 35 contrôles HTTPS réussis (20 fichiers du build, neuf routes SPA, session et refus attendus), puis écran anonyme inspecté dans Chromium sans erreur, avertissement ni requête échouée.
- Contrôle final à 13:28:07 UTC : cinq services actifs sans redémarrage automatique, readiness API interne 200, 53 migrations et empreintes attendues confirmées en lecture seule. Journal web sans entrée depuis la bascule ; API/worker/`current` restent sur `5888f03`.
- L’IPA 381 reste non signée pour iLoader : son installation est distincte du déploiement web.

## 26 octobre 2026 : agenda unifié, lot qualifié pour intégration

Lot #144/#145/#146/#147/#172/#173/#175 sur `codex/agenda-fiable-20261026`. Leçons et séances partagent la chronologie, les repères et les compteurs ; les sources se relisent avec erreurs et couverture partielle explicites ; l'ouverture conserve le rendez-vous choisi. Produit `23b19f3`, inchangé dans `00f0f45` qui ajuste uniquement deux tests UI. Aucun nouveau contrat API ni migration.

- Vérifications finales sous Node 24.22.1, `00f0f45` : [745 tests API/PostgreSQL, 363 tests web, typages, builds et intégrité réussis](https://github.com/tomyrms/Drivy/actions/runs/40320751047) ; [ouverture d'école réussie sur `b42e5ea`](https://github.com/tomyrms/Drivy/actions/runs/40318236608), sources web/API inchangées. Recette Edge : 19 contrôles agenda et 10 scénarios de navigation exacte réussis, avec captures inspectées.
- Apple `23b19f3` : [58 tests métier, 62 exécutions avec paramètres réussis](https://github.com/tomyrms/Drivy/actions/runs/40317621203), aucun échec ni saut. [IPA 381](https://github.com/tomyrms/Drivy/actions/runs/40317577943) non signée pour iLoader, téléchargée et empreinte vérifiée.
- Visuel `849bb27` : 24 PNG après correction (12 normaux, 12 en grands textes) et 7 références valides inspectés sur iPhone/iPad, clair/sombre. Chronologie, jour avec cours seul et erreur confirmés dans les zones visibles ; limites sous le pli et absence de preuve VoiceOver consignées dans le rapport.
- UI : [2 tests réussis sur iPhone et 2 sur iPad](https://github.com/tomyrms/Drivy/actions/runs/40320751020) dans `00f0f45`, zéro échec ni saut. Avec les 4 autres cas déjà réussis sur chaque appareil dans `bee144c`, couverture de 6 cas par appareil ; seuls 2 ont été réexécutés sur le dernier commit. Produit et fixtures restent identiques à `23b19f3`.
- Exception CI temporaire retirée, workflows habituels restaurés. Intégration et clôture suivies par la [PR #178](https://github.com/tomyrms/Drivy/pull/178), sans les annoncer déjà effectuées. Aucun déploiement ; aucune qualification globale #84 ni preuve physique VoiceOver, GPS ou batterie. [Rapport, preuves et historique des échecs](agenda-fiable-20261026.md).

## 25 octobre 2026 à 15:33 UTC : cours déployés, worker de notifications actif

Accord du porteur à 15:28 UTC.
- Sauvegarde CT113 `/root/drivy_refonte-before-courses-5888f03-20261025T1529Z.dump`, 1 878 057 octets, 0600, catalogue et blocs relus par `pg_restore`. Aucune restauration d'essai revendiquée.
- Release `5888f03718045e13dc3c304040ead26991ffe719` (archive SHA-256 `3760d12e…aceb2`, identique avant et après transfert) installée par `install-api-release.py`. Migrations 042 à 046 appliquées : 53 au registre, empreintes identiques au dépôt. Contrôle runtime/RLS réussi.
- API seule redémarrée : readiness 200, `/v1/me` et préférences de notification 401 sans jeton, aucune erreur au journal.
- Web basculé à 15:37 UTC : override `90-qa84-web-anchor.conf` réancré sur `5888f03` (ancienne version gardée dans `/root/web-anchor-36a3a70.conf.bak`). Aucune variable nouvelle, pas de journal web à migrer. Port 3002 : `/app/` et `/app/bff/session` 200, aucune erreur. Depuis `https://drivy.shulker.ch` : `/app/` sert `index--_OE6dnW.js`, présent dans 5888f03 et absent de 36a3a70. Retour : restaurer le `.bak`, `daemon-reload`, redémarrer le web.
- Worker vérifié en base : une session `drivy_refonte_course_worker` ouverte, 21 transactions validées en 30 s, 0 redémarrage et 0 échec de cycle depuis 15:32:11 UTC.
- Avant activation : 0 série, 0 événement en attente, 0 notification en attente, 0 appareil inscrit. Rien ne pouvait donc partir d'un coup.
- `drivy-refonte-course-worker` activé et démarré sous `drivy-course-worker` : actif, aucun redémarrage ni avertissement après plusieurs cycles.
- IPA non signée pour iLoader : run `40207657410`, build 356 v0.7.0, bundle `ch.drivy.qualification`, `aps-environment=development` (jeton déclaré SANDBOX). Le topic APNs configuré sur le serveur est identique au bundle (comparé sans afficher la valeur), et les 4 clés APNs sont présentes. Conditions de réception : compte développeur payant, App ID `ch.drivy.qualification` avec Push, bundle non renommé par iLoader.
- Reste à qualifier : réception réelle sur un iPhone signé avec le droit push. Aucune notification n'a été envoyée à ce jour.
- Retour arrière : `systemctl disable --now drivy-refonte-course-worker`, lien `current` vers `79468863…`, redémarrage de l'API. Les migrations 042 à 046 sont additives et n'ont pas besoin d'être annulées. Restauration de la sauvegarde seulement en dernier recours.

## 25 octobre 2026 à 15:03 UTC : défauts d'envoi push corrigés avant toute activation

Revue de déploiement NO-GO sur `48b78d1` : le worker aurait pu envoyer des notifications devenues fausses. Corrigé, non déployé :
- Migration `046_course_push_revalidation.sql` (additive) : `course_push_revalidate(uuid)`, réservée au rôle worker, relit juste avant chaque envoi les préférences, l'adhésion, l'abonnement, l'accomplissement, l'inscription, l'offre active et l'horaire. Refus durable `SKIPPED` (`PREFERENCE_DISABLED`, `RECIPIENT_INELIGIBLE`, `EVENT_OBSOLETE`) ou `EXPIRED`. Le worker n'obtient aucun `SELECT` métier.
- Même migration : une offre réémise après replanification et un rappel d'horaire déplacé ont une clé distincte (avant : ignorés en silence). L'expiration des offres ne touche plus la nouvelle offre de la même entrée.
- Transport APNs : la raison Apple est lue (corps borné à 4 Kio). Seuls `400 BadDeviceToken` et `410 Unregistered/ExpiredToken` révoquent l'appareil. Toute autre erreur, coupure ou délai est retentée.
- Exécuté sur PostgreSQL 16.14 synthétique : 14 régressions (RED observé avant correctif), notifications, upgrade 042..046 après messagerie, inscriptions, 34 tests transport : PASS. Suite API complète non rejouée localement.
- Reste : CI complète, sauvegarde puis bascule, recette d'envoi réel sur appareil dédié. Fenêtre résiduelle connue : une offre acceptée pendant l'appel APNs peut encore être notifiée.
- Test UI iPhone : ouverture des membres synchronisée sur la feuille Messages (`3a803f6`), run ciblé `40203913273` (`MessagingThreadUITests`, iPhone et iPad) PASS.

## 25 octobre 2026 à 14:32 UTC : un seul blocage UI iPhone restant

Campagne `40198021398` sur `48b78d1` : scripts, primitives SDK, API/PostgreSQL, web/BFF, navigateur, intégrité et IPA PASS. iOS FAIL : `MessagingThreadUITests.testGeneralMembersOpenProfileWithNameAndPhotoOnly`, ligne23, liste des membres absente après le geste d’ouverture sur iPhone. Le même test passe sur iPad, où les38 tests UI passent. Le correctif du test Profil/Signalements et celui de la confirmation de retrait ne sont plus en échec.

Diagnostic ciblé et revue finale du déploiement délégués en parallèle. Aucun succès global revendiqué, aucune bascule API/web ni activation du worker. Prochaine étape : correction fondée sur les preuves, qualification ciblée de la suite messagerie iPhone/iPad avant nouvelle campagne complète.

## 25 octobre 2026 à 13:32 UTC : relance sur 48b78d1

Les deux échecs de qualification sont corrigés en `7384363` : import OIDC local sans password grant Apple (validation de sécurité conservée) et sélection du bouton terminal de confirmation messagerie sans choix arbitraire entre deux actions. Le setup réel a été rejoué dans des conteneurs isolés : 6 contrôles réussis, migration 045, reprise idempotente et refus de configurations dangereuses inclus. Le correctif UI reste à vérifier sur runner Apple.

Audit des dépendances runtime après correctifs ciblés `beee4f1` : zéro vulnérabilité signalée API et web. Typages réussis, 352 tests web réussis localement sous Node26 hors cible24. Versions verrouillées Fastify5.12.6, Zod4.6.6, Nodemailer10.1.4, fast-uri corrigé dans les locks. La CI utilise Node24.

Test `course-upgrade.integration.test.ts` réellement réussi sur PostgreSQL16.14 jetable : état001..041 puis sept migrations messagerie, ajout042..045 sous propriétaire restreint, conservation des données synthétiques, droits et fonctions messagerie, empreintes et réexécution sans effet. Les48 empreintes de migrations actives en production correspondent exactement au candidat Git. Conteneur de test supprimé après réussite.

Campagne complète `40198021398` en cours sur `48b78d1621f6e3eb1eab4082e75634ce1a0b0899`. Aucun déploiement applicatif ni activation worker à ce stade. Prochaine bascule seulement après résultat et nouvelle sauvegarde. Web actif ancré sur `36a3a70`, API sur `7946886`.

## 25 octobre 2026 à 13:27 UTC : connexion worker prête, qualification intégrée encore rouge

Run `40194237882` sur `85d63a4` : API/PostgreSQL, web/BFF, navigateur, intégrité documentaire, primitives SDK et IPA réussis. Échecs : scripts (`scripts/dev/setup.ts`, validation de configuration OIDC) et UI messagerie (`MessagingThreadUITests.swift:50`, identifiant de confirmation ambigu sur iPhone et iPad). Corrections en cours. Ces échecs ne sont pas masqués par les suites vertes.

Après sauvegarde CT113 `/root/drivy-before-worker-login-20261025T1325.dump` (1 877 924 octets, catalogue vérifié et synchronisation), `provision-course-worker.py --check` puis `--apply` ont réussi : mot de passe initial généré sur CT113, aucun remplacement de credential existant. Coffre transféré directement vers CT114, connexion dédiée dans `course-worker.env` root/0600. HBA dédié CT114/TLS/SCRAM ajouté après sauvegarde `/root/pg_hba-before-course-worker-20261025T1326.conf`, zéro erreur de parsing, rechargement sans redémarrage PostgreSQL.

Compte système `drivy-course-worker` et unité installés, `systemd-analyze verify` réussi. Connexion PostgreSQL réellement réussie depuis CT114 sous ce compte : vérification TLS complète, attributs du login restreints et `SET LOCAL ROLE drivy_course_worker` dans une transaction en lecture seule. **Worker non démarré, aucune migration cours appliquée ni bascule API/web.** Réception APNs physique toujours non vérifiée.

## 25 octobre 2026 : provisionneur du login worker cours, code seulement

`infra/deploy/provision-course-worker.py` ajouté pour root sur CT113, après `apps/api/scripts/prepare-course-worker.sql`. `--check` ne modifie rien durablement. `--apply` refuse tout coffre préexistant ou mot de passe non nul, contrôle les attributs et memberships contraints, conserve le secret généré sur place dans `/root/drivy-course-worker-bootstrap.json` (clé `courseWorkerPassword`, création exclusive root/0600, fsync fichier et répertoire), puis applique uniquement le vérificateur SCRAM. Contrôles répétés sous verrous de catalogues NOWAIT avant ALTER. Un échec partiel impose une reprise manuelle sans suppression automatique du coffre ni réinitialisation.

Validation locale : syntaxe Python et 13 tests mocks sans réseau réussis. Aucun appel PostgreSQL réel, aucune exécution distante, migration, modification de contrat ou activation de service dans ce travail. Qualification DB et déploiement réservés au coordinateur, après nouvelle sauvegarde. Les contrôles de permissions, durabilité et journalisation côté serveur restent à qualifier sur CT113.

## 25 octobre 2026 à 12:37 UTC : finalisation et déploiement des cours autorisés

Le porteur demande de terminer la qualification et le déploiement des cours ainsi que l’activation du worker. Pas de bascule avant vérification, sauvegarde renouvelée avant modification distante. La version déployée `7946886` contient la messagerie et le replay absents de la branche cours : intégration sur `vague/cours-collectifs` en `3a68ee8`, sans fusion dans master, pour éviter leur régression.

Le run iOS `40186160920` sur `10a77b0` a échoué dans `NativeNavigationTests.testProfileOpensObservationThemesWithItsCounterAndPreview`, ligne 104 : thème `indicators` hors des cellules matérialisées sur iPhone. Correctif test `85d63a4` : compteur vérifié en haut, défilement borné, présence et interactivité des deux thèmes toujours exigées. Pas encore qualifié sur Apple.

Typages API et web et suite web exécutés localement avec succès après intégration. Campagne complète `40194237882` lancée sur `85d63a4591a16e0bb86db5bb04522cdd809f8776` : API/PostgreSQL, web, navigateur, iOS, IPA et scripts. Résultats en attente. Aucun nouveau déploiement à ce stade, réception APNs physique non vérifiée.

## 25 octobre 2026 : préparation APNs sur le homelab

Autorisation explicite du porteur à 12:03 UTC. Sauvegarde préalable CT113 : `/root/drivy-before-course-worker-20261025T1205.dump`, 1 871 853 octets, catalogue `pg_restore --list` vérifié, synchronisée. Aucune restauration de test revendiquée.

`prepare-course-worker.sql` exécuté avec arrêt sur erreur et COMMIT. Les deux rôles sont sans SUPERUSER, BYPASSRLS, CREATEDB, CREATEROLE ni INHERIT. Le rôle de groupe reste NOLOGIN. Aucun mot de passe de connexion worker configuré à ce stade.

Clé APNs transférée directement par SSH vérifié dans CT114, sans affichage. `/etc/drivy-refonte/apns-auth-key.p8` et `course-push.env` appartiennent à root en 0600. Validité structurelle de la clé contrôlée avec OpenSSL. Configuration préparée pour SANDBOX et le Bundle ID du projet, à confirmer avec le profil iLoader et la portée de la clé Apple. Aucun secret enregistré dans Git.

**Worker non activé** : la release active est `79468863de0218a27451d4d00bda398affddb323` et la table `drivy.push_notification` est absente. Aucune migration, bascule, modification HBA ni relance de service effectuée. API toujours active. Restent le déploiement autorisé des cours, la connexion DB dédiée, l’unité worker et une réception réelle sur appareil. La configuration des clés ne vaut pas livraison APNs.

## 25 octobre 2026 : résultats de la campagne finale (#84)

Branche `vague/cours-collectifs`, aucun déploiement.
- Exécuté : e2e navigateur réussi sur `a8a0729` ([run 40184333047](https://github.com/tomyrms/Drivy/actions/runs/40184333047)) ; IPA d'essai avec le droit APNs `aps-environment=development` compilée sur `6744408` ([run 40184742677](https://github.com/tomyrms/Drivy/actions/runs/40184742677)), signature et installation iLoader non faites.
- Campagne iOS sur `495f97b` : 29 tests UI sur 30 réussis. Échec de `FieldFlowTests.testLeavingLiveThroughTheExitButtonKeepsTheStartedLessonWithoutCancellingIt` (requête de l'accessoire capture-return sous iOS 26), corrigé dans `c169a7f`. Relance ciblée en cours ([run 40184805111](https://github.com/tomyrms/Drivy/actions/runs/40184805111)).
- Reste à qualifier : campagne iOS complète ; livraison APNs réelle (clés `APNS_*` et script `prepare-course-worker.sql` non exécutés).

## 24 octobre 2026 : cours collectifs, appel (#42), règlements sur place (#81), validation (#82)

Branche `vague/cours-collectifs`, non fusionnée, aucun déploiement. Commits `3056515`, `a419e90`, `f1f726f`. Contrat : [cours-collectifs-faits-42-81-82.md](cours-collectifs-faits-42-81-82.md).
- Migration 044 : présence par élève et séance (Présent, Absent, Excusé), versionnée avec historique et auteur, jamais déduite ; règlement « payé sur place » annulable avec motif, sans effet sur présence ni validation ; validation explicite par une personne habilitée seulement si toutes les séances obligatoires sont présentes, retrait avec motif, retrait de l'élève des listes d'attente du même type.
- Web : feuille du cours (élèves × séances, règlement, validation selon les droits). iOS : appel du moniteur, règlement et validation selon les droits, « Mes cours » pour l'élève (validations, progression).
- Exécuté : 34 tests API ciblés des cours réussis en local (PostgreSQL 17 jetable, migrations 001 à 044) ; web : typage et 47 tests ciblés ; IPA compilée sur `f1f726f` ([run 40118350531](https://github.com/tomyrms/Drivy/actions/runs/40118350531)). Pas une recette.
- Non exécuté : tests Swift, UI, navigateur, suite complète (#84). Annuler un règlement et retirer une validation ajoutés sur iOS dans `ded66fa` (IPA [run 40118916758](https://github.com/tomyrms/Drivy/actions/runs/40118916758) compilée). Limite : une correction de présence après validation ne retire pas la validation automatiquement.

## 24 octobre 2026 : cours collectifs, inscription (#39), liste d'attente (#40), annulations (#41)

Branche `vague/cours-collectifs`, non fusionnée, aucun déploiement. Commits `3d911b8`, `af10b48`, `4d9c4ae`, `9109b74`. Contrat : [cours-collectifs-inscriptions-39-41.md](cours-collectifs-inscriptions-39-41.md).
- Migration 043 : inscription à toute la série (élève ou personnel habilité), liste d'attente prioritaire avec proposition exclusive et place retenue, annulation autonome jusqu'à l'échéance (24 h par défaut), annulation tardive par le personnel avec motif, annulation de série, changement de dates sans mise à jour partielle. Un seul compteur de places, occupations dans `drivy.reservation` (conflits cours/leçon refusés dans les deux sens).
- Valeurs provisoires non approuvées : expiration 2 h avant la séance, seuil 30 min ; le délai de réponse (12 h proposé) n'est pas appliqué tant que l'école ne le saisit pas.
- Web (personnel) : inscrits et file, inscrire, annuler, annuler le cours, modifier les dates, réglages. iOS : fiche élève (statuts, inscription, file, proposition, annulation ou contact), bandeau des propositions, inscrits côté personnel habilité.
- Exécuté : 29 tests API ciblés réussis en local (PostgreSQL 17 jetable, migrations 001 à 043) ; web : typage et 40 tests ciblés ; IPA compilée sur `9109b74` ([run 40039016177](https://github.com/tomyrms/Drivy/actions/runs/40039016177)). Ce ne sont pas des recettes.
- Non exécuté : tests Swift, UI iPhone/iPad, navigateur, suite API complète en CI (campagne #84). Limites : pas de worker d'expiration autonome (la file avance à chaque commande ou lecture), abonnement « prochaines sessions » et push non livrés (#43, #44), motif perdu si l'annulation web échoue, mise en page web non vue.

## 23 octobre 2026 : cours collectifs, cadrage (#79), socle (#80), création et publication (#38)

Branche `vague/cours-collectifs`, non fusionnée, aucun déploiement. Commits `7c3bcef`, `6877eea`, `efc6a85`.
- Cadrage : [cours-collectifs-cadrage-79.md](cours-collectifs-cadrage-79.md). Règles confirmées, propositions groupées (délai d'acceptation 12 h, non approuvé, file désactivée tant que l'école ne l'active pas), OAC art. 10 et 18 lus sur Fedlex (versions 2026 et 2027).
- Socle : migration 042 et `apps/api/src/courses.ts` ([cours-collectifs-socle-80.md](cours-collectifs-socle-80.md)). Types, séries, séances, inscriptions, file, propositions avec retenue de place, présences, règlements sur place, accomplissements, conditions d'annulation versionnées (24 h par défaut). Occupation des formateurs dans `drivy.reservation`, donc conflits cours/leçon refusés dans les deux sens.
- #38 : création, brouillon et publication depuis l'agenda web et iOS/iPadOS ; capacité modifiable après publication, jamais sous les places prises.
- Exécuté : 11 tests API ciblés réussis une fois en local sur PostgreSQL 17 jetable (migrations 001 à 042) ; web : typage et 35 tests (`course-model`, `school-bff`) ; IPA d'essai compilée sur `efc6a85` ([run 39940836151](https://github.com/tomyrms/Drivy/actions/runs/39940836151)). Ce ne sont pas des recettes.
- Non exécuté : suite API complète en CI, tests Swift (dont `SchoolCourseClientTests`), parcours UI, navigateur. Tout est différé à la campagne finale #84 ([manifeste](../qa/validation-finale-20261021.md)).
- Restent : #39 à #43, #81, #82 (inscription, file, annulation, appel, règlement, validation) ; modification ou annulation d'une série publiée (#41). iOS : les séances de cours ne sont pas encore comptées dans la bande semaine et la grille du mois, une erreur de lecture des cours n'est pas affichée.

## 25 octobre 2026 : signalements durables et Mes appareils, tests métier iPhone

- Run Apple `40203243767` sur `e210f7c` réussi : 135 XCTest sans échec sur simulateur iPhone, dont les 34 tests `MatrixMessagingCryptographyTests` (vérification croisée, refus partiels, cible révoquée, reprise du bootstrap), les 11 tests `MessagingOwnDevicesTests` et le scénario FFI → HTTPS → Fastify → PostgreSQL (`RELAY_EXECUTION_PASSED: 1 scenario, 0 skipped`).
- Campagne complète `40199762381` sur `911739f` en échec. Passent sur iPhone et iPad : reprise durable des signalements, confirmation de retrait/réintégration d'un membre, thèmes du profil. Échouent : `FieldFlowTests` ligne 129 (sortie du live) et `READINESS` du relais (`-1001`, avant tout chiffrement, deuxième run consécutif, déjà vu sur `40199170223`). Les échecs « Mes appareils » de ce run portent sur la version antérieure à `e210f7c`.
- Non qualifié : UI iPad et iPhone de « Mes appareils », bascule réelle de compte, signature croisée sur deux appareils physiques, VoiceOver. Aucun déploiement.
- Run `40208270037` sur `8f6146f` (UI ciblée iPhone et iPad) : `FieldFlowTests` sortie du live réussi sur les deux appareils après correction du rôle bouton de la barre « Revenir au trajet en cours » (`58ea12a`). `MessagingOwnDevicesUITests` en échec : le tap XCUITest au centre de la ligne ne basculait pas l'interrupteur iOS 26 (valeur 0 lue dans la hiérarchie exportée). Défaut du test, pas du produit.
- Run `40210771935` sur `4295172`, nouveau mode `ui_iphone_only` (`4318b96`, iPhone seul, sans iPad ni captures, contrôle intermédiaire uniquement) : `MessagingOwnDevicesUITests` réussi sur iPhone. L'iPad de ce scénario reste à rejouer dans la campagne finale.
- Reste avant clôture : une campagne complète iPhone et iPad sur le dernier SHA. Puis recette physique « Mes appareils » sur deux appareils, VoiceOver et bascule réelle de compte.

## 25 octobre 2026 : vérification crypto de ses appareils, candidat non qualifié

- Apple `40199170223` : découverte d'un appareil ajouté tardivement réussie après rafraîchissement explicite. Cinq RED métier atteints : révocation, accusé mal formé, refus partiel HTTP 200, reprise d'un bootstrap non publié, tentative de remplacement depuis B sans clé privée. Nominal, mauvaise empreinte, mauvais contexte et réponse de bootstrap perdue réussis. La panne distincte du relais réel à l'étape `READINESS` n'a pas de lien causal établi avec ces changements.
- Candidat en revue : intention de publication scellée et reprise sans remplacement d'identité, validation des accusés de signatures, relecture du périphérique avant/après signature. Parcours natif « Mes appareils », empreinte locale du SDK, comparaison explicite, disponibilité de la clé privée et absence de succès optimiste. Aucun SAS/QR, reset, changement API ou nouvelle politique de confiance pour l'envoi.
- Après revue P1, l'intention de bootstrap est isolée dans un journal `device-signing.sealed`, coordonné entre instances et conservé après acquittement. Une sauvegarde d'un ancien snapshot sync/backup ne réécrit plus ce journal. Test ajouté avec deux adaptateurs sur le même coffre, upload suspendu, backup concurrent et reprise après réouverture sans reset. Décision et limites : `messaging-device-verification-20261025.md`. **Test non exécuté Apple à cette étape.**
- Contrôlé localement : lecture du log et `git diff --check`. Les tests ajoutés du modèle/UI, de reprise après réouverture et de source locale de l'empreinte **ne sont pas encore exécutés sur Apple**. Aucun GREEN ni résultat physique/VoiceOver annoncé. Rapport de remise : `artifacts/qa84-device-verification-progress.md`.

## 25 octobre 2026 : QA84, assertions UI terrain et profil

- Run Apple `40194505714`, log local `artifacts/qa84-full-native-failure.log` : terrain échoué sur iPhone/iPad, profil Signalements échoué sur iPhone clair/sombre mais réussi sur iPad.
- Diagnostic : assertion d’interdiction d’annulation devenue obsolète depuis la décision #61 du 21 octobre, et recherche sans défilement du 12e thème dans la liste native iPhone. Produit et fixtures inchangés. Les deux parcours restent couverts, avec annulation proposée explicitement, sortie/retour live conservés et recherche bornée par défilement des mêmes thèmes.
- Vérifié localement : `git diff --check`, conservation des 10 tests terrain et 5 tests de navigation, confrontation au contrat, au code et à la hiérarchie du log. **Pas de compilation ni de tests Apple après correction**, outils Apple absents sous Windows. Aucun commit, push ou déploiement. Rapport et fichiers gelés : `artifacts/qa84-field-profile-ui-fix.md`.

## 25 octobre 2026 : nouveaux messages confirmés sur appareil

- Le porteur signale `D-NOKEY` avec l'IPA 354 en alternant deux comptes sur le même téléphone. Ce code signifie que la session de déchiffrement est absente localement, pas que sa perte définitive est démontrée.
- Relevé serveur à 10:40 UTC : deux anciens messages, aucun nouvel envoi accepté, aucun partage to-device et aucun nouvel appareil du second compte. Ces constats ne prouvent pas à eux seuls un défaut local : un refus réseau/API avant écriture reste possible.
- La suite Apple `40184451319` est réussie après correction d'une assertion devenue obsolète. Son relais en mémoire ne qualifie pas l'intégration HTTP réelle.
- Le 25 octobre à 12:17 UTC, run Apple `40191511234` sur `65eddbf` réussi : 99 XCTest sans échec, dont le scénario Matrix FFI → HTTPS → Fastify → PostgreSQL. Échange privé A/B, répétition idempotente, sauvegarde et restauration sur un appareil neuf, refus des contextes étrangers réellement exécutés. La garde confirme `RELAY_EXECUTION_PASSED: 1 scenario, 0 skipped`. Ce résultat ne couvre pas encore Général avec inscription tardive de B, l'interface d'envoi, ni l'essai physique.
- Campagne API/PostgreSQL `40191346532` sur `7946886` réussie. Le relevé de journaux entre 10:41 et 12:01 UTC ne contient aucun parcours d'envoi, seulement des lectures et les sondes de déploiement : aucun rejet d'envoi authentifié n'est prouvé.
- Run Apple `40192648610` sur `4d8c156` réussi : 99 XCTest sans échec, garde relais positive. Le scénario étendu vérifie Général avant inscription B, publication des clés B, `device_lists.changed` réellement consommé par A, nouvel envoi avec la même session Megolm, déchiffrement B puis réponse B déchiffrée par A. Aucun reset ni réponse HTTP simulée. Cela ne reproduit pas la bascule OIDC/UI sur l'iPhone du porteur, ni la lecture des anciens messages envoyés avant publication des clés B.
- À 12:36 UTC le 25 octobre, le porteur confirme que les nouveaux messages fonctionnent sur son appareil et précise que `D-MEGOLM` concerne un ancien message. Réception des nouveaux messages confirmée par le porteur, sans attribuer ce succès à un correctif causal non démontré. Le diagnostic supplémentaire est arrêté, aucune suppression d'app, de clé ou de message. La récupération de cet ancien message n'est ni réalisée ni déclarée impossible. Cette confirmation ne clôt pas la qualification globale #84 (iPad, VoiceOver et autres scénarios physiques restent distincts).

## 24 octobre 2026 : campagne #84 engagée sur la messagerie

- Demande du porteur : tester puis afficher Messages une fois qualifié. Travail sur `openai/65-messagerie`, PR #96 en brouillon, checkout des cours collectifs préservé. [Rapport et limites](qualification-messagerie-84-20261024.md).
- Candidat initial `e2657c4` : API/PostgreSQL run `40031983397`, **596 tests réussis et 21 échoués**. Navigateur OIDC/BFF/API/PostgreSQL run `40031985954` réussi. Apple run `40031925552` échoué à la compilation des tests : aucune suite XCTest/UI exécutée, aucune IPA produite par ce run.
- Corrections et requalification en cours. Contrôles locaux complémentaires : web 320 tests, typage/build réussis sous Node 26 hors cible 24 ; scripts sélection 14 tests et captures 11 tests réussis après correction du harnais. Ces scripts simulent les commandes Apple.
- Requalification Apple run `40032779482` réussie sur `d11301b` : 71 XCTest sans échec et 752 tests Swift Testing dans 68 suites réussis, sur simulateur iPhone. Aucun résultat UI/iPad/physique ni validation des correctifs crypto ultérieurs n'en est déduit.
- À la demande explicite du porteur, l'accès physique ne dépend plus de la recette physique : option de compilation `DRIVY_MESSAGING_QUALIFICATION`, vraie composition et badge Test, sans fixture. **IPA iLoader 348**, run `40037792388`, **SUCCESS** sur `4ff47790b07bee9f8214fe22c87075add9c3484d` ; téléchargée et checksum vérifié par le coordinateur. Elle remplace l'IPA 347, incompatible avec le serveur actuel et à ne pas utiliser pour cette recette. Trois tests du paramètre de compilation réussis localement. Compilation/paquet ne valent pas essai physique.
- **API `4ff47790` déployée pour qualification limitée à l'école Ramos**, après sauvegarde privée vérifiée et seconde copie d'empreinte identique. `NODE_ENV=production` conservé, OIDC réel, allowlist d'une seule école. Les 48 migrations correspondent au SHA déployé, contrôle runtime/RLS et santé réussis. Web maintenu exactement sur `36a3a70`, sans redémarrage : PID, instant d'activation, répertoire réel et 29 fichiers de build inchangés. HTTPS : web 200, identité/messagerie/crypto anonymes 401 avec en-têtes syntaxiques requis, hors allowlist messagerie/crypto 503. Aucun message ni compte créé par ces contrôles.
- Apple même SHA : run `40037795156` **in_progress**, état relu le 23 octobre à 23:17 UTC. Compilation réussie à **23:13:10 UTC**, tests métier iPhone `all` en cours. Le code 124 du processus local de suivi indique son expiration, pas un échec des tests distants. Aucun résultat final, UI/iPad ou physique n'est déduit de cette exécution encore ouverte.
- **Qualification globale et activation générale non validées** : accès physique de qualification et service limité à Ramos disponibles, mais échange E2EE sur appareils, recette physique et preuves restantes à exécuter. Les cours collectifs non intégrés restent dans le périmètre #84 comme non qualifiés. Aucune fusion ni clôture d'issue.

## 24 octobre 2026 : premier essai physique de la messagerie

- IPA 350 (`8542699`) : 94 XCTest et 752 Swift Testing réussis sur simulateur iPhone (run `40115336741`). Code de diagnostic non sensible affiché sous les erreurs de protection.
- Sur appareil, le diagnostic a affiché `H-UPLOAD-400` : la liaison FFI de matrix-sdk-crypto envoie `device_keys: null` et l'API refusait ce champ. Correctif `d012c41` avec un test rejouant des corps réellement produits par le SDK (rouge avant, vert après) : 69 tests messagerie sur PostgreSQL 16.
- `d012c41` déployé sur le homelab, API seule, après une sauvegarde vérifiée. Registre des migrations inchangé, web préservé, mode qualification limité à une école.
- **Porteur, 24 octobre 2026** : après le déploiement, essai sur iPhone réussi (envoi dans Général et clé de récupération). Restent à qualifier : réception sur un deuxième appareil, restauration, retrait/réintégration, VoiceOver, iPad. #77 n'est pas implémenté. Pas d'activation générale.

## 23 octobre 2026 : messagerie #65, bilan après décisions du porteur

Les entrées messagerie du 23 octobre ci-dessous sont des relevés historiques. Leur absence de tests, déploiement ou accès Release à cette date est remplacée, pour l'état courant, par la campagne du 24 octobre en tête de ce document.

- Décisions du porteur appliquées ([decisions-messaging-20261023.md](decisions-messaging-20261023.md)) : E2EE Olm/Megolm via `matrix-sdk-crypto` 0.17.0 officiel, relais de clés sur l'API Drivy, sauvegarde par clé de récupération, fin du lien, arrivée et réintégration comme WhatsApp, contacts élève limités aux moniteurs attribués, général avec nom et photo, administrateurs du groupe, suppression pour moi ou pour tous, réactions, réponses, épinglage, recherche locale, accusés de lecture, sondages, signalements. Photos et fichiers renvoyés à #97.
- Deux revues ciblées (chiffrement iOS, API) : constats P2/P3 corrigés. Risque de confiance au premier usage documenté et accepté.
- Exécuté : `npm run typecheck` et `npm run build` ; dernière IPA non signée `ipa-essai` run `40030459842` sur `b39fce4`, compilation seulement.
- **Non exécuté** (#84) : tests PostgreSQL (`messaging-v2`, `messaging-keys`), XCTest et UI, scénarios crypto, VoiceOver, appareils physiques. Migrations `20261023b/c/d` appliquées nulle part. Messages reste masqué en Release. Aucun déploiement, fusion ni clôture d'issue.
- Limites connues : identifiant de signalement perdu si l'app redémarre pendant l'envoi ; vérification croisée des appareils sans écran dédié ; conservation et export des données non tranchés.

## 23 octobre 2026 : messagerie iOS, plafond d'appareils et réintégration (#65)

- `409 DEVICE_LIMIT_REACHED` du relais crypto devient `MessagingFailure.deviceLimitReached` (« Trop d'appareils… Retire un appareil… ») ; composition, file et reprise s'arrêtent, aucun repli non chiffré.
- Membres du général : un administrateur voit les personnes retirées pendant la session (section « Retirés ») et peut les réintégrer (`PUT general/members/:p`) après confirmation ; libellés VoiceOver « Réintégrer {nom} ». L'annuaire serveur ne liste pas les retirés : rien n'est proposé pour un retrait antérieur à la session.
- Arrivée (`readable_after`) : fil vide accepté sans erreur, aucun curseur, écriture permise.
- XCTest (`MessagingThreadTests`) et UI (`testAdminReinstatesRemovedMemberAfterConfirmation`) écrits, **non exécutés** (#84). Build IPA : voir rapport du run `ipa-essai.yml`.

## 23 octobre 2026 : messagerie API, corrections de revue (#65)

- Arrivée comme WhatsApp (plage lisible après `last_sequence` à l'entrée, réactions/sondages/votes/accusés compris), réintégration `PUT /general/members/{personId}` (époque +1), preuve des signalements conservée après suppression. RLS de lecture des réactions/sondages/votes bornée à la plage lisible. Ordre des verrous droits puis conversation pour envoi, réactions, votes, épinglage, suppression. Appareils : plafond de 10 actifs, création liée à la session OIDC, repli d'autrui modifiable seulement sur `used`, suivi (`messaging_device_tracking`) privé. `sendToDevice` concurrent idempotent. Fonctions sur une personne quelconque retirées de `drivy_app`, écritures directes sur votes et clôture retirées.
- Exécuté : `npm run typecheck` et `npm run build`. Tests PostgreSQL écrits, **non exécutés** (#84). Migrations 20261023b/c modifiées en place, appliquées nulle part.

## 23 octobre 2026 : messagerie iOS v2 (#65), branche `openai/65-messagerie`

- SwiftUI : annuaire du général avec nom et photo, profil limité au nom et à la photo, lecture seule après la fin du lien (composeur masqué), suppression pour moi et pour tout le monde, actions des administrateurs du groupe, réactions, réponse citée, bandeau des messages épinglés, recherche locale dans l'historique scellé AES-GCM, accusés de lecture, sondages, signalement de messages choisis. [Décisions](messaging-ios-v2-20261023.md).
- Déchiffrement et scellement pour les administrateurs : interfaces de l'agent crypto. Les implémentations par défaut restent indisponibles et échouent fermé.
- **Rien d'exécuté** : XCTest `MessagingThreadTests` et UI `MessagingThreadUITests` écrits, non compilés et non lancés (#84, pas de runner Apple ici). Aucun résultat VoiceOver ou Dynamic Type sur appareil revendiqué. `changes?afterChange` n'est pas encore consommé.

## 23 octobre 2026 : messagerie #65, livraison partielle sur branche isolée

- Branche `openai/65-messagerie`, base `master` à `6d08b40`, PR **#96 en brouillon**. Aucun changement de notre part dans le worktree `vague/cours-collectifs`. [Périmètre, commits, tableau des issues et arbitrages](messaging-20261023.md), [matrice #78/#84](../qa/messaging-78-20261023.md), [revue ciblée](messaging-review-20261023.md).
- Code intégré : droits scolaires/RLS et migration nouvelle `20261023_messaging_foundation.sql`, contacts, privé/général, mentions, enveloppes durables, idempotence/pagination/événements, non-lus et sourdine versionnée. Swift : transport HTTP, coffre de brouillons/file AES-GCM/Keychain, reprise bornée indépendante du GPS, entrée réversible et dossier. Consommateur #44 sans stockage parallèle ni émission push. Une conversation refusée ne provoque plus la purge des autres intentions/brouillons. Ces comportements restent à qualifier.
- **Pas de messagerie E2EE utilisable annoncée** : composition API réelle fermée, adaptateur cryptographique produit indisponible, présentation uniquement DEBUG simulateur avec argument explicite. L'IPA Release n'affiche pas Messages. Prototype Matrix officiel isolé au commit `60e845f`, quatre scénarios écrits et compilés, non exécutés. Aucun homeserver déployé ni appareil/clé produit raccordé.
- Exécuté : installation verrouillée, `npm run typecheck` et `npm run build` réussis sur le dernier code le 23 octobre 2026, `git diff --check` réussi. Node local 26.8.1, hors cible projet Node 24. `cargo check --locked --offline --all-targets`, `cargo build --locked --offline --tests` et format réussis sans exécution des scénarios. Revue ciblée : constats identifiés corrigés statiquement, pas un audit ni une preuve de sécurité.
- Apple : premier build `39885534839` échoué sur `797563a` (isolation MainActor et variable `error` masquée), corrections intégrées. Build `39886114549` réussi sur `53b564e`, archive Release et IPA non signé. Build final `39886599190` sur `ffa40d8` **réussi** : archive Release et IPA non signé incluant la correction anti-perte. Tests Swift non compilés par ce workflow IPA. Aucun test métier/Swift/UI/crypto exécuté conformément à #84.
- CI : campagnes PR `39886245946` et `39886246040` **skipped**, pas des tests réussis ; GitGuardian Security Checks **SUCCESS** sur `ffa40d8`. Aucun workflow ni scanner modifié.
- Complément de préparation : fixtures API étendues (annuaire exact sur plusieurs pages, conversations, reprise d'événements, acquittement ignoré, révocation et mentions inter-écoles) et script `scripts/messaging-build-for-testing.sh` sans exécution de suites. Typage et syntaxe Bash vérifiés ; compilation des tests Apple toujours non exécutée, aucun workflow partagé modifié. `prototypes/messaging-environment/` prépare PostgreSQL et une restauration séparée exclusivement synthétiques, image verrouillée existante, sans démarrage ni migration. Syntaxe JS/YAML vérifiée seulement, aucune preuve de restauration ou de résidence suisse.
- Restent : approbation #66/#67 puis intégration E2EE/appareils/récupération, attribution ADMIN auditée, sondages/modération selon règles validées, raccord #44, photos de profils, temps réel si retenu, hébergement/restauration suisse et campagne #78/#84. #75/#76 non confirmées. Aucun déploiement, migration appliquée, fusion ou clôture d'issue ; aucune preuve physique GPS/batterie/VoiceOver revendiquée.

## 23 octobre 2026 : replay #91 fusionné, déployé et clôturé à la demande du porteur

- Autorisations explicites reçues après la livraison sur branche : fusion, déploiement, puis clôture de #91. Fusion `36a3a70` dans `master`, sans changement du checkout des cours collectifs. Aucun workflow ni contrôle de secrets modifié ; les campagnes restent différées à #84.
- Sauvegarde préalable CT113 : `/root/drivy_refonte-before-replay91-36a3a70-20261023T010832Z.dump`, 1 404 069 octets, mode 0600, fichier synchronisé et catalogue `pg_restore --list` vérifié. La base séparée `drivy_web` n'existe pas sur cet hôte. Aucune restauration d'essai revendiquée.
- Release `36a3a70` active sur CT114. Installation verrouillée et compilation API/web sous Node 24.21.0, contrôles runtime/RLS de l'installateur réussis. Les 41 migrations appliquées correspondent aux empreintes du snapshot, sans nouvelle migration. Configurations API/web/migration inchangées, OSRM privé conservé.
- Contrôles exécutés : répertoires réels des processus API/web et empreinte du source API conformes à la release, API/web/identité actifs, readiness interne réussie. HTTPS : web et découverte OIDC 200, `/me` et `matched-route` anonymes 401, santé interne et administration identité non exposées (404). [Preuves sans données métier](proofs/deployment-replay91-20261023.json).
- #91 clôturée le 23 octobre à 01:10 UTC sur demande explicite, sans fermer #88. L'IPA `39880760958` reste celle du code iOS fusionné, identité des sources vérifiée ; signature et installation reviennent au porteur. La recette authentifiée du replay, les suites API/Swift/UI et les essais physiques restent à qualifier dans #84.

## 23 octobre 2026 : disponibilité et reprise du replay (#91), branche isolée

- Branche `openai/91-replay-finalisation-20261023`, issue de `master` à `26297dd`. Contrat et API dans `2be1783` : motifs distincts pour synchronisation, calcul, résultat vide, moteur désactivé et erreurs ; délai de reprise serveur exposé sans modifier les trois statuts historiques. Algorithme serveur 2, compatibilité OSRM >= 2 et découpage des lots conservés. Aucun changement du direct, du démarrage #95, des cours collectifs ou des migrations.
- Client iOS `cc72954` : erreurs explicites, synchronisation/calcul/résultat complet ou partiel/absence fiable/indisponibilité distincts, six reprises automatiques au plus avec espacement et conseil serveur, relance manuelle, annulation et rejet des réponses périmées. Les pages actualisées sont remplacées ensemble avant d'appliquer une géométrie confirmée ; vitesse, instant de lecture et sélection sont conservés. Préparation des assertions Swift complétée dans `1d5127a`.
- Exécuté : typage et compilation TypeScript, contrôle du diff, revue ciblée API/iOS sans blocage P1/P2 confirmé. Node local 26.8.1 hors cible projet 24. Compilation Release, archive et IPA non signé réussis sur `cc72954`, run `39880760958` du 23 octobre 2026. Tests PostgreSQL et Swift préparés, non exécutés conformément à #84 ; les tests Swift ne sont pas compilés par ce workflow IPA. Détail et matrice de reprise : [replay-disponibilite-91-20261023.md](replay-disponibilite-91-20261023.md).
- Aucun déploiement, aucune modification de données réelles, aucune fusion dans `master`. Les suites API/Swift/UI et la recette physique restent à exécuter dans #84. La stratégie CI a été coordonnée avec les cours : push `openai/**` sans campagnes, pas de PR vers `master`, IPA manuelle uniquement, workflows inchangés.
- Complément `bb7d0fc` : omission de `SchoolCaptureReplayTests` dans la sélection GPS reproduite puis corrigée dans `scripts/ios/test-selection.sh`. Les sept contrôles ciblés `TestSelection` passent en appelant le vrai script, sans commande Apple, sans tests métier et sans campagne complète. Les modes `all`, UI, visuel et le rejet des entrées invalides restent vérifiés. Cela valide la sélection future des tests, pas le comportement du replay.

## 22 octobre 2026 : démarrage compact et choix GPS réutilisé (#95), intégré dans `master`

- « Démarrer une leçon » : le récapitulatif est une carte flottante centrée, hauteur au contenu, fond flouté (plus de `.large`). Un choix GPS valide (accord ou refus) n'affiche plus ni cartes ni panneau « Accord GPS » : le bouton annonce Avec/Sans GPS, « Modifier le choix GPS » reste accessible. Chargement et panne de lecture ne passent ni pour une absence de choix ni pour un accord. Détail : [demarrage-compact-gps-95.md](demarrage-compact-gps-95.md). Aucun changement API, OpenAPI ni base, aucun déploiement.
- Exécuté : IPA d'essai compilée sur `525779d` ([run 39863074618](https://github.com/tomyrms/Drivy/actions/runs/39863074618)). Sur `ce7e3a8`, parcours UI iPhone et iPad réussis ([run 39860421236](https://github.com/tomyrms/Drivy/actions/runs/39860421236)) ; tests métier : 728 tests, un seul échec, `aChangedChoiceIsWrittenOnlyAtDeparture` ([run 39860417871](https://github.com/tomyrms/Drivy/actions/runs/39860417871)), causé par le serveur synthétique du test. Il a été corrigé dans `1826c04` (test seul), mais pas relancé : le porteur a demandé d'arrêter les tests. Nouvelle exécution rattachée à #84.
- Dossier d'essai sur le homelab : élève fictif « Lucas Moreau » ajouté à Ramos Auto ecole (formation A1, moniteur affecté, aucun choix GPS), après sauvegarde `drivy_refonte-before-add-learner-20261022T220253Z.dump`.
- À qualifier sur appareil : rendu de la carte, clavier, grandes tailles de texte, iPad, paysage, VoiceOver, Réduire les animations, GPS réel. Campagne complète réservée à #84.

## 22 octobre 2026 : une seule identité et une seule page « Mon profil » (#94)

- Décision du porteur : une seule donnée par information. Prénom, nom, nom affiché, e-mail, téléphone, naissance, adresse et photo vivent sur le compte (`drivy.person`), lu par toutes les écoles ; le dossier d'élève ne garde que ce qui appartient à l'école. Migration `041_single_person_identity.sql`. L'administration modifie après confirmation. Détail : [mon-profil-unifie-20261022.md](mon-profil-unifie-20261022.md).
- La première livraison (deux formulaires sur une page, 7cf25a3) affichait les informations en double ; elle est remplacée.
- Exécuté localement sur PostgreSQL 17 : 569 tests API passés, web 320 tests et typage passés. CI verte sur `d05ca59` : vérifications PostgreSQL et web, parcours navigateur Chromium · OIDC · BFF · API · PostgreSQL ; IPA 0.7.0 build 326 (`0730c3d`, run 39834157534, SHA-256 `ba8196b8…`).
- **Déployé le 22 octobre 2026** à la demande du porteur : release `d05ca59` sur le homelab, sauvegarde vérifiée `/root/drivy_refonte-before-d05ca59…-20261022T191259Z-0286e6eb8b2d.dump` sur CT113, 41 migrations aux empreintes conformes (041 appliquée), API/web/identité actifs, environnement API et OSRM inchangés. Contrôles : plus aucune colonne d'identité sur `learner_profile`, les dossiers existants ont leurs noms sur le compte, `/app/` 200, `/refonte/v1/me` et `/refonte/v1/me/profile` 401 sans jeton.
- Non exécuté : tests unitaires et UI Apple, captures iPhone/iPad, VoiceOver, Dynamic Type, essai sur appareil.
- Suite demandée par le porteur (app seule, sans déploiement) : un crayon à droite de l'en-tête de l'onglet Profil ouvre « Mon profil » (VoiceOver « Modifier mon profil »), pour l'élève comme pour le moniteur ; la ligne « Mon profil » quitte l'onglet Profil pour la tête de la section Compte des Paramètres. Test UI `SchoolEntryTests` adapté, non exécuté ; seule la compilation `ipa-essai.yml` qualifie cette suite.

## 21 octobre 2026 : contourner le proxy Cloudflare (#93), non retenu

- Inventaire en lecture seule et procédure : [contournement-cloudflare-20261021.md](contournement-cloudflare-20261021.md). Caddy CT109 a déjà un certificat Let's Encrypt valide pour `drivy.shulker.ch` sans défi DNS, seuls 80/443 sont joignables, aucun filtrage « IP Cloudflare » n'existe : passer l'enregistrement `drivy` en « DNS only » suffit, sans changement Caddy ni IPA.
- Mesuré (Wi-Fi, médiane de 5) : découverte OIDC 3,8 s par Cloudflare contre 20 ms en direct ; `/app/` 1,4 s contre 17 ms. Certificat vérifié en direct, chemins internes en 404.
- Décision du porteur (21 octobre 2026) : pas de bascule, le proxy Cloudflare est conservé. La lenteur mesurée par Cloudflare reste ouverte.

## 22 octobre 2026 : replay en zigzag, cause et recette propre (#91)

- Cause des zigzags partout : 7d20d3a avait passé l'algorithme de recalage en version 3, alors que l'app installée n'affiche que la version 2. L'app retombait donc sur les mesures brutes pour tout le trajet. Corrigé dans 49121c0 : le serveur reste en version 2 (même format), la migration `040_matched_route_resplit.sql` purge une fois les anciens caches pour qu'ils soient recalculés avec la découpe des lots, et l'app accepte désormais toute version OSRM >= 2.
- Recette : à la demande du porteur, les 37 autres leçons de Dania Badoni (28 trajets) sont supprimées. Il reste une leçon « Test : trajet simulé » du 21.10 à 08:00 : boucle de 7,1 km à Kirchenfeld sans demi-tour, 767 mesures, bruit GPS corrélé, deux arrêts aux feux, 5 signalements. Contrôle visuel de la ligne du replay contre la route : 100 % recalé, 4 virages parasites sur 735 segments. Bilan complet publié (révision 1, partagé avec l'élève) : travaillé, observations, prochaine étape et 5 compétences (3 autonome, 1 guidé, 1 découverte) ; les 5 signalements portent leur compétence. Progression de la formation vérifiée.
- Sauvegarde préalable `/root/drivy_refonte-before-49121c0-20261022T005410Z.dump`.

## 22 octobre 2026 : replay, découpe des lots mal recalés (#91), déployé

- Un lot de 100 points dont la confiance tombe (rond-point, demi-tour, conduite lente bruitée) restait entièrement brut. Il est maintenant recoupé en deux moitiés chevauchantes redemandées au moteur, jusqu'à 24 points ou 4 niveaux (`track-matching.ts`, algorithme v3 : les caches v2 sont recalculés à la prochaine lecture).
- Mesuré (vrais modules sur CT114) : leçon de recette de Dania 71 % → 82 % du trajet recalé ; trajets synthétiques Berne 71 % → 85-90 %, 57 % → 87 %, sans écart de ligne ajouté (p99 0,1 m), au plus trois fois plus d'appels.
- Tests : 48 (unitaires + intégration PostgreSQL). Déployé 7d20d3a après sauvegarde `/root/drivy_refonte-before-7d20d3a-20261022T002745Z.dump`.

## 21 octobre 2026 : recalage direct sur la route (#90), déployé

- Donnée de recette (22.10, 00:25) : leçon terminée « Test : trajet simulé » du 21.10 à 08:00 pour Dania Badoni (Ramos Auto ecole), trajet synthétique de 1 000 points (17 min, ~9 km dans Berne, trois arrêts), chiffré avec la clé de capture, sans aucune position réelle. Sauvegarde préalable `/root/drivy_refonte-before-test-lesson-20261021T222437Z.dump`. Déchiffrement et recalage du replay vérifiés (71 % du trajet recalé). À supprimer après la recette.
- API 0c887e1 déployée sur CT114 (00:17 Zurich) après sauvegarde vérifiée `/root/drivy_refonte-before-0c887e1-20261021T221632Z.dump`. Sans migration. L'ancienne app ignore le champ `route` et reste compatible.
- Ligne et marqueur en direct suivent la route (OSRM privé) : mesures espacées de 20 m, plus de garde de vitesse, tronçon routier ancré renvoyé par l'API (`live-match` v2), réponses tardives conservées pour la ligne, Réduire les animations garde le recalage. Détails et mesures : `recalage-direct-route-20261021.md`.
- Exécuté : tests API (53, dont 26 sur PostgreSQL réelle), validation du vrai module sur CT114 contre CT117 (0 % → 25 à 67 % de fenêtres recalées en conduite synthétique, position p50 3 à 5 m, 0 % à pied hors route), compilation IPA.
- À qualifier : conduite réelle, réseau mobile, iPad, VoiceOver ; tests Swift sur runner Apple non lancés.

## 21 octobre 2026 : profil personnel complet et photo (#64), déployé

- Complément 7d14a39 (déployé 23:05 Zurich, sauvegarde `/root/drivy_refonte-before-7d14a39-20261021T210412Z.dump`) : migration `039_self_profile_contact.sql`, e-mail de contact, date de naissance et adresse postale dans « Mon profil » (contrat v3). L'e-mail de contact n'est pas l'adresse de connexion. Suite API : 546/566 dans la passe complète, les 20 échecs restants sont dans `g1b` et le fichier passe seul (27/27) ; instabilité sous charge à surveiller.
- Déployé e2d3711 sur CT114 (22:08 Zurich) après sauvegarde vérifiée `/root/drivy_refonte-before-e2d3711-20261021T200800Z.dump` (CT113). Migration 038 appliquée ; depuis CT109, `/v1/me/profile` et `/v1/people/{id}/photo` répondent 401 sans jeton. Clé de capture présente dans l'environnement (noms seuls contrôlés).
- API : migration `038_self_profile_details.sql` (prénom, nom, téléphone, version de photo sur `person` ; table `person_photo` chiffrée AES-256-GCM avec la clé de capture, RLS : soi-même ou membre actif d'une même école). Routes `GET`/`PATCH /v1/me/profile`, `PUT`/`DELETE /v1/me/profile/photo`, `GET /v1/people/{id}/photo` ; contrat `self-profile.json` v2. Le serveur retire EXIF/XMP/ICC/commentaires, borne 64 à 1024 px et 256 Kio.
- iOS : « Mon nom » devient « Mon profil » (photo, prénom, nom, nom affiché, téléphone) pour tous les rôles. PhotosPicker sans autorisation photothèque ; recadrage carré 512 px réencodé sur l'appareil. Photo en mémoire seulement, affichée dans l'en-tête du compte et du dossier élève.
- Exécuté : suite API complète avec PostgreSQL réelle (566 tests ; 3 invariants mis à jour : 50 tables RLS, instantané de migration), typecheck, compilation IPA.
- À qualifier sur appareil : choix d'une photo réelle (HEIC, panorama, orientation), VoiceOver de la feuille.

## 21 octobre 2026 : renommer son compte (#64) et annuler une leçon commencée (#61), déployé

- #64 : `PATCH /v1/me/profile` (extension, `apps/api/contracts/self-profile.json`), migration `037_self_profile.sql` : chaque personne renomme son propre compte, quel que soit son rôle ; la base refuse l'écriture hors de cette route et sur une autre personne. iOS : ligne « Mon nom » dans le compte pour tous les rôles. La photo de profil reste à faire (stockage protégé d'images).
- #61 (décision du porteur : « Annulée », comme si la leçon n'avait pas eu lieu) : une leçon commencée mais non terminée s'annule ; `actual_start` est effacé, un trajet actif est révoqué par `capture_lesson_changed`, positions et signalements déjà reçus sont conservés. Une leçon terminée ne s'annule toujours pas. iOS : « Annuler la leçon » dans le menu du GPS actif (arrêt du GPS avant l'envoi) et dans la fiche.
- Exécuté (PostgreSQL 17 local) : suite API complète, 564 tests réussis, dont `self-profile` et `lesson-cancel-started` ajoutés et cinq tests de l'ancienne règle A2-11 adaptés. Les deux tests SMTP passent avec `TEST_SMTP_PORT=11025 TEST_MAILPIT_URL=http://127.0.0.1:18025` (ports du Mailpit local). IPA compilée (`39662108676`). Non exécuté : tests Swift, recette appareil.
- **Déployé le 21 octobre 2026 à 21:37 Europe/Zurich** : release `eef3291` (web inchangé depuis `d537784`), archive SHA-256 `87101c60…b685`. Sauvegarde avant installation `/root/drivy_refonte-before-eef32912f3252d3889c96fc492c4b17641785128-20261021T193701Z-9ca1939fd78b.dump` sur CT113, root 0600, relue par `pg_restore`. 37 migrations, politique `person_self_profile_update` présente. Seule l'API redémarrée ; API, web et identité actifs ; depuis Caddy : readiness 200, `/v1/me` 401, `PATCH /v1/me/profile` sans version 428, web 200 ; aucune erreur API.

## 21 octobre 2026 : démarrage d'une leçon et départs GPS résiduels (#86, #87), non qualifié

- Mesure homelab (lecture seule, aucune modification) : API et base répondent en 0,5 à 8 ms depuis Caddy. Box vers Internet 5 ms. Mémoire et charge des CT113/114/117/109 normales. Pas de tunnel `cloudflared`. Par Cloudflare, la même requête prend 0,6 à 3,4 s. Même `drivy.shulker.ch/cdn-cgi/trace`, servi par Cloudflare sans joindre l'origine, prend 0,45 à 0,9 s, contre 30 à 50 ms pour `www.cloudflare.com` sur la même adresse. Le porteur constate la même lenteur en 5G. Cause : chez Cloudflare (ZRH, après sa maintenance du 20-21 octobre), pas dans le homelab. Aucune configuration changée.
- #87 : un départ GPS refusé (4xx) ou jamais émis est classé dans le coffre (`settleStartWithoutAuthorization`) et ne bloque plus les autres leçons. À l'ouverture, les départs en attente de plus de 2 min sont relus (5 s au plus, en lecture) ; ceux que l'école ne connaît pas sont retirés. Le bouton « Vérifier auprès de l'école » reste en place avec « Vérification… ». Une demande émise sans réponse reste à vérifier.
- #86 : préférences et élèves lus en parallèle, première page affichée tout de suite, élève connu relu seul, lieu de rendez-vous lu sur 20 leçons récentes sans bloquer le bouton ni écraser une saisie. Départ GPS en un geste : relecture finale remplacée par la seule lecture de l'école quand le contexte a moins de 60 s (l'école revoit version, accord et diagnostic à l'écriture), mesure et diagnostic sans relire le contexte, accord et diagnostic relus en parallèle.
- Exécuté : compilation IPA (premier lot). Non exécuté : tests Swift, recette appareil, mesure avant/après sur iPhone.

## 21 octobre 2026 : captures locales illisibles isolées sans perdre les autres (#48), non qualifié

- Avant : dans le coffre SQLCipher, une seule ligne de trajet ou de commande impossible à décoder faisait échouer toute la lecture. À l'ouverture, `recoverInterrupted` scellait tous les trajets interrompus dans une seule transaction : un trajet défectueux bloquait l'ouverture du coffre et la récupération des trajets sains.
- Maintenant, les lectures de trajets et de commandes (`sessions`, `pending`, finalisations confirmées, adoption d'époque, purge, récupération) décodent ligne par ligne. Une ligne illisible est notée dans une nouvelle table `quarantine` (identifiant, table, compte et école, cause `decode` ou `recovery`, état d'avant, date), puis sautée. Ses octets restent tels quels dans leur table : rien n'est effacé, aucune position n'est copiée. Une nouvelle détection ne crée pas de doublon.
- La récupération après relance scelle chaque trajet dans sa propre transaction. Un trajet qui échoue est isolé et passe à l'état « interrompu » (seule la colonne d'état change), sans commande inventée. Un trajet actif illisible est traité pareil, pour qu'il ne bloque pas les départs suivants. Avant cette relance, son état actif continue à empêcher tout nouveau départ.
- Une panne de base (stockage chiffré illisible, disque, clé absente) n'est pas une ligne défectueuse : l'erreur remonte telle quelle. Pas de nouvelle clé, pas de réinitialisation, pas de repli en clair.
- « À envoyer » montre « Un trajet de cet appareil ne peut plus être lu. Il reste gardé, sans envoi. » pour les trajets isolés du compte et de l'école en cours.
- Tests ajoutés dans `SchoolCaptureLifecycleTests` : ligne illisible à côté d'un trajet sain, trajet actif illisible à la relance (deux relances, rien d'effacé), mauvaise clé refusée sans réinitialisation. Exécuté : compilation de l'IPA. Non exécuté : ces tests et la suite Swift (runner Apple), recette sur appareil. Reste à faire : aucune action de support ou d'export du diagnostic.

## 21 octobre 2026 : agenda web tenu à jour des changements faits ailleurs (#49), non qualifié

- Avant : la minuterie de 30 secondes ne mettait à jour que l'heure affichée. Les leçons n'étaient relues qu'au retour sur l'onglet après une minute.
- Maintenant, tant que l'onglet est visible, la semaine affichée et le répertoire sont relus en arrière-plan quand la dernière lecture date d'une minute (vérification toutes les 15 secondes, donc un délai cible d'environ 60 à 75 secondes, non mesuré en production). Un onglet masqué ne lit rien. Il relit en revenant si la lecture date d'une minute.
- La relecture en arrière-plan (`useLoad().refresh`) ne passe pas par l'état de chargement : semaine, filtres, recherche et défilement restent en place. Elle ne se superpose jamais à une lecture en cours. Une réponse d'une ancienne semaine ou d'un autre moniteur est ignorée (génération et portée déjà en place).
- En-tête : « À jour à HH:MM » (heure de la dernière lecture réussie, distincte de l'horloge d'affichage) et un bouton « Actualiser ». Un échec garde la semaine affichée avec le message « Lecture impossible… Les informations affichées peuvent être anciennes. » et l'heure de la dernière lecture réussie.
- Pas d'événements serveur : la relecture bornée suffit à l'infrastructure actuelle et reste réutilisable pour les cours collectifs.
- Exécuté : typecheck web, tests `load-model`, `agenda-model`, `console-agenda-learners`. Non exécuté : suite complète, essai avec deux appareils.
- Déployé le 21 octobre 2026 à 14:20 (accord du porteur), web seul, version `d537784a971db4fffd3dda4465a4426b5f14a699` (#49 et partie web de #53). Sauvegarde préalable dans CT113 : `/root/drivy_refonte-before-web-d537784a971db4fffd3dda4465a4426b5f14a699-20261021T121943Z-345d5980fa00.dump`, 1 447 298 octets, 0600, catalogue `pg_restore --list` lu (1 081 entrées). Aucune migration, serveur BFF et dépendances identiques à `a70c17d`. Archive `apps/web` transférée par SHA-256, build sous Node v24.21.0 dans `/opt/drivy-refonte/web-releases/d537784…/apps/web` (CT114), override `90-web-release.conf`, seul `drivy-refonte-web` redémarré. API, identité et `current` (`a70c17d`) inchangés. Contrôles : `/app/` HTTP 200 sert le nouveau build, API sans jeton HTTP 401, trois services actifs. Retour arrière : supprimer l'override (le web revient sur `current`), `systemctl daemon-reload`, `systemctl restart drivy-refonte-web`.

## 21 octobre 2026 : homonymes distingués avant une action sur un compte (#53), non qualifié

- Quand deux membres, deux moniteurs ou deux invitations ont le même libellé (comparaison sans accents, casse ni espaces doublés), chacun reçoit une courte référence « Réf. A1B2 ». Elle reprend la fin de l'identifiant technique (partie aléatoire des UUID) et s'allonge jusqu'à différer de tous les homonymes. Un libellé unique n'a pas de référence.
- Aucune donnée personnelle supplémentaire n'est lue ni exposée : l'API et les droits ne changent pas. Les actions gardent l'identifiant technique comme clé. Le code d'invitation n'est jamais utilisé.
- Web : liste et détail de l'équipe, titre des confirmations (modifier les accès, retirer l'accès), messages de résultat, recherche (la référence est cherchable), liste et détail des invitations, sélecteur et confirmation du moniteur d'un code élève, filtre moniteur de l'agenda. Règle `client/person-reference.ts`, test `test/person-reference.test.ts`.
- iOS : même règle (`Core/HomonymReference.swift`) dans les sélecteurs de moniteur de la planification et des invitations.
- Exécuté : typecheck web, tests `person-reference` et `invitation-model`, compilation de l'IPA. Non exécuté : suite complète, recette VoiceOver et clavier.

## 21 octobre 2026 : positions conservées après une coupure du signal (#46), non qualifié

- Avant : quand un lot de positions iOS contenait une coupure de signal, la première position reçue après la coupure et le reste du lot étaient jetés. Le nouveau segment ne gardait que les positions arrivées ensuite.
- Maintenant (`SchoolCaptureLocationSource`), le segment interrompu s'arrête exactement à la première position reçue après la coupure. Le segment suivant de la même capture commence à ce même instant, ce que le stockage local et le serveur acceptent : il commence au plus tôt à la fin du segment précédent, sans chevauchement.
- Les positions gardées repassent par les contrôles habituels, avant le redémarrage du GPS (pour garder l'ordre des temps) : bail, permission, précision, âge, ordre. Rien n'est inventé pendant la coupure, qui reste visible entre les deux segments.
- Un arrêt, un changement d'école ou de compte, ou une capture différente annulent cette reprise.
- Pas de test automatisé ajouté : la source dépend d'un vrai `CLLocationManager`. Exécuté : compilation de l'IPA. Non exécuté : tests, recette sur appareil (perte puis retour du signal).

## 21 octobre 2026 : commandes de la carte GPS (#59), non qualifié

Causes trouvées en lisant le code (le problème n'a pas été reproduit sur appareil) :
- Le bouton de suivi parcourait trois modes : libre, puis nord en haut, puis sens du trajet, puis libre. Au troisième appui, il coupait donc le suivi, ce qui ressemble à « une fois sur deux ».
- La caméra ne se recentrait que si le mode changeait. Après un déplacement manuel, ou avant le premier point enregistré, un appui pouvait ne rien faire de visible.
- « Voir tout le trajet » cadrait sans tenir compte de l'en-tête ni des commandes posés sur la carte, et sans revenir au nord. Sur un trajet court, le résultat ressemblait à un recentrage.

Corrections :
- Le bouton ne coupe plus le suivi. Il recentre, puis alterne entre nord en haut et sens du trajet. Seul un geste sur la carte repasse en mode libre, comme dans Plans.
- Chaque appui recentre la caméra (`recenterRequest`), y compris sur la position de l'appareil avant le premier point.
- « Voir tout le trajet » remet le nord en haut et cadre le tracé avec des marges qui évitent l'en-tête et les commandes. Le bouton est désactivé tant qu'aucun tracé n'existe, et son icône montre maintenant un tracé au lieu des flèches de plein écran.
- Le replay garde ses deux états.
- Exécuté : compilation de l'IPA. Non exécuté : tests, recette sur iPhone en voiture, iPad, VoiceOver.

## 21 octobre 2026 : dossier depuis la fiche leçon (#62), confirmation des signalements (#58), toutes les compétences au bilan (#57), sortie de la clôture abandonnée (#47), non qualifiés

- #62 : pour l’équipe (moniteur, administration), le nom de l’élève en tête d’une fiche leçon ou d’un récapitulatif porte un chevron et ouvre son dossier en feuille, à partir de l’identifiant de l’élève et de l’école de la leçon. La fiche reste en dessous, avec sa saisie et le trajet. Côté élève, le nom du moniteur reste du texte. Le dossier ouvert ainsi n’a ni « Démarrer » ni « Planifier ». Il devient aussi l’élève sélectionné dans l’onglet Élèves.
- #58 : « Rétablir la configuration d’origine » utilise maintenant une alerte avec un message, comme les autres confirmations (« Recharger les informations de l’école ? »). Le message précise que le classement intelligent ne change pas. Le bouton revérifie le droit avant d’envoyer.
- #57 : l’étape Compétences du bilan affiche toutes les compétences du référentiel de la formation, à plat et dans son ordre. Le regroupement par signalement, objectif ou niveau déjà noté et le repli « Autres compétences » sont supprimés (règle `competencyGroups` et ses deux tests retirés). Les saisies et les brouillons restent attachés à chaque compétence.
- #47 : après une fin de leçon abandonnée (feuille du permis fermée) ou refusée, le trajet est arrêté et enregistré alors que la leçon continue. La fiche affiche déjà « Le trajet est arrêté. La leçon continue. ». Sa barre propose maintenant « Terminer la leçon » et « Reprendre le GPS ». La reprise est seulement manuelle : elle ferme le trajet arrêté sur l’appareil (ses points et son heure d’arrêt ne changent pas, son envoi continue), puis repasse par la préparation habituelle avec la vérification de l’accord. Rien ne repart tout seul. Un trajet en échec garde sa propre reprise.
- Relecture de validation : #47 planifie l’envoi du trajet arrêté avant de le fermer (sinon il n’aurait été repris qu’au prochain retour au premier plan). Pour #62, le nom est en bouton `.borderless` de 44 pt, pour ne pas capter les touches de la ligne de formulaire. Le test UI `FieldFlowTests` qui quittait le trajet par les onglets suit maintenant le parcours #60 : onglets absents, sortie, Agenda, retour au trajet.
- Exécuté : compilation de l’IPA, plus le test UI ciblé ci-dessus. Non exécuté : campagne complète, recette iPhone/iPad, VoiceOver.

## 21 octobre 2026 : GPS en plein écran et sortie sans arrêt (#60), non qualifié

- Pendant le trajet, la barre d’onglets est masquée (depuis Aujourd’hui et depuis la fiche leçon).
- Un bouton « Quitter l’écran du trajet » (chevron bas) se trouve à côté des trois points. Il ne met pas en pause, ne termine et n’annule rien : l’état « écran quitté » est séparé de l’existence de la capture dans `SchoolHomeView`.
- Une fois l’écran quitté, « Revenir au trajet en cours » reste au-dessus des onglets (`tabViewBottomAccessory(isEnabled:)`, iOS 26.1+). Sur iOS 26.0, le rappel est affiché en bas d’Aujourd’hui.
- Un nouveau trajet, un changement d’école ou de droits rouvrent l’écran normal. Un trajet déjà confirmé par l’école se ferme quand on le quitte.
- Exécuté : compilation de l’IPA seulement. Non exécuté : tests Swift/UI, recette iPhone/iPad, VoiceOver.

## 21 octobre 2026 : signalements autonomes (#56), déployé

Fusion en avance rapide dans `master` à la demande du porteur, puis **release `a70c17d` déployée à 02:18 Europe/Zurich**. Code serveur identique à `c1592b3`, dont la CI vérifications et navigateur est verte. Avant installation : sauvegarde privée CT113 `/root/drivy_refonte-before-a70c17d4b70a2c2de8bf224fb63067c20d9b196c-20261021T001819Z-7bfb2e5b1fba.dump`, root 0600, vérifiée par `pg_restore --file=/dev/null`. Pré-contrôle : aucune des 14 observations existantes ne contredit les nouvelles contraintes. Migration 036 appliquée, 36 empreintes conformes, contraintes `geo_observation_live_qualified` et `geo_observation_theme_key` présentes, 14 observations inchangées. API, web et identité actifs sur la release, readiness interne 200, routes publiques `/v1/me` et `/observation-themes` sans jeton 401, web 200, environnement API et configuration OSRM inchangés, aucune erreur API au contrôle du 21 octobre à 11:42.

IPA à installer : build 290 (`39517398901`, commit `2e23999`, code de l’app identique à `a70c17d`), SHA-256 `fffb3e63816d28f4e05159775a60dfef908694af6aee0aac09b3086292424a6c`.

Décision et détail : [signalements-autonomes-20261021.md](signalements-autonomes-20261021.md). La palette « Signaler » ne dépend plus du référentiel de la formation : un signalement se qualifie par son thème et son statut, la compétence devient facultative. Migration `036_autonomous_signals.sql` (remplace deux contraintes de 009/026 sans les réécrire).

**Exécuté** : 557 tests API sur vraie PostgreSQL et Mailpit en local, 316 tests web ; CI vérifications `39517398912`, parcours navigateur `39517398907` et IPA d’essai `39517398901` verts (l’IPA prouve que l’app compile, pas que ses tests passent).

**Pas exécuté** : les tests Swift modifiés et ajoutés. La campagne `39517398394` a été annulée à la demande du porteur après la compilation (`TEST BUILD SUCCEEDED`, cible `DrivyTests` comprise) et 6 premiers tests XCTest réussis, avant les suites de #56. Recette iPhone/iPad (18 tuiles, VoiceOver) non faite. Ordre de déploiement : service (036) avant l’app.

## 20 octobre 2026 : recalage suisse OSRM déployé, tests Apple réussis

Branche `claude/recalage-suisse-osrm-20261020`, issue de la branche GPS ci-dessous. Intégration dans `master` autorisée par le porteur à 22:12 UTC, avec les 25 commits des deux branches du 20 octobre. OSRM **v26.10.0**, profil voiture, extrait Suisse Geofabrik préparé sur Windows puis installé dans le nouveau **CT 117**. Écoute `192.168.1.158:5000`, accessible seulement à CT 114 et à l'hôte. Connexions sortantes nouvelles bloquées, sorties du moteur et core dumps désactivés. Service systemd et pare-feu vérifiés après redémarrage du conteneur à 22:59 Europe/Zurich : accès depuis CT 114 réussi, accès depuis le PC refusé, connexions sortantes nouvelles toujours bloquées, aucun redémarrage spontané du moteur.

**Bascule API exécutée à 22:56 Europe/Zurich** : `MAP_MATCHING_PROVIDER=osrm`, anciennes variables Mapbox commentées, service actif et readiness 200. Sauvegarde privée préalable vérifiée par lecture du catalogue et de tous les blocs (`pg_restore --file=/dev/null`), sans restauration d'essai. **Écart de procédure** : la création et l'installation initiales du CT 117 avaient été effectuées sans sauvegarde préalable. La sauvegarde faite ensuite ne corrige pas rétroactivement cet écart. Bascule API et durcissement ultérieur ont chacun leur sauvegarde vérifiée.

**Mesures exécutées en lecture seule** : trajet court 116/116 mesures couvertes (confiance 0,679, 43 ms), trajet lent 228/1 058 (0,960, 23 ms), mêmes couvertures que les résultats Mapbox déjà stockés. Aucun nouvel envoi de ces positions à Mapbox. RSS du moteur environ 650 Mio ; le compteur cgroup inclut aussi le cache de fichiers, sans OOM observé. Ces couvertures ne mesurent pas la justesse terrain.

**Release serveur `cf0f316` déployée à 23:14 Europe/Zurich**, après nouvelle sauvegarde vérifiée par décompression complète. Migration 035 appliquée, 35 empreintes conformes. Deux caches Mapbox supprimés, aucun ancien bail, 18 chunks et 204 483 octets chiffrés strictement inchangés. API readiness 200, route live sans identité 401, processus configuré OSRM privé sans jeton Mapbox actif. Aucun message d'échec API depuis la bascule au contrôle de 23:15.

**Vérifications serveur** : CI `39498076583` verte sur Node 24 avec vraie PostgreSQL et SMTP, 552 tests API et 316 web, types/builds ; parcours navigateur `39498076715` vert. Rejeu du direct exécuté en lecture seule : les deux captures restent sous 2 m/s avec vitesse estimée, donc aucune correction routière appliquée, avant/après identiques. Comparaison Mapbox/OSRM effectuée seulement sur une trace synthétique identique. Détails et limites dans [recalage-suisse-20261020.md](recalage-suisse-20261020.md).

**Vérifications Apple** : campagne `39501661059` réussie, 705 tests Swift Testing dans 66 suites et 6 XCTest. Les égalités flottantes du test ont été corrigées dans `1bc5b7f`, sans changement du code produit. IPA build 288 verte (`39498733858`), téléchargée et empreinte vérifiée. Le recalage n'est plus confié à un tiers ; les fonds de carte restent Apple Plans. Notices déjà adoptées non modifiées automatiquement. GPS, batterie, VoiceOver et fluidité physique restent à qualifier sur iPhone.

**Workflow ciblé** : à la demande du porteur, `unit_only=true` sélectionne désormais dix suites GPS par défaut ; `unit_test_scope=all` conserve la régression native complète. Quatorze tests locaux d'orchestration réussis. Campagne GPS Apple `39503905801` réussie : 108 tests dans dix suites. Détails : [workflow-ios-cible-20261020.md](workflow-ios-cible-20261020.md).

| Exigence | Vérification | Résultat observé |
|---|---|---|
| Recalage privé sans tiers | Configuration du processus, firewall et redémarrage CT117 | OSRM privé, sorties réseau nouvelles bloquées, aucun jeton Mapbox actif |
| Purge sans altérer les mesures | Migration 035, comparaison des chunks et baux avant/après | 2 caches Mapbox supprimés, 18 chunks identiques, 35 migrations conformes |
| Droits, panne, retard et confidentialité | Tests API sur vraie PostgreSQL en CI | 552 tests API réussis, dont 52 tests directs unitaires/intégration |
| Comparaison des moteurs | Même trace synthétique via le client applicatif | 98,1 % OSRM / 93,4 % Mapbox, référence biaisée OSRM, aucune donnée réelle envoyée |
| Direct sur leçons réelles | Rejeu privé avant/après et diagnostic moteur séparé | Aucun collage à faible vitesse, métriques identiques, aucune qualification terrain déduite |
| Swift et IPA | Runner Apple, version iOS corrigée | 705 Swift et 6 XCTest réussis : `39501661059` ; IPA build 288 réussie : `39498733858` |
| GPS, batterie, VoiceOver et fluidité physique | Recette sur iPhone | Non exécutée, à faire par le porteur |

## 20 octobre 2026 : GPS en direct et replay fluides

Branche `claude/gps-replay-fluide-20261020`, non fusionnée, non déployée. Détail : [gps-replay-fluide-20261020.md](gps-replay-fluide-20261020.md).

Cause mesurée sur la leçon réelle avec Dania (homelab, lecture seule, statistiques seulement) : le filtre d’affichage ne gardait que 151 mesures sur 1 058, et le curseur restait figé 4 s (médiane) puis sautait d’environ 4 m. Le replay tire maintenant son horaire de toutes les mesures, avec une vitesse continue ; la flèche et la caméra visent la route plus loin et tiennent à ×5 et ×10. En direct, le marqueur est prédit à partir de la vitesse et du cap mesurés par iOS ; le mode direction suit le cap de route. Carte à 120 Hz.

**Exécuté** : comparaison avant/après sur la leçon réelle (curseur figé de 906 s à 287 s, uniquement les arrêts réels ; 147 arrêts de plus d’une seconde à 17), scénarios des tests rejoués en JavaScript avec le filtre de l’API. Tests Swift sur runner Apple : premier passage, un seul échec, le nouveau test de la flèche (fenêtre mal recentrée au bord d’un tronçon), corrigé ; second passage vert (run `39482372052`, 685 tests Swift Testing dans 63 suites, plus les tests XCTest). Vérifications et IPA d’essai `fc7c4c3` vertes (runs `39482372248`, `39482372250`). Dernier commit de code `bce961c` (le marqueur en direct ne compare plus l’heure de la mesure, sur l’horloge de l’école, à celle du téléphone) : tests Swift `39485169131` (685 tests), vérifications et IPA `39485169031` verts. Rejeu du direct sur les leçons réelles : écart médian au véhicule de 2,6 m à 0,25 m, arrêts de plus d’une seconde de 146 à 14.

**À qualifier sur iPhone** : fluidité perçue, prédiction en virage serré, au rond-point et au freinage, 120 Hz réel. **Pas fait** : collage à la route pendant la leçon par le SDK Navigation Mapbox. Il demande une carte Mapbox à la place de MapKit et un destinataire de positions de plus ; c’est une décision du porteur.

## 19 octobre 2026 : V4 intégrée à la production et déployée

PR #36 fusionnée dans `master` en `d9a67c0`, à la demande du porteur. La branche réunit la refonte V4 (`design/ui-ux-v4-20261018`, `a93969f`) et la production `claude/audit-4agents-20261018` (`3893b7c`) : connexion native, création de compte par code, formations et tarifs, migration 034, confirmation d’identité et GPS. Sept conflits résolus : agenda web, BFF, session, test UI iOS, recette d’ouverture, `STATUS.md`. La recherche d’agenda V4 est conservée ; la réauthentification garde la vérification de fraîcheur de la production.

**Exécuté localement** : typage API et web, 488 tests API avec PostgreSQL 17, 316 tests web, 148 tests unitaires API, builds API et web. **CI `master` verte** : vérifications, parcours navigateur d’ouverture d’école avec Keycloak/PostgreSQL, GitGuardian, IPA d’essai.

**Déployé le 19 octobre 2026** : release `d9a67c0` sur le homelab, sauvegarde vérifiée `/root/drivy_refonte-before-d9a67c0a4d312d51b5074f82d017e012360e4f3f-20261019T145938Z-9900a00f3e76.dump` sur CT113, 34 migrations aux empreintes conformes, API/web/identité actifs, `/app/` 200 avec le bundle V4, `/app/bff/session` anonyme 200, `/refonte/v1/me` 401 sans jeton, aucune alerte dans les journaux. Aucune autre donnée de production modifiée.

**À qualifier sur appareil** : VoiceOver, grandes tailles de texte et GPS réel. Le test iPhone des thèmes de signalement reste en échec, défaut antérieur à la V4, à corriger séparément. Campagne iOS sur `release/v4-20261019` : compilation réussie, iPhone 29 tests exécutés dont 2 échecs du même test connu des thèmes, iPad partiel sans échec avant la limite de temps du workflow. La campagne complète iPad reste à rejouer.

## 18 octobre 2026 : audit V2, 20 agents et recette réelle locale

Branche `audit/intelligent-v2-20261018`, basée sur V1 `7c117cd`. Vingt explorateurs réellement exécutés : 16 GPT-5.6 Luna et 4 GPT-5.6 Sol. **26 signaux initiaux arbitrés, deux bugs confirmés corrigés : un P1 et un P2, aucun P0.** La réauthentification reste liée au compte initial. Le dossier élève distingue chargement, erreur et reprise de l’accord GPS, sans révéler un statut refusé en 403. Aucun défaut V1 résiduel ni régression démontré dans les parcours vérifiés.

**Validation exécutée : 447 tests API avec PostgreSQL/SMTP, 236 tests web, 51 scénarios navigateur à transport synthétique et 82 contrôles réels Edge/Keycloak/BFF/API/PostgreSQL/SMTP réussis.** Types, builds et intégrité des 556 fichiers canoniques passent. Le blocage Docker de V1 a été levé localement. Récupération de compte explicitement exclue, aucun mot de passe réinitialisé. Node 26 local au lieu du 24 requis, Apple/Safari/VoiceOver/GPS terrain non qualifiés. Aucun push, fusion, déploiement ou changement de production. Validation humaine avant intégration.

[Rapport V2 : décisions, preuves, fichiers et commits](audit-v2-20261018.md) · [Plan et bilan](audit-v2-20261018-plan.md) · [Matrice de clôture et observations](audit-v2-20261018-acceptance.md). Rejeu complet du lot committé réussi à 17:23:47 UTC, avec preuve nominative de chaque sortie modifiée et des frontières d’intégration, sans nouveau changement produit.

## 18 octobre 2026 : audit multi-agents local, non déployé

Branche isolée `audit/intelligent-20261018`, base `5482dd8`. Dix audits spécialisés terminés avec sept GPT-5.6 Luna et trois GPT-5.6 Sol, puis contre-revue ciblée Astra. **13 signaux arbitrés, 2 défauts confirmés corrigés : un P1 et un P2, aucun P0.** Le formulaire d’accès équipe conserve son brouillon lors d’une relecture concurrente et exige une résolution explicite avant écriture. Le vérificateur OIDC refuse les sujets non textuels sans transformer les identifiants opaques valides. Pas de refonte visuelle ni nouvelle dépendance.

**Exécuté localement :** 135 tests unitaires API, 233 tests web, types et builds, cinq scénarios de régression Edge, 41 interactions existantes, 30 captures ciblées et contrôle de reflow. L’intégrité des 556 fichiers canoniques est préservée. Les scénarios navigateur utilisent un BFF synthétique, pas le backend de production. PostgreSQL isolée indisponible : suite API complète tentée mais bloquée. Node 26 local au lieu de 24 requis. iOS, Safari et VoiceOver non exécutés. Aucun push, fusion, déploiement ou modification de données de production. Validation utilisateur et qualification CI requises avant intégration.

**Complément à 18:03 +02:00 :** recette officielle `check-school-opening.ts` réellement tentée sur PostgreSQL loopback réservée. Exit 1 avant le premier contrôle, étape base vierge, aucun service local requis disponible et daemon Docker absent. Aucun succès d’acceptation de bout en bout revendiqué. Les preuves avant/après établissent seulement les améliorations dans les tests contrôlés.

[Rapport complet, arbitrages, preuves et limites](audit-intelligent-20261018.md) · [Plan réalisé](audit-intelligent-20261018-plan.md).

## 18 octobre 2026 — audit à quatre agents (UI/UX, bugs, architecture, QA)

Intégré sur `claude/audit-4agents-20261018` : confirmation avant déconnexion avec une demande à vérifier, saisies conservées au retour par le cache de navigation, avis au-delà de 1 000 invitations, chevauchement d’horaires refusé dans la console, renouvellement du jeton sur 401 dans dix clients iOS, rappel « à terminer » sur cinq pages, agenda prévenu d’un démarrage sans rendez-vous, heure répétée du passage à l’heure d’hiver dans `next-slot`, ombres de menu et Réduire les animations alignés sur DESIGN.md. Architecture : rien de mort ni de dupliqué à retirer sans risque. **Exécuté** : typage web et API, 264 tests web, 132 tests API sans base. **À qualifier par la CI** : changements Swift (non compilés ici), tests PostgreSQL. Aucun déploiement. [Compte rendu](audit-4agents-20261018.md).

**Suite, même jour.** La branche intègre aussi `codex/lesson-gps-start-20261017` (`d97dfa9`, déjà en service : connexion native, GPS d’école), pour ne pas retirer du homelab ce qui y tournait. CI verte sur `3893b7c` : vérifications avec PostgreSQL, parcours navigateur d’ouverture d’école, IPA, **660 tests Swift**. Deux corrections issues de la CI : le test de reprise des migrations attend la 034 ; la relecture ratée d’un bilan (`ecdc144`) laissait enregistrer, elle bloque de nouveau l’écriture jusqu’à une relecture réussie. Le refus serveur des horaires qui se chevauchent est écarté : quatorze tests d’intégration empilent volontairement des plages pour un même moniteur ; c’est une décision produit (le homelab n’en a aucun). **Déployé le 18 octobre 2026** à la demande du porteur : release `3893b7c` sur le homelab, sauvegarde vérifiée `/root/drivy_refonte-before-3893b7c…-20261018T133933Z-a16f4abadaaa.dump` sur CT113, 34 migrations aux empreintes conformes (034 : politique RLS seule), API/web/identité actifs, `/health/ready` 200, `/app/` 200, `/refonte/v1/me` 401 sans jeton. L’app correspondante est à installer depuis l’IPA de la CI.

## 17 octobre 2026 — essaim de recherche de bugs

Vingt agents ont audité API, base, web et iOS ; 15 lots de corrections sont fusionnés sur `claude/essaim-bugs-20261017` : arrêt de trajet après finalisation qui effaçait des points reçus, tolérance d’horloge du téléphone, réauthentification pour inviter un ADMIN ou un moniteur, motifs de retrait cachés à l’élève dans la base (migration 034), limiteur d’entrée du BFF, leçon en attente qui disparaissait d’Aujourd’hui, bilan vidé après une relecture ratée, et plusieurs défauts d’agenda, de formations et d’accessibilité web. **Exécuté** : typage, 138 tests API sans base, 260 tests web, build web. **À qualifier par la CI** : tests PostgreSQL ajoutés et tests Swift. Aucun déploiement. Dix questions produit et les constats différés sont listés dans le [compte rendu](essaim-bugs-20261017.md).

## 17 octobre 2026 — démarrage d’une leçon et GPS inaccessible

Cause reproduite dans le code : une nouvelle école garde le GPS désactivé, aucun écran web ne permettait son activation, et l’app ouvrait une leçon commencée avec seulement « Terminer » sans expliquer le trajet absent. Correction : réglage explicite **Trajets GPS** dans la confidentialité du portail, motif et relecture dans l’app, départ libellé **avec GPS / sans GPS**. La connexion native est conservée ; la relecture d’un réglage ne démarre jamais une capture. [Décisions et vérification](demarrage-lecon-gps-20261017.md).

**En cours de vérification** : tests web, Swift, parcours UI et IPA sur runner Apple. **Non qualifiés** : GPS physique, batterie, VoiceOver et fluidité ressentie sur appareil. Aucun réglage d’école réelle ni déploiement n’a été effectué à ce stade.

## 15 octobre 2026 — connexion native, inscription réservée aux codes

- Exécuté : routes `access-codes/preview` et `accounts` (tests unitaires et PostgreSQL), BFF et écrans web « Se connecter » / « J’ai un code » (251 tests web), recette navigateur complète avec Keycloak réel à inscription fermée (compte responsable par code d’ouverture, moniteur et élève par lien d’invitation SMTP), écrans iOS natifs (connexion, code, création de compte, ouverture d’école).
- À qualifier : rendu iOS sur appareil, connexion Face ID après une connexion par mot de passe, parcours complet élève dans l’app. Détails : [connexion-native-20261015.md](connexion-native-20261015.md).

## 14 octobre 2026 — Formations et tarifs : une fiche par permis, déployé

À la demande explicite du porteur, version **`0f76da1` publiée vers 12:55 Europe/Zurich** sur [Drivy](https://drivy.shulker.ch/app/) (API et portail). Sauvegarde `drivy_refonte` vérifiée avant bascule (`pg_restore --list`), migration 033 appliquée, 33 empreintes de migration contrôlées ; le drop-in qui figeait le web sur `web-releases/2b4ca81` est retiré, API et web tournent sur la même release. Une première tentative (`8801aee`) s’est arrêtée avant toute migration : la compilation API dépassait les 256 Mo de l’installeur ; typage allégé et limite portée à 512 Mo. Complément publié à la demande du porteur : release **`061f846`** (nouvelle sauvegarde vérifiée), la liste des permis affiche en colonnes durée habituelle, prix des leçons, compétences, tarifs et élèves en formation. Vérifié après bascule : portail 200 servant la nouvelle interface, routes Formations protégées (401 sans session), `/health/ready` 200, services actifs, aucune erreur journalisée, aucun parcours existant renommé.

Branche `claude/formations-tarifs-20261014`, partie de `5482dd8`, DA Studio conservée. « Formations et tarifs » liste les permis ; Permis A s’ouvre directement sur sa fiche (Général, Compétences, Déroulement et annulation, Tarifs, Historique en action secondaire), chaque rubrique ayant son adresse, avec lecture puis édition sur place. Assistant distinct d’une seule formation, prestations sans permis à part, anciennes adresses `/offres`, `/referentiels`, `/procedures`, `/prestations`, `/conditions` résolues vers la version exacte. Socle : lecture agrégée indépendante de `readAll`, trois commandes composées atomiques (`CREATE_FORMATION`, `UPDATE_FORMATION_PROGRAMME`, `SAVE_TARIFF`) avec têtes attendues sous verrou, droits relus, audit et reçu AP72 ; migration 033 (nom facultatif d’un parcours) ; refus d’une version future sur un tarif applicable.

**Exécuté localement** (PostgreSQL 17 isolée en conteneur) : 451 tests API dont 12 scénarios Formations (concurrence, rollback injecté, AP72, droits, historique élève/bilan/réservation), 247 tests web, types et builds ; **98 contrôles intégrés** navigateur → OIDC → BFF → API → PostgreSQL sur le build compilé ; 45 scénarios et 66 captures axe sur fixture, sans échec. **À qualifier** : exécution CI, Safari, lecteur d’écran, zoom natif 200 %, recette avec une école ; cinq arbitrages à valider.

[Décisions, contrats, résultats et limites](formations-tarifs-20261014.md) · [Captures synthétiques](proofs/formations-tarifs-20261014/index.html).

## 14 octobre 2026 — Studio, portail inspiré de Mercury, déployé

Version **`2b4ca81` publiée à 01:01 Europe/Zurich** sur [Drivy](https://drivy.shulker.ch/app/), depuis `codex/portail-studio-20261014`, à la demande explicite du porteur. Sauvegarde de la base vérifiée avant bascule, 32 migrations existantes contrôlées, aucune migration exécutée ; seul le web redémarre. **19 contrôles HTTPS réussis** et page publique inspectée sans erreur console. [Version et retour arrière](web-studio-deployment-20261014.md).

La démo Mercury a été parcourue réellement : **35 captures sur 17 chemins**, menus, filtres, recherche, fiches, formulaires et deux thèmes. Studio reprend sa composition et ses proportions avec le cobalt Drivy et un sombre anthracite : Manrope embarquée, navigation secondaire dans le rail, espace de paramètres séparé, menus de choix dessinés et recherchables, listes avec identité/contact, fiches et éditeurs dédiés, paramètres en lecture puis modification, agenda regroupé par jour. Parcours, droits et contrats conservés ; aucun changement Apple. [Direction et composants](web-studio-20261014.md) · [Benchmark](web-studio-benchmark-20261014.md) · [Pages et parcours couverts](web-studio-inventory-20261014.md).

**Exécuté sur la version publiée** : [439 tests API/PostgreSQL, 233 tests web, types, builds et contrôles documentaires](https://github.com/tomyrms/Drivy/actions/runs/38481209557), [80 contrôles intégrés OIDC/BFF/API/PostgreSQL](https://github.com/tomyrms/Drivy/actions/runs/38481209552). Campagne locale consolidée : **41 scénarios réussis**, **240 configurations visuelles distinctes** clair/sombre à 1440/1024/390 px, aucun débordement ni erreur JavaScript. Les reprises ciblées remplacent les configurations antérieures sans gonfler le total. **160 audits axe** : 140 sur les pages produit et 8 sur composants fermés sans violation ni indétermination ; les 12 audits de menus ouverts conservent quatre signalements de sentinelles Base UI et 24 règles indéterminées, examinés et documentés avec leurs résultats bruts. Aucune conformité globale revendiquée. [Rapport, preuves et limites](web-studio-verification-20261014.md).

[Galerie de 21 captures avant/après](proofs/web-studio-20261014/index.html), quatre écrans représentatifs, thèmes clair/sombre et liste mobile. Restent à qualifier : zoom navigateur natif à 200 %, Safari, lecteur d’écran et recette avec une auto-école ; le reflow émulé et les données synthétiques ne les remplacent pas.

## 14 octobre 2026 — Registre Drivy déployé

À la demande explicite du porteur, version **`1c43c35` publiée à 00:10 Europe/Zurich** sur [Drivy](https://drivy.shulker.ch/app/), depuis `codex/portail-registre-20261013`. Sauvegarde `drivy_refonte` vérifiée avant bascule, 32 migrations existantes contrôlées, aucune migration exécutée. Seul le web redémarre ; API et identité inchangées. **19 contrôles HTTPS réussis** et page publique inspectée sans erreur console. [Version, preuve et retour arrière](web-registre-deployment-20261014.md).

Listes élèves/équipe structurées, contacts pour les homonymes, pagination de 25 lignes et liens natifs, fiches sur une page dédiée avec retour au contexte, annuaire indépendant des enrichissements et lecture individuelle hors liste. Cinq recherches du catalogue, validation par Entrée et focus d’erreur, actions d’enregistrement regroupées ; cases à cocher cohérentes et confirmations. Proportions et formulaires ajustés sur les tokens existants. Navigation, recherche des paramètres et thèmes personnels de la première passe conservés. Aucun changement natif.

**Exécuté sur cette version produit** : [439 tests API/PostgreSQL, 233 tests web, types et builds](https://github.com/tomyrms/Drivy/actions/runs/38475181117) ; [80 contrôles intégrés OIDC/BFF/API/PostgreSQL](https://github.com/tomyrms/Drivy/actions/runs/38475181157). Localement : **26 parcours**, **210 configurations visuelles distinctes** clair/sombre à 1440/1024/390 px sans débordement ni erreur JavaScript ; **140 audits axe distincts** sans violation. Deux contrastes indéterminés automatiques sont résolus par inspection et mesure (14,67:1 / 14,00:1), résultats bruts conservés. Couleurs forcées, reflow et focus des champs devant la barre d’actions exécutés. [Qualification détaillée et limites](web-registre-verification-20261014.md).

[Direction, composants et références](web-registre-20261013.md) · [Galerie avant/après, quatre vues et deux thèmes](proofs/web-registre-20261013/index.html). Restent : vrai zoom navigateur à 200 %, lecteur d’écran, Safari, recette avec une école et essais physiques ; aucune certification WCAG complète revendiquée. Les réponses synthétiques du harnais et les tests intégrés réels sont distingués dans les preuves.

## 13 octobre 2026 — refonte web déployée

Déploiement demandé et effectué à **23:12 Europe/Zurich** : portail et BFF `bad540b` en service sur [Drivy](https://drivy.shulker.ch/app/). **Sauvegarde de la base vérifiée avant bascule**, 32 migrations existantes contrôlées, aucune migration exécutée. API, identité et lien partagé restent sur leur version précédente ; seul le web redémarre. Les sessions navigateur peuvent demander une reconnexion.

**Exécuté** : [439 tests API/PostgreSQL et 233 tests web, types et builds](https://github.com/tomyrms/Drivy/actions/runs/38468486548) ; [80 contrôles navigateur OIDC/BFF/API/PostgreSQL réels](https://github.com/tomyrms/Drivy/actions/runs/38468486729), sources produit identiques à la release. Après publication, **19 contrôles HTTPS réussis**, dont les 12 empreintes de fichiers, préférences, session anonyme et refus API sans jeton ; page publique inspectée sans erreur console. La limitation Docker locale est contournée par cette recette CI, sans réinitialisation locale.

[Preuve, version, retour arrière et override à traiter au prochain déploiement global](web-redesign-deployment-20261013.md). Restent la recette avec une école, le lecteur d’écran, le zoom natif et les essais physiques ; les données métier de production ne servent pas à la recette.

## 13 octobre 2026 — homelab : ouverture des écoles (PR #31) et web enfin à jour

Déployé à la demande du porteur depuis la branche de la PR #31, non fusionnée : release `c5bfb73`, migrations 031 `school_opening` et 032 `school_setup_draft` (32 au total, empreintes vérifiées). Sauvegarde vérifiée de `drivy_refonte` juste avant, sur CT113 (`/root/drivy_refonte-before-c5bfb73…-20261013T194604Z-d376faba5ca1.dump`). Configuration de l’API inchangée : aucun opérateur d’ouverture déclaré (`SCHOOL_OPENING_OPERATORS_JSON` absent), donc personne ne peut encore émettre de lien d’ouverture.

**Le web était figé depuis le 9 octobre** : le réglage systemd `90-brand-web-release.conf` (mise en ligne de la marque) pointait le service web vers `web-releases/b710303`, et les déploiements suivants, dont les textes de l’école (lots 0 et 1), n’avaient mis à jour que l’API. Réglage retiré (copie dans `/root/systemd-retired/` sur CT114) : le web tourne désormais dans `current/apps/web`, vérifié par le répertoire réel du processus. `/app`, `/app/ouvrir`, `/app/operateur`, `/app/gestion` répondent 200, en local et sur le domaine public.

Puis, à la demande du porteur, « Luc auto école » est supprimée pour essayer l’ouverture d’une école de bout en bout (sauvegarde vérifiée de `drivy_refonte` et `drivy_identity` dans `/root/drivy-before-opening-20261013T194941Z/` sur CT113). Les personnes et comptes de connexion restent. Un lien d’ouverture valable sept jours est inséré directement en base, faute d’opérateur déclaré ; le jeton n’est enregistré nulle part dans le dépôt.

IPA correspondante : run 38427200996 (`43d0a3b`, dernier commit iOS de la PR), empreinte vérifiée. **Non exécuté** : parcours connecté sur le homelab après déploiement.

## 13 octobre 2026 — refonte complète du portail web

La direction **Bureau de précision** est implémentée sur `codex/refonte-portail-web` : navigation stable et sous-pages visibles, séparation école/compte, recherche des paramètres jusqu’au champ, listes élèves/équipe, contexte conservé au retour, résolution des profils incomplets, formulaires et protection des saisies, thèmes Clair/Sombre/Système persistants. Les pages d’entrée, invitations, catalogue, guide et opérateur réutilisent les mêmes fondations. Liens existants et contrats préservés ; aucun changement Apple ni déploiement.

**Exécuté localement** : typage, **233 tests web dans 21 fichiers**, build et contrôle des espaces réussis ; **18 parcours navigateur réussis**. **186 configurations visuelles distinctes** (138 de la campagne initiale et 48 complémentaires), à 1440/1024/390 px dans les deux thèmes, sans débordement du document ni erreur JavaScript. **124 audits axe distincts** sans violation ou vérification indéterminée, avec recontrôles ciblés après corrections. Contrastes : **60 couples sur 60** au seuil testé. Les scénarios fonctionnels exécutés et les retouches qualifiées sont détaillés dans la [preuve de vérification](web-redesign-verification-20261013.md). Inspection manuelle sur les captures, en complément des parcours clavier.

**Limites** : les composants réels sont exercés avec des réponses BFF synthétiques. La recette OIDC/API/PostgreSQL réelle de cette branche n’est pas exécutée : Docker Desktop échoue sur son socket local avant le démarrage du moteur. Aucun volume n’est réinitialisé. Le reflow équivalent à 200 % est exécuté, sans manipulation du zoom natif ; lecteur d’écran, recette humaine des commandes métier longues et utilisation avec une école restent à qualifier. Aucune conformité WCAG complète ni qualification physique n’est déduite des tests. Le build conserve l’avertissement du script initial de thème classique et du bundle principal de plus de 500 Ko.

[Synthèse et pages migrées](web-redesign-20261013.md) · [Direction, benchmark et tokens](web-redesign-design-20261013.md) · [Inventaire des parcours](web-redesign-inventory-20261013.md) · [Galerie avant/après clair et sombre](proofs/web-redesign-20261013/index.html).

## 13 octobre 2026 — sortie du guide et recette jusqu’à la première leçon

Un défaut supplémentaire est reproduit et corrigé : « Enregistrer et quitter » restait bloqué si la sauvegarde réussissait mais que sa réponse était perdue. Le dialogue se ferme désormais pour laisser vérifier la demande ; la sortie reste explicite après récupération. Contrôles locaux clic/clavier, 228 tests web, types et build réussis. La recette intégrée ajoute la reconnexion dans un navigateur indépendant, ce cas de sortie et la préparation jusqu’à une première leçon réservée par l’API de l’app, sans écriture SQL de préparation.

**Exécuté** : [439 tests API et 228 tests web, types, builds et migration peuplée](https://github.com/tomyrms/Drivy/actions/runs/38427201119) à `43d0a3b` ; [79 contrôles navigateur](https://github.com/tomyrms/Drivy/actions/runs/38424749543) à `769254a`, sources API/web inchangées ensuite. Reprise indépendante, sortie incertaine et premières actions jusqu’à la réservation réelle par l’API réussies ; huit captures téléchargées, Agenda final inspecté. [Preuves et limites](verification-onboarding-20261013.md).

**Apple à `43d0a3b`** : [deux scénarios racine réussis sur iPhone et iPad](https://github.com/tomyrms/Drivy/actions/runs/38427200596), quatre passages sans échec ni test ignoré, huit captures inspectées. La vraie racine et le retour système au premier plan vérifient DRAFT → ACTIVE avec accueil moniteur, puis la relecture des rôles vers ADMIN seul. Seules l’identité et les réponses serveur sont simulées, exclusivement en DEBUG simulateur. La première campagne échouait sur des clés nulles omises par la fixture ; cette correction est qualifiée. [IPA 0.7.0/270 compilée et vérifiée](https://github.com/tomyrms/Drivy/actions/runs/38427200996), exécutable identique à la 269. Aucun déploiement. Restent la recette avec une école, la messagerie cible, Safari/OIDC réel, le zoom natif, le lecteur d’écran et les essais physiques ; aucune qualification humaine ou physique n’est déduite des fixtures.

## 13 octobre 2026 — vérification complémentaire de l’onboarding

Défauts reproduits et corrigés : étape suivante hors écran sur mobile, mauvais champ ciblé pour une explication ou une compétence, erreurs absentes auprès des champs du guide, erreur de fuseau trop vague, styles de saisie absents à l’ouverture, prochaine action visant le mauvais réglage, dossier personnel introuvable pour ADMIN + LEARNER au-delà de la première page. [Vérification, preuves et limites](verification-onboarding-20261013.md).

**Exécuté sur les dernières sources API/web `5d42465`** : [439 tests API sur PostgreSQL et 228 tests web, types et builds](https://github.com/tomyrms/Drivy/actions/runs/38420532256), [53 contrôles navigateur intégrés](https://github.com/tomyrms/Drivy/actions/runs/38420532259). Parcours clavier, rendus d’ouverture clair/sombre à 320/390/1440 px et erreurs liées aux champs également vérifiés localement. **Apple `563166b`, sources natives inchangées depuis** : [634 tests distincts réussis](https://github.com/tomyrms/Drivy/actions/runs/38419091299), [IPA 0.7.0/268 compilée et empreinte vérifiée](https://github.com/tomyrms/Drivy/actions/runs/38419088103). Le [scénario UI ADMIN + LEARNER](https://github.com/tomyrms/Drivy/actions/runs/38419095872) réussit sur iPhone et iPad ; les deux captures sont inspectées. Aucun déploiement ni qualification physique. Le retour Safari/OIDC réel, le lecteur d’écran et la recette avec une école ne sont pas attestés par ces contrôles.

## 13 octobre 2026 — onboarding école et navigation web

Le porteur a validé la réalisation des six lots du [plan](plan-onboarding-ecole-navigation-20261013.md). Navigation à sous-pages sous la catégorie, création par lien opérateur à usage unique, guide web de six étapes avec exemples adaptables et brouillon serveur, activation transactionnelle explicite, ajout guidé des formations/tarifs, prochaines actions serveur, invitations d’équipe disponibles selon la messagerie et renvoi natif DRAFT vers le web. [Réalisation et exploitation](realisation-onboarding-ecole-20261013.md), [contrat de réalisation](onboarding-api-20261013.md).

**Intégration** : fusion des textes de l’école déjà livrés sur `master` ; mêmes propositions dans le guide et les réglages, informations élèves appliquées dès confirmation, impact GPS chiffré. Les migrations d’ouverture et de brouillon sont 031/032 ; les migrations 029/030 déjà déployées restent intactes. Aperçu élève partagé, explications consultables dans la revue, étapes reportées/à revoir, références de prestations générées et tableaux lisibles à 320/390 px.

**Exécuté web/API** : 435 tests API sur PostgreSQL 17, dont migration synthétique peuplée 030→031/032 conservant les données historiques, reçus et lectures GPS ; 227 tests web ; types, builds et intégrité documentaire ([CI `75e79f9`](https://github.com/tomyrms/Drivy/actions/runs/38408861311)). [Navigateur intégré](https://github.com/tomyrms/Drivy/actions/runs/38408861092) : 45 contrôles, Keycloak et SMTP de test, compte vérifié, ouverture, brouillon/reprise AP72 après rechargement, activation, ajout de tarif avec réponse perdue récupérée sans rechargement ni doublon, mobile/clavier, invitation d’équipe acceptée et récupération du compte. Revue Chrome locale avec réponses simulées et captures, dont 29 contrôles après fusion et 17 de finition du guide.

**Apple** : sur la fusion `cfe6912`, [628 tests Swift Testing et 3 XCTest](https://github.com/tomyrms/Drivy/actions/runs/38406649916) réussis ; [IPA 0.7.0/267 compilée](https://github.com/tomyrms/Drivy/actions/runs/38406612192), SHA-256 vérifié. Cette preuve précède les corrections complémentaires ci-dessus ; la correction `a9eb11e` touchait seulement le test de lecture des textes et sa fixture DEBUG de simulateur. La [campagne UI ciblée](https://github.com/tomyrms/Drivy/actions/runs/38406656380) valide les trois entrées scolaires et le choix GPS sur iPhone et iPad, soit huit passages et douze captures inspectées. La [requalification de la lecture des textes](https://github.com/tomyrms/Drivy/actions/runs/38410881577) réussit sur les deux appareils après correction d’une attente erronée du test concernant le bouton Continuer légitime de l’accueil : deux passages couvrant chacun trois contextes, garde de fixture interdisant les écritures actif, six captures supplémentaires inspectées sans débordement observé.

**Non exécuté** : déploiement de cette branche sur le homelab, recette avec un responsable d’auto-école, essais physiques GPS/batterie/VoiceOver. Les modèles restent à adapter par l’école ; aucune validation juridique ni évolution du régime GPS n’est revendiquée. Une école créée par lien conserve les modules désactivés ; le guide permet de démarrer sans capture GPS et ne fournit pas de commande d’activation du module GPS scolaire.

## 13 octobre 2026 — homelab remis à zéro

À la demande du porteur, pour essayer le parcours d’une école neuve. **Sauvegarde vérifiée avant tout effacement** (`pg_dump` puis `pg_restore --list`) de `drivy_refonte` et `drivy_identity` : `/root/drivy-reset-20261013T112412Z/` sur CT113 et sur l’hôte Proxmox, copie dans `.local/backups/` (empreintes identiques). Toutes les données de Drivy sont effacées : écoles, élèves, leçons, trajets, bilans, textes. Les comptes de connexion (`luc`, `moniteur`, `eleve`) sont gardés. Une seule école est recréée : « Luc auto école », en préparation, vide, luc administrateur et moniteur, GPS actif (repris de l’ancienne école : une école neuve l’a désactivé et aucun écran ne permet de l’activer).

## 13 octobre 2026 — textes de l’école : lot 1

[Décisions du porteur](decisions-2026-10-13.md) : textes proposés par défaut, un seul texte, informations demandées sans brouillon, plus de motif d’approbation.

- **API.** `GET /text-proposals` (textes rédigés par Drivy, jamais adoptés par une lecture ; Mapbox cité seulement s’il est configuré ; aucune durée chiffrée). `PUT /data-policy` avec `publishProposedFields` publie aussi les informations demandées proposées : prénom et nom requis, téléphone et e-mail facultatifs, rien qui bloque la planification. `POST /profile-field-policies` avec `publishNow`. `approvalReason` facultatif. `GET /recording-choices` (migration 030) : accord GPS de chaque élève pour l’administration.
- **Web.** Réglages : École, **Confidentialité et conditions**, Signalements. La page regroupe les textes (préremplis tant qu’ils ne sont pas adoptés), les informations demandées en tableau et un accès aux conditions. Le menu ne montre plus « Préparation » : l’Agenda affiche ce qui manque pour planifier, avec un lien par manque. Le dossier élève montre l’accord GPS (« À redonner » s’il date d’anciens textes). Plus de « Motif » ; une nouvelle procédure ou de nouvelles conditions partent des textes proposés.
- **iOS.** Un seul composant pour les textes de l’école : trois lignes sur le GPS (« Enregistré pendant la leçon seulement », « Visible par toi et ton école », « Sans GPS, la leçon a lieu quand même »), puis « Tes données » (élève) ou « Confidentialité » (moniteur) ouvre le texte complet. Il remplace les six présentations différentes.

**Exécuté** : API sur PostgreSQL en CI (nouveaux tests : textes proposés, adoption en un geste, accords GPS lus par l’administration, motif facultatif, publication immédiate) ; tests unitaires des textes proposés en local ; web 199 tests, typecheck et build en local. CI verte et IPA compilée sur `0775be9`. **Non exécuté** : tests Swift, captures, essai sur appareil. **Déployé le 13 octobre 2026** à la demande du porteur : release `0775be9` sur le homelab après sauvegarde vérifiée, 30 migrations aux empreintes conformes, services actifs (`.local/deploy-textes-lot1-release.py`).

## 13 octobre 2026 — textes de l’école : lot 0

Suite de l’[analyse des textes de l’école](analyse-textes-ecole-20261013.md), lot 0 seulement (aucune décision juridique requise) :

- **Adoption prévenue.** Le dialogue « Relire les textes » lit `GET /v1/schools/{id}/data-policy/impact` (administration seule, migration 029). Il dit combien d’élèves avaient accepté le GPS avec les textes actuels et combien de trajets en cours s’arrêteront. L’API ne renvoie que deux nombres, jamais un nom.
- **Textes vides refusés.** L’information et la conservation demandent au moins 40 caractères utiles, dans l’API comme dans le web : « ddd » n’est plus accepté.
- **École sans textes.** L’app affiche « L’école n’a pas encore publié ses textes de confidentialité. La leçon peut se faire sans GPS. » au lieu de « L’accord GPS n’a pas pu être lu ».
- **Vocabulaire.** Web : « Confidentialité », « Lire les textes », « Modifier les textes », « Adoptés le … » au lieu de « Version 2 » ; « Informations demandées » dans le menu et le titre. « Services de l’école » (toujours « À configurer ») et « Enregistrer l’avancement » sont retirés ; le bloc « Activation » n’apparaît que pour une école en préparation. App : « Tes données » pour l’élève, « Confidentialité » pour le moniteur, « Conservation » ; plus de « notice » ni de « Version N » à l’écran.

**Exécuté** : typecheck API ; web 193 tests (dont 3 nouveaux) et typecheck en local. **À exécuter sur la CI** : tests API sur PostgreSQL (nouveau test d’impact, textes trop courts), compilation de l’IPA. **Non exécuté** : tests Swift, captures, essai sur appareil. **Déployé le 13 octobre 2026** à la demande du porteur : release `a2ab75a` sur le homelab après sauvegarde vérifiée de `drivy_refonte`, 29 migrations aux empreintes conformes, services actifs (`.local/deploy-textes-release.py`). Les textes adoptés de Luc auto école restent « ddd » / « wssd » : les réécrire depuis le web redemandera l’accord GPS à 23 élèves (30 accords).

## 13 octobre 2026 — actions à effectuer : du point bleu jusqu’à la résolution

Le point bleu d’« Élèves » et les lignes « Profil à compléter » ne menaient à rien dans le dossier. Cause : un état de profil stocké qui ne suivait pas la politique de l’école (11 faux « à compléter » sur le homelab, dont la politique n’exige que prénom et nom). L’API calcule désormais l’état à la lecture, avec la même règle que le dossier et la planification. Le dossier nomme chaque information manquante (« Profil à compléter · 3 informations manquantes ») ; chaque ligne ouvre le formulaire sur le champ, clavier prêt, et le formulaire marque d’un point les champs requis encore vides. Le point de l’onglet suit toute l’école, plus la page affichée, et s’éteint dès la correction relue. L’élève qui a laissé son accueil en route le reprend depuis Profil (« Reprendre l’accueil »), sans attendre sept jours. Sur le web, le dossier d’un élève incomplet nomme les informations manquantes et les fait saisir sur place. Corrigés aussi : « Leçon à terminer » s’allume à la fin prévue et s’éteint à la confirmation ; « Accord GPS » allume Profil sans visite préalable ; une panne ne retire plus « Reprendre l’accueil ». [Audit, décisions et limites](guidage-actions-20261013.md).

**Exécuté** : API, 340 tests sur PostgreSQL dont 4 nouveaux (sans politique, champ facultatif, incomplet → partiel → complet, champ vidé) ; **571 tests Swift réussis** dont 10 nouveaux ; IPA d’essai compilée ; captures iPhone clair/sombre du dossier incomplet (`dossier-incomplete`). Web : 188 tests, dont 3 nouveaux (décompte, corps de la saisie, routes du relais), types. **Non exécuté** : parcours UI, iPad, rendu du bloc web dans un navigateur. **Déployé** sur le homelab le 13 octobre (release `e2f78a1`, API et web, sauvegarde `drivy_refonte-before-e2f78a1…-20261012T235700Z` prise avant, 28 migrations vérifiées) ; l’app est à installer. **Reste à qualifier** : ouverture au clavier et défilement jusqu’au champ sur appareil, VoiceOver, grand texte.

## 13 octobre 2026 — classement intelligent des signalements

Paramètres → Signalements porte une option « Classement intelligent », désactivée par défaut, propre à chaque moniteur. Activée, elle range **tous** les signalements affichés d’après ses habitudes ; la grille de « Signaler » garde ses trois colonnes et ses neuf tuiles visibles, qui sont simplement les neuf premières places. L’ordre manuel reste celui de l’école et n’est jamais écrit par le classement : désactiver l’option le rend tel quel. Le service classe (moteur pur, `observation-ranking-engine.ts`) au plus une fois par jour, sur les usages des jours précédents lus dans `geo_observation` ; l’app applique l’ordre et le fige pour toute la leçon, reprise comprise. Conception, paramètres, contrat et simulations : [classement-intelligent-20261013.md](classement-intelligent-20261013.md) ; app : [classement-intelligent-ios-20261013.md](classement-intelligent-ios-20261013.md).

**Exécuté** : moteur et simulations en local et sur la CI (25 tests) ; tests PostgreSQL sur la CI (10 tests : défaut, activation, retour au manuel, un reclassement par jour avec deux lectures simultanées, isolement entre moniteurs et entre écoles, RLS), suite API complète verte ; compilation de l’IPA ; tests Swift sur la CI (cinq suites du classement vertes). Une assertion de hauteur de la grille, antérieure à ce lot (quatre et six tuiles tiennent sur deux rangées), est corrigée. **Déployé sur le homelab** le 13 octobre à la demande du porteur : release `be5d5d8` (API de cette branche, qui porte aussi la recherche du prochain créneau), sauvegarde vérifiée avant, 28 migrations aux empreintes conformes, `/health/ready` 200, la route répond 401 sans jeton. **Reste à qualifier** : l’app qui porte l’option n’est pas installée ; l’écran de réglage et la grille classée n’ont pas été vus, ni sur simulateur ni sur appareil ; VoiceOver non essayé ; les paramètres viennent de simulations, pas d’usages mesurés. **À confirmer par le porteur** : l’ordre manuel reste celui de l’école (pas d’ordre manuel personnel par moniteur) ; une leçon fige l’ordre connu de l’app à sa première ouverture de « Signaler », qui peut dater de la veille si l’app n’est pas repassée par l’accueil.
## 12 octobre 2026 — reprise d’une leçon après fermeture ou crash

Après une fermeture, un crash ou un redémarrage, la fiche propose « Continuer le trajet » au lieu de « Démarrer le trajet ». Le chronomètre reprend la durée réelle de la leçon depuis son départ enregistré par l’école ; la carte redessine le tracé et les signalements des trajets précédents ; l’arrêt du trajet interrompu part avant le nouveau départ, sans doublon. Rien n’était perdu avant, rien n’était repris. [Cause, décisions et limites](reprise-lecon-20261012.md).

**Exécuté** : rien ici (pas de toolchain Swift sous Windows) ; tests Swift ajoutés (crash simulé sur le coffre SQLCipher, durée de leçon, tracé antérieur), à exécuter sur la CI. **Reste à qualifier** sur iPhone : fermeture forcée, crash, redémarrage, reprise après plusieurs minutes, perte de réseau au moment de continuer.

## 12 octobre 2026 — Paramètres du moniteur, ouverts depuis le Profil

L’engrenage du Profil du moniteur (barre de navigation, « Paramètres », `profile-settings`) pousse une page « Paramètres » dans la pile du Profil : Préférences de leçon (la feuille existante), Signalements (mêmes conditions qu’avant : droit de gérer les thèmes), Apparence, Sécurité (verrou biométrique, si l’appareil en a un), Se déconnecter (même ligne et même confirmation pendant un trajet). Ces lignes ont quitté le Profil, qui garde l’en-tête, Leçons et le compte (Mes informations, Reprendre l’accueil, Invitations, Gérer l’école, Changer d’école). Aucun réglage nouveau ; Profil et Paramètres de l’élève inchangés. Vue `SchoolStaffSettingsView`.

**Exécuté** : rien (pas de compilation possible sur la machine Windows). **Reste à qualifier** : compilation, tests UI mis à jour (`NativeNavigationTests`, `AppearanceSettingsTests`), push et retour natifs, feuille des préférences ouverte depuis la page poussée, clair et sombre à l’œil, VoiceOver, grand texte, iPad.

## 12 octobre 2026 — « Planifier une leçon » s’ouvre sur le prochain créneau libre

À l’ouverture, l’école cherche le prochain créneau réellement libre (ouvertures du moniteur, pauses, indisponibilités, leçons du moniteur tampon compris et de l’élève dans toute l’école, durée, affectation, jours non travaillés) et l’app le présélectionne ; un squelette tient la place de la date pendant la recherche, sans saut. Choix manuel prioritaire, « Chercher plus loin » quand la période est vide. Calcul au serveur parce que les occupations de l’élève sont masquées au moniteur : nouvelle route `GET …/lessons/next-slot`, extension hors contrat canonique, sans migration. [Architecture, comportement et limites](prochain-creneau-20261012.md).

**Exécuté** (Windows, sans base ni toolchain Swift) : 17 tests purs de la recherche (`test/next-slot.test.ts`, fuseau, heure d’été et d’hiver, pauses, fermetures, tampon, élève, affectation, période vide) et les 85 autres tests unitaires de l’API, réussis ; `tsc --noEmit` sans erreur. **Écrit, non exécuté** : `lesson-next-slot.integration.test.ts` (PostgreSQL : occupation privée de l’élève, tampon, fermeture, contrat, droits) et 11 tests Swift, 17 cas (`SchoolPlanningNextSlotTests`). **Reste à qualifier** : compilation et tests Swift sur la CI, squelette et position du calendrier sur appareil, clair et sombre, VoiceOver. **Ordre de déploiement** : API d’abord ; une app plus récente que l’API retombe sur la saisie manuelle (404 silencieux).

## 12 octobre 2026 — audit global et corrections

Cinq audits en lecture seule (écrans iOS, API et base, UI/UX, architecture, fiabilité terrain), puis corrections par lots. 65 constats distincts : 1 P0, 8 P1, 30 P2, 26 P3 ; 41 corrigés. Le P0 : une affectation faite au bureau arrêtait le trajet du moniteur et bloquait l’iPhone (positions jamais envoyées, plus aucun départ). Corrigé côté serveur (migration 025) et côté app. Aussi : verrou Face ID au-dessus des feuilles, bilans lisibles au bureau, l’élève ne reçoit plus que la version courante d’un bilan, heure réelle d’un départ hors ligne, signalements renvoyés seuls, reprise du GPS sans réseau, positions purgées une fois confirmées, replay paginé sans tout déchiffrer. [Constats, décisions du porteur, changements d’API et limites](audit-global-20261012.md).

**Exécuté** : API 322/322 tests sur PostgreSQL locale (base 311) ; web 149/149 ; IPA d’essai compilée ; tests Swift sur la CI (résultat dans la PR). **Non fait** : audit UI/UX sur captures (agent arrêté par la limite d’usage), aucune retouche visuelle. **Non déployé** : migrations 025 et 027, `WEB_TRUST_PROXY`. **Reste à qualifier** : tout sur iPhone (verrou au-dessus d’une feuille, adoption d’époque, purge, reprise hors réseau). **Au porteur** : un départ immédiat lancé par erreur ne s’annule plus, il se termine puis l’école corrige l’issue.

## 12 octobre 2026 — « Signaler » : douze tuiles visibles, la suite défile

Le volet montre d’emblée les douze premiers signalements affichés, dans l’ordre de l’école ; au-delà, la même grille continue en dessous et défile, avec l’amorce estompée de la rangée suivante. Le volet garde la hauteur de douze tuiles quel que soit leur nombre ; tuiles de hauteur égale. [Règle et contrôle](signalements-ios-20261012.md#mise-à-jour--douze-tuiles-visibles-la-suite-défile-12-octobre-troisième-lot).

**Exécuté** : voir la PR (IPA et captures sur la CI). **Reste à qualifier** : défilement et fondu sur appareil, tailles d’iPhone autres que celle de la campagne, VoiceOver.

## 12 octobre 2026 — signalements configurables : 18 thèmes, réglés par école

« Signaler » ne déplie plus le référentiel tel quel : un catalogue de dix-huit thèmes à clés stables (les onze d’avant, plus Clignotants, Distance de sécurité, Freinage, Changement de voie, Démarrage, Virages, Éco-conduite), dont douze affichés à l’origine. Chaque école règle l’ordre et l’affichage ; l’administrateur le peut toujours, un moniteur avec le nouveau droit « Gérer les signalements ». Masquer un thème ne retire aucune observation : chaque observation garde la clé de son thème. Réglage dans l’app (Profil → Signalements, glisser-déposer natif) et sur le web (section Signalements, droit dans Équipe). Sept pictogrammes dessinés avec les skills logo-design et brand-identity, trois études chacun. [Contrat et décisions](signalements-configurables-20261012.md) · [icônes](icones-signalements-20261012.md) · [iOS](signalements-ios-20261012.md) · [web](signalements-web-20261012.md).

**Exécuté** sur `506f205` : API, 14 tests d’intégration nouveaux sur PostgreSQL (droits, RLS, conflit de version, deux écoles, historique après masquage) et « Refonte · vérifications » verte ([run 38288053857](https://github.com/tomyrms/Drivy/actions/runs/38288053857)) ; web, 186 tests, types et build, section vue dans Chromium avec une API simulée ; IPA d’essai compilée ([run 38288054203](https://github.com/tomyrms/Drivy/actions/runs/38288054203)) ; **538 tests Swift réussis** ([run 38289548778](https://github.com/tomyrms/Drivy/actions/runs/38289548778)). **Non exécuté** : parcours UI iOS, captures d’écran, migration 026 sur le homelab (rien n’est déployé). **Reste à qualifier** : glisser-déposer et grille de 13 à 18 tuiles sur appareil (hauteur calculée, pas vue ; la grille défile sur un petit iPhone), clair et sombre à l’œil, VoiceOver, toucher sur le web, synchronisation iOS ↔ web contre une vraie API, choix du porteur sur les sept icônes (`assets/icones-signalements-20261012/choix.png`). **Ordre de déploiement** : API avant l’app ; une app plus récente que l’API garde son catalogue embarqué et n’envoie pas la clé de thème.

## 12 octobre 2026 — leçon terminée en onglets, « Mon souhait », Formation d’un permis, icône Progression

La leçon terminée se lit en trois onglets sous la carte de l’élève (Bilan, Compétences, Trajet & notes), même vue pour le moniteur et l’élève. Côté élève, « Mon souhait » ferme enfin son clavier, et l’accord GPS sous le souhait ne reste plus en squelette (une lecture annulée par un `Group` n’était jamais relancée). Dans le profil, la Formation d’un permis passe au-dessus de Leçons et Progression, dense, avec des décomptes réels du référentiel. L’onglet Progression de l’élève a son icône dessinée (une courbe montante, choisie par le porteur parmi dix pistes). [Décisions, causes et limites](lecon-onglets-20261012.md).

**Exécuté** : IPA d’essai compilée ; 497 tests Swift réussis dont 7 nouveaux ; captures iPhone clair/sombre des nouveaux écrans relues. **Reste à qualifier** : clavier et transitions sur appareil, VoiceOver, grand texte, iPad, icône dans la barre d’onglets réelle. Pas de note sur 10 (l’école évalue en trois niveaux) ni d’exigences de formation (aucune donnée dans l’API).

## 12 octobre 2026 — icônes des catégories de permis

Les 16 catégories de l’OAC (A, A1, M, B, B1, BE, C, C1, CE, C1E, D, D1, DE, D1E, F, G) ont leur icône. L’atelier a produit trois directions par catégorie ; la direction « Signature » (aplats, roues = repère de la marque) est retenue partout sur notes pondérées. Composant central `DrivingLicenseIcon`, assets vectoriels `License-*`, intégration dans les filtres Leçons/Progression, le Profil, l’accueil élève, la planification, « Commencer maintenant », les réglages d’agenda et l’invitation. [Démarche, notes et limites](icones-permis-20261012.md).

**Exécuté** sur `b56bde5` : IPA d’essai 0.7.0/212 compilée ([run38233544399](https://github.com/tomyrms/Drivy/actions/runs/38233544399)) ; **490 tests Swift réussis**, dont les 4 nouveaux ([run38233574292](https://github.com/tomyrms/Drivy/actions/runs/38233574292)) ; vérifications API/web vertes ; captures iPhone clair/sombre de 7 écrans ([run38233578314](https://github.com/tomyrms/Drivy/actions/runs/38233578314), `assets/icones-permis-20261012/captures-simulateur.png`) où les icônes apparaissent dans Progression, Profil, invitation et planification. **Non vu en capture** : le menu de filtre ouvert, l’accueil « Ta formation » (la scène capturée est l’étape récapitulative), le sélecteur de « Commencer maintenant » (scène à une formation). **Reste à qualifier** : appareil réel, VoiceOver, iPad ; lisibilité des ensembles avec remorque à 16 pt.

## 12 octobre 2026 — audit du thème sombre « Soft Charcoal »

54 écrans iPhone capturés en clair et en sombre avant et après, couleurs mesurées sur les pixels, bascule clair → sombre → clair à chaud sur chaque écran (nouvelle option `visual_hot_switch`). Le thème est appliqué partout. Un défaut corrigé : les interrupteurs et les sélecteurs de date prenaient le bleu d’encre pastel sous un élément blanc ; ils prennent l’aplat `accentFill`, inchangé en clair. [Constats, méthode et limites](sombre-audit-20261012.md).

**Exécuté** : IPA d’essai compilée ; 54 captures claires identiques au pixel près, hors heure, chronomètre et animations ; contraste du thème 204/204. **Non exécuté** : tests Swift, parcours UI. **Reste à qualifier** : appareil réel, états pressés et menus ouverts, Contraste accru, iPad. **Au porteur** : bleu système des alertes (pas de couleur d’accent globale).

## 12 octobre 2026 — couleurs de l’échelle d’appréciation en clair

« Signaler » peignait ses trois appréciations avec les encres de texte (`success`/`warning`/`danger`, réglées pour 4,5:1), d’où un bordeaux, un brun et un vert bouteille en clair. Trois tokens de signal (#26A058, #D1760E, #E5484D en clair, sombre inchangé) servent désormais à tout ce qui *dessine* un état : feuille Signaler, marqueurs de carte, rail et frise du replay, fil du bilan, alerte GPS, point d’état. Le texte garde ses encres. `theme-contrast.py` couvre les nouveaux couples ; clair existant inchangé. Rendu sur appareil non qualifié. [Cause, décision et audit](couleurs-signal-20261012.md).

## 11 octobre 2026 — dossier de l’élève en blocs

À la demande du porteur, le dossier prend le fond et les blocs blancs de Profil et de l’historique des leçons ; « Informations personnelles » devient une ligne qui se déplie. [Détail](direction-artistique-20261011.md).

**Exécuté** : IPA d’essai compilée ; captures iPhone clair et sombre relues. **Non exécuté** : tests Swift, parcours UI. **Reste à voir** : onglet Progression du dossier, volet déplié, VoiceOver.

## 11 octobre 2026 — GPS fluide, tracés fidèles et recalage routier

Une seule carte pour la leçon et le replay, animée image par image : le marqueur glisse vers chaque position enregistrée, la caméra suit sans à-coups, le curseur du replay avance en continu et répond aussitôt à la chronologie. Le filtre d’affichage ne dessine plus la dérive à l’arrêt ni les sauts, sans couper le trait à chaque feu rouge. Le serveur sait recaler un trajet sur la route (Mapbox ou OSRM auto-hébergé), à la première lecture, en couche distincte des mesures. [Causes, architecture, décisions et limites](gps-fluide-recalage-20261011.md).

**Exécuté** : IPA d’essai compilée ; tests Swift (482 tests passent après fusion de master) ; 311 tests API sur PostgreSQL ; client vérifié contre l’API Mapbox réelle avec une ligne synthétique. **Non exécuté** : parcours UI. **Reste à qualifier** : tout sur iPhone — fluidité, position du marqueur sous les panneaux, seuils du filtre sur route, VoiceOver. Aucune mesure de performance n’a été faite.

**Déployé le 11 octobre 2026**, à la demande du porteur : release `de2f331` sur le homelab après sauvegarde vérifiée de `drivy_refonte`, 24 migrations aux empreintes conformes, services actifs. Recalage activé avec Mapbox (`MAP_MATCHING_PROVIDER=mapbox` et le jeton du porteur dans `api.env`, copie de l’ancien fichier conservée à côté) ; la route répond 401 sans jeton d’accès et l’API atteint `api.mapbox.com`. Aucun trajet réel n’a encore été recalé en production : à constater à la première ouverture d’un replay. **Reste au porteur** : les conditions de Mapbox demandent d’afficher ses résultats sur une carte Mapbox et interdisent de les stocker, et les positions partent chez un tiers, ce qui touche la notice ; un OSRM sur le homelab évite les deux. Pour couper : retirer les lignes `MAP_MATCHING_*` et redémarrer l’API.

## 11 octobre 2026 — direction artistique commune (Profil, Élèves, Agenda)

Audit croisé des onglets et de leurs feuilles, puis règles communes : une ligne prend le rythme de sa famille de page (liste groupée ou page de lecture), une seule action en texte, un badge pour ce qui attend une réponse, « Fermer » toujours au même endroit, vides et attentes par les composants partagés. Le Profil du moniteur prend la structure des Paramètres de l’élève, et les deux Profils posent l’en-tête sur le fond. Aujourd’hui n’est pas refait. [Audit, règles et décisions](direction-artistique-20261011.md). Branche `claude/da-harmonisation-20261011`, sur la PR #12.

**Exécuté** : IPA d’essai compilée sur chaque lot ; captures iPhone clair et sombre avant et après, relues ; contraste du thème vérifié (clair inchangé). **Non exécuté** : tests Swift et parcours UI. **Reste à qualifier** : VoiceOver, grand texte et iPad sur appareil.

## 11 octobre 2026 — Profil de l’élève restructuré

Identité et « Mes informations », permis en liste compacte (une ligne et une synthèse par permis, détail au toucher avec accès à Leçons et Progression sur ce permis), « Paramètres » dans la barre (compte, enregistrement GPS, Face ID, déconnexion). Le message « Le choix n’a pas pu être vérifié » venait d’une lecture de l’accord GPS annulée et prise pour une panne : corrigé à la source. La Progression de l’élève suit : mêmes cartes que le Profil, et une toile des compétences (niveaux publiés, sans score). [Détail et arbitrages](profil-eleve-20261011.md).

**Exécuté** : IPA d’essai compilée sur `e78b00c`. **Reste à qualifier** : rendu réel (clair, sombre, iPad, grand texte, VoiceOver), jamais vu tourner ; tests Swift non lancés à la demande du porteur.

## 11 octobre 2026 — thème sombre « Soft Charcoal »

Le thème sombre de l’app native est refait en anthracite neutre : un bloc est plus clair que la page qui le porte, le bouton principal est un cobalt plein au libellé blanc, une feuille monte d’un niveau. Le thème clair ne change pas. Détail, références et mesures : [dark-soft-charcoal-20261011.md](dark-soft-charcoal-20261011.md). Branche `claude/dark-soft-charcoal-20261011`, partie de la PR #10.

**Exécuté** : IPA compilée sur `73bd0ec` ; 455 tests métier passent ; 141 couples de contraste sombres au-dessus de leur seuil (calcul sur les valeurs déclarées) ; 28 écrans iPhone capturés en clair et en sombre avant et après. En clair, 23 écrans sont identiques au pixel près ; les 5 autres diffèrent par l’heure, un chronomètre, une animation ou la galerie enrichie.

**Reste à qualifier** : carte sombre réelle, Liquid Glass, ombres et bascule clair/sombre sur appareil ; Contraste accru, Réduire la transparence, grand texte, iPad et paysage, jamais rendus ; parcours UI non rejoués. **Au porteur** : valider à l’œil le bleu du bouton principal (`#3D70E2` au lieu de `#4D80EB`, pour le contraste du libellé) et l’aspect des interrupteurs. Le thème sombre du web n’est pas touché.

## 11 octobre 2026 — audit des parcours moniteur et élève

Une leçon ne se commence plus que le jour de son rendez-vous (l’agenda proposait de commencer celle de la semaine suivante) ; un rendez-vous manqué propose « Élève absent » et ne reste plus en tête d’Aujourd’hui ; accord GPS synchronisé entre la fiche et Profil ; filtres de l’élève alignés sur sa carte ; VoiceOver et Réduire les animations dans Progression ; lectures réseau de la fiche réduites ; l’app accepte un trajet sans identifiants d’appareil du moniteur. [Détail, points ouverts et limites](audit-parcours-20261011.md).

**Exécuté** : IPA d’essai sur chaque lot, sans avertissement ; 455 tests métier ; parcours UI iPhone et iPad (un échec de dérive corrigé, voir le détail). **Reste à qualifier** : tout sur iPhone, VoiceOver compris. **API (validé par le porteur)** : départ refusé avant le jour du rendez-vous (`LESSON_NOT_TODAY`), identifiants d’appareil du moniteur retirés des trajets lus par l’élève ; 275 tests API et 148 tests web passent. **Non déployé** : l’app de l’élève doit être installée avant l’API.

## 11 octobre 2026 — parcours de l’élève : Profil, prochaine leçon, Progression

Trois onglets pour l’élève (Leçons, Progression, Profil), prochaine leçon en tête, historique lu en entier, Progression refaite sur retours du porteur (un permis à la fois, « 4 sur 9 en autonomie », détail déplié sur place), ralentissements corrigés (dates et formateurs mis en cache). [Détail, relecture QA et points ouverts](parcours-eleve-profil-20261011.md).

**Exécuté** : IPA d’essai compilée sur chaque lot ; campagne complète sur `4e1b594` (452 tests métier, 12 parcours UI iPhone, 12 iPad). Tests métier relancés sur la dernière version (`941ea06`) : 453 passent ; les parcours UI n’y ont pas été rejoués. Fluidité confirmée par le porteur sur son iPhone.

**Reste à qualifier** : dernière version de la Progression, zoom de la carte, VoiceOver et grandes tailles de texte sur appareil. **Au porteur** : identifiants d’appareil du moniteur envoyés à l’élève (API et déploiement), objectifs visibles avant la leçon.

## 11 octobre 2026 — parcours de l’élève et agenda

Fiche de leçon chargée en parallèle (élève et moniteur), souhait et replay plus calmes ; planning qui se ferme dès la confirmation, formulaire stable pendant la vérification du créneau, semaines de l’agenda réaffichées sans squelette. [Détail et questions ouvertes](parcours-eleve-agenda-20261011.md).

**Exécuté** : compilation de l’IPA d’essai. **Non exécuté** : tests Swift, à la demande du porteur.

Accord GPS de l’élève lui-même (`SELF`) : question sous « Mon souhait » dans la fiche de sa prochaine leçon, envoyée aussitôt. Depuis la passe suivante, le choix général se modifie aussi depuis Profil. Non vu tourner.

## 11 octobre 2026 — parcours terrain fluides, deuxième passe

« Commencer la leçon » part directement sous le rideau quand rien n’est à demander ; la fin de leçon n’a plus qu’une attente et revient proprement à Aujourd’hui ; l’écran du trajet garde son dock stable. [Détail](parcours-fluides-20261011.md).

**Exécuté** : compilation de l’IPA d’essai sur chaque lot. **Non exécuté** : tests Swift, à la demande du porteur. **Reste à qualifier** : tout le parcours sur iPhone.

## 10 octobre 2026 — démarrage instantané en un seul parcours

Le geste « Démarrer une leçon » devient une seule interface : élève, récapitulatif et accord GPS dans une même feuille, puis le trajet sous le rideau ou la leçon ouverte sur place. [Causes, décisions et limites](demarrage-instantane-20261010.md).

- **Accord GPS** demandé dans le récapitulatif, au niveau de l’élève, enregistré au départ avec la leçon ; plus jamais pendant le rideau. Même chose depuis « Démarrer le trajet » d’une leçon planifiée.
- **GPS** : récepteur réveillé dès que le trajet est voulu et permis, conservé jusqu’au segment ; mesure de diagnostic tirée du réveil ; une seule relecture du départ et lectures en parallèle (environ 18 requêtes de moins).
- **Rideau** : plus de séquence fixe de 2 s ; levé à la première position (7 s au plus), hors de toute vue ; la carte montre la position de l’appareil tant qu’aucune n’est enregistrée.
- **Fiabilité** : garde contre le double appui, autorisation de capture toujours enregistrée pour être scellée, attente du premier plan avant le départ.

**Exécuté** : compilation de l’IPA d’essai (workflow « IPA d’essai · iLoader »). **Non exécuté**, à la demande du porteur : tests Swift (nouveaux tests écrits, cible de tests non compilée).

**Reste à qualifier** : parcours vu tourner sur iPhone, délai réel de première position, question d’iOS au premier usage.

## 10 octobre 2026 — audit global et corrections

Audit technique et UI/UX de toute l’application en cinq lots (API, web, trois lots iOS) suivis d’une revue croisée. [Corrections, limites et constats laissés au porteur](audit-global-20261010.md).

- **Règle commune** : 503 et 408 se réessaient et ne déconnectent jamais, 400 `INVALID_REQUEST` est un refus définitif, un reçu introuvable après une écriture confirmée reste une incertitude.
- **API** : panne d’identité en 503, valeur inacceptable en 400, pool protégé contre une connexion coupée, ouvertures modifiables pendant une leçon en cours.
- **Web** : sortie d’une session expirée, refus affichés dans leur dialogue, session gardée pendant une panne d’identité, fuseau de l’école.
- **iOS** : signalement refusé qui ne bloque plus la file, écriture confirmée jamais annoncée perdue, session conservée hors réseau, bouton d’école masqué pendant un trajet, leçons « À terminer » sous Aujourd’hui.
- **Déployé** : release `071af98` sur le homelab après sauvegarde vérifiée de la base ; aucune migration nouvelle.

**Exécuté** sur `071af98` : 436/436 tests Swift, IPA Release compilée, vérifications serveur et web réussies ; 148/148 tests web et 58/58 tests unitaires API en local.

- **Rideau de départ (retour du porteur)** : le contenu du rideau était vidé à l’instant où son fondu commençait, d’où une coupure nette ; il reste dessiné jusqu’à la fin, le symbole se retire avant le fond, et il entre en fondu. Le fond suit le thème (`canvas`) au lieu d’un noir ou d’un blanc pur. Second retour : le rideau attend la première position sur la carte, sept secondes au plus après la confirmation de l’école, et la séquence est jouée par Core Animation pour ne plus se figer quand le fil principal est occupé. Compilé ; le porteur a vu la première version sur son iPhone, pas la seconde.

**Reste à qualifier** : aucun écran iOS de cette passe n’a été vu tourner ; aucun parcours réel rejoué sur l’école hébergée ; aucun appareil physique.

## 10 octobre 2026 — demandes bloquées, recherche d’élève et API à jour

Incident du porteur : impossible de commencer une leçon (« Demande à vérifier », puis message de droits) ni d’en lancer une sans rendez-vous. Cause unique : l’app à départ explicite parlait à une API sans la route de départ ; le 404 restait en file sans issue et bloquait toute l’école sur l’appareil. [Cause, corrections et limites](deblocage-demandes-20261010.md).

- **Déployé** : API `040c8ed` puis `771a131` sur le homelab, migration 023, chaque fois après sauvegarde vérifiée de la base.
- **iOS** : refus 404 définitif, demande inconnue de l’école renvoyable ou abandonnable sur chaque écran, panneau qui nomme la demande, choix de l’élève avec recherche, droits de déplacement et d’annulation alignés sur l’école, GPS arrêté avant annulation.
- **Web** : même sortie pour une demande introuvable, relances manquantes, recherches agenda et invitations.

- **Seconde passe** : demandes GPS inconnues de l’école abandonnables, confirmation avant déconnexion pendant un trajet, recherche d’élèves sans accents, liste Élèves à chargement continu ; API `771a131` redéployée après sauvegarde. Huit constats GPS, adhésion et élève laissés au porteur.

**Exécuté** sur `771a131` : 420/420 tests Swift, IPA Release compilée, vérifications serveur et web réussies ; 138/138 tests web en local.

**Non vérifié** : aucun écran iOS de cette passe vu tourner ; aucune leçon réelle démarrée sur l’école après déploiement ; pas d’essai web avec l’identité réelle.

## 9 octobre 2026 — stabilité des parcours, démarrage réel des leçons et nettoyage

À la demande du porteur, revue de l’existant sans ajout de fonctionnalités ni refonte visuelle. Décisions et périmètre : [stabilite-parcours-20261009.md](stabilite-parcours-20261009.md), [serveur](stabilite-api-20261009.md), [iOS](stabilite-ios-parcours-20261009.md), [web](stabilite-web-20261009.md).

- **Leçons** : départ explicite durable (`actualStart`) depuis agenda ou manuellement ; « En attente » après dépassement sans départ, « Continuer »/« À terminer » seulement après départ confirmé. Fin fondée sur les heures réelles de la leçon, indépendante du trajet facultatif. Aucune annulation ni réalisation automatiques. Migration 023 reprend uniquement les départs prouvés par une commande ou capture.
- **Données et droits** : réponses anciennes ignorées, conflit de profil conservé jusqu’au rechargement explicite, dossier accessible après nouvelle lecture autorisée ; les détails web suivent immédiatement le filtre et le périmètre affichés. Les formulaires refusés gardent leur saisie et la déconnexion attend une confirmation réelle.
- **Navigation et nettoyage** : refus de démarrage manuel conservé sur son écran ; parcours sans GPS vers la fiche ; retraits d’états et de branches sans lecteurs vérifiés. Les écrans de recette visuelle sont conservés. README remis en accord avec l’application actuelle.

**Exécuté après fusion.** Sur `f8f5c63` : **248 tests API/PostgreSQL et 125 tests web réussis**, typage, builds et contrôles documentaires ([run37940876067](https://github.com/tomyrms/Drivy/actions/runs/37940876067)). Agenda web, changement de semaine lent et refus du formulaire de permis vérifiés avant fusion dans le navigateur à 1280 × 900 et 390 × 844 ; captures synthétiques dans la revue web. Après fusion, compilation, tests et fichiers d’icônes vérifiés ; navigateur indisponible pour une nouvelle capture.

**Vu après fusion.** 24 captures sur `6443d02`, iPhone 17 Pro et iPad Pro 13 pouces M5, clair/sombre, portrait, taille usuelle : attente et démarrage réel distingués, agenda/dossier/fiche/historique lisibles dans les viewports examinés. Le départ manuel secondaire est clarifié en « Leçon sans rendez-vous » puis vérifié dans deux captures iPhone supplémentaires sur `45691db`. [Preuve des 26 images et limites](proofs/stabilite-native-visual-20261009.json).

**Tests natifs.** **413/413 tests Swift et 3/3 tests de présentation réussis** sur `bc0bfa7`, sans échec ni test ignoré ([run37939864868](https://github.com/tomyrms/Drivy/actions/runs/37939864868)). Les quatre régressions de transfert GPS passent après remise en conformité des réponses de test ; [preuves et périmètres](proofs/stabilite-verifications-20261009.json). La campagne `6026104` avait réussi **12 parcours UI et 3 tests de présentation sur chaque appareil**, iPhone 17 Pro et iPad Air 11 pouces M4 ; les échecs de fixture et leurs corrections sont détaillés dans la revue.

**Finition du bilan vérifiée.** Huit captures des parcours UI ont révélé la saisie iPhone paysage masquée par la barre fixe puis un défilement inadapté. `ccef297` et `f8f5c63` libèrent l’espace et ramènent le champ actif dans la zone visible. La [recette renforcée sur `f8f5c63`](https://github.com/tomyrms/Drivy/actions/runs/37940876364) réussit **1/1 test sur iPhone et 1/1 sur iPad**, sans échec ni test ignoré. Ses cinq captures ont été ouvertes : saisie visible, texte conservé après rotation, retour de l’enregistrement après fermeture du clavier. [Preuve d’interaction, avant/après et limites](proofs/stabilite-native-interactions-20261009.json). Les autres parcours UI n’ont pas été répétés après ce correctif de disposition ; les textes longs et les autres champs en cours de frappe restent à qualifier.

**IPA préparée.** Version 0.7.0 **build 128**, source `f8f5c63`, [compilation Release réussie](https://github.com/tomyrms/Drivy/actions/runs/37940876258). Paquet non signé téléchargé ; les trois empreintes SHA-256 de l’artefact sont vérifiées. IPA : `16f2412e12767ef807094298acb5e983fcf0b1f974eabd8aa92374c45b5cb9b1`.

**Non déployé.** Les corrections restent sur la branche de travail. Mise à jour API/migration avant distribution de l’app ; sauvegarde obligatoire avant migration lors du déploiement.

**Fusion demandée par le porteur.** La branche `claude/marque-la-trace-20261006`, au commit `b710303c40b8f4462e8a4b39817544ecb53bde65`, est réunie à cette passe : marque et icônes web/iOS, carte Aujourd’hui compacte, cartes et écrans de protection conservés. Les conflits d’Aujourd’hui conservent le démarrage durable et la stabilité des feuilles ; les deux historiques documentaires sont conservés. Les tests finaux portent sur la version fusionnée. Le déploiement web séparé préparé par le porteur garde l’API hors de sa bascule ; son résultat n’est pas vérifié ici.

**Non qualifié.** Aucun essai physique GPS, batterie ou VoiceOver. Le navigateur utilise uniquement des données synthétiques ; la CI native utilise des simulateurs et transports synthétiques. La revue ne vaut pas qualification exhaustive de tous les écrans, tailles de texte, volumes ou usages sur appareil.
## 9 octobre 2026 — branding web en ligne

**Déployé à 14:36 Europe/Zurich** sur `https://drivy.shulker.ch/app`, source `b710303` : logo, cobalt, favicon et manifeste. Release web isolée, seul `drivy-refonte-web` redémarré. API et lien partagé restent sur `ef0ea216` ; ancienne release conservée, sauvegarde privée vérifiée avant bascule. Aucun fichier de la passe stabilité `codex/stabilite-parcours-20261009` livré.

**Vérifié** : build Linux sous Node verrouillé, onze fichiers publics avec empreintes exactes, routes d’entrée et protections anonymes, rendu du logo dans le navigateur sans erreur. [Détails, preuve et retour arrière](web-brand-deployment-20261009.md). Le prochain déploiement global doit traiter le drop-in `90-brand-web-release.conf` pour mettre le web à jour ; une simple bascule du lien partagé n’y suffit plus.

## 9 octobre 2026 — carte Aujourd’hui et logo de protection

À la demande du porteur : résumé Aujourd’hui réduit à horaire, élève, lieu et état inhabituel ; prochaines leçons repliées initialement sur iPad aussi. Le masque d’arrière-plan et l’écran verrouillé montrent le logo Drivy. Face ID et les règles métier restent identiques. [Décisions et suivi](today-privacy-20261009.md).

**Vérifié sur `86ef790`** : relecture indépendante, diff propre, deux contrôles du harnais ; 238 tests API/PostgreSQL et 104 tests web ; compilation Release/simulateur. Six tests d’interface ciblés réussissent ; 20 captures en taille usuelle inspectées sur iPhone 17 Pro et iPad Air 11 pouces M4, clair/sombre, portrait et iPad paysage. Résumé lisible, état À terminer et suivante préservés, logo centré sur les deux écrans de protection. [Preuve et limites](proofs/today-privacy-20261009.json).

**Livré** : IPA 0.7.0 **build 121**, non signée pour iLoader, téléchargée et SHA-256 vérifié. La suite native métier complète n’est pas répétée pour cette passe graphique. Face ID et les transitions d’arrière-plan sur appareil physique restent à qualifier.

## 9 octobre 2026 — intégration de La trace

Le chantier de marque reprend à la demande du porteur. [Décisions et périmètre](brand-integration-20261009.md).

- **Implémenté** : primitives ligne/repère, parcours des compétences, fils de l’agenda, de la progression et des observations ; cartes atténuées, bornes et lacunes mesurées ; symbole de connexion animé, icônes d’application, marque/cobalt/favicons web.
- **Vérifié** : 238 tests API/PostgreSQL et 104 tests web, types/builds et intégrité documentaire réussis sur `bb75ae5` ([CI](https://github.com/tomyrms/Drivy/actions/runs/37858824079)) ; 52 couples de contraste web conformes aux seuils mesurés. Tests natifs et parcours iPhone/iPad réussis sur `aecdac1` ([campagne](https://github.com/tomyrms/Drivy/actions/runs/37857755974)). Les deux corrections graphiques ultérieures de `bb75ae5` ont été compilées et capturées, sans nouvelle campagne complète.
- **Vu** : 56 captures des écrans natifs sur iPhone 17 Pro et iPad Pro 13 pouces M5, clair/sombre, 28 en grands caractères sur `aecdac1` et 28 à taille normale sur `bb75ae5`. Toutes ouvertes pour inspection, [preuve et limites](proofs/brand-native-visual-20261009.json), [six aperçus](assets/brand-integration-20261009). Quatre vues web inspectées. Contenu hors viewport, interactions et détails du replay synthétique non qualifiés : voir le [suivi](brand-integration-20261009.md#limites-des-captures).
- **Livré** : IPA 0.7.0 **build 120**, source `bb75ae5`, [compilation Release réussie](https://github.com/tomyrms/Drivy/actions/runs/37858824190), téléchargée et SHA-256 vérifié ; paquet non signé pour iLoader.
- **Différé** : vignettes de trajet dans les listes (aucune géométrie dans leur contrat), déploiement homelab, validation physique et recherche de marque. Aucune donnée ni règle d’accès modifiée.

## 6 octobre 2026 — passe de marque « La trace » (proposition, non codée)

Trois territoires explorés, « La trace » retenu : [compte rendu](brand-pass-20261006.md), [Drivy Brand System](brand-system.md), [fichiers](assets/brand-20261006).

- **Exécuté** : audit du code et des captures ; rendus et audits SVG du logo, de l'icône et des pictogrammes ; contrastes calculés ; onze maquettes avant/après capturées sous Windows (police de repli, carte schématique).
- **Reste à qualifier** : validation du porteur ; toute l'implémentation Swift et web ; rendu MapKit atténué ; icône sur appareil (Liquid Glass, mode teinté) ; Dynamic Type et VoiceOver sur le rail et le parcours ; mouvement ; impression ; recherche d'antériorité de la marque.

## 5 et 6 octobre 2026 — dossier par permis, fiche et récapitulatif de leçon, bilan en étapes, Leçons du moniteur

À la demande du porteur. Décisions : [passe-ui-20261005-soir.md](passe-ui-20261005-soir.md), conception : [conception-dossier-lecon-20261006.md](conception-dossier-lecon-20261006.md), reprise : [reprise-passe-ui-20261005-soir.md](reprise-passe-ui-20261005-soir.md).

- **Données fictives** : plus aucune mention « exemple » dans les noms, fermetures, conditions générales et adresses de l’école du homelab (`infra/deploy/provision-realistic-labels.sql`, sauvegarde vérifiée, répétition sur copie). E-mails et téléphones laissés non attribués. Photos de profil non faites : la base les interdit et aucun dépôt de documents n’existe.
- **États de leçon** : un mot de texte dans la ligne, plus de pastille ; lignes de compte et de profil sans symbole de tête.
- **Dossier** : sous l’identité, « Leçons | Progression » en place, un seul filtre par permis. Ligne de leçon avec « Bilan · Trajet » en mots. Progression : dernière leçon évaluée, décompte en mots, à travailler, en autonomie, pas encore vues.
- **Leçon** : récapitulatif en lecture par défaut à toute largeur (bilan, compétences, trajet avec bouton lecture sur la carte, observations, objectifs prévus), deux colonnes sur iPad large. La rédaction du bilan ne s’ouvre qu’après « Terminer la leçon » ou sur demande : étapes Trajet → Compétences → Bilan sur iPhone, un envoi final, brouillon local chiffré. Le constat de fin de leçon ne publie plus les objectifs comme bilan.
- **Profil** : « Leçons » remplace « Trajets » ; historique récent d’abord, par mois, recherche par élève, même fiche que partout ailleurs.
- **API** : paramètre `order` sur la liste des leçons (extension hors contrat canonique, le contrat du dossier de conception n’est pas modifié).

**Exécuté sur la CI.** Sur `0d42721` : **388 tests unitaires sur 388 et les parcours d’interface iPhone et iPad** ([run37422613310](https://github.com/tomyrms/Drivy/actions/runs/37422613310)) ; captures de dix écrans sur simulateur iPhone et iPad, en clair ([run37422615940](https://github.com/tomyrms/Drivy/actions/runs/37422615940)) : [dossier](assets/passe-ui-20261006/iPhone-dossier-multi.png), [leçon](assets/passe-ui-20261006/iPhone-lesson.png), [leçon iPad](assets/passe-ui-20261006/iPad-lesson.png), [leçon annulée](assets/passe-ui-20261006/iPhone-lesson-cancelled.png), [progression](assets/passe-ui-20261006/iPhone-progression-multi.png), [leçons du moniteur](assets/passe-ui-20261006/iPhone-lessons-history.png). Vérifications API et web réussies, dont les tests PostgreSQL du tri et du trajet masqué à l’élève. IPA compilée sur `5054914` ([run37422673391](https://github.com/tomyrms/Drivy/actions/runs/37422673391)), non téléchargée ; ce dernier commit (situation notée en Progression) n’a que la compilation.

**Déployé.** Release `ef0ea21` sur le homelab le 6 octobre, après sauvegarde vérifiée (`/root/drivy_refonte-before-ef0ea216…-20261006T055442Z-4c5d61b6eca2.dump`), 22 migrations inchangées, services actifs. Elle inclut le nom affiché recomposé (`4daae5f`), accepté par le porteur le 6 octobre : écart assumé avec R77.

**Non qualifié.** Les étapes de rédaction du bilan et l’écran deux colonnes de rédaction sur iPad n’ont jamais été capturés (les tests d’interface les traversent, sans image regardée). Aucun essai sur appareil : clavier, longs textes, rotation, reprise du brouillon après arrêt de l’app, VoiceOver, grand texte, mode sombre. Profil → Leçons n’a pas été vu avec un compte réel ni avec du volume ; sa recherche lit tout l’historique. Aucun trajet GPS dans le jeu fictif : carte et bouton lecture ne se voient que sur des leçons réellement enregistrées.

## 5 octobre 2026 — passe UX sobre : dossier, leçon, bilan, GPS, modification du dossier

À la demande du porteur. Décisions : [ux-sobre-20261005.md](ux-sobre-20261005.md). Reprise : [reprise-ux-sobre-20261005.md](reprise-ux-sobre-20261005.md).

- **Identité de l’élève** : composant partagé `DrivyLearnerIdentity` (dossier, fiche de leçon, bilan, Leçons, Progression, observations, préparation du trajet).
- **Dossier** : en-tête compact avec pastilles de contact ; coordonnées, date de naissance, adresse et « Modifier les informations » dans une zone dépliable.
- **Fiche de leçon et bilan** : une vingtaine de symboles décoratifs retirés ; une ligne « Prix de la leçon » ; « À payer » retiré (aucun paiement n’est enregistré) ; bouton « Enregistrer et partager le bilan » ou « pour moi » selon le partage.
- **Planification** : un seul tarif possible s’affiche en une ligne, le sélecteur n’apparaît qu’avec plusieurs tarifs.
- **Modification du dossier** : les six champs en accès complet, e-mail et téléphone pour le moniteur affecté, alignés sur les droits du serveur. Le formulaire ne suivait que la politique de champs de l’école.
- **GPS actif** : « Signaler » ne se grise plus pendant l’envoi ; pause, reprise et perte de signal récupérée ne reconstruisent plus le panneau ni la carte.
- **Relectures** : fiche de leçon, observations, profil, planification, démarrage et préparation du trajet ne se grisent plus et ne se décalent plus pendant une relecture silencieuse.

**Exécuté sur la CI.** IPA compilée à chaque étape. Vérifications API et web réussies sur `fa72b75`, dont le nouveau test PostgreSQL du dossier ([run37297614674](https://github.com/tomyrms/Drivy/actions/runs/37297614674)). Campagne native sur `4cb4cee` ([run37335264393](https://github.com/tomyrms/Drivy/actions/runs/37335264393)) : 322 tests unitaires sur 324 et les 12 parcours d’interface, iPhone et iPad. Les deux échecs venaient de fixtures de test écrites la veille sans être exécutées (reçu de déplacement à version inchangée, attente oubliant la création confirmée) ; elles sont corrigées et la campagne de confirmation réussit sur `e1097eb` : **324 tests unitaires sur 324 et les parcours d’interface iPhone et iPad** ([run37340252666](https://github.com/tomyrms/Drivy/actions/runs/37340252666)). IPA finale compilée sur `e1097eb` ([run37340253321](https://github.com/tomyrms/Drivy/actions/runs/37340253321)), non téléchargée. Captures de 15 écrans sur simulateur iPhone, en clair ([run37332255921](https://github.com/tomyrms/Drivy/actions/runs/37332255921)) : [dossier](assets/ux-sobre-20261005/dossier.png), [leçon](assets/ux-sobre-20261005/lecon.png), [saisie](assets/ux-sobre-20261005/saisie.png), [GPS](assets/ux-sobre-20261005/gps.png).

La cible de tests ne compilait plus depuis `9dcad86` (macros `#require` imbriquées ou sans `try` interne) : corrigé.

**Non déployé.** `apps/api/src/profiles.ts` recompose le nom affiché quand le prénom ou le nom changent. C’est un écart avec R77 (nom public distinct de l’identité administrative) : le porteur tranche avant tout déploiement. Sans lui, les six champs fonctionnent déjà ; seul le nom affiché dans les listes ne suit pas.

**Non qualifié.** Aucune transition n’a été vue : clignotement de « Signaler », pause et reprise, relectures. Ni GPS réel, ni VoiceOver, ni grandes tailles de texte, ni mode sombre, ni rendu iPad de ces écrans. Le dossier déplié, le formulaire du moniteur affecté et la liste des pays n’ont pas été capturés.

## 4 octobre 2026 — jeu de volume fictif en production

À la demande du porteur, la base du homelab contient maintenant un jeu d’essai volumineux : **86 élèves (+80), 7 moniteurs (+5 sans compte), 108 formations (+102) et 1 298 leçons (+1 236)** sur 180 jours passés et 45 jours à venir, avec 751 révisions de bilan, 1 912 observations sans position, des objectifs, 82 contrôles de permis, des disponibilités et deux fermetures. La catégorie B reprend l’offre existante ; les offres A et BE sont nouvelles. Script `infra/deploy/provision-volume-data.sql`, une transaction, refuse une seconde exécution ; il vérifie avant validation qu’aucune ligne existante n’a changé, hors champs vides du dossier de l’élève d’essai. **Sauvegarde vérifiée avant application**, répétition jouée deux fois sur une copie restaurée puis supprimée, résultat identique en production. Sous les droits par ligne : `luc` lit tout, `moniteur` 66 élèves sur 86, `eleve` ses 174 leçons, 93 bilans partagés, aucun brouillon ni repère privé. API prête après application. [Preuve](proofs/volume-seed-20261004.json), [reprise](reprise-jeu-volume-20261004.md).

**Non qualifié :** aucun écran n’a été vu avec ce volume ; rendu, pagination et temps de réponse restent à constater dans l’app et sur le web. Aucune capture GPS d’exemple : les 1 236 leçons ajoutées n’ont pas de trajet.

## 4 octobre 2026 — dossier par pages et corrections tarif/Signaler

Le tarif et le solde sont affichés directement dans la fiche de leçon, sans seconde fenêtre. Signaler gagne 40 pt et conserve trois colonnes sur petit iPhone. Le dossier ouvre une carte d’informations de l’élève, puis des pages séparées Leçons et Progression avec retour natif ; coordonnées et champs personnels suivent les droits serveur existants. Samaritains/sensibilisation restent non implémentés, sans statut inventé. Le rapprochement générique des commandes ne peut plus acquitter une annulation de signalement avec un reçu de création. Sources relues et contrôles généraux réussis. **IPA 0.7.0/build103 compilée et téléchargée**, source `9603eb3` ([run37219639586](https://github.com/tomyrms/Drivy/actions/runs/37219639586)), archive et empreintes vérifiées. Tests Apple et rendu physique non exécutés à cette étape. [Décision et limites](dossier-pages-tarif-signaler-20261004.md).

## 4 octobre 2026 — retours de signalement, disponibilité et accès directs

**IPA 0.7.0/build102 compilée et téléchargée, empreintes vérifiées**, source `9dcad86` ([run37217708082](https://github.com/tomyrms/Drivy/actions/runs/37217708082)) : bandeau Signaler avec annulation durable, modes carte libre/centré/orienté, profil et tarif visibles, alertes compactes. La planification vérifie le créneau avant le tarif et retire la case d’acceptation locale. **Serveur déployé après sauvegarde vérifiée** : release `52c355f`, migration022, services actifs et contrôles HTTPS conformes. **234 tests API dont dix nouveaux sur PostgreSQL, 104 web, types et builds réussis** (run37217180774). Tests Apple ajoutés/adaptés non exécutés ; rendu, gestes, GPS et VoiceOver sur appareil restent à qualifier. [Décisions et vérifications](live-feedback-planning-20261004.md).

## 4 octobre 2026 — prochaines leçons, palette Signaler et confirmation de fin

Le porteur valide les feuilles stables de build100. La liste secondaire d’Aujourd’hui conserve les prochaines leçons PLANNED uniquement (créneau en cours inclus), sans terminées/annulées/absences ni doublon du focus. Signaler devient une palette sur la carte iPhone, avec ses catégories et appréciations réunies ; iPad et grand texte gardent une présentation native. La fin de leçon demande confirmation avant toute mutation et conserve une attente neutre jusqu’au bilan, sans formulaire planifié fugitif. **IPA 0.7.0/build101 compilée avec succès** sur `ffd860c`, [run37215218985](https://github.com/tomyrms/Drivy/actions/runs/37215218985), téléchargée et empreintes vérifiées. Tests ciblés adaptés mais non exécutés ; aucune longue campagne native. Rendu et transitions sur appareil restent à qualifier. [Décision et limites](today-signal-finish-20261004.md).

## 4 octobre 2026 — correction des hauteurs et gestes de feuille

Le retour du porteur sur build99 signale une mauvaise hauteur initiale et des saccades à l’agrandissement. Le composant de mesure automatique est supprimé : dix présentations utilisent désormais des hauteurs natives stables, sans pilotage de la sélection ni recalcul sur le contenu ; popover Signaler iPad fixé à 480 × 560 pt. Contenus compacts et gestes gérés par SwiftUI. **IPA 0.7.0/build100 compilée avec succès** sur `9c1b12a`, [run37213508972](https://github.com/tomyrms/Drivy/actions/runs/37213508972), téléchargée et empreintes vérifiées. Fluidité, clavier et accessibilité sur appareil restent à qualifier. Aucune longue campagne native lancée. [Décision et limites](stable-sheets-20261004.md).

## 4 octobre 2026 — panneaux compacts et orientation du téléphone

Livraison initiale build99, dont le dimensionnement est remplacé ci-dessus après retour du porteur. Feuilles ajustées au contenu pour Démarrer, préparation/accord GPS, Signaler, préférences, période et choix d’école. Signaler passe en rangées compactes puis se réduit aux trois appréciations. La carte active reçoit le cap réel du téléphone, sans changer les positions enregistrées ni le replay. Relectures de code terminées ; **IPA 0.7.0/build99 compilée avec succès** sur `a2dc49c`, [run37212556376](https://github.com/tomyrms/Drivy/actions/runs/37212556376), téléchargée et SHA-256 vérifié. À la demande du porteur, aucune nouvelle longue campagne native/captures. Rendu réel, clavier, iPad, VoiceOver et boussole sur appareil restent à qualifier. [Décision](compact-sheets-20261004.md), [cap de la carte](live-device-heading-20261004.md).

## 4 octobre 2026 — revue native, icônes et IPA livrée

Huit lots intégrés : Aujourd’hui, squelettes, navigation de leçon, sélection GPS partagée, agenda/planification, dossiers/progression, bilan/observations et compte/invitations. Cinq propositions d’application et cinq pictogrammes par catégorie conservés, puis sélection et finition ; Signaler simplifié. À la demande du porteur, skill logo-design installé, trois pistes vectorielles comparées et d continu intégré à l’icône et à l’accueil.

**Livré : IPA 0.7.0/build98**, source `e36b0d4`, [compilation Apple réussie](https://github.com/tomyrms/Drivy/actions/runs/37210789141), téléchargement et SHA-256 vérifiés. [PR5 ouverte](https://github.com/tomyrms/Drivy/pull/5), retirée du brouillon à sa demande. Le porteur souhaite l’IPA sans attendre toutes les campagnes : tests natifs restants et captures complémentaires arrêtés, aucun succès supposé pour ces vérifications.

**Exécuté** : 224 tests API PostgreSQL et 104 web sur la CI générale ; première campagne Apple : 241 Swift et 12 UI iPhone réussis, UI iPad 11/12 (sélecteur corrigé). 48 captures finales normales et AX inspectées individuellement ; aucun nouveau P0–P2 établi, avec limites de champ documentées. Tests ajoutés après la première campagne non déclarés qualifiés. Deux captures AX complémentaires confirment la fixture Aujourd’hui corrigée et la connexion ; quatorze autres vues non qualifiées. GitGuardian signale trois détections non vérifiées, détails absents du résultat accessible. Aucun résultat physique GPS, batterie ou VoiceOver ; aucun déploiement homelab. [Revue et preuves](native-ui-review-20261004.md), [icônes](native-icon-signal-review-20261004.md), [logo](drivy-logo-skill-20261004.md), [passation](reprise-revue-ui-20261004.md).

## 30 septembre 2026 — diagnostic de la campagne de captures iOS

Correctif local de l’archive jointe : noms de captures validés avant lancement, diagnostics explicites avant les assertions, attente du compte sur son identifiant existant et export des pièces jointes même après échec. Le code 65 reste propagé ; les contrôles de rotation et de complétude restent obligatoires. **Le journal d’échec et l’archive sont des versions différentes** : l’ancien écran `student-file` n’existe pas dans cette campagne. Aucune équivalence avec un autre écran ni résolution de l’ancien parcours n’est revendiquée.

**Exécuté** : syntaxe Bash, analyse syntaxique Swift Linux et 11 contrôles du script avec commandes Apple simulées. **Non exécuté** : compilation Apple et XCUITest iPhone/iPad. Aucun push ni déploiement. [Diagnostic et reprise](visual-ci-diagnostics-20260930.md).

## 30 septembre 2026 — passe UI/UX native iPhone et iPad

Le porteur autorise maintenant la revue et l’amélioration des écrans natifs. Trois agents traitent agenda/démarrage, dossiers/compte et séance/carte avec les UI Skills et SwiftUI. Les changements de composition conservent l’identité native, les droits et la persistance. Compilation, tests et nouvelles captures Apple en cours de préparation. [Périmètre et suivi](native-ui-pass-20260930.md).

## 30 septembre 2026 — deuxième passe des layouts web

Les 18 destinations web ont reçu une seconde revue de composition, avec trois agents et une revue indépendante des changements. Les en-têtes sont rapprochés, les fils d’Ariane limités aux véritables sous-pages, les listes/détails adaptés à la largeur du conteneur. Annuaires entièrement cliquables, horaires/absences côte à côte, réglages en sections alignées et entrée simplifiée. Palette et typographie conservées. [Décisions et vérification](web-layout-pass2-20260930.md).

- **104 tests web**, typecheck et build réussis. Revue visuelle à 1200/390 px, contrôles des 18 destinations à 320 px avec textes longs, détails/formulaires et clavier à 834 px sombre. Après correction, aucun débordement mesuré sur les 58 relevés retenus. [Preuve](proofs/web-layout-pass2-20260930.json).
- **Déployé sur le homelab : `e30e4ea`**, après nouvelle sauvegarde vérifiée. API/web/identité actifs, migrations 001–021 conformes, JavaScript/CSS/police publics identiques au build testé. CI réussie : **224 tests API et 104 tests web**. [Preuve de déploiement](proofs/deployment-web-layout-pass2-20260930.json). Zoom 200 %, lecteurs d’écran et appareils physiques restent à qualifier.

## 30 septembre 2026 — finition esthétique et ergonomique de chaque écran web

Le porteur juge l’organisation plus claire mais l’apparence encore trop élémentaire. Passe réalisée, **web uniquement** : palette encre/papier, typographie Source Sans 3 auto-hébergée, contrôles et tableaux retravaillés, hiérarchie des identités, heures et prix, états ordinaires allégés. Deux agents ont partagé composants communs et parcours métier ; l’intégration couvre catalogue, réglages, entrée et revue navigateur. Les cinq espaces de navigation sont conservés. [Décisions et guides](web-craft-20260930.md).

- **104 tests web et 224 tests API** réussis sur la CI `36733112389` du commit `946476a`, typechecks et builds réussis. 18 destinations desktop/mobile inspectées, contrôle de repli à 320 px, tablette sombre 834 px, liste/détail 1360 px ; 44 captures, filtres et clavier contrôlés. 52 couples de contraste passent les seuils mesurés. [Preuve](proofs/web-craft-20260930.json).
- **Déployé sur le homelab : `946476a`**, après nouvelle sauvegarde vérifiée de `drivy_refonte`. API/web/identité actifs, migrations 001–021 conformes, JavaScript/CSS/police servis en HTTPS identiques au build local. [Preuve de déploiement](proofs/deployment-web-craft-20260930.json). Zoom 200 %, lecteur d’écran, Safari et appareils physiques restent à qualifier.

## 30 septembre 2026 — organisation des parcours web

Le retour complémentaire sur la difficulté à se repérer a conduit à une nouvelle répartition des informations : **cinq espaces**, accueil Planning, formations reliées à leurs compétences/procédures/tarifs, invitations séparées et détails mobiles avec retour. Les liens conservent leurs identifiants et filtres ; les brouillons de catalogue non soumis survivent aux renvois dans la même session. Le dossier place le suivi avant les formulaires administratifs. [Décision](web-architecture-20260930.md).

- Typecheck/build et **100 tests web** réussis ; parcours vérifiés dans le shell réel avec données synthétiques, aux largeurs320/390/834/1440, clair et sombre. [Preuve](proofs/web-architecture-20260930.json). Déployé sur le homelab : `b5c6c38`, après nouvelle sauvegarde vérifiée. API/web/identité actifs, migrations001–021 conformes, assets HTTPS identiques au build local. [Preuve](proofs/deployment-web-architecture-20260930.json).
- IPA native **0.7.0/build87** téléchargée et vérifiée ; source produit identique à `fe9fe6b`, seule la fixture de captures a changé sur `cd5a394`. [Preuve](proofs/native-ipa-retours-20260930.json).
- Tests Apple : après correction des six échecs de fixtures/macros, reprise `36727211560` sur `e4eea1c` réussie : **218/218 iPhone** (208 Swift Testing, 3 présentation, 7 UI), **10/10 iPad** (3 présentation, 7 UI). IPA **0.7.0/build129** vérifiée ; binaires identiques à la build87. [Preuve complète](proofs/native-retours-20260930.json).
- 24 captures ciblées Apple inspectées, avec limites explicites (observations vides, notification système sur une capture, cartes synthétiques). [Revue](native-visual-retours-20260930.md).

## 30 septembre 2026 — retours complémentaires, validation en cours

Source native et web `fe9fe6b` : **refonte visuelle générale web uniquement**. Le thème et l’identité iOS/iPadOS restent conservés ; les modifications natives portent sur les demandes ciblées. [Liste détaillée](plan-retours-20260930.md).

- **Web** : navigation par usages, palette papier/forêt, sections plates et listes compactes. Rendu navigateur vérifié à 320/390/834/1440 px, clair/sombre, menu mobile et retour de focus. Typecheck/build et 93 tests réussis ; contrastes mesurés. Zoom texte 200 %, lecteurs d’écran et appareils physiques restent à qualifier. [Direction web](web-direction-20260930.md).
- **Carte/replay** : caméra orientée et suivi initial, exploration/recentrage, géométrie retenue, signalements après persistance chiffrée avec ancre durable, compteur retiré, annulation sans bilan depuis la carte. Le recalage automatique sur route n’est pas activé ; précision réelle et batterie restent à mesurer. [Décision carte/GPS](carte-replay-gps-20260930.md).
- **Planification** : lieu facultatif, moniteur courant éligible, préférences personnelles de catégorie/tarif dans Profil, secondaires repliés. Migration021 et routes `/planning-defaults` déployées sur le homelab. [Détail](planning-defaults-20260930.md).
- **Dossier/bilan** : mois/année, pagination complète, propagation après reçu durable, relecture au premier plan, évaluations réversibles dans la leçon et observations compactes partagées. [Détail](dossier-progression-20260930.md).
- **Revue croisée** : reprise d’historique pendant une page lente, confirmation d’une autre leçon, annulation suivie d’une panne de relecture, changement d’école dans les préférences corrigés et couverts par des tests ajoutés.
- **Serveur/web qualifiés localement** : API **224/224**, web **93/93**, typechecks et builds réussis sur PostgreSQL17.11 et Mailpit Docker isolés ; 21 migrations et 45 tables avec RLS forcée. Trois attentes de test obsolètes adaptées au lieu facultatif et à la nouvelle table, sans retirer les contrôles. Conteneurs temporaires supprimés. [Preuve](proofs/backend-retours-20260930.json).
- **Homelab déployé** : `fe9fe6b`, sauvegarde privée vérifiée avant migration, empreintes001–021 concordantes, API/web/identité actifs, chemins des processus et routes HTTPS contrôlés. [Preuve](proofs/deployment-retours-20260930.json).
- **Qualification Apple exécutée** : les échecs de macros/fixtures des premiers runs ont été corrigés dans les tests ; reprise finale `36727211560` réussie, 218 tests iPhone et 10 tests iPad, IPA129 vérifiée. Les 24 captures ciblées et leurs limites sont conservées dans la preuve native. Les essais physiques restent distincts.

## 30 septembre 2026 — reprise de la passe de bugs

- **Passe Claude reprise et validée sur `8547d95`** : la fixture du test de filtre des trajets répondait avec des trajets au contrôle d'identité ; correction du test et ajout d'un cas de révocation pendant pagination. Run Apple `36716875435` réussi : **198/198 iPhone 17 Pro et 10/10 iPad Air 11 M4**, zéro échec/ignoré, iOS simulateur 26.4.1. [Preuve native](proofs/native-resume-20260930.json).
- **Correction complémentaire** : une panne de relecture des formations ne retire plus le dossier déjà affiché et ses feuilles ; une erreur avec Réessayer reste visible.
- **Agenda** : les erreurs au retour sur l'onglet sont affichées ; la feuille de leçon reste portée par la racine stable.
- **Backend déjà déployé et revérifié** : release `5406f65`, code API/web identique à `39704b6`, 20 migrations comparées par nom/SHA-256, trois services actifs, chemins des processus et santé/HTTPS contrôlés. La migration020 est donc exécutée, contrairement au dernier paragraphe historique ci-dessous. Aucun redéploiement identique nécessaire.
- **Tests serveur exécutés** : run `36716860267` sur `8547d95`, API 218/218 sur PostgreSQL 17.11 et Mailpit, web 93/93, typechecks/builds réussis. Même résultat sur le PC, avec PostgreSQL Docker isolée et 20 migrations. [Preuve backend](proofs/backend-resume-20260930.json).
- **Docker rétabli** : sockets temporaires inaccessibles conservés dans des dossiers de sauvegarde ; moteur opérationnel, volumes et conteneurs antérieurs présents. Les deux conteneurs de recette ont été arrêtés et retirés. [Intervention](docker-recovery-20260930.md).
- **IPA disponible** : 0.7.0/build 83, source `8547d95`, run `36716860249`. Téléchargement, CRC ZIP, hashes des binaires, absence de signature et configuration du homelab vérifiés. [Preuve IPA](proofs/native-ipa-resume-20260930.json).
- **Nouveaux retours en cours** : carte/replay/GPS, préférences de planification, dossier/compétences/synchronisation et refonte visuelle **web uniquement**. [Liste complète](plan-retours-20260930.md). Les résultats de `8547d95` ne qualifient pas les modifications ultérieures de ce chantier.
- **Reste sur appareil** : gestes iPhone/iPad, GPS, batterie et VoiceOver. [Détail de la reprise](reprise-bugs-20260930.md), [vérification homelab](proofs/deployment-resume-20260930.json).

## 29 septembre 2026 — retour sur appareil et revue UI Skills

Le retour du porteur après installation a ouvert une nouvelle passe ; les résultats de la passe précédente ci-dessous ne qualifient pas ces corrections.

- **Signalement restauré** : Signaler → type de situation → statut explicite → écriture durable et fermeture. Même geste avec ou sans GPS ; type visible dans le replay. Accord GPS direct, documents sur demande, arrêt/transfert automatiques à la fin de leçon, bilan facultatif et fermeture après confirmation. [Revue de chaque écran natif](ui-review-native-20260929.md).
- **Serveur exécuté et déployé** : 215/215 tests sur PostgreSQL 16.14 isolée ; API/web du homelab à `f054bc6`, sauvegarde privée contrôlée avant migration019, 19 migrations comparées par nom et SHA256, trois services actifs et routes publiques contrôlées. [Tests](proofs/api-field-flow-20260929.json), [déploiement](proofs/deployment-field-20260929.json).
- **iPad autorisé pour essai** : profil limité au modèle réel `iPad13,17`, conservé au déploiement. [Preuve](proofs/ipad-trial-20260929.json). Aucune qualification GPS/batterie physique n’est revendiquée.
- **UI Skills installé** : dix guides permanents, appliqués à l’inventaire natif et aux composants communs. Les rapports distinguent lecture du code, mesures de contraste, rendus et gestes exécutés.
- **Validation Apple exécutée** : source `e720c45`, run `36584364280`, **171/171 tests iPhone et 8/8 iPad**, zéro échec/ignoré. Dix images d’étapes terrain inspectées. La revue visuelle comprend aussi 90 originaux iPad Pro 13 en clair dans les deux orientations, quatre en sombre et huit iPhone ; les preuves conservent les limites de chaque lot. La campagne complémentaire sur Air 11 et rotation de saisie est distincte. Première position, autonomie, biométrie et VoiceOver physiques restent à constater sur les appareils du porteur.
- **iPad portrait et paysage** : dispositions fondées sur la largeur disponible, colonnes pour agenda/journée/listes et détails, largeur bornée des formulaires, signalement ancré au-dessus du trajet. [Revue des compositions](ui-review-ipad-lessons-20260929.md). Les nouvelles captures tournent le simulateur réellement et vérifient les dimensions des originaux.

- **IPA d’essai disponible** : version 0.7.0 build 73, source `be76813`, archive non signée et configuration du homelab contrôlées ; bundle français et orientations iPad vérifiés. [Preuve](proofs/native-ipa-final-20260929.json). Signature et installation par le porteur avec iLoader.

## 29 septembre 2026 — reprise et intégration des parcours

L’inventaire ci-dessous décrit le code intégré, avec les [corrections API du 29 septembre](corrections-api-2026-09-29.md) et les [décisions du porteur](decisions-2026-09-28.md). L’app couvre le terrain ; la console web couvre l’administration. La présence d’un parcours et sa compilation ne constituent pas une qualification sur appareil.

| Parcours / problème | Correction présente | Preuve et qualification |
|---|---|---|
| **Comptes et entrée élève :** invitation e-mail bloquée sans SMTP, formation unique. | Connexion OIDC existante ; « J’ai un code » ; invitation multi-permis avec moniteur, copie/partage et renouvellement. Acceptation atomique et reprise de la même opération. | Tests API codes, double acceptation et droits ; tests Swift réussis (campagne ci-dessous). [Invitations natives](native-invitations-design.md), [entrée dans l’école](native-join-school.md), [contrat codes](api-trajets-codes.md). |
| **Élèves, formations et équipe :** cycle de vie incomplet, lectures en attente prises pour des données absentes. | Retrait d’accès, fin d’affectation, pause/reprise/clôture/réouverture, archivage/restauration ADMIN ; filtre équipe et dossiers archivés ; permis et moniteurs attendent leur lecture. Offre déjà active/en pause exclue du nouveau formulaire. | Tests PostgreSQL des droits, versions, rejeux et affectations futures annulées ; tests web des commandes et règles de formulaire. [Contrats et refus](corrections-api-2026-09-29.md). |
| **Agenda et leçons :** entrées dispersées, création immédiate difficile, réglages et tarifs incohérents. | Aujourd’hui, Agenda et dossier ouvrent la même leçon : préparation, trajet, observations, bilan et fin. Démarrage immédiat, déplacement/annulation, contrôle du permis et dernière prestation applicable raccordés. | Tests API de planification, permis, issues et bilans ; tests Swift de la leçon réussis sur simulateur Apple. [Planification](g2-lessons.md), [permis](g2-permis.md), [corrections](corrections-api-2026-09-29.md). |
| **Trajets et replay :** historique peu accessible et administration sans vue d’école. | Onglet Trajets iOS et page web ; moniteur limité à ses trajets accessibles, ADMIN à son école. Replay, erreurs et transferts en attente restent visibles ; départ toujours avec un élève. | Tests PostgreSQL d’isolement des écoles et des observations privées ; tests Swift trajets réussis sur simulateur Apple. [Trajets et droits](api-trajets-codes.md), [capture native](native-capture-live.md). |
| **Observations et compétences :** signalement pendant le trajet trop lent, repères vulnérables à l’interruption. | Tuiles directes horodatées au geste, intention chiffrée avant envoi, même opération au renvoi ; précision ultérieure depuis le référentiel réel. Progression par compétence avec accès à la leçon source. | Tests API observations/bilans et tests Swift de persistance réussis sur simulateur Apple. [Observations natives](native-school-observations.md), [dossier et progression](native-training.md). |
| **Espace élève et console :** accès au suivi et séparation des rôles à consolider. | Élève : Leçons/Progression, trajet, observations partagées, bilan et objectifs ; notes gardées privées exclues. Console : école, politique de profil, catalogue/tarifs, équipe, invitations, élèves, agenda, trajets et disponibilités. | Tests API partage et confidentialité ; TypeScript et 93 tests web réussis. [Partage élève](partage-eleve.md), [console](../../apps/web/README.md). |

**Vérifications exécutées :** PostgreSQL **16.14 réel sur le homelab**, dans une instance de recette distincte : **208 tests réussis**, puis **98 tests ciblés réussis** après les dernières corrections ([preuve](proofs/review-api-20260929.json)). La [CI serveur/web 36570914236](https://github.com/tomyrms/Drivy/actions/runs/36570914236) passe également sur PostgreSQL 17 : **208 tests API et 93 tests web**, typage, builds et intégrité du canon. Le [run Apple 36569928729](https://github.com/tomyrms/Drivy/actions/runs/36569928729), source native `1014cce`, réussit : **145/145 tests iPhone** (métier et UI) et **4/4 iPad** (présentation et lancement), sans échec ni test ignoré, sur simulateurs iOS 26.4.1. Les rapports exportés ont été relus ; le build final ajoute seulement les deux finitions visuelles et les fixtures de contrôle. Les captures ont conduit à centrer le formulaire de leçon sur iPad et à remplacer « À venir » par « Prévues » pour ne pas mal classer les leçons en retard. La [revue visuelle finale 36572113947](https://github.com/tomyrms/Drivy/actions/runs/36572113947) a produit **28/28 captures exploitables et relues**, sur iPhone/iPad en clair et sombre : trajets, replay synthétique, progression, accueil, dossier et leçons. Aucune anomalie visuelle bloquante relevée sur ces captures. [Preuve native détaillée](proofs/native-review-20260929.json).

**Homelab déployé :** API et web `7b2d8aa`, migrations **001 à 018**, trois services actifs, chemins des processus et contrôles HTTPS vérifiés. Sauvegarde privée de `drivy_refonte` avant migration et de `drivy_identity` avant activation de l’inscription ; catalogues `pg_restore --list` relus. Inscription OIDC et libellés français actifs, sans SMTP ni vérification par e-mail ; aucun compte créé pour cette vérification. [Preuve de déploiement](proofs/deployment-review-20260929.json).

**IPA exportée :** **0.7.0 / build 63**, source `41f6c791177c76cddb077eb7d6fd6aa68018578b`, [run 36572072736](https://github.com/tomyrms/Drivy/actions/runs/36572072736). Archive Xcode créée, IPA appareil arm64 non signée ; téléchargement, CRC ZIP, hashes des binaires et configuration API/OIDC de production vérifiés. SHA-256 : `4d633e74ff1ce291b96405f70800d43267db21f3872994db69eb4ed2db3a6b8f`. Le code API/web de cette source est identique à la release déployée `7b2d8aa`. Fichier local : `artifacts/review-20260929/ipa-final/Drivy.ipa`. Signature et installation par le porteur avec iLoader ; aucune installation de ce build revendiquée.

**Limites :** pas encore de documents, cours collectifs/packs, saisie des règlements ni notifications in-app/push ; les charges du compte de leçon ne constituent pas un module de paiements. Aucun SMTP ajouté : le code permet l’invitation élève, mais la récupération de mot de passe par e-mail reste indisponible. Les sauvegardes ne sont pas automatisées. **Les brouillons web ne sont pas persistés** : les saisies restent en mémoire ; seules les métadonnées de commande permettent de rechercher un reçu après rechargement, sans restaurer le contenu. Après reconnexion, une saisie peut donc devoir être refaite. Installation iPhone/iPad, GPS réel, autonomie et VoiceOver restent à qualifier ; aucun résultat physique n’est déduit du simulateur.

## Historique (états datés)

Les états suivants sont conservés avec leurs dates et leurs preuves. Leurs mentions « courant », « déployé » ou « reste » décrivent leur jalon historique ; l’état du 29 septembre ci-dessus prévaut.

**28 septembre 2026 · phase 2 en cours** ([décisions du porteur](decisions-2026-09-28.md), [carte cible](carte-cible.md)). Branche `claude/refonte-parcours`, issue de `claude/tender-volta-bxdjd9`.

- **Homelab :** CT114 agrandi à chaud de 16 à 32 Go (45 % utilisés). Release API et web `1b03ae1` déployée le 28 septembre 2026 (migrations 010 à 013), chaque installation précédée d’une sauvegarde `/root/drivy-refonte-before-<SHA>.dump` sur CT113 ; services actifs, `/app/gestion` sert la console avec Élèves et Disponibilités. Aucune tâche de sauvegarde automatique n’existe sur le Proxmox.
- **Correctif du 28 septembre (retour du porteur) :** planifier une leçon bouclait sur « la procédure de la formation a changé ». Cause : l’iPhone envoie les UUID en majuscules et plusieurs contrôles serveur les comparaient comme du texte aux valeurs minuscules de PostgreSQL. L’API normalise désormais les UUID reçus (paramètres, requête, corps) ; test PostgreSQL ajouté. « Démarrer le trajet » enchaîne en un geste accord de l’élève (demandé une fois), localisation, mesure, diagnostic (valable 5 minutes) et départ ; seul un blocage s’affiche.
- **Données d’essai (production) :** `luc` devient ADMIN et INSTRUCTOR ; offre Permis B complétée (9 compétences, 95 CHF les 50 min, conditions, disponibilités) ; 21 leçons fictives, 12 bilans publiés, 32 observations. Sauvegarde préalable `/root/drivy-refonte-before-example-seed-20260928.dump` (CT113). Aucun trajet GPS d’exemple.
- **1. Connexion unique : appliquée.** Thème `drivy`, e-mail accepté, `offline_access`, sessions hors ligne 30/180 jours, verrou Face ID. Première connexion sur appareil à qualifier. [Détail](connexion-unique.md).
- **2. Partage automatique et « Ma leçon » : déployés.** Migration 012 et extensions `/sharing`, `/captures` en production ; l’écran de leçon unique montre trajet, erreurs, bilan et objectifs, avec « Visible par l’élève » (trajet, bilan) et « Gardée pour moi » (observation). [Détail](partage-eleve.md).
- **3. Trajet toujours avec un élève : fait.** Laboratoire G0 et trajets d’exemple retirés ; Aujourd’hui lance le trajet depuis la leçon. Profil GPS d’essai de l’iPhone du porteur actif (`NOT_QUALIFIED`).
- **4. Administration sur le web : déployée.** Console : élèves (ouvrir une formation, affecter un moniteur) et disponibilités/absences des moniteurs, en plus du reste. Une invitation d’élève peut porter sa formation et son moniteur (migration 013, test PostgreSQL réel). Les écrans d’administration de l’iPhone sont supprimés.
- **5. Onglets par rôle : compilés.** Moniteur Aujourd’hui/Agenda/Élèves ; élève Leçons/Progression ; compte derrière l’avatar avec « Gérer l’école » (web) pour l’administration. Passe « moins de texte » sur ces écrans et le planning. IPA [run 36457219287](https://github.com/tomyrms/Drivy/actions/runs/36457219287) ; tests natifs sur runner Apple en cours ; aucun écran vu sur appareil.
- **Bloquant : e-mail.** Sans relais SMTP en production, créer une invitation répond `INVITATION_DELIVERY_UNAVAILABLE` : « Inviter un élève » et « mot de passe oublié » ne fonctionnent pas encore.
- **CI :** tests serveur et web à chaque push (y compris `claude/**`).
- **Travail Codex conservé :** `codex/g1d-profils` et `codex/g1d-web-wip` (non relu, non testé).
- **Reste :** relais e-mail, essais sur appareil (connexion, trajet, écrans élève), passe « moins de texte » sur profil, accueil guidé et web, sauvegardes automatiques du homelab, purge de l’ancienne base locale G0 sur les appareils.

Mise à jour : 25 septembre 2026 (passe de design) ; 24 septembre 2026, après recentrage demandé par le porteur. **L’application complète reste en construction.** Priorité aux parcours utilisables et à l’apparence des maquettes ; campagnes exhaustives reportées à la fin. Les builds restent automatiques, la suite native et les tests serveur sont déclenchables manuellement. Une capture des vraies vues SwiftUI avec fixtures sert à corriger l’affichage, sans déclarer une recette métier complète.

**Web de gestion (25 septembre 2026, non déployé) :** console d'administration `/app/gestion` (vue d'ensemble, configuration et activation, champs du profil, catalogue : offres, référentiels, procédures, prestations et conditions commerciales, équipe et accès, invitations) derrière un BFF à liste blanche stricte méthode+chemin, CSRF, Idempotency-Key = operationId, If-Match fort, ETag relayé, no-store ; demandes incertaines vérifiables par AP72 et renvoyables à l'identique. Typecheck, 44 tests web et build réussis localement ; aucune recette contre l'API/Keycloak réels, aucun test navigateur en CI. Non couverts : disponibilités, dossiers/formations/affectations, profil administratif élève. L'iPhone conserve ses écrans d'administration jusqu'à qualification du web. Accueil guidé iOS et refonte trajet/replay intégrés (IPA run `36138415242` pour l'accueil). Audit fonctionnel : [plan restant](plan-fonctionnel-restant.md).

**Passe de design du 25 septembre 2026 :** système de design partagé iOS/web (tokens 3.8 complets, composants communs, Liquid Glass limité aux commandes sur la carte, signalement à grandes tuiles, haptique de succès après écriture durable) appliqué à tous les écrans principaux, sans changement métier. Voir [le système de design](design-system.md). IPA compilé avec succès jusqu’à `c07b4c6` (run `36131760336`) ; le lot final est vérifié par le run déclenché au push. Captures, VoiceOver, grand texte, sombre et appareil restent à qualifier.

**État courant :** API001–009 déployée depuis `069ea8fa369317543668ca7541e6c10269099aba`, sauvegarde vérifiée avant migration, trois services actifs. Profils, catalogue, formations, affectations, planification, préparation, constat, compte de leçon, publication du bilan et observations privées pendant la leçon sont implémentés côté serveur. Les limites effectives sont détaillées dans [la planification](g2-lessons.md) et [les bilans](g2-reports.md). L’école « Luc auto école » avait été activée par son administrateur ; ses coordonnées et textes ont été conservés. Six dossiers et six formations fictifs, identifiés « exemple », ainsi que deux comptes réels `moniteur` et `eleve` ont été ajoutés à sa demande. Connexion OIDC client Apple via navigateur : moniteur voit six dossiers/formations ; élève un seul. Les formations d’exemple initiales utilisent encore une offre désactivée sans configuration métier complète ; elles ne constituent pas des leçons planifiables déjà approuvées. Aucun mot de passe de `luc` n’a été utilisé, changé ou réinitialisé.

**API — tranches du 25 septembre 2026 (branche de travail, non déployées, migrations 010–011 non appliquées au service public) :** sondes internes `/health/live` et `/health/ready` ([exploitation-sante.md](exploitation-sante.md)) ; contrôle du permis AP29/AP30 avec `permitWarning` calculé et anomalie de constat exigée seulement sans permis valide ([g2-permis.md](g2-permis.md)) ; absence AP44, approbation AP88, correction AP50 entre issues closes (retours vers PLANNED/COMPLETED refusés explicitement) et retrait AP57 ([g2-issues-lecon.md](g2-issues-lecon.md)) ; filet de tests du planning, des prestations et du bilan ([tests-planning-bilan.md](tests-planning-bilan.md)). **Exécuté** sur PostgreSQL 16 local (`drivy_test`) : `tsc --noEmit` et `npm run build` réussis ; suite API **131 tests, 128 réussis, 3 échecs préexistants** (2 cas F02 sans Mailpit, 1 cas G1B « RLS interdit mutation… » qui échouait déjà avant ces tranches). Les 3 nouveaux fichiers (14 tests) et les deux fichiers capture mis à jour réussissent ; les réponses nouvelles sont validées contre l’OpenAPI 3.11.0 canonique. **Reste à qualifier** : PostgreSQL 17, CI d’intégration sur push, déploiement et règle Caddy `/refonte/health*`, écrans web/iOS du permis et des issues, transitions AP50 vers PLANNED/COMPLETED, frais d’absence/annulation.

**IPA courant compilé et téléchargé : 0.7.0/build28**, source `cfde4d8d12d3f7a727db768180cf642666b343e3`, [run36063213867 réussi](https://github.com/tomyrms/Drivy/actions/runs/36063213867), SHA-256 conforme au manifeste : `8f8f87eb68d5afddf201a744eb525cccfb5446fa5802eecd74bf9abc32389f0a`. Il inclut les correctifs de navigation du build25, profils/agenda/équipe/invitations/planning affinés, signalement personnel, préparation GPS scolaire et choix de l’élève, diagnostic, départ explicite AP154 et carte scolaire liée au propriétaire conservé à la racine. Fermer une feuille ou changer d’onglet ne réinitialise pas cette séance. La collecte reste conditionnée à un profil physique qualifié ; aucun profil n’a été inventé. Les reprises après relance et la passe visuelle demandée sur séance/replay sont en intégration après ce snapshot.

**IPA 0.7.0/build 20 livré**, source `05febc56afd118d8a747590597d1d0094c7f76bc`, [run `36052457170` réussi](https://github.com/tomyrms/Drivy/actions/runs/36052457170) : accueil Séance, trajet et replay avec carte dominante, catalogue, planification et bilans natifs, Équipe et accès. Deux trajets fictifs sont installés une seule fois dans le stockage local chiffré : Cernier → Neuchâtel et retour via Peseux, cinq observations et un bilan chacun. Leur origine d’exemple est visible ; aucune acquisition GPS n’est revendiquée. Ils sont supprimables sans réapparition au lancement suivant. SHA-256 de l’IPA téléchargé, conforme au manifeste : `57f1c4afcf2c46ce95b9ba93ae45165c9348ee6ce95245299720c5706c3127d4`.

Dix captures iPhone clair/sombre des vues natives de `072e724` ont été inspectées ; aucune qualification iPad supplémentaire n’est revendiquée. **IPA 0.7.0/build21 compilé et téléchargé**, source `394d4cd1d4736c33e1c4792a98e715dad51fea66`, run`36054482531`, SHA-256 `d76b2c64c0e96953167d6cd96f5bc1e514c79732e9c232aa2d67a75e3a29796c` : nouvelle hiérarchie des formulaires planning/bilan, catalogue/configuration et [dossier de formation](native-training.md) avec leçons, bilans publiés et progression. Les finitions suivantes restent en intégration. [L’accès Équipe](native-members.md) utilise une réauthentification OIDC ; la présence de `auth_time` dans un véritable jeton d’accès a été vérifiée sur l’hébergement avec le compte moniteur fictif, sans utiliser `luc`.

**Correctif de navigation compilé et livré dans le build25 :** les feuilles Équipe, catalogue, profil, configuration, invitations et rejoindre une école reçoivent désormais leur modèle dans l’item de présentation ; formation et éditeur du catalogue transportent également tous leurs paramètres dans cet item. Fermer Équipe sans changement de ses propres droits ne recharge plus le compte. Fermer les réglages sans changement ne recharge plus l’école. L’onglet actif appartient à la racine et survit à une relecture des accès ; seul un changement volontaire de destination ou la déconnexion le remplace. Les rafraîchissements du dossier conservent les sélections. IPA 0.7.0/build25, source `0676b8318a56cfaf981d6a84c35f3fa532532423`, [run36058166375 réussi](https://github.com/tomyrms/Drivy/actions/runs/36058166375), SHA-256 du téléchargement vérifié : `b580c875b748a937de7e59ea3770183c9746ebe11502957c41abb9c6617e59b8`. La première ouverture et le maintien de l’onglet restent à confirmer sur appareil ; la compilation ne remplace pas cette observation.

**API001–009 déployée** : le serveur expose les autorisations de capture, lots chiffrés, arrêt, finalisation, relecture privée et AP161–164. Les observations temporelles existent sans GPS et sont rattachées au brouillon lors du constat, sans publication implicite ; une ancre exige un lot confirmé. Le [transport natif](native-capture-transport.md), le coffre SQLCipher, le collecteur Core Location et la composition scolaire sont compilés dans le build28. Les clés dédiées sont actives sur CT114 ; aucun profil physique n’est déclaré qualifié. L’extension iOS AP190 conserve la capacité disque sur l’appareil (`freeBytes:null`). Le web hébergé reste G1C.

Les [finitions du profil et de la politique de champs](native-profile-design.md), intégrées dans `dbc5037`, sont compilées dans les builds26 et28 : libellés persistants, action principale fixe, validation des champs, relecture de la version réellement publiée et conservation des erreurs de commande.

Le journal web durable reste compilable mais non qualifié/non déployé ; le web hébergé conserve G1C. Aucun mode produit « Drivy Démo » séparé : les données d’exemple empruntent les vrais accès. La capture scolaire partagée, les documents, les packs/cours et l’envoi SMTP externe restent des chantiers nécessaires à l’application complète ; un trajet privé local n’est pas encore lié à une leçon scolaire.

Les paragraphes et tableaux suivants conservent les jalons antérieurs et leurs preuves ; ils ne remplacent pas l’état courant ci-dessus.

**G1C testé et déployé, G1D1 en développement :** invitations API/iOS, outbox d’email chiffrée et acceptation web React/BFF sont implémentées. L’API passe **89 tests** sur PostgreSQL 16.14 et 17.11 (57 précédents + 32 F02), avec SMTP Mailpit réel. Le web passe **19 tests**, **10 contrôles** de connexion locale et la [recette complète de 18 contrôles](recette-entree-web.md) SMTP → vérification d’adresse → identité nouvelle → acceptation explicite → un dossier minimal, sans formation. Le [run serveur/web `36033466605`](https://github.com/tomyrms/Drivy/actions/runs/36033466605) réussit. **API et web sont déployés depuis `6ffc103`**, avec **11 contrôles HTTPS publics réussis** et nettoyage de la sonde. Le transport email externe reste à raccorder. **IPA 0.4.0/build 9 compilé et vérifié** ; les tests natifs `36033239715` réussissent : **97/97 iPhone et 4/4 iPad**, zéro échec/ignoré, après correction de deux erreurs de compilation SwiftUI. [PR2 fusionnée](https://github.com/tomyrms/Drivy/pull/2), [déploiement et preuves](preparation-deploiement-web.md), [couverture complète](couverture-produit.md), [tranche F02](g1c-invitations.md), [web/BFF](../../apps/web/README.md). Les profils administratifs G1D1 sont travaillés dans un worktree séparé.

| Élément | État | Preuve / suite |
|---|---|---|
| Conception V3.17, 556 fichiers | Intégrité vérifiée | Manifeste SHA-256 conservé, contrat OpenAPI 3.11.0 immuable |
| Données et dépôt | Historique neuf, sans migration de données | `tomyrms/Drivy` public ; `tomyrms/Drivy-old` privé |
| Laboratoire G0 | Compilé et testé sur simulateurs | Séance locale, GPS facultatif, observations, historique, bilan local et SQLCipher |
| Accès scolaire G1A | Client et API implémentés | AppAuth/PKCE, écoles et rôles, élèves et formations en lecture |
| Configuration G1B | Client compilé, serveur déployé | Coordonnées, textes adoptés explicitement, préparation et activation ADMIN ; commandes chiffrées avant émission |
| Serveur G1A/G1B/G1C | 89 tests réussis | PostgreSQL 16.14 et 17.11 réels ; typecheck/build et CI réussis |
| Entrée par invitation G1C | API/web déployés ; SMTP externe manquant | 19 tests web, 18 contrôles locaux complets, 11 contrôles HTTPS de connexion |
| Tests Apple G0/G1A/G1B/G1C | iPhone 97/97, iPad 4/4 | Run `36033239715` entièrement réussi ; zéro échec ou test ignoré |
| IPA connecté | 0.4.0/build 9 disponible ; tests natifs réussis | Run `36033239737`, source `7836441`, CRC/hashes/configuration compilée vérifiés |
| Hébergement HTTPS | API, web/BFF, identité et filtrage actifs | Release `6ffc103`, CT114, PostgreSQL UTF8 CT113, Caddy CT109 |
| Première école | DRAFT, ADMIN actif | Compte `luc`, « Luc auto école » ; aucune adoption ou activation faite automatiquement |
| Essais physiques | Installation du premier IPA confirmée ; recette restante | Connexion 0.3.0, VoiceOver, interruptions réseau, GPS et budgets à qualifier |
| G1 complet / G2 connecté | À poursuivre | SMTP externe, profils/onboarding, formations administrées, planning, leçons et bilans partagés |
| G3/G4 et pilote G5 | À réaliser | Cours/packs, web de gestion, exploitation et procédures |

### G1D1 en développement isolé

La [PR3 en brouillon](https://github.com/tomyrms/Drivy/pull/3), branche `codex/g1d-profils`, contient API et formulaires natifs de politique de champs, profil scolaire et onboarding. Migration004 et AP16/AP169–177 passent **113 tests** sur PostgreSQL17.11 et16.14 ; typecheck/build réussis. Une revue indépendante a corrigé la portée AP169 non-ADMIN et l’encodage d’adresse native sans complément. Les **27 nouveaux tests Swift et une présentation capturée** sont en cours sur [GitHub Apple](https://github.com/tomyrms/Drivy/actions/runs/36037236148), version0.5.0 ; ne pas les déclarer réussis avant le rapport.

Le web G1D1 a passé34 tests et une revue visuelle synthétique, puis son journal de commandes durable a été mis en chantier : PostgreSQL séparé, chiffrement authentifié, droits et confirmation relus après reconnexion. Le harness intégré OIDC/BFF/API réel et le stockage sont en cours. Les installateurs de cette base distincte et du keyring privé sont préparés, **pas appliqués**. Aucun G1D1 n’est déployé ; l’IPA proposé et l’hébergement restent G1C.

### Preuves serveur

Sous Node 24, `npm run typecheck`, `npm test` et `npm run build` réussissent. Les **89 tests** comprennent 13 tests JWT/configuration/curseurs, 21 tests d’intégration G1A, 23 tests d’intégration G1B et 32 tests F02 ; aucun n’est ignoré. La suite passe sur PostgreSQL 17.11 et 16.14, version hébergée. Le [run `36033466605`](https://github.com/tomyrms/Drivy/actions/runs/36033466605) confirme tests serveur/web, builds et intégrité documentaire.

G1A couvre les six lectures du contrat, les dates et curseurs, affectations moniteur, accès à soi, multi-rôles, révocation avec JWT valide et séparation scolaire sous `drivy_app`. Six réponses PostgreSQL réelles servent de fixtures aux tests Swift.

G1B couvre coordonnées, progression, readiness, adoption versionnée des textes, activation et preuve AP72. Les tests vérifient atomicité effet/preuve/audit, idempotence concurrente, versions obsolètes, refus d'activation prématurée, révocation pendant l'attente, rollback sur échec d'audit et séparation des écoles. L'extension `data-policy` possède son propre schéma machine, sans modifier le canon. La migration 002 a également été éprouvée après 001 et deux écoles existantes sous un propriétaire NOSUPERUSER/NOBYPASSRLS/NOCREATEDB/NOCREATEROLE. Voir [G1B](g1b-school-setup.md) et [le guide API](../../apps/api/README.md).

### Hébergement et identité

La release API/web **`6ffc1036890ccc3d8232f5f8b90be4d77f6db195`** tourne sous Node 24.21.0 dans `/opt/drivy-refonte` sur CT114. Une sauvegarde privée vérifiée de la seule base `drivy_refonte` a précédé la migration 003. Les processus API et web utilisent les dossiers de cette release ; identité et filtrage sont actifs. Le Caddyfile complet a été validé avant le rechargement du snippet refonte. L’ancienne API sur 3000 et les anciennes bases sont conservées.

Les bases `drivy_refonte` et `drivy_identity` sont neuves, UTF8, avec rôles distincts non superutilisateurs. La vraie connexion runtime vérifie les privilèges, le certificat TLS/hostname PostgreSQL, `SET LOCAL ROLE drivy_app` et l'absence de personne visible sans contexte. Les quinze tables métier ont ENABLE/FORCE RLS. Les adaptations LXC et les bases de bootstrap SQL_ASCII conservées sont expliquées dans [le déploiement](deploiement-refonte.md).

L'API répond sous `https://drivy.shulker.ch/refonte`, Keycloak 26.7.4 sous `https://drivy.shulker.ch/identity/realms/drivy`. Discovery et JWKS répondent 200 ; les lectures protégées sans jeton répondent 401/no-store. Les chemins admin, master, health et metrics publics répondent 404 ; les ports 3001/3002/8081 refusent les connexions LAN hors proxy. Les accès sensibles sont exclus des journaux Caddy.

Le [contrôle OIDC HTTPS](controle-oidc-deploye.md) a réussi avec une sonde indépendante : PKCE S256 obligatoire, code/jetons/signatures/nonce vérifiés, identité sans lien métier refusée (403), ID token refusé comme accès API (401), renouvellement puis rejeu refusé (400). Sonde, sessions et credentials ont été supprimés, puis l'absence du compte vérifiée. La [preuve datée](proofs/oidc-https-2026-09-24.json) ne contient aucun secret. Le banc OIDC local compte également 29 contrôles réussis et le provisionnement 8 tests réussis.

Le compte initial `luc` et « Luc auto école » proviennent du provisionnement contrôlé, sans élève ni formation. `luc@example.com` est le contact d'essai autorisé par le porteur ; aucun email n'a été envoyé. Un navigateur éphémère a vérifié la connexion et le formulaire obligatoire de changement de mot de passe, sans soumettre un nouveau mot de passe. Le fichier d'accès initial est privé sur le PC ; il n'est jamais inclus dans Git ou les artefacts CI.

La [preuve du déploiement G1B](proofs/g1b-deployment-2026-09-24.json) confirme une école DRAFT, un ADMIN actif, un setup initial et une politique vide non approuvée. Aucune commande, aucun élève ni formation n'a été créé par ce contrôle. Adoption et activation restent des gestes explicites de l'administrateur.

Le client OIDC public `drivy-apple` a reçu le scope `email` le 24 septembre pour préparer F02 : scopes `basic/email/profile`, callback exact et PKCE S256 relus et inchangés. Une requête d’autorisation HTTPS avec `openid profile email` retourne le formulaire 200 sans soumettre d’identifiants. Le portail web a ensuite été déployé avec son propre client confidentiel. Sa recette HTTPS compte 11 contrôles réussis, sans utiliser `luc` ; la sonde a été supprimée et son absence relue. Ce contrôle ne qualifie pas la connexion Apple physique ou le SMTP externe.

### IPA et preuves Apple

Le [run IPA G1C `36033239737`](https://github.com/tomyrms/Drivy/actions/runs/36033239737) produit **0.4.0/build 9**, source `7836441a2e1a2f62071f28fdcadb8239a2780efb`, SHA-256 `bad253440bd97bca2a2a5fa4051832d1a5c13e2ef38dc7523adfc751e6faf1e1`. CRC ZIP, manifeste, hashes des deux binaires et configuration HTTPS ont été vérifiés après téléchargement ; aucun bundle signé. Le [run natif `36033239715`](https://github.com/tomyrms/Drivy/actions/runs/36033239715) réussit : **97/97 tests sur iPhone 17 Pro et 4/4 sur iPad Pro 13 pouces (M5), simulateurs iOS 26.4.1**, zéro échec/ignoré. Les 27 nouveaux tests Swift et le nouveau test de présentation G1C passent. Les huit captures F02 iPhone/iPad (clair, sombre, grand texte, demande incertaine) sont relues sans défaut visuel bloquant ; [preuve native](proofs/g1c-native-2026-09-24.json). Le champ descriptif `scope` de son manifest mentionne encore G1B ; la source et les versions ci-dessus identifient le contenu G1C. Les précédentes preuves G1B sont conservées ci-dessous pour la traçabilité. Les essais physiques restent distincts.

Le [run IPA `36024174745`](https://github.com/tomyrms/Drivy/actions/runs/36024174745) produit **Drivy 0.3.0/build 5**, minimum iOS/iPadOS 26.0, bundle `ch.drivy.qualification`, source `c3e5e6733282a77be779f1c99661f0831c74c5d8`. Xcode 26.6 (17F113), SDK iPhoneOS 26.5. Les deux binaires sont arm64 appareil et les quatre bundles non signés. SHA-256 : `8d7ecee21aaa72e29e3f6c9b3fb1ca7e9ba8bc4f6ee1601c4314790cb8e0405f`. Après téléchargement, CRC ZIP, hashes du manifeste et des binaires, ainsi que les trois paramètres HTTPS dans Info.plist ont été vérifiés ; `schoolConnectionConfigured=true`.

Le workflow d'essai produit cet IPA indépendamment des tests. Le [run natif G1B `36024174590`](https://github.com/tomyrms/Drivy/actions/runs/36024174590) est entièrement réussi : **69/69 tests iPhone** (66 Swift Testing, deux tests de présentation XCTest et un parcours G0), **3/3 tests iPad**, sans échec ni test ignoré. Les sept tests de stockage des commandes passent individuellement avec le vrai Keychain, chiffrement, barrière de fichier et synchronisation de dossier sur simulateur. Les rapports et captures ont été téléchargés et relus : configuration G1B claire lisible, état non approuvé explicite, contraste de sélection iPad rétabli et navigation G0 visible sous son bandeau. La capture G1B ne qualifie pas encore son apparence sombre sur appareil. Le précédent [run G1A `36020145724`](https://github.com/tomyrms/Drivy/actions/runs/36020145724) avait réussi 43/43 tests iPhone et 2/2 iPad, dont historique et bilan après relance. G1B corrige aussi le contraste de la ligne sélectionnée iPad et le bandeau de retour des essais qui masquait la navigation.

Les rapports G0 joignent un avertissement UIKit sur l'insertion de `UIKitToolbar` dans un `UIHostingController`. Aucun test n'échoue et la navigation reste visible sur les captures ; cet avertissement reste à surveiller dans la recette physique. Les simulateurs étant configurés en anglais, les dates et le nom localisé du fuseau suivent cette locale ; les libellés applicatifs sont français.

Les [commandes scolaires](commandes-ios.md) sont chiffrées et persistées avant chaque émission. Une demande incertaine conserve son UUID, son contenu exact et sa version à travers les relances ; une preuve AP72 peut confirmer le résultat sans renvoi. Un refus lors d'une reprise ne suffit pas à effacer la demande. Les tests de recréation et d'erreur de stockage ne constituent pas des essais physiques de perte d'alimentation.

Le porteur a confirmé l'installation et l'ouverture du premier IPA 0.1.0/build 1 (`ebdb6ca`, run `36013615026`), tout en signalant son faible contenu. Cela ne valide pas encore la connexion AppAuth ni la configuration de 0.3.0 sur appareil. La [recette scolaire](recette-g1b.md) et la [recette G0](recette-g0.md) restent à exécuter sur les appareils concernés.

### Limites de qualification et suite

Le laboratoire G0 n'est pas une capture scolaire ni un bilan partagé. Le produit complet conserve invitations, onboarding, administration des formations, agenda, leçons, bilans publiés, cours collectifs, packs et web de gestion dans son périmètre. Aucun service d'envoi d'emails utilisable n'a été établi par la documentation de l'ancien hébergement ; il reste à raccorder pour les invitations.

Les 434 scénarios métier et 68 scénarios mobiles ne changent pas de statut par simple création de code ou de workflows. G0 complet reste **NOT_QUALIFIED** : tests physiques GPS, autonomie, VoiceOver et budgets à mesurer. Aucune conformité juridique, disponibilité ou performance n'est déduite des tests automatisés.

### Progression des compétences (essai terrain du 30 septembre 2026)

Écrit, non exécuté : la migration `020_admin_progress_read.sql` (progression lisible en lecture seule par l'administration de l'école, bilans et brouillons inchangés), le rappel du niveau actuel de chaque compétence dans le bilan d'une nouvelle leçon (sans l'écrire dans ce bilan), et la relecture de la formation à chaque affichage. Les tests PostgreSQL (`lesson-reports.integration.test.ts`) et Swift (`SchoolLessonFinishTests`, `SchoolLessonHubTests`) tournent dans la CI « Refonte · vérifications ». À revérifier sur l'iPhone après déploiement (sauvegarde de la base d'abord) : enchaîner deux leçons, puis ouvrir la progression en moniteur, en élève et en administrateur.
 
## Messagerie #98 refonte UI/UX (25 octobre 2026) 
 
- PASS : IPA d'essai compilee (run 40214002610), tests metier iOS complets (run 40214008527). 
- FAIL hors perimetre : typecheck API (variable inutilisee dans course-push-revalidation, deja sur master). 
- NOT_EXECUTED : tests UI messagerie, captures avant/apres iPhone/iPad clair/sombre/grands textes, essai sur appareil.
- PASS : tests UI MessagingThreadUITests et MessagingOwnDevicesUITests iPhone/iPad (run 40215297685). 
- PASS : IPA avec acces Messages (run 40215714427).

## #100-#104 (25 octobre 2026, b6673c6)

- PASS : tests metier iOS complets (runs 40236644565, 40237951212), verifications API/PostgreSQL (40237952137), IPA avec acces Messages (40239305741).
- NOT_EXECUTED : controle UI fonctionnel MessagingFeatureCheckUITests sur le dernier SHA, recette reseau 1/5/15 s, essai iPhone, push reel.
- BLOCKED : alerte de mention (migration 20261025 non deployee) ; aucune alerte � nouveau message � cote serveur.

## Retours porteur 25 octobre soir (6bfea69)

- PASS : tests metier iOS (run 40299656866), verifications API (6bfea69), IPA avec Messages (40299653098).
- En cours : MessagingFeatureCheckUITests + MessagingThreadUITests (40301689859). Echecs connus sur c84d489 : reaction (cible non actionnable), chargement des precedents.
- NOT_EXECUTED : essai iPhone de la fermeture de palette, du glisser pour repondre et du gras des mentions.

## 27 octobre 2026 : messagerie (#98, #100 à #104, #141, #169, #170) verte en UI iPhone et iPad

- PASS : MessagingFeatureCheckUITests 17/17 sur iPhone et sur iPad (run 40467664787, 696d01d) ; MessagingKeyBackupUITests 4/4 sur iPhone et sur iPad (run 40463125585, a4acced) ; IPA d'intégration avec accès Messages (run 40463298255, 01109b1 = master + PR #180 + cette branche, code app identique à 696d01d).
- Corrigé : le test de recherche visait la pastille épinglée restée derrière la feuille (même texte) au lieu du résultat, désormais identifié `messaging.search.result`. Sur iPad, glisser vers le bas en haut du formulaire de sauvegarde fermait la feuille Messages : le formulaire ramène lui-même l'erreur de restauration à l'écran (#169), le test ne glisse plus. testLoadOlderMessages attend la page 2 avant de glisser.
- PR #180 : la recette navigateur suivait encore l'ancien relais « Planifier dans l'app Drivy » retiré par #51 ; elle suit la planification depuis l'agenda web (run 40422727867, b41d7b9). Un contrôle réussi n'est plus annoncé comme l'étape en échec. Liste Swift des captures alignée sur capture-screens.sh (48 tests Python de qualification réussis localement).
- NOT_EXECUTED : essai sur iPhone ou iPad physique de cette IPA ; campagne complète iOS sur le dernier SHA ; validation finale de la PR #180 relancée.
- BLOCKED : notification de mention et de nouveau message, migration 20261025_messaging_mention_push.sql non déployée.

## 27 octobre 2026 : master 54b6ea9 déployé (messagerie, bilans, planning web)

- PR #180 et #181 fusionnées. Release `54b6ea9` installée après sauvegarde vérifiée de `drivy_refonte` ; migrations 53 → 55 ; API, web et worker sur la release, override web retiré. [Compte rendu et retour arrière](deploiement-messagerie-20261027.md).
- Validation finale de `4014c52` (run 40545726242) : tout réussi sauf la campagne iOS, coupée à 90 min ; deux tests de saisie iPhone corrigés en `75c8851`, fin de la campagne iPad non exécutée. Limite du job portée à 150 min.
- Mentions : push générique actif côté serveur. Nouveau message : pas de push (#74, choix ouverts dans #66).
- NOT_EXECUTED : essai sur iPhone/iPad physique, réception push réelle, campagne iOS complète sur `54b6ea9`.

## 27 octobre 2026 : deux tests UI de #180 corrigés, lecture VoiceOver des champs

- `DrivyFormField` forçait une valeur d'accessibilité vide : VoiceOver n'annonçait jamais la saisie. La valeur est désormais le texte saisi, ou « À renseigner » pour un champ requis vide.
- Tests : recherche des participants touchée sur le champ visible (son cadre d'accessibilité remonte sous la barre), confirmation fermée par le bouton terminal ou la région du popover au premier plan.
- PASS : SchoolCourseJourneyUITests et SchoolFormProtectionUITests, 7/7 sur iPhone et sur iPad (run 40574916579, b40ac04).
- NOT_EXECUTED : écoute VoiceOver réelle sur appareil.

## 28 octobre 2026 : réactivité, lots A à D (#111 à #113, #115, #117, #121 à #123)

- Branche `claude/reactivite-20261028`. Signaler en file (#112), préparation saisissable pendant l'envoi (#113), reprise GPS sans attendre l'école (#111), replay rouvert depuis un cache en mémoire et progression lue avec les leçons (#115, #117), états en cours sur les lignes web et coordonnées modifiables pendant l'envoi (#121 à #123). [Détail](reactivite-lots-20261028.md).
- PASS : compilation de l'app (IPA, run 40603892937, d4da07b) ; `npm run typecheck` et 401 tests web.
- NOT_EXECUTED : tests Swift ajoutés et adaptés (la cible de tests n'est pas compilée par l'IPA) ; essai sur appareil ; réseau dégradé réel.
- Issues livrées fermées avec leurs commits : #38 à #42, #51, #79 à #82, #88, #98, #100 à #104, #141, #143, #162, #163, #169, #170 ; #75 renvoyée à #97.
- Tests Apple sur `a817d92` : PASS, 847 tests métier sur 76 suites (run 40609074704) ; `FieldFlowTests` 10 parcours sur iPhone et iPad (run 40606267774, deux échecs d'infrastructure ou de délai sur un seul appareil chacun, relancés et réussis sur les deux appareils, run 40610221505). La première campagne métier (40606256388) avait révélé un vrai défaut de #111, « Terminer » pendant l'ouverture locale d'une reprise, corrigé en `a817d92`, et deux défauts de tests.

## 28 octobre 2026 : master 7a7031d déployé (réactivité, PR #189)

- Release `7a7031d` installée sur le homelab par `.local/deploy-reactivite-20261028.py` (copie du script du 27 octobre) : sauvegarde vérifiée de `drivy_refonte` (`/root/drivy_refonte-before-7a7031d…-20261028T100056Z-…dump`), 55 migrations inchangées et empreintes vérifiées, API, web et worker sur la release, API prête (200), web public 200 avec le nouveau bundle.
- Seul le web change côté serveur (#121 à #123). Aucune migration.
- NOT_EXECUTED : essai du portail web déployé par le porteur.

## 28 octobre 2026 : #182 fil Messages présenté par Exyte Chat (PR #184)

- Fil Exyte par défaut, ancien fil et réglage d’essai retirés : bulles, heure, coches, réactions, avatars, menu d’Exyte 3.3.0 aux couleurs Drivy ; composeur, citations intégrées aux réponses, sondages, droits, E2EE et file protégée Drivy ; glisser à gauche pour répondre, appui long de 0,25 s, réaction retirée d’un appui. [Décisions et reprise](reprise-exyte-chat-182-20261027.md), PR #184.
- Qualification Apple : tests UI messagerie adaptés et réussis sur iPhone et iPad (FeatureCheck 17, Thread 8, Latency 3), 71 tests métier `messaging`, IPA avec Messages sur le commit fusionné avec `master` ([run 40668797322](https://github.com/tomyrms/Drivy/actions/runs/40668797322)).
- Reste : décision Giphy (binaire MPL 2.0 embarqué d’office par Exyte) avant diffusion publique ; VoiceOver physique, réseau et GPS en leçon non qualifiés. Aucun déploiement nécessaire (iOS seul).


## 28 octobre 2026 : suite des issues non commencées (#114, #118, #126, #128-#130, #142, #168, #177)

- Branche `claude/suite-issues-20261028`, partie des lots 5 à 8 de l'audit UX (#188). [Reprise](reprise-suite-issues-20261028.md).
- Messages : sourdine selon l'état réel (#168), refus à consulter puis masquer (#177), zones tactiles à 44 pt sans chevauchement (#142). Cours : appel, règlements et validation par élève, sans verrou global (#128-#130) ; inscription de l'élève sans écran retenu (#126). Profil : photo affichée dès le cadrage, envois en file (#118). Bilan : rédaction continue pendant l'envoi (#114).
- Non fait : planification optimiste (#108-#110), qui demande une file de commandes reprise hors de l'écran et une projection dans l'agenda.
- NOT_EXECUTED : recette physique, VoiceOver et réseau dégradé réel.
- Messages (#142, #168, #177) : fait aussi par le lot 9 (PR #191) ; la version de master est gardée, avec en plus les durées de sourdine 1 h, 8 h, 1 jour et les lignes de sondage à 44 pt.
- Qualification : essai du porteur validé (IPA `226dee20`) ; 859 tests métier et suites UI Messages, cours, formulaires et bilan réussis sur iPhone et iPad (runs 40686053375, 40686057743, 40694974479). iOS seul, aucun déploiement.


## 28 octobre 2026 : accueil web et premier rendez-vous (#247 / #258, lot partiel)

- Branche `codex/accueil-premier-rendezvous`, base `e5166404`. L’aperçu d’une école active rejoint le planning existant ; préparation dans Réglages et recherche, école archivée explicite. La prochaine action est relue avec le planning et ne disparaît plus pour une première leçon annulée ou une absence seule. [Périmètre et procédure d’essai](accueil-premier-rendezvous-20261028.md).
- PASS : compilation API, compilation web et contrôle TypeScript web, Node 24.22.1. Aucun nouveau composant externe ni migration.
- NOT_EXECUTED : essai du porteur, tests PostgreSQL et tests web ciblés adaptés, recette clavier/petit écran. À faire après retour, puis contrôles requis avant fusion. Aucun workflow complet lancé.
- Aucun changement natif, IPA, fusion ou déploiement. Le reste de #247/#258 et les autres catégories de #253 ne sont pas réalisés par ce lot.


## 28 octobre 2026 — Épic #253, implémentation de qualification

Branche `codex/simplification-253`. [État des 24 sujets et recette](simplification-253-20261028.md). Guide unique, programmes suisses, conditions communes, échéance d’annulation, choix GPS personnel, départ atomique de qualification, bilan et aide intégrés. Typage et compilation API/web : PASS sous Node 24.22.1. Générateurs de contrats exécutés. Tests PostgreSQL/Swift/navigateur/physiques : NOT_EXECUTED, préparés pour après l’essai du porteur. Compilation Apple et IPA à relever après leur exécution. Migration additive d’annulation préparée, non exécutée. Mise en service GPS obligatoire BLOCKED par #266 ; configuration vide par défaut. Qualification des sources et preuves de cours limitée comme détaillé dans [la matrice suisse](regles-suisses-20261028.md). Aucun déploiement ni fusion de cette branche.
## 28 octobre 2026 : cours collectifs, audit UX B29 à B31 et B34 (#221, #222, #223, #226)

- Branche `claude/cours-audit-b29-b34-20261028`, partie de `master` `e5166404`. iOS seul : aucun contrat, aucune migration, aucun déploiement.
- Langue du cours dans la fiche et la confirmation d'inscription, seulement si l'école l'a renseignée ; un code hors catalogue garde son nom système (#221). Haut de Leçons : les places proposées sont comptées et le prochain cours reste visible ; en très grand texte, une seule ligne les résume et ouvre la liste (#222). Refuser une place ou quitter la liste d'attente demande une confirmation qui dit la conséquence réelle des fonctions SQL : place passée à la personne suivante, rang perdu, retour en dernier (#223). « Payé sur place » devient « Enregistrer un règlement », feuille « Règlement sur place » (#226).
- PASS : compilation de l'app par l'IPA d'essai. NOT_EXECUTED : tests métier et UI (deux tests métier ajoutés, test UI du règlement adapté au nouveau titre), essai du porteur, VoiceOver physique.

## 28 octobre 2026 : replay, audit UX B42 à B44 (#234, #235, #236)

- Branche `claude/replay-audit-b42-b44-20261028`, empilée sur celle des cours (#221-#226) pour une IPA commune. iOS seul : aucun contrat, aucune migration, aucun déploiement.
- Choisir une observation (pastille, carte, liste, repère de la chronologie) met la lecture en pause sur elle : la tête de lecture ne la remplace plus ; « Lecture » reprend le suivi, précédente et suivante parcourent sans pause (#235). Un titre ou une note coupés à trois lignes affichent « Voir tout », qui met en pause et ouvre le texte entier ; fermer rend la sélection et l'instant (#234). Recherche (sans casse ni accents) et filtres par type dans la liste dès quatre observations ; le filtre s'applique au rail, à la liste, aux repères de la chronologie, aux épingles et au suivi automatique, jamais au tracé ni à ses interruptions ; rail avec « n sur N » qui efface d'un appui ; mention du chargement partiel (#236).
- PASS : compilation de l'app par l'IPA d'essai. NOT_EXECUTED : tests métier (`SchoolReplayObservationFilterTests`, 3 tests ajoutés) et UI, essai du porteur, VoiceOver physique.

## 28 octobre 2026 : Messages, audit UX B47, B50 et B51 (#239, #242, #243)

- Même branche que le replay (#234-#236). iOS seul : aucun contrat, aucune migration, aucun déploiement.
- Bulle illisible : la cause connue et la suite utile d'abord (« Pas encore lisible sur cet appareil… restaure tes clés » seulement pour `D-NOKEY` ; « non partagé avec cet appareil » pour une clé retenue ; « pour l'instant » pour le stockage local ; sinon cause non inventée), le code en petit dessous (#239). Sondage : les refus de `MessagingPollRules.validated` sont expliqués sous le champ concerné par `MessagingPollRules.problems` (mêmes règles, aucune limite ajoutée) ; un manque n'est signalé qu'après avoir quitté le champ (#242). Saisie protégée : glisser ne ferme plus une feuille remplie, Annuler demande confirmation, une mise en file échouée garde la saisie et le dit (#243).
- PASS : compilation de l'app par l'IPA d'essai. NOT_EXECUTED : tests métier (2 tests XCTest ajoutés dans `MessagingThreadTests`) et UI Messages, essai du porteur, VoiceOver physique.

## 28 octobre 2026 : audit UX B32, B33, B41, B52 et B53 (#224, #225, #233, #244, #245)

- Même branche que le replay et Messages. iOS seul : aucun contrat, aucune migration, aucun déploiement.
- Cours : une place proposée dont l'échéance passe pendant que la fiche est ouverte n'est plus présentée comme acceptable (« Délai de réponse passé ») ; une seule relecture à l'échéance et au retour dans l'app, rien n'est envoyé automatiquement (#224). Participants : le titre du cours remplace « Participants », la séance est nommée dans l'appel, règlements et validation disent porter sur tout le cours (#225).
- Replay : « Tracé ajusté à la route », « … en partie », « Tracé GPS mesuré, sans ajustement », « Ajustement à la route… » ; aide à la demande sur le tracé et les pointillés ; « Incomplet » au lieu de « Partiel », aussi dans la liste des trajets (#233).
- Recherche Messages : extrait centré sur la correspondance, occurrences en gras, mêmes règles de casse et d'accents, coupé entre caractères entiers (#245) ; « Recherche… » tant que la réponse n'est pas celle de la saisie, portée dite quand rien n'est trouvé (messages déjà ouverts sur cet appareil), historique illisible ou absent signalé (#244).
- PASS : compilation de l'app par l'IPA d'essai. NOT_EXECUTED : tests métier (2 tests ajoutés, 2 adaptés) et UI, essai du porteur, VoiceOver physique.


## 28 octobre 2026 — IPA combinée épic #253 et 15 corrections UX B

À la demande du porteur, intégration de `claude/replay-audit-b42-b44-20261028` (`db855a853f9c64b438d521e25fbe2666f50145a5`) dans la branche de travail `codex/simplification-253`. Les 15 issues #221–226, #233–236, #239, #242–245 sont incluses ; aucune n’est fermée. Conflits de replay et de ce suivi résolus en conservant les deux ensembles. La compilation indépendante de la branche UX B a réussi (run 40727684500). Le run IPA 40730352252 de #253 seul a été annulé après l’élargissement ; il ne qualifie pas cette intégration. Nouvelle compilation combinée à relever après exécution. Tests ciblés et essai physique restent NOT_EXECUTED ; aucun merge vers master ni déploiement.


## 28 octobre 2026 — preuve IPA combinée et demande de remise à zéro

IPA du commit `77306e9882216688b3250c77f72047619c42ad04` compilée et vérifiée : [preuve](preuve-ipa-253-uxb-20261028.md), run 40731165137 PASS, build 441, accès Messages de qualification inclus. Empreintes du paquet et fichiers annexes vérifiées. Tests et appareil physique NOT_EXECUTED. Le porteur a ensuite explicitement demandé le déploiement web et l’effacement des données et des comptes Drivy, confirmé dans la clarification. Préparation en cours : inventaire, sauvegardes vérifiées, conservation des services techniques et retour arrière ; aucune suppression annoncée avant exécution. Revue supplémentaire : la révision des conditions communes conserve désormais aussi leurs bornes de validité ; typage et compilation API PASS, trois régressions PostgreSQL préparées non exécutées. Aucun changement natif depuis le commit de l’IPA.


## 28 octobre 2026 — web/API déployés et données/comptes réinitialisés sur demande

Déploiement `a41cf64d153252dc133a60f29755f0685516be8f` exécuté ; [reçu, sauvegardes et retour arrière](deploiement-reset-253-20261028.md). Sauvegardes métier/identité restaurées avec succès dans deux bases temporaires puis copies temporaires supprimées. Migration additive qualifiée sur copie puis appliquée, registre 56. Réinitialisation transactionnelle des données métier et suppression ciblée des 5 comptes humains Drivy ; comptes techniques/configuration/références conservés. Contrôle final : 0 personne/école/appartenance/leçon ; 1 code d’ouverture et 2 références de cours. Services actifs, RLS/readiness et HTTPS vérifiés ; 21 fichiers publics correspondent au build. IPA combinée build 441 disponible, source native inchangée depuis 77306e98. GPS obligatoire reste désactivé/BLOCKED #266. Aucun compte créé pour le porteur, aucun test métier/UI/physique ni merge master exécuté ; attente de son essai.


## 28 octobre 2026 — qualification après essai : épic #253 et 15 corrections UX B

Le porteur a accepté l’essai puis demandé tests, corrections et clôtures. La PR #279 conserve #278 et la branche native UX B dans l’historique. Le [reçu de qualification](qualification-253-uxb-20261028.md) rassemble les preuves et la [revue de clôture](revue-cloture-253-20261028.md) les 24 sujets et 15 corrections.

- Corrections après essai : permission d’audit précise du départ préparatoire GPS (migration additive), prérequis reliés aux faits de cours autorisés, heure serveur monotone pour les offres ; recettes actualisées sans suppression des contrôles métier. La sélection manuelle du replay possède une preuve exécutée de pause et de reprise.
- PASS API/PostgreSQL : 796 tests ; web/BFF : 423 tests, aucun ignoré, sur `4a1a6885` (run40742565492). PASS navigateur : 162 contrôles sur `83aadc37` (run40743521660). Typage, compilation, contrats et intégrité documentaire réussis.
- PASS Swift sur `94348f6f` : 1 091 tests, aucun échec/ignoré (run40742298060). PASS UI initiale : 16 tests iPhone et16 iPad sur `36d75142` (run40739185025) ; PASS cours corrigés : 7 iPhone et7 iPad sur `94348f6f` (run40745176299). Simulateurs iPhone17Pro/iPadAir11(M4), iOS26.4.1. Aucun résultat physique déduit.
- IPA corrigée : version0.7.0 build442, SHA `94348f6f4b32c9e92c6e91843e40cf28aebd454a`, run40742302908, artefact12841010670. Archive téléchargée, trois empreintes concordantes, Messages de qualification inclus. Les sources natives sont identiques dans les commits ultérieurs ; API/web identiques au SHA qualifié, dernières recettes identiques à `83aadc37`.
- Exploitation : version publiée toujours `a41cf64d`. Aucun nouveau déploiement ni effacement après l’essai. Le responsable de l’épic #280 a reçu les commits à intégrer et les contraintes de déploiement ; son worktree reste indépendant. Un prochain déploiement devra inclure la migration d’audit nouvelle après sauvegarde et accord distinct du porteur.
- Limites conservées : S14/#266 est un audit terminé avec décision BLOCKED pour le GPS obligatoire réel ; configuration de qualification vide en exploitation. Lacunes S07 explicites. GPS/batterie/provenance réelle/délai de retrait distant/VoiceOver physique et qualification générale Messages non revendiqués. Le parent #192 n’entre pas dans les clôtures de cette livraison.

## 28 octobre 2026 : qualification de l'audit UX B (PR #310, 15 issues)

- Essai du porteur validé sur l'IPA `db855a85` (run 40727684500).
- PASS : tests métier `db855a85` (run 40738918926), 864 tests Swift Testing en 79 suites, 202 XCTest, scénario réel du relais exécuté. Les deux premières tentatives ont échoué sur le seul `MatrixMessagingRelayIntegrationTests`, aux étapes READINESS puis CONVERSATION (relais jetable injoignable) ; la troisième est passée sans changement de code.
- PASS : UI iPhone et iPad (run 40738923088), `SchoolCourseJourneyUITests`, `MessagingThreadUITests`, `MessagingFeatureCheckUITests/testSearchInsideConversationFindsMessage`, 16 tests par appareil.
- NOT_EXECUTED : VoiceOver physique, réseau dégradé réel. iOS seul, aucun déploiement.

## 28 octobre 2026 — EPIC #280, candidat de refonte web avant essai

Branche isolée `codex/epic-280-web`, base qualifiée #253/#278/#310 intégrée par merge complet (`c94ec2bb` dans `52fe0320`). [Réalisation W01–W31](epic-280-implementation.md), [110 sous-vues](epic-280-inventory.json), [fondation et sécurité](epic-280-foundation.md), [mesures courtes](epic-280-performance.md), [livraison/rollback](epic-280-delivery.md). Composition Untitled UI et primitives officielles shadcn/ui Base UI avec tokens Drivy ; accès hors console, navigation, dossiers, planning/cours, catalogue et réglages recomposés desktop/mobile. Contrats, historique #253, règles commerciales et protections conservés. Aucun changement natif propre à #280.

PASS : typage client/BFF et compilation web/API sous Node24 ; audits dépendances sans vulnérabilité signalée ; contrôles navigateur ciblés6/6 de reprise/isolement/commandes/clavier ; captures synthétiques sans débordement global sur les vues capturées à320/390/1440 selon manifeste, clair/sombre ; comparaison courte12/12 sans erreur JS. Les chiffres exacts et limites sont dans les reçus liés. Ce n'est pas la campagne complète #309/#84 ni une recette physique.

Homelab relu sans mutation : API/web/worker à `a41cf64d`, configuration/OIDC/RLS valides ; 56 migrations concordantes, seule policy additive `20261028b_lesson_gps_preparation_audit.sql` en attente. L'API #253 doit accompagner le web (faits de cours). Aucun reset à répéter ; données existantes à préserver. GPS obligatoire toujours désactivé/#266 BLOCKED. Vitest de développement API/web et Vite corrigés aux versions verrouillées ; aucune protection/CI désactivée.

NOT_EXECUTED : sauvegarde fraîche et bascule #280 (confirmation finale requise), essai personnel, validation du porteur, campagne complète #309/#84, navigateurs/appareils physiques et VoiceOver. W01–W30 sont implémentés avec qualification encore partielle ; W31 préparé et différé selon l'instruction du porteur. Aucune clôture d'issue ni livraison complète revendiquée. Après déploiement autorisé, attendre son retour avant toute campagne exhaustive.

## 28 octobre 2026 — #280 publié pour essai personnel

Après autorisation explicite de déployer directement, release `be8a02457ef2c8877117e9a13557b288738fc4bf` publiée sur [Drivy](https://drivy.shulker.ch/app/) à19:21UTC. [Reçu de publication et rollback](epic-280-publication.md), [preuve homelab](epic-280-publication-homelab-20261028.json). Sauvegarde fraîche privée1805023octets, catalogue/blocs vérifiés (pas de restauration d'essai) ; API/web/course-worker au même SHA, readiness/HTML/assets/401 anonyme vérifiés. Migration additive d'audit appliquée :57/57, empreintes concordantes,91tables FORCE RLS. Aucune purge, restauration de base, modification d'identité/configuration/DNS ; GPS obligatoire désactivé. Ancienne release a41cf64d conservée, rollback logiciel prêt, non exécuté.

Premier staging interrompu avant installation pour incompatibilité Python3.11/tarfile ; extraction confinée corrigée et nouvelle sauvegarde avant reprise réussie. Contrôle du vrai build sous CSP :4gestes popups réussis, probe Zod préexistant bloqué/intercepté, aucune politique assouplie. Entrée publique nouvelle relue dans le navigateur ; aucune opération métier réelle effectuée pour la sonde.

État : DEPLOYED_AWAITING_USER_TRIAL. Essai et validation personnelle NOT_EXECUTED. Campagnes complètes #309/#84 différées ; attendre le retour du porteur. L'épic et les sous-issues ne sont pas déclarés qualifiés/clos par le seul déploiement. Les reçus postérieurs au SHA produit ne modifient pas le build installé.

## 31 octobre 2026 — Pilotage #373 : dictionnaire (#374) et agrégations API/BFF (#375)

T01 (#374) : dictionnaire des indicateurs, matrice des droits, jeu synthétique et 12 décisions acceptées, dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md). T02 (#375) : routes `metrics` (définitions, cartes, séries, détails, export CSV) côté API, relais et export côté BFF, migration additive de fonctions et d'index (`20261031_pilotage_metrics.sql`, aucune table, aucune donnée). Exécuté : tests d'intégration contre une vraie PostgreSQL 17 (jeu de référence de T01, jeu de 10 000 CHF au-delà d'une page, droits, export, paramètres) et tests du BFF. Mesure ponctuelle sur 10 064 leçons réalisées : deux défauts de coût trouvés et corrigés (somme des écritures relue pour chaque leçon : 4,7 s à 86 ms ; noms recalculés pour chaque ligne d'une page : export refusé au-delà de 10 000 lignes passé de 12,2 s à 2,1 s), chiffres et réserves en section 11 du document. Reste à qualifier : aucun objectif de performance n'est déclaré atteint (une école, une machine locale, pas de charge concurrente) ; le contrat OpenAPI 3.11.0 n'est pas modifié ; aucun écran (T03 à T09) ; rien n'est déployé et la migration n'est appliquée sur aucune base de production.

## 31 octobre 2026 — Messagerie : alertes de messages et préférences (#74), signalements chiffrés et boîte des administrateurs (#77)

#74 : alertes de messages privés et du général (déclencheur SQL, relecture avant envoi, validité de 15 minutes, titre générique sans contenu), trois préférences par personne dans l'objet versionné existant, portail web et Réglages de l'app, ouverture de la bonne conversation depuis une alerte ([document](messaging-notifications-74.md)). « Refonte · vérifications » verte sur `051a2d37` ([run 41200814594](https://github.com/tomyrms/Drivy/actions/runs/41200814594)), tests métier iPhone « reactivity » verts ([run 41200806812](https://github.com/tomyrms/Drivy/actions/runs/41200806812)). Reste à qualifier : aucune alerte APNs réelle n'a été reçue sur appareil, pas de regroupement anti-rafale côté serveur.

#77 : signalement d'abus chiffré pour les administrateurs de l'école ([document](messaging-reports-77.md)). API : statut `OPEN`, `HANDLED`, `DISMISSED` avec historique, cadence (3 par heure et par conversation, 10 par jour et par école), destinataires de clés, migration additive ; « Refonte · vérifications » verte sur `071401ca` ([run 41225134866](https://github.com/tomyrms/Drivy/actions/runs/41225134866)). iOS : session Megolm par signalement partagée par to-device Olm, boîte « Signalements » réservée aux administrateurs, confirmation avant transmission ; le Swift compile (workflow d'IPA lancé seulement pour vérifier la compilation sur `bd4e3e80`, [run 41225717502](https://github.com/tomyrms/Drivy/actions/runs/41225717502) ; IPA ni téléchargée ni livrée, lancement hors consigne). Reste à qualifier : le partage de clé et le déchiffrement chez l'administrateur n'ont jamais été exercés de bout en bout, aucun parcours d'interface n'est automatisé, et la conservation des preuves attend #68. Aucun déploiement, aucune activation de la messagerie.

## 31 octobre 2026 — Tests de recette #83, #78 et #73, reprise des issues du jour

#83 : cinq fichiers de tests API de cours et un fichier de tests web ajoutés, sans changement de code produit ; « Refonte · vérifications » verte sur `c71fbd06` ([run 41201921118](https://github.com/tomyrms/Drivy/actions/runs/41201921118)). Matrice de traçabilité recomptée : 59 critères, 19 PASS, 34 PARTIAL, 6 NOT_COVERED. #78 : `MessagingLessonIndependenceTests` (MSG-17) vert dans les tests métier iPhone ([run 41201923959](https://github.com/tomyrms/Drivy/actions/runs/41201923959)) ; matrice `messaging-78-20261023.md` relevée sur ce qui a réellement tourné. #73 : le test UI du vote et de la clôture d'un sondage passe sur iPhone et iPad ([run 41224876858](https://github.com/tomyrms/Drivy/actions/runs/41224876858)) après correction de l'attente de « hittability » et du contrôle d'activation. Ce même run était rouge sur `testReactionFromLongPressClosesMenuAndUpdatesCapsule` (sélecteur corrigé sur le candidat #339, fusionné dans `master` le 31 octobre) : après fusion de `master` dans la branche, ce seul test est vert sur iPhone et iPad ([run 41242976214](https://github.com/tomyrms/Drivy/actions/runs/41242976214)). Reste à qualifier : les tests Swift et UI de cours n'ont pas été rejoués ; aucun résultat physique. Reprise détaillée : [reprise-issues-20261031.md](reprise-issues-20261031.md).

## 1er novembre 2026 — Pilotage #373 : navigation et composition (T03 #376)

Espace « Pilotage » (Tableau de bord, Statistiques → Activité et Finances), adresses à filtres, droits d'affichage, composants partagés (période, mesure, aide au calcul) et préparation de l'aperçu synthétique, dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 12. Web seulement, aucun changement d'API. Exécuté : `tsc --noEmit` sur `apps/web`, sans erreur dans les fichiers touchés (modules `lucide-react` et `class-variance-authority` absents de cette machine). Non exécuté : tests unitaires et de routes écrits mais pas lancés, rendu navigateur, essai du porteur. Reste à qualifier : composition à 390 et 1440 px en clair et en sombre, barre mobile à six entrées, choix du graphique en T05.

## 1er novembre 2026 — Pilotage #373 : accueil quotidien (T04 #377)

Le tableau de bord devient l'entrée par défaut d'une école active (les adresses avec contexte d'agenda gardent l'agenda). Blocs : Aujourd'hui, À traiter, Prochains rendez-vous (projection de l'agenda), Ce mois-ci avec écart à date et histogramme SVG sans dépendance, Finances du mois pour qui y a droit. Détail dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 13. Web seulement, aucun changement d'API. Exécuté : `tsc --noEmit` sur `apps/web`, sans erreur dans les fichiers touchés. Non exécuté : tests écrits mais pas lancés, rendu navigateur, essai du porteur. Reste à qualifier : l'entrée par défaut, la composition à 390 et 1440 px en clair et en sombre, le graphique en sombre.

## 1er novembre 2026 — Pilotage #373 : statistiques d'activité (T05 #378)

Statistiques → Activité : filtres Permis et Prestation en second niveau, mesures regroupées (leçons, heures, élèves, cours collectifs), comparaison seulement sur base équitable (période écoulée, ou mois en cours à date), trois graphiques (évolution, heures par moniteur rangées par nom, leçons par permis ou prestation) lisibles au clavier et au toucher. Détail dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 14. Web seulement, aucun changement d'API. Exécuté : `tsc --noEmit` sur `apps/web`, sans erreur dans les fichiers touchés. Non exécuté : tests écrits mais pas lancés, rendu navigateur, comparaison chiffre à chiffre avec le jeu de référence, essai du porteur. Hors lot : liens vers les détails (T07), onglet Finances (T06).

## 1er novembre 2026 — Pilotage #373 : statistiques financières (T06 #379)

Statistiques → Finances : valeur des leçons réalisées, à venir, total attendu selon le planning (titre qui dit la couverture), leçons en attente de constat hors du total, règlements enregistrés par date de saisie, cours collectifs indisponibles ; évolution de la valeur (réalisée en plein, à venir en hachuré), règlements à part, répartition par permis, prestation ou moniteur rangée par nom. Détail dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 15. Web seulement, aucun changement d'API ni calcul de montant côté web. Exécuté : `tsc --noEmit` sur `apps/web`, sans erreur dans les fichiers touchés. Non exécuté : tests écrits mais pas lancés, rendu navigateur, comparaison avec le jeu de référence, essai du porteur. Hors lot : détail et export (T07).

## 1er novembre 2026 — Pilotage #373 : détail des mesures et export CSV (T07 #380)

Une tuile mène aux lignes qui la composent (même période, portée et filtres, adresse `measure`), avec total du serveur et lignes affichées distincts, pagination complète, écart signalé et relecture, ouverture de la fiche dans l'agenda, et export CSV du serveur pour qui a le droit d'export (octets conservés, aucun fichier partiel). Détail dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 16. Web seulement, routes de #375 inchangées. Exécuté : `tsc --noEmit` sur `apps/web`, sans erreur dans les fichiers touchés. Non exécuté : tests écrits mais pas lancés, téléchargement dans un navigateur, lecture du fichier dans un tableur, révocation de droit en cours d'affichage. Hors lot : clic d'une barre vers les lignes de son intervalle.

## 1er novembre 2026 — Pilotage #373 : responsive, accessibilité et états réseau (T08 #381)

Pages de pilotage seulement : chiffres, graphiques et rendez-vous déjà lus restent affichés avec l'heure de leur calcul quand une mise à jour échoue, focus rendu à la tuile d'origine au retour du détail, cibles de 44 px sur écran tactile ou étroit, tableau des valeurs confiné, contraste forcé, comparaison à date mutualisée. Détail et limites dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 17. Exécuté : `tsc --noEmit` sur `apps/web`, sans erreur dans les fichiers touchés. **Non exécuté : aucune vérification dans un navigateur ou sur appareil (largeurs, thèmes, zoom), aucune capture, aucun test.** Reste à qualifier : tout ce qui est visuel, par le porteur puis en T09.

## 1er novembre 2026 — Pilotage #373 : qualification du candidat `27a5a4e2` (T09 #382)

Exécuté : typage web et API sans erreur ; 593 tests web ; 83 tests API du pilotage sur PostgreSQL 17 (dont un nouveau test de contrat qui fait lire les vraies réponses de l'API par les schémas du web) ; build de production et d'aperçu ; 23 contrôles d'un parcours dans Edge (détail, retour, focus, pagination, export CSV avec BOM et CRLF, F06 par partie, filtres, période invalide, clavier du graphique) ; 50 captures (5 pages, 1440 à 320 px, clair et sombre) sans débordement ni erreur JavaScript. Défaut réel trouvé et corrigé : le détail de F06 était refusé par l'API faute de `part`. Trois défauts visuels corrigés (barre mobile à six entrées, onglets d'un graphique à 320 px, texte de graphique réduit sur téléphone). Aperçu synthétique publié sur https://shulker.ch/drivy-preview/ (`20261101T153438Z-27a5a4e2612d`, SHA servi vérifié, retour arrière `--rollback`). Matrice critère → preuve dans [pilotage-373-indicateurs.md](pilotage-373-indicateurs.md) section 18. **Non exécuté : aucun workflow GitHub, aucun essai sur la vraie pile (BFF, API, OIDC) depuis un navigateur, zoom, paysage, appareil physique, chargement lent, changement d'identité en cours d'affichage.** Rien n'est fusionné ni déployé hors aperçu ; l'essai du porteur est l'étape suivante.

## 1er novembre 2026 — Pilotage #373 déployé sur le homelab (web seulement)

**Déployé :** `8d6350c53e1326fbf6410b029149832de8ae1794` (master après la PR #395), accord du porteur (« oui stp » à l'offre de déployer, déploiements du homelab autorisés avec sauvegarde). Frontal seul par `scripts/homelab/deploy-web-311.py` : plan en lecture seule, puis `--execute`. Aucun changement d'API, de BFF compilé, de dépendances, d'identité ni de migration (60 migrations inchangées) ; API, worker et identité tournent sur la même version `bdcf1faf`.

- **Reçu :** `20261101T180106Z-8d6350c53e13`, version précédente `/opt/drivy-refonte/releases/bdcf1fafa676494eac6c02af6ef0cacf7ed68a03/apps/web`, nouvelle `/opt/drivy-refonte/web-releases/8d6350c53e1326fbf6410b029149832de8ae1794/apps/web`.
- **Sauvegarde avant bascule :** `/root/drivy_refonte-before-web311-20261101T180106Z.dump` (CT113, 2 397 220 octets), catalogue vérifié et tous les blocs lus ; **restauration jamais répétée**.
- **Contrôles exécutés :** les cinq services actifs avant et après, seul le web a changé de répertoire, configuration privée inchangée, page d'accueil servie identique octet pour octet au build, puis lecture publique : `https://drivy.shulker.ch/app/` répond 200 avec le SHA `8d6350c5`, les assets sont servis, CSP, HSTS et `Cache-Control` présents, et la route du pilotage du relais répond 401 sans session.
- **Retour arrière :** `python scripts/homelab/deploy-web-311.py --rollback 20261101T180106Z-8d6350c53e13` (plan), puis avec `--execute`.
- **Non prouvé :** aucun parcours authentifié sur le serveur de production (aucune connexion réelle ; l'école du homelab est vide). Le même code a été lu sur la vraie API par le test navigateur de la CI, avec une école synthétique sans leçon. Les chiffres réels d'une école n'ont jamais été vus à l'écran.
- **À savoir :** l'entrée par défaut d'une école active est désormais le tableau de bord, plus l'agenda (documentation du pilotage, section 13.1). Les issues #373 et #376 à #382 restent ouvertes.
