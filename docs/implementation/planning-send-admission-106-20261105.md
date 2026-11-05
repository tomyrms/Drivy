# N106 — admission atomique avant transport, pilote planification

Date : 5 novembre 2026. Branche `tomyrms/issues-annulation-native-106`, base exacte
`bc2c53cbaae6fa719e6203ea77119a753d6780d7` (L1b garde du créneau après jeton/`/me`). Lot local, sans push,
sans CI distante, sans déploiement. Contrat commun : `L2-interface-annulation-native-20261105.md`
(worktree `bristleworm`), propriété N106 = admission + `SchoolPlanningClient` + tests.

## 0. Runtime et préflight

Modèle effectivement servi : `opencode-go/deepseek-v4.1-flash` (OpenCode), sans variante d'effort demandée.
Skills Superpowers réellement chargés dans cette session : `test-driven-development`, `systematic-debugging`,
`verification-before-completion`. Aucun RED/GREEN observé (pas de compilateur Swift sur Windows) : les tests
ont été écrits avant l'implémentation, mais aucun échec n'a pu être exécuté ni présenté comme preuve.

Codebase Memory : projet de CE worktree indexé par chemin absolu
`C:/Users/jtoma/orca/workspaces/Drivy/issues-annulation-native-106`, nom retourné
`C-Users-jtoma-orca-workspaces-Drivy-issues-annulation-native-106` (ready, réindexé à 53 232 nœuds et
203 690 arêtes, génération 2026-11-05T01:16:30Z, watch actif relu à 01:30:44Z, mode moderate). Recherches :
`search_graph` `SchoolPlanningClient send`, lecture du source `SchoolPlanningClient.swift` (lignes 1-412),
`search_code` sur `Admission`, `trace_path` entrant sur `SchoolPlanningClient.send` (aucun appelant indexé,
le seul appel de production étant `SchoolPlanningWorkspace.transmit:817`), `check_index_coverage` sur les
trois fichiers lus (`no_recorded_issue`, `metadata_match`, best effort) ; à la correction 1/2,
`search_graph` sur `SchoolCommandSendAdmission`/`AdmissionTokenSource` a retrouvé les symboles du type et du
harnais dans les nouveaux fichiers. Aucun index d'un autre worktree consulté.


## 1. Défaut visé

Le workspace conservait d'abord la commande dans le coffre puis appelait `client.send`. Entre le geste et
`transport.send`, le client attend le jeton, lit `/me` et vérifie la portée puis la barrière de créneau L1b.
Pendant ces suspensions, le porteur ne pouvait pas retirer la demande locale sans risquer qu'elle parte
quand même. L'abandon existant ne visait qu'une demande relue absente (404) : il ne couvrait pas cette
frontière avant première émission, et un 404 ne prouve jamais qu'une écriture n'a pas eu lieu.

## 2. Interface livrée (gelée par le contrat)

`apps/ios/Drivy/SchoolConfigurationAPI/SchoolCommandSendAdmission.swift`, Foundation/Observation seuls :

- `SchoolCommandSendPhase` : `waiting`, `handedToTransport`, `cancelledBeforeSend`, `cancellationStorageFailed`.
- `SchoolCommandCancellationResult` : `cancelledBeforeSend`, `alreadyHandedToTransport`, `storageFailure`.
- `SchoolCommandAdmissionFailure` : `cancelledBeforeSend`, `cancellationStorageFailed`, `wrongCommand`.
  Erreur nue, sans `LocalizedError` ni texte d'écran.
- `SchoolCommandSendAdmission` (`@MainActor @Observable`), une commande conservée à l'init, sans jeton, sans
  URL et sans copie mutable du corps.

L'identité comparée est la commande complète (`PendingSchoolCommand ==`) : identifiant, portée, type, version,
octets, horodatage, ressource et intention de suivi. Un même UUID avec un autre corps, une autre époque
d'accès ou une autre version est refusé (`wrongCommand`).

Sémantique :

| Appel | État avant | Effet | État après |
|---|---|---|---|
| `check`, même commande | `waiting` | aucun | `waiting` |
| `check`, même commande | `handedToTransport` | aucun | `handedToTransport` |
| `check`/`handOff`, autre commande | quelconque | `wrongCommand` | inchangé |
| `handOff` | `waiting` | remise | `handedToTransport` |
| `handOff` | `handedToTransport` | idempotent (répétition 401) | `handedToTransport` |
| `cancel`, retrait réussi | `waiting` ou `cancellationStorageFailed` | ferme puis retire | `cancelledBeforeSend` |
| `cancel`, retrait échoué | idem | ferme, annonce l'échec | `cancellationStorageFailed` |
| `cancel` | `cancelledBeforeSend` | idempotent, aucun second retrait | inchangé |
| `cancel` | `handedToTransport` | aucun retrait | `handedToTransport` |
| `check`/`handOff` | `cancelledBeforeSend` | `cancelledBeforeSend` | inchangé |
| `check`/`handOff` | `cancellationStorageFailed` | `cancellationStorageFailed` | inchangé |

