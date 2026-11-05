# #106 L1b — barrière native de créneau avant émission

Date : 4 novembre 2026. Branche de travail `tomyrms/issues-reprise-native-106`, base
`e2edc85ed092237016620079d52d11eb7a2d02b5` (candidat déjà qualifié Apple 1515/1515 et Linux).
Ce lot complète un mécanisme existant ; il ne crée ni moteur de file, ni écran, ni politique de TTL globale.
Il ne clôture ni L1 entier, ni #106/#131.

## 1. Défaut ciblé et comportement avant/après

Le défaut observé était statique : `SchoolPlanningWorkspace.transmit` vérifiait `canRetry` avant de remettre
la commande au client, puis `SchoolPlanningClient.request` attendait le jeton, `perform` attendait `/me`,
et l’écriture partait sans relire le début demandé. Une création ou un déplacement devenu périmé pendant
ces attentes pouvait donc encore être émis. Par ailleurs `isStaleLessonRequest` répondait `false` quand
`plannedStart` était absent ou illisible : l’absence autorisait implicitement un renvoi.

| Moment | Avant | Après |
|---|---|---|
| Début futur | essai autorisé | essai autorisé, inchangé |
| Début égal à l’horloge | `canRetry` pouvait rester vrai si le début n’était pas encore évalué, puis l’écriture partait | refus local avant tout jeton et avant tout transport |
| Début passé pendant l’attente du jeton | écriture encore émise | refus local après l’attente, aucune écriture |
| Début passé pendant `/me` | écriture encore émise | refus local après `/me`, aucune écriture |
| Début passé avant le second essai après 401 | second POST encore émis | seul le premier 401 a eu lieu ; pas de second POST |
| `plannedStart` absent, non textuel ou illisible | `isStaleLessonRequest == false`, renvoi possible | refus fermé et non définitif |
| Reçu AP72 après expiration | consultable | consultable, inchangé |

La règle est pure et unique : `SchoolPlanningRecoveryPolicy.admission(command, at:)`. Seules
`createLesson` et `moveLesson` sont concernées par `plannedStart`. Un début strictement postérieur à
l’horloge autorise l’essai ; un début égal ou passé, absent ou illisible l’interdit. Aucun TTL arbitraire
n’est introduit et `cancelLesson`, `startLessonNow`, les offres, invitations et autres commandes gardent
leur propre contrat.

## 2. Points d’application

1. `SchoolPlanningClient.send` vérifie la règle avant de demander un jeton, lorsqu’elle est déjà connue.
2. `SchoolPlanningClient.perform` la revérifie juste avant chaque `transport.send` d’écriture, après le
   jeton, après `/me` et après l’éventuel renouvellement 401. Les lectures et `receipt(for:)` ne passent
   pas par cette barrière.
3. `SchoolPlanningWorkspace.pendingIsStale` lit la même horloge injectée que le client ; `canRetry` ne
   propose donc pas un renvoi que le client refusera. Aucun texte ni geste nouveau n’est ajouté.
4. `isStaleLessonRequest` réutilise la règle au lieu de dupliquer le parsing ; ses libellés et le
   comportement des autres types restent inchangés.

Le refus est `SchoolPlanningWriteRefusal.lessonStartNotAdmissible`, sans copie d’écran et sans
`LocalizedError`. Il n’est ni `conflict`, ni `rejected`, ni `notFound` : la commande reste dans le coffre
avec les mêmes identifiants, octets et version, et aucun rollback global n’est déclenché. Une entrée peut
déjà correspondre à un commit dont la réponse a été perdue ; l’expiration ne prouve jamais l’absence
d’enregistrement. La vérification et le reçu AP72 restent disponibles, y compris après l’échéance.

## 3. Fichiers

- `apps/ios/Drivy/SchoolAgendaAPI/SchoolPlanningClient.swift` : horloge injectable (`now`,
  `currentDate`) et barrière de l’écriture uniquement. Droits, authentification, en-têtes,
  idempotence, `If-Match`, renouvellement 401 et reçus inchangés.
- `apps/ios/Drivy/SchoolConfigurationAPI/SchoolPlanningRecoveryPolicy.swift` : nouveau fichier, règle
  pure et refus dédié, sans texte UI.
- `apps/ios/Drivy/SchoolConfigurationAPI/SchoolPendingCommandText.swift` : `isStaleLessonRequest`
  délègue à la règle ; `requestedLessonStart`, les libellés et les autres types sont conservés.
- `apps/ios/Drivy/SchoolAgendaUI/SchoolPlanningWorkspace.swift` : même horloge pour l’affichage du renvoi
  et note d’expiration seulement lorsqu’un début lisible est réellement passé. Aucune View modifiée.
- `apps/ios/DrivyTests/SchoolPlanningRecovery106Tests.swift` : nouveau fichier de tests.

