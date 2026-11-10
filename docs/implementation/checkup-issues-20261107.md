# Check-up des issues — 7 novembre 2026

Mandat : examiner les issues restantes et réaliser leurs correctifs de bout en bout
avec le skill orchestre-go. Branche de travail :
`tomyrms/issues-manquantes-orchestre-go`. Base locale et master distant vérifiés :
`2a801eaf6930976760b79372c75b3fa04efd1796`.

## Inventaire initial

GitHub renvoie **39 issues ouvertes**, dont 30 anomalies d’audit #421–#450
et neuf sujets antérieurs. Aucune PR ouverte. Une issue ouverte n’est pas
assimilée à une absence totale d’implémentation : les correctifs intégrés et
preuves des 4–5 novembre sont conservés. La modification préexistante de
`package-lock.json` (30 lignes retirées) est laissée intacte et hors commits.

Le dossier de conception est une référence conservée. Il ne justifie pas
d’étendre ce mandat à Android ou aux options explicitement différées.
Aucun nouveau défaut vérifié hors backlog n’est encore établi.

## Lots et ordre de réalisation

| Lot | Issues | Résultat attendu | État |
|---|---|---|---|
| A · Planning API | #423, #424, #439, #444, #446 | Congés/réservations cohérents, conditions conservées, replanification atomique, examens traitables et rangs exacts | 9864cc86 relu et intégré en 5d98a126 ; 166 tests ciblés, typage/build réussis ; raccords clients encore en cours |
| B · Confidentialité iOS | #425, #426 | Annotations revalidées, données et actions purgées sur refus d’accès | Intégré ; compilation Apple et 264 tests ciblés réussis sur 3d213e7c ; limites UI conservées |
| C · Identité et portraits | #421, #450 | Versions cohérentes inter-écoles et générations de photos monotones ; API puis lecteurs clients coordonnés | API qualifiée et intégrée en 441b261d ; natif intégré, compilation et 17/17 tests profile réussis sur cb60fd27 (42783630248) |
| D · Reprise web et finances | #422, #430, #432, #433, #434, #437, #442, #443 | Saisies conservées, conflits explicites, historique financier accessible, créations rapprochées sans doublon | Cinq premières intégrées en 9a159fb2 ; complément cfb05e33 intégré en 0fd890ea : 13 contrôles navigateur, 20 tests, typage/build réussis ; pas de serveur réel ni CI |
| E · Intentions natives | #427, #431, #438 | Reprise atomique sans verrou fantôme ni écrasement concurrent | 1ff5c148 compilé ; agenda 42781642234 en échec (154/155, les 24 tests exactness passent). Extension du scénario de redémarrage soumise au porteur ; reports/reactivity/UI en cours sur cb60fd27 |
| F · Messagerie et clés | #428, #435, #436, #440 | File récupérable, sauvegarde restaurable, clés à usage unique non redistribuées | Serveur 40fa87a8 intégré en da9be6e8 ; Node 24, typage/build et 29/29 tests PostgreSQL réussis ; retour serveur 1/2 résolu. Natif avec #445 attribué à ctx_d039d4038603 sur 6a7ac8d0, budget neuf 0/2 |
| G · Notifications serveur et appareil | #429, #441, #445, #448 | Identités distinctes, reprises par appareil, révocation et réception active cohérentes | Serveur 77dca790 accepté et intégré, 41 tests ciblés réussis ; combinaison du harnais qualifiée (10/10 PostgreSQL, build API Node24). Budget #448 2/2. Natif #441 intégré, reactivity en cours ; #445 confiée au lot natif F |
| H · Boîtes natives | #447, #449 | Listes complètes et actualisation cohérente | 8586e5f6 non intégré/non compilé ; retour 1/2 ctx_27ea04d2b3a0 : cible exacte et preuves des deux boîtes |
| I · Restes antérieurs | #37, #50, #65, #68, #78, #97, #105, #106, #131 | Réutiliser les lots existants, compléter code et preuves manquantes, distinguer contraintes externes | Rapprochement ctx_82ec49650369 livré ; compléments 6c1f8957 récupérés dans le candidat, échecs UI média et READINESS conservés |

