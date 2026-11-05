# U106-L2 — retrait avant transport, planification native

## Préflight du 5 novembre 2026

État initial du préflight : attente du checkpoint N106, sans raccord ni stub.
Le raccord livré après réception est décrit en fin de rapport.
Base vérifiée : `bc2c53cbaae6fa719e6203ea77119a753d6780d7`, branche
`tomyrms/issues-annulation-planification-ui-106`, arbre initial propre.
Le runtime `orca orchestration worker-show --dispatch ctx_03e2318e5896 --json --full`
rend `startOptions.launch.effective` = Codex, `gpt-6-astra`, effort `high`.
Le contrat commun de bristleworm `docs/implementation/L2-interface-annulation-native-20261105.md`
a été lu intégralement. Checkpoint ensuite consommé : **8edb13c0b80fa4e932aa5cdd92483490d1e5f144**, via la livraison finale
**d5c9dee086d5868ac3f8effd4531ff08a63879cf** fusionnée localement sur le préflight `f5a1e76b`.

Skills effectivement lus sous `C:/Users/jtoma/.codex/skills/` :

- `systematic-debugging/SKILL.md` : source et cause avant correction.
- `test-driven-development/SKILL.md` et `writing-good-tests.md` : scénarios avant implémentation ; RED/GREEN Apple non exécutés sous Windows, conformément au contrat.
- `verification-before-completion/SKILL.md` : preuves fraîches et limites explicites.
- `impeccable/SKILL.md` (4.8.0), `reference/operate.md` ; contexte exécuté avec le binaire déjà présent `impeccable/scripts/bin/windows-x64/impeccable.exe context --target apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningView.swift` (aucune installation).
- `uncodixfy/SKILL.md` : composants sobres, sans décoration ni nouveau panneau explicatif.
- `ui-skills-root/SKILL.md` : route UI connue ; pas d'installation CLI additionnelle.
- `C:/Users/jtoma/.agents/skills/orchestration/SKILL.md` et `orca-cli/SKILL.md`, puis guides versionnés fournis par Orca.

Impeccable signale PRODUCT absent et autorise cette correction ciblée sur le contexte existant.
DESIGN.md et la source native servent de référence. Les prescriptions CSS/rem, dimensions web,
et interdictions génériques de bleu/rayons d'Uncodixfy ne remplacent pas les tokens Drivy ni
la géométrie système SwiftUI : la spec impose leur conservation. Mode Operate ; Form existante,
styles Dynamic Type, couleurs sémantiques et cible native, sans nouvelle hiérarchie.

Références parcourues : AGENTS, COMMENCER_ICI, DESIGN ; F04/F05, R09–R14,
J02/J04/J05, synchronisation (outbox, matrice de reprise, AP72), rapports de fermeture et
repères de planification du 3 novembre, sources du workspace/vue/client et tests de sortie/reprise.

## Codebase Memory et diagnostic