Les trois méthodes sont synchrones sur MainActor : l'état est écrit avant le callback de retrait, et aucune
suspension ne sépare le verdict de la remise. Le callback ne reçoit jamais qu'une commande identique à celle
de l'init ; une reprise du retrait ne réécrit ni corps, ni version, ni horodatage.

## 3. Câblage client

`SchoolPlanningClient.send(_:admission:)` gagne un paramètre facultatif, compatible avec tous les appels
existants. Une admission n'est acceptée que pour `createLesson` et `moveLesson` ; toute autre famille est
refusée localement (`SchoolPlanningFailure.invalidResponse`) avant jeton et réseau.

Points de contrôle propagés uniquement à cette écriture (`request`/`perform` reçoivent l'admission) :

1. `send` : `check` après les validations existantes, avant toute demande de jeton.
2. `request` : `check` juste après l'obtention du jeton (première tentative et renouvellement), avant `/me`.
3. `perform` : `check` après `/me`, puis la barrière L1b existante (`requireAdmissibleLessonStart`).
4. `handOff` immédiatement avant `transport.send`, après construction de la requête.

Conservés tels quels : `/me` et la vérification de portée, refus 401/403, un seul renouvellement forcé, même
corps, même `Idempotency-Key`, même `If-Match`, reçu AP72, lectures et `receipt(for:)` (jamais soumis à
l'admission ni au refus de créneau). Un second essai après 401 appelle `handOff` sur une admission déjà
remise : il reste remis et ne redevient pas annulable. Un échec de transport après remise laisse la
commande suivie : l'absence de réponse ne prouve pas l'absence d'écriture.

## 4. Frontière et preuve

- Annulation gagnante avant `handOff` : aucune mutation métier. Des lectures ou un renouvellement peuvent
  déjà avoir eu lieu ; « zéro mutation » ne prétend pas « zéro paquet ».
- Annulation perdante après `handOff` : aucun retrait, `alreadyHandedToTransport`, la preuve AP72 et le
  suivi existants continuent.
- Retrait échoué : l'émission reste fermée (`cancellationStorageFailed`), la commande et sa saisie restent
  dans le coffre, un nouvel appel `cancel` retente le retrait du même record.
- Une commande restaurée ou déjà émise ne doit jamais recevoir une admission neuve : la création de
  l'admission appartient au geste qui vient de conserver la commande (U106-L2), pas à la reprise.
- L'abandon sur 404 et le bouton métier « Annuler la leçon » restent distincts et inchangés.

## 5. Fichiers

- `apps/ios/Drivy/SchoolConfigurationAPI/SchoolCommandSendAdmission.swift` : nouveau, type et transitions.
- `apps/ios/Drivy/SchoolAgendaAPI/SchoolPlanningClient.swift` : paramètre d'admission, contrôles et remise.
- `apps/ios/DrivyTests/SchoolCommandSendAdmissionTests.swift` : nouveau, sémantique de la barrière.
- `apps/ios/DrivyTests/SchoolPlanningAdmission106Tests.swift` : nouveau, câblage client et courses.
- `docs/implementation/planning-send-admission-106-20261105.md` : ce rapport.

Aucun workspace/vue, store/outbox, format persistant, API serveur, capture/GPS, autre famille de commandes,
dépendance, workflow, projet XcodeGen, `STATUS.md`, registre ou dossier de conception modifié.

## 6. Tests préparés (écrits avant l'implémentation)

Barrière : attente sans remise sur `check` ; remise sur `handOff` ; refus d'une autre commande y compris
même UUID avec autre corps, autre version ou autre portée ; retrait du record exact et fermeture ; répétition
idempotente ; échec de retrait puis reprise sans réécriture ; remise finale, `cancel` sans callback et
répétition `handOff` après 401 ; **remise réentrante refusée pendant le callback de retrait** (la tentative
`handOff` sur la même commande lève `cancelledBeforeSend`, n'aboutit pas et n'émet rien, l'état est déjà
fermé avant le callback).

Client : admission facultative pour les appels existants ; annulation avant jeton (zéro jeton, zéro requête) ;
annulation pendant le jeton (aucune requête, aucun `/me`) ; annulation pendant `/me` (zéro mutation, une
lecture déjà faite) ; annulation après remise pendant que le transport tient la mutation (course perdue,
aucun retrait, reçu et suivi conservés) ; annulation pendant le renouvellement après 401 (deux écritures
identiques en corps et `Idempotency-Key`) ; retrait échoué puis réussi (record exact, autre record intact,
aucune réécriture) ; autre commande ou autre portée refusée avant jeton ; admission refusée pour une autre
famille ; lectures et AP72 non soumis à la barrière ; garde L1b toujours appliquée avant `handOff` ;
reprise après refus avant remise (mêmes octets, même admission) ; reprise après échec de transport (admission
déjà remise, requête identique). Les doubles comptent séparément lectures et mutations et ne touchent ni
compte ni serveur réel.

### Correction 1/2 : harnais borné

Aucun code produit ni signature n'a changé depuis `d5c9dee0` ; seuls les deux fichiers de tests et ce
rapport sont corrigés. Les retenues du jeton, de `/me` et de l'écriture ne sont plus des continuations nues :

- `BoundedHold` porte une échéance interne (5 s par défaut), échoue explicitement (`timedOut`) au lieu
  d'attendre indéfiniment, refuse une seconde attente concurrente (`duplicateWait`) et mémorise une
  libération arrivée avant l'enregistrement de la continuation. `release()` est idempotente et annule son
  minuteur ; elle ne produit jamais un succès métier.
- `requireArrival` borne l'attente d'arrivée à 3 s et lève `arrivalTimedOut` ; le test enchaîne une condition
  `#require` au lieu de se fier au retour silencieux de `HubFixture.wait` (inchangé, non modifié).
- `boundedValue` borne la terminaison de l'opération (10 s) avec une course indépendante : la première issue
  gagne, l'échéance publie un échec explicite puis annule la tâche. Aucun groupe de tâches, aucune jointure
  d'une tâche non coopérative ne décide du verdict.
- Chaque tâche d'envoi est créée puis immédiatement suivie de `defer { hold.release(); attempt.cancel() }`,
  avant toute attente : une assertion qui interrompt le scénario libère les retenues et annule l'opération.
- Contrôles du harnais : une retenue jamais libérée échoue explicitement à son échéance ; une opération qui
  n'atteint jamais la retenue échoue sur l'arrivée bornée puis est libérée/annulée ; une opération qui ne
  termine jamais est rejetée par la borne externe, échéance publiée puis tâche annulée (confirmation bornée) ;
  une libération arrivée avant l'attente n'est pas perdue et ne suspend rien.
- Toutes les assertions métier et tous les compteurs lectures/mutations sont conservés.


### Exécution Apple requise (NON EXÉCUTÉE)

Aucun `swift`, `swiftc` ni `xcodebuild` dans ce worktree Windows : aucun RED/GREEN, aucune compilation et
aucun résultat Apple ne sont revendiqués. Le projet `apps/ios/Drivy.xcodeproj` est généré à partir de
`apps/ios/project.yml` (sources par dossier, nouveaux fichiers pris en compte) et n'est pas versionné ici.

```sh
xcodebuild test -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DrivyTests/SchoolCommandSendAdmissionTests \
  -only-testing:DrivyTests/SchoolPlanningAdmission106Tests
```

Puis la suite `DrivyTests` complète au même SHA, en particulier `SchoolPlanningRecovery106Tests`,
`SchoolPlanningBookingTests`, `SchoolPlanningLeaveWhileSendingTests`, `SchoolPlanningDefaultsTests`,
`SchoolPlanningNextSlotTests`, `SchoolStartNowClientTests`, `SchoolCommandScopes106Tests` et
`SchoolCommandOutboxTests`. Aucun résultat antérieur n'est réutilisé comme vert.

## 7. Limites et restes

- Le pilote ne qualifie que `createLesson`/`moveLesson` d'un premier geste ; les autres familles gardent
  leur contrat et ne reçoivent aucune admission.
- Les doubles sont synthétiques : ni PostgreSQL, ni réseau réel, ni capture de paquets. L'absence de
  mutation est comptée sur le transport du test, pas observée sur un serveur.
- La création de l'admission, le bouton « Annuler l'envoi », le texte « La demande est déjà transmise… »
  et la gestion de génération de geste appartiennent à U106-L2 (workspace/vue), hors de ce lot.
- VoiceOver, Dynamic Type, rendu, latence et comportement batterie ne sont ni modifiés ni vérifiés ici.
- Les bornes du harnais (5 s retenue, 3 s arrivée, 10 s opération) ne s'appliquent qu'aux chemins d'échec ;
  un scénario nominal libère immédiatement. Elles restent non compilées et non exécutées sous Windows.
- `STATUS.md`, le registre, la conception, l'OpenAPI et les workflows restent inchangés.

Commit local : relevé après rédaction de ce document et rapporté au coordinateur avec le SHA exact.