Les lots A et B sont indépendants : deux workers isolés suffisent pour commencer.
Le routage initial était OpenCode Go pour A et Codex GPT-6-Astra pour B.
Après l’erreur `Go usage limit exceeded`, le porteur a demandé explicitement
Claude Sonnet 5.5 pour les tâches restantes. Le routage est donc remplacé par
`--agent claude --model claude-sonnet-5-5 --effort medium`, pour le backend
comme pour l’UI. Cette instruction utilisateur prime sur le routage du skill.
Les mêmes tâches, branches et worktrees sont réutilisés ; aucun fichier produit
n’avait encore été modifié. Le budget de reprises par problème reste inchangé ;
l’échec de quota n’est pas un échec de correction produit.

Run de cette session : `run_c89bc7c0cfbd`. Lot A : `task_c79eb56f8380`,
premier dispatch `ctx_2805e5e51a0e` arrêté après quota. Lot B :
`task_9be193226778`, premier dispatch `ctx_67dee16934c1` arrêté pour le
changement de modèle demandé. Les deux arrêts sont confirmés par Orca
(`state: stopped`, `processAction: closed_agent_terminal`).

## Travaux préexistants à réutiliser

Le worktree `integration-issues-20261105` à `6c1f8957` comporte des compléments
de signalement média et de qualification absents de la base actuelle. Trois
dispatchs de l’ancien run `run_3634d37dc612` sont encore inscrits ready :
`ctx_c430fa0c16e6`, `ctx_7aad80e17c5e`, `ctx_2af50fda2427`.
La liste indique une liveness non vérifiable ; cela ne prouve pas leur arrêt.
Aucune reprise, suppression ou modification de ces espaces n’a été faite.
Leur état, leurs sources et leurs preuves seront rapprochés avant d’attribuer
les lots I/F qui pourraient les recouvrir.