Index dédié créé avec le chemin absolu de **ce** worktree :
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106`.
Résultat : 53 125 nœuds, 202 936 arêtes ; 963 fichiers exclus, 88 parsings partiels,
4 inutilisables (signalements globaux, pas preuve de couverture exhaustive).
Recherches `SchoolPlanningWorkspace|SchoolPlanningClient|SchoolPlanningView`, puis
`transmit|SchoolCommandOutbox|SchoolPlanningFeedback` ; snippet de `transmit` et trace sortante.
La trace trouve les méthodes locales de confirmation/erreur/relecture ; elle attribue aussi
send/save/remove à des doubles sans rapport : résolution polymorphe non fiable ici, vérifiée
par lecture du source (`SchoolPlanningClient`, `SchoolCommandOutbox`, injection constructeur).

Cause observée statiquement : aucune preuve vivante ni action de retrait dans le workspace ;
`transmit` utilise la génération de chargement et un `defer { isSendingRequest = false }`
inconditionnel. Une annulation réussie permettant un nouveau geste exige de distinguer
les tentatives afin que la fin ancienne ne réécrive ni attente, erreur, brouillon ou confirmation.
`leaveWhileRequestIsSent` ferme volontairement, sans retirer le record ; conserver cette règle.
La section `SchoolPlanningFeedback` du record est le point d'insertion de l'action et de son erreur.

## Scénarios préparés avant raccord

Tests à écrire sur le vrai workspace/client/admission ; seuls token, transport et panne de retrait
sont des frontières contrôlées. Attentes bornées avec échec explicite, valeurs async extraites
avant assertions. Coffre temporaire réel avec clé exclusivement synthétique si utilisé.

| Scénario | Preuve attendue |
|---|---|
| Création et déplacement, token retenu | Retrait durable ; zéro mutation métier ; saisie inchangée ; aucune confirmation/notification |
| /me retenu après jeton | Même résultat ; compter les lectures séparément des mutations |
| Retrait refusé puis réessayé | Record conservé, erreur locale, aucun renvoi silencieux ; retrait suivant possible |
| Transport gagne avant clic | Aucun retrait, aucune annonce d'annulation ; suivi et AP72 maintenus |
| Premier essai échoue avant handOff | Admission vivante conservée ; retrait reste possible |
| Renvoi même opération | IDs, octets, version identiques ; une commande déjà handed ne redevient jamais annulable |
| Réponse perdue | Record et suivi conservés ; aucune confirmation inventée |
| Annulation puis nouveau geste, ancien retour tardif | Nouveau pending/busy/error/sending intacts ; ancien defer inoffensif |
| Reçu puis relecture | Une confirmation et une notification seulement |
| Réouverture d'un ancien record | Aucune admission neuve, donc aucune annulation avant transport prétendue |
| Sortie volontaire pendant envoi | Fermer ne retire rien ; preuve tardive annoncée selon règles existantes |
| Annulation de leçon | Action métier et préparation GPS existantes conservées, sans admission pilote |

## UI et qualification restant à faire

Libellés distincts : « Annuler l'envoi » pour le geste local ; « Annuler la leçon » pour
l'engagement existant. Le retrait échoué reste attaché au record et propose le même retrait,
sans toast global ni fausse annonce d'effacement. Vérifier iPhone/iPad, clair/sombre,
Dynamic Type maximal, clavier, ordre VoiceOver, fermeture, conservation de la saisie.

Le harnais actuel ne fournit pas de retenue déterministe du jeton ou de /me pour la planification.
Point d'injection précis à signaler avant extension : `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift`,
constructeur `SchoolOfficeVisualModels` (token `SchoolVisualToken`, transport
`SchoolOfficeVisualTransport`, outbox `SchoolOfficeVisualOutbox`, puis `SchoolAgendaClient`
et workspace), ainsi que `SchoolOfficeVisualTransport.send` pour /me.
Ces chemins sont hors périmètre : aucune extension ni fichier UITest prétendant observer
la course n'est créé à ce stade.

`Get-Command swift,xcodebuild -ErrorAction SilentlyContinue` ne trouve aucun exécutable.
Swift, XCTest/Testing, rendu Apple, VoiceOver physique : **NON EXÉCUTÉS** ; aucune capture produite.
Le pilote ne qualifie aucune autre famille de commandes, GPS ou backend.
STATUS reste à la charge de l'intégration : modification explicitement interdite à ce worker.


## Livraison après réception N106

Le coordinateur a autorisé l'extension de `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift`
(message de réponse Orca `msg_8df9e7997a55`) : constructeur et helpers de fixture uniquement.
Aucun fichier N106 n'a été édité ; les cinq fichiers de sa livraison proviennent de la fusion autorisée.

Fichiers U106 modifiés :

- `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift` : admission seulement après sauvegarde réussie d'un nouveau create/move ; comparaison de la commande complète pour utiliser la preuve et afficher son erreur ; aucune reconstruction au chargement.
- `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningView.swift` : action « Annuler l’envoi » dans la section de la demande, erreur locale et annonce accessible ; style texte natif existant, sans nouveau panneau ni changement de palette/typo. « Fermer » et « Annuler la leçon » gardent leur sens.
- `apps/ios/DrivyTests/SchoolPlanningCancellation106Tests.swift` : 9 tests, dont une matrice de 4 cas create/move × token/me, écrits avec vrais workspace/client/admission/coffre temporaire et frontières synthétiques.
- `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift` : source privée de jeton et barrière bornée, scène planning uniquement, sous le garde DEBUG simulateur existant.
- `apps/ios/DrivyUITests/SchoolPlanningCancellationUITests.swift` : 3 scénarios UI (token, /me, retrait refusé puis réessayé en taille maximale), captures seulement lors de leur future exécution.
- Le présent rapport.

Retrait réussi : pending et bloqueur relus après suppression durable, brouillon conservé, aucune ressource,
confirmation ni notification serveur. Retrait refusé : émission fermée, record inchangé, message local,
« Annuler l’envoi » retente le retrait et `canRetry` interdit le renvoi. Admission handed : aucun retrait,
suivi inchangé. Le même objet admission survit à une panne avant transport dans cette instance ; un
workspace restauré n'en reçoit jamais. Les méthodes de reprise existantes restent disponibles selon
leurs règles ; les retours de `verify` sont aussi protégés contre un retrait intervenu pendant leur attente.

Chaque envoi porte une identité de tentative ; retrait et nouveau geste invalident la précédente.
Le callback et le defer anciens ne réécrivent donc pas l'état nouveau. La génération de chargement et
les règles existantes de sortie volontaire/révocation restent distinctes. La fermeture pendant envoi
continue à permettre une notification sur preuve tardive, et ne retire pas l'intention.

Le harnais est activé seulement par `-planning-l2-cancellation-token` ou
`-planning-l2-cancellation-me`, avec l'option `-planning-l2-cancellation-storage-failure`.
Il s'arme dans `outbox.save` au geste, jamais pendant le chargement. La suppression réussie libère
la retenue ; après 25 secondes, la frontière échoue et le retrait ne peut plus passer comme succès.
Lectures /me et mutations sont comptées séparément ; un retrait exige zéro mutation et le nombre
attendu de lectures d'identité. Ce contrôle ne prétend pas mesurer de vrais paquets réseau.
Les tests workspace ont des barrières de 5 secondes et une attente de rendez-vous de 3 secondes,
avec `Issue.record` et erreur explicites à l'échéance ; aucune continuation indéfinie ni assertion async
placée dans une autoclosure.

### Vérifications réellement disponibles

- `git diff --check` puis inspection du diff : exit 0 ; avertissements de normalisation CRLF/LF seulement.
- Impeccable `detect --json` sur workspace/vue : exit 0, `[]`. Détecteur statique, aucune preuve de rendu SwiftUI.
- Nouvelle indexation Codebase Memory de la même racine après raccord : 53 341 nœuds, 204 264 arêtes ; mêmes 88 parsings partiels et 4 inutilisables globaux. Ce n'est pas un compilateur Swift.
- Recherche des assertions await et continuations dans le nouveau test : aucune ; quatre boucles d'attente ont des échéances explicites.
- `Get-Command swift,xcodebuild -ErrorAction SilentlyContinue` : aucun outil trouvé. Tests Swift/UI, compilation, RED/GREEN, rendu et captures : **NON EXÉCUTÉS**. La préparation test-first ne revendique pas un cycle RED/GREEN observé.
- Le `project.yml` inclut déjà les dossiers DrivyTests/DrivyUITests ; aucun changement du projet requis.

### Campagne Apple restante

Exécuter la suite `SchoolPlanningCancellation106Tests`, les suites N106 et les régressions
`SchoolPlanningLeaveWhileSendingTests`, `SchoolPlanningRecovery106Tests`, `SchoolPlanningBookingTests`
et `SchoolPlanningDefaultsTests`, puis la suite UI ajoutée. Faire ensuite la suite native complète
sur le candidat intégré, sans considérer ces seuls scénarios comme une qualification produit.

Préparer iPhone compact et iPad 11 pouces, portrait/paysage, clair/sombre, taille standard et accessibilité
maximale : bouton atteignable dans la section de la demande, aucune troncature, saisie intacte après retrait,
barre Planifier disponible après revalidation du créneau. Avec clavier ouvert, vérifier fermeture protégée
et réédition du lieu. Sur appareil, vérifier l'ordre VoiceOver, les deux libellés français distincts,
l'annonce de l'erreur et le focus après disparition de l'action. Aucune de ces vérifications physiques
n'est annoncée faite. GPS, autres familles de commandes, serveur/PostgreSQL et notification distante
restent hors qualification de ce pilote.

Pas de push, CI, installation, activation, changement de dépendance, de modèle ni de sous-agent.

Commit de raccord : `57179b42885cff02d9595e495ddd61163a7b3832` ; fusion locale N106 : `ac6e0080` ; préflight : `f5a1e76ba9615aa66d61bce128624ead9248c476`. Arbre propre vérifié après le commit de raccord.


## Correction 1/2 — preuves UI R106 (5 novembre 2026)

Base conservée : `7d8cd1c71155ab1185a0aa3639b6fdc2c0976fae`. Rapport R106 lu
intégralement à `review-annulation-ui-106/artifacts/review-planning-cancellation-106/RAPPORT.md`.
Deux défauts de harnais confirmés par lecture du source, aucun nouveau défaut produit établi.
Le dispatch de suivi expose des champs modèle/effort nuls ; la vérification du dispatch initial
confirme Codex `gpt-6-astra/high`, même incarnation `structured:1bfdfca6-7879-485f-8a8c-426c16376122`.
Aucun changement de modèle ni délégation.

Préflight : les cinq skills déjà intégralement chargés dans cette session ont été retrouvés et
leurs fichiers contrôlés par SHA-256, puis leurs instructions pertinentes relues :
`C:/Users/jtoma/.codex/skills/{systematic-debugging,test-driven-development,verification-before-completion,impeccable,uncodixfy}/SKILL.md`,
avec `impeccable/reference/craft-floor.md`. Le contexte Impeccable déjà exécuté et DESIGN restent
applicables, sans nouveau redesign ni installation. Sobriété/native préservées : seul un texte
technique de fixture opt-in rend le rendez-vous observable ; aucun panneau ni style produit ajouté.
Les règles web de police/dimensions/couleur ne remplacent pas les tokens natifs imposés.

Codebase Memory : `index_status` confirme ready et la racine exacte
`C:/Users/jtoma/orca/workspaces/Drivy/issues-annulation-planification-ui-106`, projet
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106` ; recherche de
`SchoolPlanningL2FixtureGate|SchoolPlanningCancellationUITests`, puis lecture directe des deux
sources et des dépendances `SchoolMeetingPointField`, `bookingActionContent`, `validBooking`,
`focusForTyping`. Pas d'utilisation de l'index du reviewer voisin.