Aucun ajustement de fixture ou d’horloge n’a été nécessaire dans les tests de planification existants :
ceux-ci construisent leurs créneaux relativement à l’instant courant, et les tests du nouveau contrôle
injectent tous une horloge fixe.

## 4. Tests préparés

Le fichier couvre : futur, égalité, passé, début absent, début non textuel et début illisible ; autres
commandes inchangées ; expiration pendant le jeton suspendu, pendant `/me` suspendu et avant le second
essai après 401 ; compteur d’écritures à zéro, ou uniquement le premier 401 ; conservation du même
identifiant, des mêmes octets et de la même version en mémoire et dans le coffre ; reçu consultable après
expiration ; confirmation tardive depuis la feuille ; aucun retrait au refus local ; en-têtes, corps et
`If-Match` du cas nominal futur.

Sur ce poste Windows, aucune compilation, aucun RED/GREEN et aucune exécution Swift ne sont revendiqués :
le worktree ne contient ni `swift`, ni `swiftc`, ni `xcodebuild`. Aucun test Python de substitution n’a
été inventé. Le RED Apple réel est celui du candidat intégré décrit ci-dessous.

### Exécution Apple requise

```sh
xcodebuild test -project apps/ios/Drivy.xcodeproj -scheme Drivy \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:DrivyTests/SchoolPlanningRecovery106Tests
```

Le projet `apps/ios/Drivy.xcodeproj` est celui généré par le workflow à partir de `apps/ios/project.yml` ; il n’est
pas versionné dans ce worktree.

Puis la suite `DrivyTests` complète, en particulier `SchoolPlanningBookingTests`,
`SchoolPlanningLeaveWhileSendingTests`, `SchoolPlanningDefaultsTests`,
`SchoolPendingPlanningProjectionTests`, `SchoolCommandScopes106Tests` et `SchoolLessonAuditTests`.
Les tests doivent être exécutés sur le même SHA que le candidat ; aucun résultat historique n’est
réutilisé comme vert.

## 5. Correction après la première exécution Apple

Run `41962003316`, job `127030313656`, candidat intégré `62560a2e` : compilation réussie, tests réellement
exécutés. Le seul échec de ce fichier était `aFutureCreationWritesOnceWithItsExactHeaders` à la ligne 72 :
`token.calls` valait **2**, l’attente disait **1**. Le reçu, l’unique mutation, les octets et les en-têtes
passaient.

Cause vérifiée dans le source réel, pas une hypothèse : `SchoolPlanningClient.send` émet d’abord la
mutation, puis appelle `receipt(for:)` pour la preuve AP72. Les deux requêtes demandent un jeton par
`accessToken()` ; `/me` utilise `PinnedToken` et ne compte pas dans `RecoveryTokenSource`. Le second appel
de jeton est donc la lecture `GET /operations/{id}` du reçu, pas un second POST. Ce comportement AP72
existait avant la barrière L1b et n’est pas attribué à l’admission optionnelle N106.

Correction apportée, limitée au test : l’attente exacte devient `token.calls == 2`, et la fixture
enregistre désormais les URL des lectures `GET` de reçu. Le scénario vérifie séparément une seule mutation
POST, une seule lecture du reçu pour l’identifiant de la commande, et les mêmes assertions de corps,
`Idempotency-Key`, `Authorization`, `If-Match` et d’horloge. Aucun client, politique ou produit n’est
modifié, et aucune assertion n’a été rendue permissive.

Observation hors périmètre, non modifiée : `SchoolPlanningAdmission106Tests.swift:157` échoue sur
`token.invalidations == 1 && token.calls == 2`. Le même mécanisme AP72 ajoute une demande de jeton après
les deux POST du scénario 401 ; ce fichier appartient à l’intégration N106 et doit être corrigé par son
propriétaire s’il est retenu. Le défaut n’est ni dans le client L1b ni dans la politique N106.

## 6. Limites et restes

- La règle ne qualifie pas une vraie transaction PostgreSQL ni un vrai réseau : les doubles sont
  synthétiques et ne remplacent pas la campagne Apple.
- Aucun écran, texte, geste, navigation, VoiceOver, Dynamic Type ou capture n’est modifié ou vérifié.
- Le reçu absent (404) reste une absence de preuve, pas une preuve d’absence ; aucune annulation fictive
  n’est ajoutée et aucun renvoi automatique n’est déclenché au lancement.
- Ce lot ne traite pas la classification globale de reprise, la durabilité exposée, l’annulation avant
  transport, la réconciliation par champ ou les autres familles de commandes.
- `STATUS.md`, le registre, la conception, l’OpenAPI et les workflows restent inchangés par ce lot.

Commit local : relevé après rédaction de ce document et rapporté au coordinateur avec le SHA exact.