Rapprochement du 10 novembre : `worker-read` de `ctx_2af50fda2427` établit
la sortie de cet agent (pas celle des deux autres). Le run UI final existant
[42135745083](https://github.com/tomyrms/Drivy/actions/runs/42135745083), sur
`6c1f8957`, a compilé puis **échoué : 4 tests sur 6 réussis sur chaque appareil**.
Les deux scénarios mixtes de `MessagingReportScreensUITests` échouent à la
ligne 231, sur iPhone comme sur iPad. Ce résultat ne qualifie donc pas les
compléments média ; aucune relance ni correction supplémentaire engagée.
Le budget antérieur de deux retours UI reste conservé. Les preuves web/API
réussies sur `f81ba3d0` et le succès métier 1814/1814 sur `d1be4068` restent
attachés à leurs candidats ; ils ne rendent pas verts ces nouveaux scénarios.

Récupération du candidat `6c1f8957` le 10 novembre : fusion locale additive,
sans conflit produit ; seul STATUS.md réunit les deux historiques. Aucun
changement dans l'ancien worktree. Le raccord média typé déjà relu reste
disponible pour le travail natif #428/#435/#436/#445 ; l'intégration ne vaut
ni qualification UI ni autorisation d'une nouvelle reprise média.
Fusion `6a7ac8d0`, blobs messagerie identiques au candidat antérieur et
25 tests Python du sélecteur intégré réussis. Le lot natif F possède seul
les sources messagerie et réception push ; le lot H garde les boîtes Élèves,
le lot G l'API des notifications. Aucun chevauchement d'écriture prévu.

### Reste des neuf anciennes issues

Rapprochement du worker I (lecture seule, critères GitHub et documents) :

| Issue | Réalisé | Reste vérifiable ou décision externe |
|---|---|---|
| #37 | Cœur cours et sous-issues livrés, processus exercé sur PostgreSQL | SIGTERM sur POSIX et rapprochement de la matrice #83 ; APNs/appareil distincts |
| #50 | Récupération et garde qualifiées sur Keycloak/Mailpit synthétiques | Choix SMTP reporté par le porteur, activation de la garde, parcours fournisseur/Face ID réel |
| #65 | Socle messagerie et sous-issues livrés | Dépend des critères #68/#78/#97 ; ne pas clore sur les seuls tests du socle |
| #68 | Cartographie et restauration PostgreSQL synthétique | Lieux/sous-traitants, destinations réseau, logs/crash, sauvegarde indépendante, conservation et frontière APNs à décider/vérifier |
| #78 | Nombreux parcours métier/UI exercés sur leurs SHA | Qualification intégrée après correctifs, média UI encore rouge, essais physiques et #68 |
| #97 | Serveur, crypto et parcours média présents ; raccord typé récupéré | Deux scénarios UI mixtes en échec, relais média réel et frontières de file à qualifier ; aucune nouvelle reprise automatique |
| #105 | Sous-issues de réactivité largement livrées | Critères propres de #106/#131 et mesures sur appareil |
| #106 | Admission, reprises et annulations présentes | Rapprocher les critères encore ouverts avec les preuves récentes ; les anciens tests rouges ne sont pas déclarés encore rouges sans résultat actuel |
| #131 | Mesures web synthétiques et campagnes natives existantes | Mesures iOS sous fautes/latences sur candidat intégré, READINESS non résolu, appareil/VoiceOver |

Aucune issue fermée. Le relevé I ne relisait pas tous les runs et mélangeait
par endroits des limites anciennes et des preuves plus récentes : les SHA et
résultats vérifiés par le coordinateur ci-dessus priment. Ni la résidence
suisse ni un résultat physique ne peuvent être déduits de ce rapprochement.

## Validation et limites initiales

- Node système 26 hors cible ; Node 24.22.2 portable déjà présent sera utilisé.
- Docker Desktop installé mais moteur indisponible au premier contrôle ; démarrage
  demandé pour les tests PostgreSQL synthétiques isolés. Disponibilité à confirmer.
- Aucun outil Apple local. Compilation et tests Swift/UI ciblés sur GitHub Actions,
  conformément au mandat ; aucune substitution par une seule lecture statique.
- Codebase Memory disponible, sans index correspondant au nouveau worktree ;
  recherche dans les sources et tests pour ce préflight.
- Qualification ciblée par lot, puis candidat intégré stable. Aucun succès
  physique GPS/batterie/VoiceOver/APNs ni résidence suisse déduit des simulateurs.
- Les critères qui exigent un appareil, une décision de conservation ou une preuve
  d’exploitation restent ouverts jusqu’à preuve. Aucun déploiement public implicite ;
  toute bascule homelab autorisée reste précédée d’une sauvegarde.
- Aucun correctif, test, clôture d’issue ou déploiement revendiqué à ce stade.

Le coordinateur est l’unique auteur de STATUS.md et de ce suivi transversal.
Les workers livrent leurs preuves dans leur rapport de lot.

## Première revue du lot B

Sonnet A : `ctx_c87ad04aa597`. Sonnet B : `ctx_73ee36443ecc`.
Le lot B livre `9dc90566` et rapporte 25 tests du sélecteur Python réussis,
mais Swift non compilé/non exécuté. Revue groupée : deux chemins résiduels
retournés au même worker, dispatch `ctx_939b65ae1a39` :
lecture tardive de loadCandidates après révocation (#426), et feuille
reading du texte intégral non réconciliée après retrait/correction (#425).
Premier retour correctif sur chacun, aucun succès produit revendiqué.
Les chemins des skills UI existants ont été fournis ; le rapport initial les
disait à tort absents. Validation Apple prévue sur le delta stable.

Le lot D peut démarrer en parallèle : son périmètre web est indépendant
des fichiers API de A et Swift de B, ce qui justifie un troisième worker.

## Intégration B et validation Apple

Le delta `8d6c00fc` ferme les deux chemins retournés ; diff relu,
`git diff --check` réussi. Fusion sans conflit en `3d213e7c46500e46a35abd4a49ec2125fe9d7cad`,
identité de tous les blobs apps/scripts avec le worker vérifiée.
Branche de travail poussée ; master et exploitation inchangés.

- GPS/replay : [run 42395051487](https://github.com/tomyrms/Drivy/actions/runs/42395051487).
- Agenda/cours : [run 42395055092](https://github.com/tomyrms/Drivy/actions/runs/42395055092).

Les deux runs ont terminé avec succès au SHA intégré : compilation et
**146 tests dans 11 suites** pour GPS/replay, **118 tests dans 7 suites** pour
agenda/cours. Résultats collectés par le worker et succès des jobs vérifiés
par le coordinateur via GitHub. Les trois nouvelles régressions de replay et
les onze de révocation sont réussies, sans test ignoré. Rapport `f1eb696a`
intégré en `82e1d651` ; pas de relance. La réconciliation du texte intégral
conserve sa limite : pas de test UI de `@State reading`, preuve par sa fonction
et son raccord. Aucune recette physique, GPS ou VoiceOver déduite de ces tests.

Un quatrième lot peut avancer sans conflit pendant cette qualification :
C ne touche que les profils/portraits API, A possède le planning, D le web
et B le client Swift. Les migrations nouvelles restent propres à chaque lot.

## Première revue du lot D

Livraison `b283b4bd`, non intégrée. Typages et build réussis selon le rapport ;
43 tests ciblés réussis. La suite web complète termine en **échec** : 903 tests
réussis, deux tests pending-recovery-106 bloqués au lancement du navigateur.
Le contrôle Chromium synthétique de #432/#433 passe ; le contrôle sur les
sources d'origine s'arrête à #433 et ne prouve donc pas le RED de #432.

Deux chemins d'écrasement résiduels relevés dans la revue de #422 : résolution
d'un conflit d'horaires à partir d'une saisie devenue périmée pendant l'alerte,
et reprise d'une intention refusée sans sa base d'origine (#430 également).
Retour groupé 1/2 au même worker Sonnet, `ctx_302dba84258e` : correction,
preuves sur les vrais composants/hooks et contrôles navigateur manquants
de #422/#430/#434. Réutilisation d'Edge et adaptation minimale du harnais
autorisées pour exécuter les deux tests bloqués ; aucune nouvelle campagne
complète demandée. Aucun succès global ni clôture d'issue déduit de la livraison.

Retour `e5224959` : les deux chemins retournés sont corrigés et le delta relu.
Les conflits d'horaires se calculent sur la saisie actuelle ; l'intention refusée
conserve la règle de départ pour la reprise. Typages/build, 63 tests ciblés,
deux tests pending-recovery et contrôles navigateur horaires/cours/participants
réussis ; journal de refus testé dans les hooks réels des trois autres familles.
Cause du lancement bloqué établie : playwright-core non épinglé demandait une
révision absente, alors que la version verrouillée utilise le navigateur présent.
Le rapport distingue les parcours avec RED observé, les confirmations seules et
les fixtures simulant l'API. Pas de nouvelle exécution PostgreSQL dans ce lot web.

Les cinq premières issues D sont fusionnées sans conflit en
`9a159fb2dd31dfd5e90cfba186135dde7947dbf7` ; blobs apps/web et scripts/dev
identiques au candidat du worker, diff propre. Preuves réutilisées sans
campagne redondante. Les compléments #437/#442/#443 et raccords A sont déjà
affectés au même worker dans `ctx_44befd0463cc`. Compteur correctif inchangé : 1/2.

## Périmètres corrigés et suite après B

La lecture des chemins sources corrige le classement initial : #437/#442/#443
sont web et rejoignent D ; #446 est API et rejoint A, propriétaire de exams.ts.
#445 rejoint les notifications G pour garder un seul auteur de SchoolPushCenter.
Il reste bien trente anomalies réparties, sans doublon. Ces ajouts ne sont pas
des retours correctifs et ne remettent aucun compteur existant à zéro.

Le même worker Sonnet de B reprend E dans son checkout conservé, sur les trois
problèmes iOS #427/#431/#438 : barrière après refus, rejeu exact après relance,
remplacement atomique du coffre réel. Il possède temporairement les sources
Swift et la sélection des tests ; les trois autres workers possèdent planning
API, identité API et web. Les nouvelles preuves Apple seront demandées sur
le candidat stable, sans rejouer les campagnes B pour de simples documents.

## Première revue du lot A et raccords clients

Livraison serveur `2878e141` : typage/build réussis, seize tests ciblés
PostgreSQL réussis après reproduction des quatre défauts. Suite API complète
en **échec** : 1 073 réussis, un ignoré, deux échecs g1c avec Mailpit absent.
Rejeu ciblé des deux échecs demandé avec un Mailpit synthétique isolé, image
déjà verrouillée ; aucune campagne complète supplémentaire demandée.

Revue groupée retournée au même worker (`ctx_ec6c6bd171dc`), premier retour
correctif pour #423 et #424 : la lecture directe des congés sous RLS peut
ignorer ceux d'un collègue pour un moniteur pourtant autorisé à gérer le
cours ou l'examen ; l'égalité par JSON.stringify des règles d'annulation
dépend de l'ordre des clés JSONB/Zod. Régressions demandées avec vraies
identités non admin, véritable aller-retour sans changement et conservation
de l'échéance lors d'une nouvelle inscription au programme révisé.

Pour #444, l'option de l'issue qui garde les examens existants corrigeables
après transition est retenue ; aucune réactivation administrative exigée,
création de nouvel examen toujours soumise à une formation active.
Les raccords web sont confiés au propriétaire D : règles structurées,
actions d'examen actuellement masquées par le statut ACTIVE, engagements
restants visibles et messages de refus. Le propriétaire E vérifie les
consommateurs Swift existants et leurs messages, sans créer d'administration
dans l'app. Le contrat et la couverture des issues A restent transversaux ;
la livraison API seule ne termine pas ces parcours.

Complément #446 livré en `b0215d88` et delta relu : rang groupé par formation
et type d'épreuve, reports sans numéro, ordre date/création/id conservé.
Régression PostgreSQL rouge puis verte rapportée : seize tests examens
réussis, seize tests planning encore réussis et typage réussi. Pas de
campagne globale répétée. Ce delta attend l'intégration du lot A corrigé ;
il n'annule ni le retour #423/#424 ni les deux échecs SMTP à requalifier.

## Première revue du lot E

Livraison `7a4d70b4`, Swift **NON COMPILÉ / NON EXÉCUTÉ**. Les 25 tests
Python de sélection passent. Les suites préparées sont agenda (exactitude
et coffre), reports (barrière de leçon) et reactivity (outbox commune).
La correction principale de #427 existait déjà en `8271c206` ; ce lot ajoute
deux relectures de barrière et sélectionne les régressions déjà présentes.

Retour groupé 1/2 #431/#438 au même worker, `ctx_b8241b8cfecb` : substitution
d'une ancienne intention absente actuellement acceptée malgré le test qui
l'interdit ; absence de parcours conservant une saisie bloquée pour une
réconciliation explicite ; abandon annoncé malgré un éventuel échec de
suppression du coffre. L'oracle du serveur simulé doit vérifier l'identité
canonique réelle incluant la version, sans dépendre de l'ordre d'encodage JSON.
Raccord Swift A également rappelé. Aucun run Apple lancé sur ce candidat
connu incomplet ; compilation et contrôles ciblés prévus dès le delta stable.

Le coordinateur a vérifié dans les sources API que schoolCommand traite
le reçu/hash après autorisation mais avant work/checkVersion, et que
PUT course-series et publish suivent ce chemin. Le test API existant couvre
le rejeu publish ; ceci n'est pas présenté comme une nouvelle exécution.

Raccord Swift A livré en `823f4410`, messages relus, toujours non compilé :
congé distingué d'un rendez-vous dans les refus ; absence de route native de
replanification documentée. Premier retour sur le raccord #444 : le bouton
Prévoir ne doit pas rester proposé après une transition connue. Le statut
existe déjà dans SchoolTrainingWorkspace reçu par la section ; aucune
extension API n'est nécessaire pour ce cas. Garder séparées création et
gestion des examens existants, y compris si une feuille est déjà ouverte.
Ce retour rejoint le dispatch E courant ; compteurs #431/#438 inchangés.

## Interruption du lot C par quota Claude

Le runtime signale `Claude hit its session limit`, réinitialisation annoncée
le 7 novembre à 22 h 50 Europe/Zurich, dispatch `ctx_611681e7d5be`.
Le porteur a explicitement choisi Sonnet 5.5 après épuisement de DeepSeek :
aucun changement de fournisseur effectué. Une question est ouverte entre
attendre Sonnet et autoriser Codex GPT-6-Astra. Le quota ne remet pas à zéro
les compteurs de correction ; aucun retour correctif coordinateur sur C à ce stade.

Worktree `audit-identite-20261107`, base `b8354517`, sept fichiers conservés :
contrat self-profile, profiles/self-profile/invitations, migration
`20261107_identity_versions_photo_generation.sql`, tests identité et adaptation
du test de migration onboarding. Rien n'a été committé, intégré ou écrasé.
Le contrat partiel ajoute photoGeneration tout en gardant photoVersion nullable ;
la revue et le raccord client ne sont pas acquis, aucun succès produit déclaré.

Traces collectées sans relance : douze tests identité réussis, typage réussi,
test temporaire de migration réussi ; après échecs intermédiaires corrigés,
le dernier test complet lancé en arrière-plan se termine à **1 069 réussis,
deux échecs g1c SMTP, un ignoré**. Le pipeline affiche un code zéro malgré ces
échecs : le contenu du journal prévaut, la suite n'est pas verte. Source locale :
`C:/Users/jtoma/AppData/Local/Temp/claude/d5157b6475162846/592eabc7-e05f-481a-a2d4-27d439268159/tasks/b9josjxlc.output`.
Le futur worker doit exploiter ces résultats, achever revue/rapport et requalifier
les tests affectés avec Mailpit synthétique avant livraison ; ne pas dupliquer
une campagne globale sans besoin établi.

## Interruption du retour E par le même quota

Le dispatch `ctx_b8241b8cfecb` (tâche `task_66f6273f991f`) signale à son tour
la limite Claude, même réinitialisation annoncée à 22 h 50 Europe/Zurich.
Le choix de reprise déjà demandé couvre aussi ce lot ; aucune nouvelle
demande ni bascule de modèle, aucun redémarrage effectué.

Le worktree `audit-confidentialite-20261107` conserve HEAD `823f4410` et
deux modifications non committées : `SchoolCommandOutbox.swift` et
`SchoolCourseIntentStore.swift`. Le delta ajoute un refus de substitution
si l'ancienne intention manque et que la nouvelle exacte n'existe pas déjà.
Ce n'est pas une livraison : aucun nouveau test ni compilation Swift observé.
La réconciliation explicite, l'abandon durable, l'oracle de rejeu et le raccord
du bouton Prévoir restent à terminer, puis à qualifier sur Apple.
Les compteurs restent à un retour sur deux pour #431/#438 et pour le raccord
#444 ; l'interruption de fournisseur n'est pas un nouvel échec produit.

## Reprise autorisée le 10 novembre

Le porteur autorise explicitement GPT-6-Astra, puis précise que Sonnet 5.5
peut également continuer. Les quatre sessions existantes reçoivent donc une
consigne de reprise avec Sonnet 5.5 ; GPT-6-Astra est autorisé en secours si
le fournisseur bloque encore. La décision de routage n'est plus en attente.
Un changement éventuel exige toujours de gérer l'ancien worker selon le
guide Orca, sans deux auteurs sur le même worktree.

État relu avant reprise : A conserve cinq fichiers modifiés sur `b0215d88`,
D cinq sur `e5224959`, E deux sur `823f4410`, C sept sur `b8354517`.
La limite Claude a aussi interrompu A et D. Aucun delta partiel n'a été
committé, écrasé ou déclaré qualifié par le coordinateur. La modification
utilisateur de package-lock.json reste seule hors commits dans son checkout.

Orca a accepté les consignes dans les mêmes dispatchs : A `msg_6a924496eb84`,
C `msg_98afdf643c37`, D `msg_5031616f464d`, E `msg_1f970daaf6b4`.
Ces reçus prouvent l'envoi, pas encore une nouvelle exécution ou livraison.
Le périmètre et les compteurs précédents restent inchangés ; aucune campagne
dupliquée ni nouveau résultat de test revendiqué. Les quatre périmètres
conservés sont indépendants : planning API, identité API, web et Swift.

### Redémarrage effectif après contrôle d'activité

À la demande de statut du porteur, les transcriptions établissent que les
anciens agents sont sortis (`terminal: exited`, `liveness: exited`) ; aucune
exécution nouvelle n'avait suivi les quatre messages acceptés. Les envois
seuls n'ont donc pas relancé ces sessions. Les quatre anciens dispatchs ont
été arrêtés par la commande gardée Orca : résultat `state: stopped` et
`processAction: closed_agent_terminal` pour chacun, sans toucher aux fichiers.

Reprise avec `worker-start --task ... --retry-of ...`, sur les mêmes tâches
et worktrees, Claude Sonnet 5.5, effort medium : A `ctx_b8f0bc19c7cf`,
C `ctx_3dcf57d0a714`, D `ctx_beb71e0a56a1`, E `ctx_83558700fe70`.
Les quatre reçus indiquent `ready`. Un contrôle unique des nouvelles
transcriptions confirme `terminal: running`, `liveness: live` et des appels
Bash/PowerShell datés du 10 novembre vers 08 h 28 Europe/Zurich dans chaque
lot. Contexte conservé et contrat worker retransmis ; budgets inchangés.
Ce constat prouve l'exécution en cours, pas la réussite des correctifs.

## Intégration finale du serveur planning — 10 novembre

Le retour A livre finalement `9864cc86` avec rapport à jour, au-dessus de
`2878e141` et `b0215d88`. Le premier message de livraison indiquait encore
des fichiers non committés ; l'état Git ensuite observé est propre et le
commit contient bien les cinq fichiers du correctif et le rapport.
Revue du delta : fonction SQL de disponibilité réservée au personnel actif
de l'école, sans exposition des lignes/motifs de congés ; affectation de
l'accompagnateur vérifiée avant disponibilité ; comparaison sémantique des
règles d'annulation ; vrai no-op et échéance de nouvelle inscription couverts ;
test SQL de bijection avec témoin positif et erreur précise.

Sorties de tests du worker consultées : planning **22/22**, g1c **64/64**
avec Mailpit isolé, suites voisines **80/80**. Typage et build réussis après
delta. Les deux anciens échecs SMTP sont donc requalifiés ; le cas SIGTERM
ignoré sous Windows reste distinct. Suite globale non répétée et aucune
qualification Linux/Apple nouvelle attribuée à ce commit.

Fusion sans conflit en `5d98a126` dans la branche coordinatrice ; comparaison
`git diff --exit-code 9864cc86 HEAD -- apps/api` vide, mêmes sources que les
preuves du worker. Package-lock utilisateur conservé. Pas de push, clôture
d'issue ni déploiement à cette étape. Raccords web/Swift encore en réalisation.
Le compteur reste à un retour correctif sur deux pour #423/#424, résolu.

## Suite G serveur : #429 et #448

Après intégration A, même worker/session/worktree repris sur le lot serveur
de notifications, tâche `task_b1c240750aac`, dispatch `ctx_2af4deb01ea6`.
Les issues GitHub ont été relues : ouvertes, sans commentaire ni changement
depuis le relevé initial. Travail : identité distincte des événements avec
transition des anciennes clés, puis reprise persistante par appareil dans
les chemins métier et messagerie, sans réexpédition des destinations acquises.
PostgreSQL réelle, transport synthétique, cas de redémarrage/révocation et
contrôles ciblés ; aucun résultat APNs physique attendu ou inventé.
Nouveau problème, zéro retour consommé. Aucun changement Swift attribué à ce
worker ; #441/#445 seront repris par le propriétaire natif après son lot E.

## Deuxième retour sur le lot E — 10 novembre

Livraison `d4cfc1f5` (rapports successifs `ctx_83558700fe70` et
`ctx_38877eb20654`) : comparaison puis conservation explicite de la saisie,
retrait durable avant abandon annoncé, oracle canonique de rejeu et gate de
création d'examen connu ACTIVE. Ce dernier raccord #444 est accepté à la
lecture ; sa preuve reste un helper et le branchement source, pas un test UI.
Le Swift reste **NON COMPILÉ / NON EXÉCUTÉ**, delta non intégré.

Revue du delta uniquement, retour groupé **2/2 #431/#438**, dispatch
`ctx_43ff1abb5af1`, tâche `task_b8d4f7106aa7` :

- Abandon : la relecture suspendue ne pose pas isBusy ; un choix de conservation
  peut remplacer kept et envoyer une nouvelle demande, ensuite retirée à tort
  par la réponse tardive de l'abandon. Sérialiser le geste et tester le vrai
  workspace avec transport suspendu.
- Comparaison : la différence est déduite des libellés, pas des identités ; deux
  moniteurs homonymes, deux types au même titre ou inconnus peuvent masquer une
  affectation différente avant réécriture. Comparer les valeurs métier avant
  formatage, sans exposer d'identifiants techniques dans l'UI.
- Rejeu du coffre : old absent/new exact déjà présent est encore refusé pour
  une intention élève, parce que l'admission considère new comme sa propre
  concurrente. Préserver idempotence exacte et refus des autres intentions,
  dans les deux coffres ; aligner aussi l'égalité de old du coffre mémoire.

Les chemins Impeccable et Uncodixfy existent et ont été revérifiés puis fournis
au worker ; son rapport doit retirer les affirmations contradictoires. Pas
de nouveau harnais d'examen exigé. Compilation/tests Apple ciblés préparés
(agenda, reports, reactivity et scénario UI de reprise), à lancer sur le delta
stable. Aucun nouveau résultat ni succès d'exécution revendiqué ici.

## Revue C/D et intégration E — 10 novembre

C `a05f457d` : contrôle des versions inter-routes/inter-écoles accepté à la
lecture, droits conservés. La preuve de portrait « migré » ne traversait pas
la migration ; le retour 1/2 exige ce passage réel avec données chiffrées
préexistantes et propriétaire non privilégié. L'oracle concurrent doit exiger
exactement un gagnant. Le rapport annonce à tort un retour transparent de
l'ancien code : son PUT ne fait pas avancer photo_generation et serait refusé
par la nouvelle contrainte. Retour `ctx_a3e4b3e13b62`, tâche
`task_ddd37116111f`, même worker/worktree ; aucun nouveau lancement global.

D `1430b7c4` : typage/build et contrôles ciblés rapportés réussis, mais revue
retournée en une fois (`ctx_d7858b74a297`, `task_54fac7b0e120`) :
conserver une règle dont cancellationHours est null ne doit pas la supprimer ;
la reprise réelle d'une leçon doit transporter sa base initiale et comparer
les valeurs avant de renvoyer sous V2 ; les vrais composants doivent prouver
503/reprise en édition et replanification, et AP72/GET échoué sans second POST.
Vérifier aussi créer-puis-publier en réponse directe et le changement de statut
pendant une feuille d'examen ouverte. Premier retour sur ce complément ;
ancien retour #422/#430 résolu, compteur conservé. L'échec Orca de remise du
courrier au worker terminé est suivi d'un envoi explicite accepté/reopened.

E `8764579b` : delta du deuxième retour relu, sans nouveau blocage établi.
Abandon sérialisé et retrait de la seule intention capturée, comparaison des
identités avant formatage, admission qui exclut seulement le rejeu exact et
égalité de l'ancienne intention en mémoire. Fusion sans conflit `35f97720` ;
blobs apps/ios et scripts/ios identiques au worker. Ces observations ne sont
pas une preuve Swift : compilation/tests Apple à exécuter. Rendu de la note
d'examen non observé ; aucune recette physique. Budget #431/#438 : 2/2.

C retour `caa97d5d` accepté : migration réellement traversée sous propriétaire
non privilégié, portrait antérieur déchiffré à l'identique, absence et cycle
retrait/remplacement qualifiés ; trois commandes concurrentes produisent un
200 et deux 412. Quinze tests ciblés réussis, preuves g1c précédentes conservées.
Fusion `441b261d` : conflit du seul filtre harness.ts résolu en conservant à
la fois skipMigrations et l'exclusion planning du mode deferCourseMigrations.
Le worker reprend ce commit pour qualification de la combinaison puis lot F
serveur #436/#440 : `task_a2b155fe5167`, `ctx_ecd1e22c16ef`, budget neuf 0/2.

Apple E : branche poussée à `d19e978f`, run agenda `42778603013`, job
`129702904628` observé en compilation (préparation réussie), aucun test encore
qualifié. Aucun doublon lancé. Le worker natif poursuit #441 et le raccord
#450 (`task_4465e8845016`, `ctx_5bda33764428`), budgets nouveaux 0/2 ; il peut
recueillir le résultat existant à sa livraison, sans relance ni polling.
#445 reste distinct tant que le complément média antérieur n'est pas rapproché.
Le worktree integration-issues-20261105 est propre à 6c1f8957 au contrôle en
lecture ; aucun fichier API dans son delta, mais plusieurs fichiers natifs
messagerie partagés. Aucune modification ni reprise de ses workers ici.