Scénarios préparés dans le test avant correction de la fixture :

- Développer explicitement « Détails du rendez-vous », atteindre le vrai TextField/TextView,
  saisir au clavier un suffixe synthétique L2 distinct, vérifier sa présence et la différence
  avec la valeur initiale ; après retrait, retrouver le champ hittable et la même valeur.
- Attendre par prédicat XCTest, en cinq secondes au plus, le témoin observable
  `waiting-token|me=0|mutations=0` ou `waiting-me|me=1|mutations=0` avant le clic.
  Le témoin provient de l'entrée réelle dans la retenue, jamais de l'apparition du bouton.
- Après retrait, vérifier `removed` et les compteurs, tout en conservant le cas existant
  de premier retrait refusé puis réessayé en grande taille.

La scène est une création : le source actuel confirme le tarif par « Planifier », sans case
« Prix et conditions acceptés ». Le lieu remet bien agreementConfirmed à false, mais cette valeur
n'est requise par validBooking que pour un déplacement ; le test ne force aucun modèle et attend
l'activation réelle de Planifier. Si le contrôle « Le nouvel horaire est convenu » est présent,
le test le réactive par un vrai appui, jamais par injection.

Le témoin est sous DEBUG/simulateur, scène planning et arguments L2 déjà explicites. Il ajoute
un texte de fixture en safe area, non interactif, avec identifiant AX dédié et observation réelle
des phases/compteurs. Les conditions sur le nombre de lectures ont été retirées de `remove` : une
annulation légitime avant /me n'est plus transformée en erreur de stockage. Les assertions de
phase appartiennent au test. Commande différente, échéance expirée, mutation inattendue et panne
explicite restent refusées. L'échéance de 25 secondes n'a pas augmenté ; aucune pause ajoutée pour
simuler un rendez-vous. Les compteurs n'établissent aucune preuve de paquets réseau réels.

Fichiers changés seulement : ce rapport, `apps/ios/DrivyUITests/SchoolPlanningCancellationUITests.swift`
et `apps/ios/Drivy/UI/SchoolOfficeVisualReview.swift`. Workspace/vue produit, client, admission,
coffre et tests N106 inchangés. Les trois tests UI existants sont enrichis ; aucune nouvelle suite.

Vérification disponible : `git diff --check` exit 0 (avertissements CRLF/LF seulement), inspection
du diff et comparaison des chemins produit avec la base sans changement. Swift/Xcode restent
absents : **NON COMPILÉ / NON EXÉCUTÉ**, aucun RED/GREEN, screenshot ou vert inventé.
Restent l'exécution et le rendu Apple du candidat, dont la représentation AX du champ multiligne,
le clavier, iPhone/iPad et grandes tailles ; le témoin de fixture ne qualifie pas le rendu produit.


## Correction 2/2 — RED Apple Q4 et contrôles AX (5 novembre 2026)

Base locale préservée : `5c3c378a7b60a1bb2877c5521dd2e41edd3a48f8`.
Preuve runtime relue : dispatch initial `ctx_03e2318e5896`, effective Codex
`gpt-6-astra/high`, incarnation `structured:1bfdfca6-7879-485f-8a8c-426c16376122`.
Les champs null des suivis ne remplacent pas cette preuve ; aucun changement de modèle.

RED réellement exécuté par Q4, run `41962003523`, job `127030313497`, candidat
`62560a2ed8c55326f73c512c9ac9dfaa08a5382b` : les summary.json/tests.json de
Tests et iPadTests montrent chacun 8 cas exécutés, 5 MessagingMedia réussis et 3 Planning
échoués, aucun ignoré. Appareils : iPhone 17 Pro et iPad Air 11-inch (M4), OS 26.4.1.
Sources réellement lues sous
`C:/Users/jtoma/orca/workspaces/Drivy/integration-issues-20261105/artifacts/qualification-62560a2e/artifacts-41962003523/Drivy-native-results-62560a2ed8c55326f73c512c9ac9dfaa08a5382b/ios/` :

- `test-reports/{Tests,iPadTests}/{summary,tests}.json`, manifeste des pièces jointes Tests.
- `Tests/attachments/7E2CBA64-DA4A-462E-A3CE-BC839FF2DBC2.txt`, ligne 140 : TextField présent, label composé « Lieu (facultatif), Lieu du rendez-vous, facultatif », valeur synthétique Gare de Cernier.
- `Tests/attachments/B4B5DC9F-E6B5-4418-B734-19591097652C.txt` : requête AX erronée par égalité exacte du label.
- `Tests/attachments/F30A21F7-29DB-4971-8291-69DABC324A43.txt` : navigation et CollectionView présentes, premières cellules seulement, témoin idle ; le bouton inférieur n'est pas encore matérialisé.
- `simulator-test.log`, lignes 428–436 : lancement du cas token iPhone après l'échec précédent, tentative de terminaison du pid 29144 puis « Failed to terminate » ; aucun défaut produit déduit de cet incident. Le manifeste associe à ce cas la vidéo `2153ED73-7125-4436-BC07-78D9BFC7BAF4.mp4`, sans arbre AX supplémentaire ; aucun visionnage vidéo ni nouvelle capture n'est revendiqué.

Préflight conservé et réappliqué : systematic-debugging, test-driven-development,
verification-before-completion, Impeccable et Uncodixfy, aux cinq chemins SKILL.md réels
`C:/Users/jtoma/.codex/skills/` déjà consignés ; instructions pertinentes relues, avec
`impeccable/reference/craft-floor.md`. Le contexte Impeccable de cette session reste chargé.
Application native : préserver labels, typo, couleurs, géométrie, navigation et interactions ;
aucune prescription CSS ne remplace DESIGN. Seul ajout produit autorisé : identifiant AX.
Codebase Memory : index_status ready de cette racine exacte, projet
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106`, puis recherche
`SchoolMeetingPointField|SchoolPlanningCancellationUITests` et lecture directe du champ/test.

Correction ciblée :

- Identifiant `planning-meeting-point` posé une seule fois sur le vrai TextField de SchoolMeetingPointField ; test filtré par identifiant et type, avec exactement un champ attendu avant/après saisie.
- Lancement : attendre la barre « Planifier une leçon » et le formulaire ; aucune attente initiale sur le bouton inférieur virtualisé. Les contrôles sont atteints par défilement borné avant leurs assertions ; aucune hausse du timeout de lancement.
- Saisie visible, valeur avant/après, accord par UI si nécessaire, waiting-token/waiting-me, compteurs, retrait refusé/réessayé et grande taille conservés.
- `addTeardownBlock` MainActor termine normalement l'app encore active, y compris après assertion, comme le modèle existant AppearanceSettingsTests. Aucun retry, délai ajouté, suppression de cas ou affirmation de réparation de l'incident simulateur.

Fichiers changés : SchoolPlanningCancellationUITests.swift, SchoolPlanningView.swift (une seule
ligne d'accessibilityIdentifier), ce rapport. Aucun workspace/client/admission/coffre/N106/gate/25s
modifié. Vérifications locales : diff-check et comparaison des chemins métier avec la base exit 0 ;
contrôle du delta de vue limité à l'identifiant, et unicité de sa déclaration source. Les preuves AX
existantes sont relues, pas remplacées par une hypothèse Windows.

**GREEN restant à exécuter sur Apple** : compiler ce delta et rejouer les trois cas sur les deux
simulateurs, en contrôlant saisie hittable, unicité AX, grand texte et rendez-vous ; vérifier aussi la
terminaison du processus entre cas. Aucun build/test Apple local, aucun nouveau rendu ou résultat
VoiceOver physique disponible. Pas de CI/push/fusion/déploiement par ce worker.


## Exception ciblée approuvée après Q6 — 5 novembre 2026

Accord explicite du porteur « Oui, appliquer cette passe ciblée », dispatch `ctx_7178dbe3df44`.
Base `8da3a4110bd9cc62865499aca6bbd0b1d4466171` préservée ; aucune nouvelle demande d'approbation.
Le diagnostic ignoré Q6, ses vidéos inspectées et les deux causes de harnais restent la preuve RED
Apple : retour waiting-token → admitted sans émission avant 25 s ; gestes grand texte dans le clavier.
Le résultat métier 1806/1806 au candidat 0c447ae7 est communiqué par le coordinateur, pas réexécuté ici.

Préflight vérifié : reçu `ctx_03e2318e5896` = Codex gpt-6-astra/high, incarnation inchangée
`structured:1bfdfca6-7879-485f-8a8c-426c16376122`. Skills déjà chargés intégralement dans cette session,
références pertinentes relues sous `C:/Users/jtoma/.codex/skills/` : systematic-debugging,
test-driven-development, verification-before-completion, impeccable (4.8.0), uncodixfy, chacun via
son SKILL.md ; craft-floor Impeccable relu avant édition. Le contexte Impeccable/DESIGN reste chargé.
Sobriété native appliquée en préservant strictement rendu/labels/layout produit ; aucune règle CSS
ne remplace les composants Apple. Aucun nouveau panneau de fixture ajouté.
MCP index_status ready et racine exacte du worktree confirmés, projet
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106` ; search_graph sur
SchoolPlanningL2FixtureGate/SchoolPlanningCancellationUITests, source et conventions compilées
SchoolCommandSendAdmissionTests/LayoutContinuityTests relues. Aucune réindexation générale.

Changements limités aux quatre chemins autorisés :

- SchoolOfficeVisualReview.swift : Set<UUID> d'attentes actives ; chaque defer ne retire que son
  identifiant, waiting dérivé du set. Helper interne uniquement sous le garde DEBUG/simulateur
  existant pour @testable ; compteur en lecture seule, horloge MainActor injectable avec Date()
  par défaut. Expiration toujours à +25 s ; retrait, armement, compteurs et refus inchangés.
- SchoolPlanningFixtureWaitTests.swift : trois contrôles sur le vrai helper, écrits avant sa correction :
  deux attentes puis annulation B laissant A visible et retrait libérant A ; annulation de l'unique
  attente ; échéance exacte de 25 s via horloge synthétique, résultat expired et retrait toujours refusé.
  Rendez-vous de trois secondes avec require explicite ; tâches annulées et rejointes dans chaque
  chemin d'erreur, résultats async matérialisés avant assertions. Aucun helper générique de timeout,
  continuation, tâche de minuteur ou horloge de fond ajouté.
- SchoolPlanningCancellationUITests.swift : gestes dans l'intersection CollectionView/fenêtre,
  coupée sous navigation/témoin et au-dessus clavier/footer/confirmation. Départ et arrivée dans cette
  zone avec marges ; instantané immédiat de jusqu'à trois repères de contenu avant geste, comparaison
  de leur identité/position après. Sans mouvement, arrêt dans cette direction ; jamais dix gestes
  clavier présentés comme une exploration. Limite inchangée 10 gestes par direction, contrôle final
  d'existence/hittabilité conservé. Saisie avant/après, unicité, accord UI, waiting-token/waiting-me,
  zéro émission, panne/retrait réessayé et grand texte inchangés.
- Le présent rapport.

Relecture des déclarations/appels : init(mode:refusesRemoval:now:) garde les appels existants grâce
au paramètre par défaut ; les trois tests utilisent arm/waitForRemoval/remove et activeWaitCount
sur MainActor ; les tâches sont rejointes avant sortie. Les coordonnées XCTest utilisent la fenêtre
comme origine et la zone visible comme bornes ; le contrôle ne force aucun état de modèle.

Vérifications locales : git diff --check ; comparaison des chemins produit/métier et du reste de la
fixture avec la base ; inspection des quatre chemins et des signatures. Swift/Xcode restent absents :
**NON COMPILÉ / NON EXÉCUTÉ localement**, aucun GREEN nouveau ni nouvelle capture Apple revendiqué.
Le set et les tests sont préparés pour compilation et exécution, pas déclarés passants depuis Windows.

À rejouer sur Apple : les trois SchoolPlanningFixtureWaitTests, les suites métier all du candidat
intégré, puis les deux suites UI média/planification iPhone et iPad. Sur iPhone XXXL/clavier ouvert,
constater le déplacement du formulaire et l'accès à Planifier ; en token, observer waiting maintenu
malgré la sortie d'une lecture concurrente, puis removed/compteurs stricts. La provenance exacte de
la lecture annulée en Q6 reste une hypothèse ; aucune augmentation du délai ni assouplissement du
verdict n'a été utilisée. Aucun client/admission/workspace/coffre/serveur/droit/layout produit modifié.
Pas de push, CI, fusion, déploiement, installation, changement de modèle ou sous-agent par ce worker.

## Finalisation des gestes après Q8 — 5 novembre 2026

Dispatch `ctx_79f2eb95037b`, arbitrage conservé dans
`sandperch/docs/implementation/reprise-q8-arbitrage-20261105.md`. Base locale
`621da6a27447a59a9ffc81f36590de16f85fb8e4`, aucun merge. Le source pertinent du candidat
Q8 `0e2edd65470ee5f5212341e420409a5b6bb287a3` est identique à cette base : test UI,
vue, workspace et fixture comparés avant édition. Budgets historiques conservés.

RED déjà exécuté : run 42025530498, iPhone 7/8 et iPad 6/8. Le diagnostic ignoré
`artifacts/q8-large-text-diagnostic/RAPPORT.md` conserve logs, vidéos, événements et images.
Sur iPhone, Planifier est recherché avant l'envoi ; le premier geste montant dans la zone du
champ actif n'avance pas, puis l'ancien helper inverse le sens. Sur iPad, Annuler est atteint
à +31,1 s après Planifier ; environ 19,6 s de préparations AX contribuent à dépasser les 25 s.
Le rouge média iPad est distinct. Ni le Set d'attentes ni le métier ne sont remis en cause.

Seuls le test UI et ce rapport changent :

- `reveal` prend un instantané AX initial de l'application, puis un après chaque geste, réutilisé
  pour l'étape suivante. Ses descendants sont parcourus en mémoire : plus de trois requêtes
  `allElementsBoundByIndex` ni de lectures distantes répétées pour chaque repère. Les fenêtres
  clavier sont incluses ; la géométrie reste l'intersection du Form et de la fenêtre, hors
  navigation, témoin, clavier et footer. La confirmation fixe est exclue, celle dans le Form
  en grand texte demeure du contenu défilant.
- Le départ et tout le trajet sont vérifiés hors frames des contrôles interactifs, avec marge.
  Les gouttières gauche/droite sont essayées alternativement ; aucune zone sûre entraîne un
  échec explicite. Le geste utilise presque toute la hauteur disponible. Un non-mouvement
  n'inverse plus immédiatement le sens ; la limite reste dix gestes par direction, vingt au plus.
- Un repère de contenu unique, proche du centre, est comparé avant/après chaque geste ; sa
  disparition par virtualisation ou son déplacement est consigné. Après des gestes, le contrôle
  hittable exige qu'un mouvement ait été observé. Coordonnées, zone, repère et frames sont
  journalisés uniquement dans cette scène synthétique pour rendre le prochain verdict vérifiable.
- Le rendez-vous `waiting-token` ou `waiting-me` est attendu immédiatement après Planifier.
  Annuler est ensuite recherché ; le dernier instantané conserve les assertions du libellé français,
  de l'absence d'Annuler la leçon et de Fermer actif, avant le clic. Une lecture fraîche exige encore
  le témoin exact juste avant le retrait. Temps monotones tap → waiting → hittable → clic/retour
  et réessai journalisés ; appel du premier clic exigé à moins de 25 s depuis l'appel Planifier.
  Ce relevé ne prétend pas mesurer seul l'instant de livraison du toucher : le log XCTest et
  les événements natifs complètent la preuve, et `removed` demeure obligatoire.

Saisie réelle visible avant/après, unicité du champ, accord par UI, nombres de lectures et zéro
mutation, refus explicite puis réessai, absence d'erreur après retrait et retour à la saisie restent
exigés. Aucun délai augmenté, sleep, état forcé, skip, admission d'expired/admitted comme waiting,
nouveau test redondant ou infrastructure ajouté. Aucun changement produit, fixture/Set ni tests métier.

Préflight : reçu initial `ctx_03e2318e5896` relu, effective Codex gpt-6-astra/high,
incarnation `structured:1bfdfca6-7879-485f-8a8c-426c16376122`. Skills rechargés sous
`C:/Users/jtoma/.codex/skills/` : `systematic-debugging/SKILL.md`,
`verification-before-completion/SKILL.md`, `test-driven-development/SKILL.md`,
`impeccable/SKILL.md` (4.8.0), `uncodixfy/SKILL.md` ; craft-floor Impeccable relu.
Profil B du skill actuel `C:/Users/jtoma/.agents/skills/orchestre-go/SKILL.md` appliqué :
RED Apple existant réutilisé, pas de revendication de cycle TDD GREEN exécuté sous Windows.
Contexte AGENTS/COMMENCER_ICI/DESIGN/R11–13/AP40–42–72/T019–20/contrat L2 conservé et relu
de manière ciblée. Impeccable et Uncodixfy appliqués à l'interaction native et aux preuves :
clavier, grand texte, contrôles réellement accessibles, aucune nouvelle décoration ni modification
de typographie/couleurs/composants. Leurs recettes CSS ne remplacent pas les conventions Apple.

MCP : projet `C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-planification-ui-106`,
racine exacte, HEAD 621da6a, index ready/watched, génération 2026-11-05T11:56:57Z ;
`search_graph` reveal/scrollViewport/Gate, `check_index_coverage` des quatre sources metadata_match.
La vue a deux plages de parsing partiel hors helper ; le source réel prime. Pas de réindexation.
Déclarations publiques vérifiées dans la documentation Apple :
[snapshot()](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshotproviding/snapshot())
retourne un instantané et peut lever une erreur ;
[XCUIElementSnapshot](https://developer.apple.com/documentation/xcuiautomation/xcuielementsnapshot)
expose les descendants. Tous les appels `reveal` portent `try` et les erreurs remontent au cas XCTest.

Contrôles locaux : `git diff --check` exit 0 ; comparaison de tous les chemins non autorisés
contre 621da6a par `git diff --exit-code` exit 0 ; revue complète du diff, des déclarations/appels,
des verdicts et des bornes. Les preuves de commande et le SHA local sont conservés sous
`artifacts/q8-planning-gesture-finalisation/`. Q6 et Q8 sont préservés. Images Q8 `phone-49.png`
et `ipad-contact.png` inspectées à nouveau ; elles documentent le rouge antérieur, pas ce delta.

**NON COMPILÉ / NON EXÉCUTÉ sur Apple pour ce delta.** Aucun GREEN Swift/UI, nouvelle capture,
qualification sombre ou VoiceOver physique revendiqué. À exécuter sur candidat intégré par le
coordinateur : métier all, dont les trois tests d'attentes, puis les huit cas des deux suites UI
sur iPhone/iPad. iPhone XXXL : mouvement montant réel hors champ, Planifier atteint et saisie intacte.
iPad XXXL : waiting-token 0/0, Annuler hittable et touché avant expiration, premier retrait refusé,
second réussi, removed et saisie intacte. Standards token/me préservés ; vérifier les traces temporelles
et les zones de chaque geste. Le coût réel du nouvel instantané et la réception des gestes restent
à mesurer sur Apple ; aucune exécution distante ni autre correction automatique par ce worker.
