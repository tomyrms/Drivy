# Audit d'accès #120 — connexion, choix d'école, invitation, accueil, déconnexion sous latence

Audit de l'issue #120 (enfant de #105) sur `origin/master` au 3 novembre 2026, branche `tomyrms/lotc-audit-120`, base `17b6b667`. **Lecture seule : aucun code applicatif n'est modifié, aucune migration, aucun contrat.** Les fichiers cités de l'issue ont changé depuis sa rédaction (#118, #121, #123, connexion native par formulaire) : l'inventaire ci-dessous est celui du code actuel, pas celui de la référence `fcfdfde`.

Deux conventions de lecture, utilisées partout dans ce document :

- **Verdict** : *fait* = le comportement de l'« Expérience cible » est présent et complet dans le code ; *partiel* = présent mais incomplet, ou limité à une plateforme/un parcours ; *absent* = rien ne le porte.
- **Preuve** : un test existant est nommé fichier + nom exact ; « non prouvé » signifie qu'aucun test ne le couvre, même si le code le fait. Aucun test n'a été **exécuté** dans cette passe : les noms cités sont lus dans les sources. Ce document ne qualifie donc ni le produit, ni un appareil, ni un déploiement.

## Ce qui a changé depuis la rédaction de l'issue

| Attendu par l'issue | Réalité du dépôt |
| --- | --- |
| `apps/ios/Drivy/SchoolUI/SchoolWorkspace.swift` | existe, 945 lignes, y compris la purge et les générations (`SchoolWorkspace.swift:119-137`, `:517-560`, `:881-894`) |
| `SchoolUI/SchoolRootView.swift` | existe, 886 lignes ; porte les feuilles d'accès, la déconnexion et la portée GPS |
| `Identity/IdentitySession.swift` | existe ; connexion native par mot de passe ajoutée (`IdentitySession.swift:113-154`) |
| `SchoolJoinAPI`, `SchoolJoinUI`, `SchoolProfileUI` | existent ; deux parcours distincts « code » et « lien », chacun avec son journal chiffré |
| `account-entry.tsx` | devenu `apps/web/client/portal/entry/account-entry-panel.tsx` + `use-account-entry.ts` (#319) |
| `school-opening.tsx` | devenu `apps/web/client/portal/opening/opening-page.tsx` + `use-school-opening.ts` ; modèle pur `apps/web/client/school-opening-model.ts` |
| `identity-confirmation.tsx` | devenu `apps/web/client/identity-confirmation-model.ts` (messages seuls) + `portal/entry/invitation-view.tsx` |
| `invitation-model.ts` | existe côté web (`apps/web/client/invitation-model.ts`) et pour l'acceptation par lien côté API |
| README (PKCE/CSRF, invitations, sessions BFF) | `apps/web/README.md:21` (PKCE S256), `:35-42` (contrat BFF), `:90` (relais de gestion) |

## Expérience cible, point par point

### 1. Réactivité des écrans, chargement limité à l'étape, formulaire ouvert sans attendre la liste scolaire

**Web — partiel.**

- Validation de forme pure, avant tout réseau : `entry-model.ts:94-112` ; les erreurs ne s'affichent qu'après une soumission et le premier champ fautif prend le focus (`account-entry-panel.tsx:12-22`).
- L'attente est portée par l'action elle-même, pas par la page : `account-entry-panel.tsx:36-40` (`Connexion…`, `Vérification…`, `Création…`). Une seule action est en vol à la fois (`use-account-entry.ts:47-57`).
- Le formulaire de connexion d'un visiteur n'attend que la lecture de session, jamais `/me` (`entry-page.tsx:55`, `use-entry-session.ts:51-79`).
- **Mais** « J'ai un code » d'une personne connectée est rendu *dans* la liste des écoles (`schools-view.tsx:38`), elle-même montée seulement après `/me` (`entry-page.tsx:58`) : ce formulaire attend donc la lecture complète des écoles, et la page entière affiche un squelette pendant `/me` (`entry-page.tsx:51-53`). L'ouverture d'école, elle, attend `boot()` (`opening-page.tsx:28`), qui enchaîne session, admission du jeton et aperçu (`use-school-opening.ts:38-58`).
- Preuve : `apps/web/test/account-entry-route.test.ts` › « une invitation et une ouverture quittent la gestion pour continuer le code reconnu » ; `apps/web/test/school-opening-model.test.ts` › « les erreurs de saisie ciblent les champs avant toute création, sans confondre refus et réponse perdue ». **Aucun test sous latence** sur l'entrée réelle (les scénarios `slow` sont ceux de l'aperçu synthétique, `apps/web/client/portal/preview/entry-transport.ts:42`).

**iOS — fait.**

- Chaque écran porte son propre `isBusy` et un libellé d'attente dans le bouton : `SchoolAccessCodeView.swift:182-211`, `SchoolSignInLanding.swift:55-70`.
- Les feuilles d'accès s'ouvrent sans lire l'école : « J'ai un code » avant connexion (`SchoolRootView.swift:380-385`), après connexion (`:429-445`), et depuis un compte sans école (`:689-693`). Le parcours code ne lit que le principal (`SchoolCodeJoinWorkspace.swift:41-59`). Nuance à noter : la feuille « lien » n'active son champ qu'après la lecture du principal (`SchoolJoinView.swift:69`), donc attend l'identité — jamais l'école.
- Pendant un envoi, seule la feuille concernée se verrouille (`SchoolJoinView.swift:36-41`, `SchoolOpeningView.swift:100-104`) ; la saisie du code n'est refusée que pendant l'envoi et redevient possible ensuite (`SchoolAccessWorkspace.swift:53-68`).
- Preuve : **non prouvé** (aucun test de latence sur ces écrans).

### 2. Connexion : aucun état authentifié local avant preuve, session réellement valide, réponses hors ordre, annulation, erreurs compréhensibles

**Web — fait.**

- Les jetons OIDC ne quittent jamais le serveur (`session.ts:11-15`, `apps/web/README.md:35`), le cookie est `__Host-`, `Secure`, `HttpOnly`, `SameSite=Lax` (`apps/web/server/app.ts:66-69`).
- `authenticated` est une réponse du BFF (`apps/web/server/app.ts:180-189`), jamais une valeur locale ; chaque lecture repasse par `accessToken` (`apps/web/server/app.ts:129-146`).
- Callback lié au cookie, `state` unique, transaction consommée une fois (`apps/web/server/app.ts:320-341`) ; après connexion, session et CSRF sont renouvelés (`apps/web/server/app.ts:219-225`, `session.ts:54-68`).
- Réponses hors ordre écartées par génération (`use-entry-session.ts:98-120`, `:51-55`), et une restauration d'historique n'est pas une vérification d'autorisation (`use-entry-session.ts:124-131`).
- Erreurs compréhensibles et bornées : `protocol.ts:113-143`, `identity-confirmation-model.ts:3-13`, `entry-model.ts:65-81`.
- Preuve : `apps/web/test/bff.test.ts` › « cookie __Host Secure HttpOnly SameSite, aucun jeton ni sujet OIDC au navigateur », « le callback est lié au cookie, state et délai et consommé une fois », « expire après inactivité et interdit de restaurer une session détruite pendant un refresh », « partage un seul refresh concurrent, puis relit API pour chaque demande », « garde la session pendant une panne du fournisseur d'identité, la ferme sur un refus », « l'invite de mot de passe n'est demandée que pour se réauthentifier ou après une déconnexion » ; `apps/web/test/reauth-bff.test.ts` › « un autre compte est refusé avant rotation et son nouveau jeton est révoqué », « une déconnexion pendant la vérification ne ressuscite pas la session ».

**iOS — fait.**

- La session n'est annoncée connectée qu'après écriture au Trousseau : `IdentitySession.swift:95-104` (navigateur) et `:132-144` (mot de passe).
- Une restauration ne rend la main qu'après renouvellement du jeton (`IdentitySession.swift:46-53`) ; un refus du fournisseur ferme la session (`:64`). Le seul cas où `isAuthenticated` reste vrai sans preuve fraîche est la panne du fournisseur (`:59-63`) — voir risque **S2**.
- Réponses hors ordre : génération changée avant annulation et relecture à chaque reprise (`IdentitySession.swift:72-79`, `:120-130`, `:163-168`, `:188-189`) ; `signOut` change la génération avant d'annuler (`:266-271`).
- Annulation silencieuse et erreurs fournisseur assainies (`IdentitySession.swift:107`, `:157`, `:290-293`).
- Preuve : `IdentityTests.swift` › `noConfigurationAndStorageFailureNeverAcknowledgeLogin`, `logoutRejectsLateRefreshAndCannotRestoreDeletedSession`, `logoutRejectsLateAuthorizationWithoutSpuriousError`, `restoreKeepsAnAuthorizedSessionWhileTheIdentityProviderIsUnreachable`, `restoreStillAsksToSignInAgainWhenTheProviderRefusesTheSession`, `concurrentTokenRequestsShareOneRefresh`, `providerErrorsAreSanitizedAndCancellationIsSilent` ; `NativeAccountTests.swift` › `passwordSignInIsDurableBeforeBeingAnnounced`, `refusedCredentialsSayItWithoutDetailAndKeepNothing` ; côté vue, `DrivyUITests/SchoolSignInFeedbackUITests.swift` › `testNetworkFailureStaysAtFormLevelWhenTheEmailChanges`, `testRateLimitDoesNotDisappearWhenThePasswordChanges` (tests d'interface sur runner Apple, non exécutés ici).

### 3. Choix d'école : purge immédiate, données de la nouvelle portée seulement, revalidation avant mutation, ancienne réponse ignorée

**Web — partiel.**

- Le web n'a pas d'écran de choix d'école : la console se sélectionne par URL (`/app/gestion/{schoolId}/…`), et chaque couple méthode + chemin est déclaré puis revérifié (`apps/web/server/app.ts:457-493`, `apps/web/README.md:80-90`).
- L'API relit les droits à chaque appel, y compris après révocation (`apps/api/test/g1a.integration.test.ts` › « révocation relue en base malgré JWT encore valide », « fin d'affectation et retrait de rôle coupent immédiatement les lectures »).
- La purge au changement de contexte existe dans la console (`apps/web/test/console-access.test.ts` › « changer d'école ou fermer la console invalide une lecture déjà partie », « une réponse scolaire tardive ne remplace pas un refus scolaire plus récent »).
- **Mais** le parcours d'entrée ne montre aucun choix : `/me` rend la liste (`use-entry-session.ts:80-88`) et le seul geste est un lien vers la console (`schools-view.tsx:43-44`). Le critère « sélection et navigation réagissent » n'a donc pas d'objet côté web, et rien ne prouve une purge d'écran d'école à école côté web hors console.

**iOS — fait.**

- Le changement d'école vide l'ancienne portée avant la lecture (`SchoolWorkspace.swift:519-536`, `:881-894`) ; une nouvelle `schoolScope` écarte toute réponse en vol (`:537-541`, `:555-559`).
- Les droits sont relus et comparés (rôle, autorisations, époque d'accès) avant de recharger (`SchoolWorkspace.swift:178-218`, en particulier `:204-210`).
- Les feuilles ouvertes sont refermées dès qu'elles ne correspondent plus à la portée courante (`SchoolRootView.swift:748-761`), et la portée GPS suit le compte et l'école (`:763-785`).
- Preuve : `SchoolWorkspaceTests.swift` › `switchingSchoolsDropsTheOwnDossierAndRejectsItsLateResponse`, `switchingSchoolPurgesImmediatelyAndIgnoresItsLateResponse`, `latePaginationCannotAppendRowsAfterChangingSchool`, `lateUnauthorizedFromOldSchoolDoesNotPurgeTheNewSchool`, `returnFromWebAppliesNewRolesOnceAndDoesNotRestoreRevokedAccess`, `crossSchoolPayloadNeverEntersTheDisplayedProjection`, `signingOutDiscardsAnAccountResponseAlreadyInFlight`.

### 4. Rejoindre/ouvrir une école : intention liée au code, « Demande en cours », aucun faux dossier, réponse perdue, expiration et révocation

**Web — fait.**

- L'intention vit côté serveur : admission par lien ou par code (`apps/web/server/app.ts:350-355`, `:292-301`), aperçu et confirmation opaque (`apps/web/server/app.ts:387-403`), acceptation avec `operationId` conservé à travers la réponse perdue (`apps/web/server/app.ts:404-432`, en particulier `:421-429`).
- L'ouverture d'école garde le corps, l'identifiant d'opération et la clé d'idempotence (`opening-routes.ts:75-89`, `:46-47`) ; un second envoi avec un corps différent est refusé (`:80`).
- Aucun faux rattachement : le reçu d'acceptation n'est montré qu'à la session qui l'a envoyé (`use-entry-session.ts:233-234`) et l'école n'est annoncée qu'après `acceptedSchema` (`:206-214`).
- État d'attente nommé : « Création non confirmée » + « Vérifier le résultat » (`opening-page.tsx:84-86`), « Vérifier et réessayer » (`invitation-view.tsx:64-69`). Le libellé exact « Demande en cours » n'existe pas (il désigne une affectation, `learner-management.tsx:67`).
- Expiration/révocation : messages distincts (`apps/web/client/school-opening-model.ts:41-57`, `protocol.ts:118-121`) et refus serveur distincts (`apps/api/test/g1c.integration.test.ts` › « révocation, expiration et If-Match ont des résultats distincts sans effet secondaire »).
- Preuve : `apps/web/test/school-opening-bff.test.ts` › « résultat perdu : charge et UUID conservés, modification refusée, renvoi identique et secret effacé après confirmation », « un premier refus métier libère la saisie ; un refus après réponse perdue conserve l'intention » ; `account-bff.test.ts` › « le code conserve la même opération après réponse perdue et ne se remplace pas avant résolution », « un aperçu de code modifié oblige à relire, sans accepter la nouvelle identité silencieusement » ; `bff.test.ts` › « survit à OAuth uniquement côté serveur et GET ne consomme pas », « un second onglet ne peut pas remplacer la cible déjà affichée puis accepter silencieusement » ; API : `g1c.integration.test.ts` › « acceptations concurrentes même opération restituent une seule preuve », « usage unique : un autre compte, puis une concurrence, échouent ; la même personne se reconfirme sans rien recréer » ; `school-opening.integration.test.ts` › « rejeu et récupération sans secret : reçu durable, accès courant relu et aucun doublon », « deux navigateurs et deux identités sur un lien : une seule école créée », « deux clics du même compte : un reçu identique et un seul commit » ; `accounts.integration.test.ts` › « un compte ne se crée qu'avec un code valable, sans le consommer ».

**iOS — partiel.**

- Parcours code : l'intention chiffrée est écrite avant l'envoi, relue avant chaque émission, et la même opération est renvoyée (`SchoolCodeJoinWorkspace.swift:83-99`, `:118-144` ; `SchoolCodeJoinJournal.swift:32-39`, `:69-85`).
- Parcours ouverture : la commande en attente est réutilisée telle quelle (`SchoolOpeningView.swift:46-63`) ; les champs restent figés tant que la réponse manque (`:40-44`, `:89`).
- Aucun faux dossier : après acceptation, le compte est relu et l'école n'est ouverte que si l'adhésion est bien dans `/me` (`SchoolRootView.swift:464-480`, `:467`, `:469-473`).
- États d'attente : panneau « La réponse de l'école n'est pas arrivée. Ta demande est conservée sur cet appareil. » (`SchoolJoinView.swift:134-143`), « Vérifier auprès de l'école » (`:185-189`, `SchoolCodeJoinView.swift:170-175`), « La réponse n'est pas arrivée : la même demande sera renvoyée. » (`SchoolOpeningView.swift:128`). Le libellé exact « Demande en cours » n'est pas utilisé.
- Preuve : `SchoolInvitationCodeTests.swift` › `joiningByCodeSendsTheNormalizedCodeUnderOneOperation`, `anUncertainJoinIsKeptAndVerifiedWithTheSameRequest`, `aRefusedRetryKeepsTheUncertainOperationAndNeverInfersSuccessFromASchoolName`, `aJoinTheSchoolRefusesAsInvalidIsDefinitiveAndLeavesNothingPending`, `aPendingCodeCannotBeResentIfItsEncryptedRecordCannotBeRead`, `aTrainingTheSchoolCouldNotOpenIsAnnounced`, `aRefusedCodeIsExplainedAndNothingStaysPending` ; `NativeAccountTests.swift` › `anInterruptedOpeningReusesTheNameFromTheRestoredNativeSessionWithoutAPerson`.
- **Lacunes** : le parcours **lien** (`SchoolJoinWorkspace`) n'a aucun test ; `SchoolOpeningWorkspace` n'a aucun test de rejeu de la même opération ; `SchoolJoinIdentityTests.swift` ne couvre que la lecture des noms structurés.

### 5. Onboarding : saisies protégées, étape remplie distincte de la formalité validée, pas d'acceptation implicite

**Web — absent.**

- Aucun accueil guidé côté web : une recherche `onboarding` sur tout `apps/web/client` ne rend aucun fichier. Le web porte l'administration (`champs-profil`, `readiness`, `apps/web/README.md:56-57`) et non le parcours d'accueil personnel, qui reste dans l'app. Les consentements (`data-policy`, notices) sont adoptés par l'administration, pas par la personne accueillie.

**iOS — partiel.**

- Progression : chaque étape franchie est enregistrée par une commande versionnée (`SchoolProfileWorkspace.swift:283-292`) et l'achèvement est une commande distincte qui exige l'absence d'action en attente (`:294-299`). Une étape remplie n'est jamais une formalité validée : la revue et la notice viennent du serveur (`:144-221`) et l'API le vérifie (`apps/api/test/g1d.integration.test.ts` › « onboarding propre : noms, revue explicite, facultatifs réellement passables, aucun consentement inventé »).
- Saisies protégées : la requête exacte est écrite dans le journal chiffré **avant** émission (`SchoolProfileWorkspace.swift:327-337`, `SchoolCommandOutbox.swift:302-305`, `:331-349`). En revanche le **brouillon de formulaire** (avant envoi) ne vit qu'en mémoire (`SchoolProfileWorkspace.swift:40`, réinitialisé par `invalidate()` `:136-143`) ; fermer avec des modifications demande une confirmation d'abandon (`SchoolOnboardingView.swift:521-529`) mais un abandon perd la saisie.
- Preuve : `SchoolProfileWorkspaceTests.swift` › `optionalDeviceStepsAndCompletionAreSeparateExplicitCommands`, `uncertainMutationSurvivesRestartWithOriginalBytesAndScope`, `durabilityFailurePreventsEmissionButAllowsReading`, `unauthorizedResponsePurgesDraftButRetainsDurablePending`, `refusedFieldLeavesNoPendingCommandAndKeepsTheDraftForCorrection`, `silentRereadKeepsTheFormOpenAndWhatWasTypedMeanwhile`, `knownJoinIdentitySkipsRepeatedInformationWithoutCompletingTheWelcome` ; `SchoolCommandOutboxTests.swift` › `encryptedRequestSurvivesRecreationAndRetainsExactBytes`, `scopeIsolatesAccountsSchoolsAndServersButPreservesChangedRights` ; interface : `DrivyUITests/SchoolPersonalWelcomeTests.swift` › `testKnownIdentityGoesToFormationAndReviewEditingReturnsToReview`.

### 6. Déconnexion et verrouillage : masquage, purge et révocation séparés, réponse tardive sans reconnexion, intentions jamais rejouées ailleurs

**Web — partiel.**

- `POST /app/bff/logout` détruit la session locale, efface le cookie et demande la révocation du refresh token (`apps/web/server/app.ts:342-349`) ; le client relit le CSRF et attend la confirmation avant d'effacer son état (`protocol.ts:107-111`) ; preuve `apps/web/test/protocol-session.test.ts` › « relit la session et utilise son CSRF courant avant la fermeture », « une session déjà fermée ne demande pas une seconde fermeture ».
- La page se vide immédiatement après la déconnexion (`use-entry-session.ts:172-183`).
- Pas de verrou local côté navigateur (sans objet).
- **Lacunes** : l'échec de révocation est avalé après la destruction de la session (`apps/web/server/app.ts:347`) et le résultat n'est jamais distingué du succès local — voir risque **S7** ; la déconnexion efface aussi l'invitation préparée (`apps/web/server/app.ts:345`, `apps/web/README.md:40`).

**iOS — partiel.**

- Ordre explicite : masquer la portée et fermer les feuilles, puis retirer l'appareil, puis effacer la session (`SchoolRootView.swift:730-739`) ; le jeton n'est retiré que « tant que le jeton d'accès vaut encore » (`:737`).
- Verrou local distinct du logout : l'app ne fait que masquer, la session reste au Trousseau (`AppLock.swift:7-8`, `:61-68`, `:99-109`).
- Un trajet en cours n'est jamais arrêté en silence : la déconnexion demande un accord explicite (`SchoolAccountComponents.swift:75-78`, `:121-124`).
- Une réponse tardive ne reconnecte pas : `SchoolWorkspace.swift:157`, `:190` et `IdentitySession.swift:163-168` ; preuve `SchoolWorkspaceTests.swift` › `signingOutDiscardsAnAccountResponseAlreadyInFlight`, `IdentityTests.swift` › `logoutRejectsLateRefreshAndCannotRestoreDeletedSession`.
- **Lacune** : la révocation distante n'a ni preuve ni résultat distinct — c'est exactement le trou #74 du § suivant.

## Acceptation, critère par critère

| Critère d'acceptation | Web | iOS |
| --- | --- | --- |
| Réseau lent : formulaires utilisables, étape en attente identifiable, aucun faux accès | **Partiel** — attente portée par l'action (`account-entry-panel.tsx:36-40`), un seul envoi en vol (`use-account-entry.ts:47-57`), squelette pendant `/me` (`entry-page.tsx:51-53`) ; **aucun test de latence** sur l'entrée réelle. | **Partiel** — `DrivyBusyLabel` par étape (`SchoolAccessCodeView.swift:182-211`), feuille retenue pendant l'envoi (`SchoolJoinView.swift:36-41`) ; **aucun test de latence** ; preuve fonctionnelle `DrivyUITests/SchoolSignInFeedbackUITests.swift` › `testNetworkFailureStaysAtFormLevelWhenTheEmailChanges`. |
| Double validation du code, réponse perdue et relance : une seule adhésion/école | **Fait** — `opening-routes.ts:75-89`, `apps/web/server/app.ts:404-432` ; tests `school-opening-bff.test.ts` › « résultat perdu… », « un premier refus métier libère la saisie… » ; API `school-opening.integration.test.ts` › « deux clics du même compte : un reçu identique et un seul commit », « deux navigateurs et deux identités sur un lien : une seule école créée ». | **Partiel** — code prouvé (`SchoolInvitationCodeTests.swift` › `anUncertainJoinIsKeptAndVerifiedWithTheSameRequest`) ; lien et ouverture sans test de rejeu ; API commune prouvée (`g1c.integration.test.ts` › « acceptations concurrentes même opération restituent une seule preuve »). |
| Changement d'école, de compte, expiration et anciennes réponses ne montrent jamais le contenu précédent | **Fait** — `use-entry-session.ts:132-146`, `apps/web/server/app.ts:219-225` ; tests `console-access.test.ts` › « changer d'école ou fermer la console invalide une lecture déjà partie », « une ancienne réponse ADMIN ne rétablit pas les écrans après un retrait plus récent », `school-opening-bff.test.ts` › « un autre compte OIDC ne voit aucun reçu confirmé ni données du premier compte ». | **Fait** — `SchoolWorkspace.swift:517-560`, `SchoolRootView.swift:748-761` ; tests `SchoolWorkspaceTests.swift` › `switchingSchoolPurgesImmediatelyAndIgnoresItsLateResponse`, `lateUnauthorizedFromOldSchoolDoesNotPurgeTheNewSchool`, `returnFromWebAppliesNewRolesOnceAndDoesNotRestoreRevokedAccess`. |
| Annuler/reprendre l'onboarding conserve les bons champs sans valider implicitement conditions, permissions ou étapes serveur | **Absent** — aucun onboarding web. | **Partiel** — progression serveur par étape (`SchoolProfileWorkspace.swift:283-292`), brouillon en mémoire seulement, abandon confirmé mais destructif (`SchoolOnboardingView.swift:521-529`) ; tests `SchoolProfileWorkspaceTests.swift` › `optionalDeviceStepsAndCompletionAreSeparateExplicitCommands`, `silentRereadKeepsTheFormOpenAndWhatWasTypedMeanwhile`. |
| Verrou local, logout BFF et révocation distante : résultats distincts et testés ; GPS selon son contrat | **Partiel** — logout confirmé (`protocol-session.test.ts`), révocation non distinguée (`apps/web/server/app.ts:347`) ; pas de verrou local ; GPS hors périmètre web. | **Partiel** — masquage (`AppLock.swift:99-109`) et purge (`IdentitySession.swift:265-281`) distincts et testés (`protectionWindowShowsTheLockThenTheShieldOnlyOverAnOpenSession`) ; GPS arrêté sur accord explicite (`SchoolAccountComponents.swift:121-124`) ; **révocation distante non prouvée** (trou #74). |

### Récapitulatif chiffré

| Plateforme | Fait | Partiel | Absent |
| --- | --- | --- | --- |
| Web (6 points d'expérience + 5 critères) | 4 | 5 | 2 |
| iOS (6 points d'expérience + 5 critères) | 4 | 7 | 0 |

## Risques de sécurité constatés

Aucun n'est corrigé dans cette passe, sauf S5 (3 novembre 2026). Les quatre familles demandées par l'issue sont couvertes ; « aucun constat » est une conclusion, pas une omission.

| # | Famille | Constat | Fichier:ligne |
| --- | --- | --- | --- |
| S1 | Accès local avant preuve (web) | **Aucun constat.** `authenticated` et les droits viennent du BFF à chaque lecture ; le navigateur ne garde ni jeton ni droit. | `apps/web/server/app.ts:180-189`, `:129-146` ; `apps/web/README.md:35`, `:42` |
| S2 | Accès local avant preuve (iOS) | **Résiduel.** Une panne du fournisseur laisse `isAuthenticated` vrai sur la seule foi de la session enregistrée ; aucun contenu d'école n'est montré avant `/me`, mais l'app se présente comme connectée et une exigence de step-up n'est connue qu'à la première lecture. | `apps/ios/Drivy/Identity/IdentitySession.swift:59-63` ; garde d'affichage `apps/ios/Drivy/SchoolUI/SchoolRootView.swift:79-81`, `:699-709` |
| S3 | Réponse tardive qui reconnecte | **Aucun constat.** Générations côté app et côté web ; une restauration d'historique n'est pas une vérification. Résiduels : `boot()` de l'ouverture n'a aucune garde de génération — seules la sérialisation de `perform` et la désactivation des boutons pendant `busy` l'empêchent de courir deux fois. | `IdentitySession.swift:163-168`, `:179`, `:188-189` ; `SchoolWorkspace.swift:157`, `:190` ; `apps/web/client/portal/entry/use-entry-session.ts:98-120` ; `use-school-opening.ts:38-58`, `:60-65` |
| S4 | Intention rejouée sous un autre compte (iOS) | **Aucun constat.** Journaux et file chiffrée indexés par principal ; l'adhésion est relue avant d'ouvrir l'école. | `SchoolJoinJournal.swift:45-48` ; `SchoolCodeJoinJournal.swift:53-56` ; `SchoolCommandOutbox.swift:321-329` ; `SchoolRootView.swift:467`, `:469-473` |
| S5 | Intention rejouée sous un autre compte (web) | **Corrigé le 3 novembre 2026.** L'intention d'ouverture admise survivait à la rotation de session même quand le sujet OIDC changeait ; l'intention d'opérateur, elle, était filtrée par sujet, et l'invitation perdait sa confirmation. Le garde `OPENING_IDENTITY_CHANGED` ne s'armait qu'après le premier envoi, donc une école pouvait être créée sous un compte qui n'avait pas ouvert le lien. Décision du 3 novembre 2026 : un lien d'ouverture appartient au compte qui l'a ouvert — l'identité OIDC (sujet de l'émetteur configuré) est enregistrée dès l'admission, la rotation ne la transfère jamais, et une intention sans identité enregistrée est refusée sans rien créer. Preuve : `apps/web/test/school-opening-bff.test.ts` > « un lien ouvert puis un autre compte connecté : aucune école créée sous ce compte », « un lien ouvert depuis une session déjà connectée reste au compte qui l'a ouvert », « une intention sans identité enregistrée est refusée et ne crée rien », « même compte, nouvelle connexion de session : l'ouverture aboutit ». | `apps/web/server/session.ts:54-72` ; `apps/web/server/opening-routes.ts:39-46`, `:60-65` ; `apps/web/test/school-opening-bff.test.ts` |
| S6 | Fin de session sans révocation | **Constaté.** Détail et option au § suivant. | `IdentitySession.swift:64`, `:192`, `:198` ; `SchoolPushCenter.swift:52-65` |
| S7 | Révocation distante non constatée (web) | **Constaté.** La session locale est détruite, puis l'échec de révocation du refresh token est ignoré : l'écran ne peut pas distinguer « déconnecté » de « révoqué ». | `apps/web/server/app.ts:342-349` (en particulier `:345-347`) ; `apps/web/README.md:40` |
| S8 | Secret dans une URL, un journal ou un stockage local (web) | **Aucun constat.** Fragments retirés avant tout réseau, jeton gardé en mémoire de session serveur, aucune journalisation de requête. | `apps/web/client/school-opening-model.ts:6-12` ; `apps/web/client/invitation-link.ts:4-16` ; `apps/web/server/app.ts:70` ; `apps/web/README.md:37` |
| S9 | Secret dans une URL, un journal ou un stockage local (iOS) | **Résiduel.** Une invitation reçue par code e-mail est reconstruite en URL avec le jeton dans le fragment et conservée en mémoire tant que la feuille vit ; aucun journal, aucune persistance, journaux d'intention au Trousseau (`AfterFirstUnlockThisDeviceOnly`). | `SchoolRootView.swift:353`, `:407-411` ; `SchoolJoinJournal.swift:79-90`, `:83` |

## Le cas #74 dans #120 : fin de session sans déconnexion explicite

Le trou relevé par #74 est un cas de l'axe 6 de #120 (« Déconnexion/verrouillage ») et du critère d'acceptation « Verrou local, logout BFF et révocation distante ont des résultats distincts, explicitement testés ». Il n'ajoute aucun besoin : il nomme un chemin par lequel la révocation distante n'est jamais tentée.

**Le fait.** `SchoolPushCenter.sessionEnding()` (qui appelle `POST /v1/me/push-devices/revoke`) n'a que deux appelants, tous deux gestes explicites : « Se déconnecter » et « Se reconnecter » (`SchoolRootView.swift:738`, `:705`) — vérifié par recherche de symbole sur l'index (3 occurrences, aucune autre). Or `IdentitySession` passe `isAuthenticated` à faux sans passer par `signOut()` dans trois chemins : restauration échouée (`IdentitySession.swift:64`), renouvellement refusé (`:192`), échec d'écriture du Trousseau (`:198`). Dans ces trois cas, le jeton d'appareil reste actif côté serveur : les alertes continuent d'être remises à cet appareil (titre générique, aucun contenu) alors que l'app affiche l'écran de connexion, et aucune révocation n'est possible sur le moment faute de jeton d'accès valide. Le même angle mort couvre l'expiration de session détectée par l'école : `SchoolWorkspace.swift:911-925` (`invalidateAccess`) propose « Se reconnecter » (`SchoolRootView.swift:699-709`), et l'utilisateur qui ferme l'app sans appuyer laisse son appareil inscrit.

**Option proposée — une capacité de révocation propre à l'appareil, sans jeton d'accès.**

À l'enregistrement (`PUT /v1/me/push-devices`), le serveur rend une fois un secret aléatoire de 256 bits lié à la ligne `drivy.push_device` ; seule son empreinte (HMAC à clé serveur) est stockée dans une nouvelle colonne. L'app le garde au Trousseau, à côté du jeton, avec la même protection `AfterFirstUnlockThisDeviceOnly`. Une route anonyme `POST /v1/push-devices/revoke` accepte `{ token, secret }`, compare l'empreinte en temps constant et révoque **cette seule ligne** ; elle est freinée par IP et par jeton comme les autres points d'entrée anonymes. `SchoolPushCenter.sessionEnding()` utilise la route authentifiée quand un jeton vaut encore, la route anonyme sinon — donc aussi bien depuis `restore()`, depuis un renouvellement refusé que depuis un échec du Trousseau, et de nouveau au lancement suivant si le réseau manquait. Toute nouvelle inscription réémet le secret et invalide l'ancien.

Pourquoi cette forme :

- elle ne demande **aucun** jeton d'accès au moment de la fin de session, seule contrainte posée par #74 ;
- elle ne permet pas de révoquer l'appareil d'autrui : le secret est lié à une ligne, et le pire usage d'un secret volé est de révoquer un appareil que son porteur contrôle déjà — le jeton APNs n'est pas un secret d'accès aux données, il ne sert qu'à adresser une alerte ;
- elle n'ajoute aucun état d'authentification local : la capacité ne donne accès à aucune donnée, elle ne fait que retirer un appareil ;
- elle se teste sur PostgreSQL réelle, comme le reste de la file push.

Coût : une migration (colonne + fonction de révocation étendue), une route anonyme, le contrat OpenAPI, le stockage au Trousseau côté app, et deux tests nommés par chemin (authentifié et anonyme), dont un « deux comptes sur le même appareil : le secret du premier ne révoque pas l'appareil repris par le second ».

Deux variantes plus faibles, pour mémoire :

- **Report de la révocation** : garder au Trousseau « token + révocation due » et réessayer à la prochaine connexion, sous le même compte (`push_device_revoke` filtre déjà `person_id`). Aucune route nouvelle, mais l'appareil reste inscrit tant que personne ne se reconnecte, et un autre compte sur le même appareil ne révoque rien (`push_device_claim` réattribue, ce qui protège les alertes mais ne prouve pas la révocation).
- **Expiration d'inactivité côté serveur** : ne plus envoyer à un appareil sans activité depuis N jours. Utile en défense en profondeur, insuffisant seul (le cas #74 est immédiat).

## Découpage proposé

Six tâches, classées par gain décroissant puis risque croissant. Chacune est purement **logique** (serveur, web sans écran, Swift non visuel) ou purement **interface** ; aucune ne mêle les deux.

| # | Tâche | Nature | Gain | Risque | Fichiers touchés |
| --- | --- | --- | --- | --- | --- |
| T1 | Révocation d'appareil sans jeton d'accès (secret de révocation, route anonyme, migration, tests PostgreSQL) | logique | Fort : ferme S6 et rend la révocation réellement possible | Moyen : nouvelle route anonyme, nouvelle colonne, secret local en plus | `apps/api/migrations/<n>_push_device_revoke_secret.sql`, `apps/api/src/notification-preferences.ts`, `Drivy_Conception_v3_17_2026-09-20/04-technique/openapi.yaml` (contrat canonique 3.11.0), `apps/api/contracts/` si une forme de charge change, `apps/api/test/push-device-revocation.integration.test.ts` |
| T2 | App iOS : la fin de session tente la révocation à chaque passage à faux (restauration échouée, renouvellement refusé, échec du Trousseau), secret au Trousseau, reprise au lancement | logique | Fort : le trou #74 disparaît côté app | Moyen : trois chemins de sortie à couvrir, un secret de plus au Trousseau | `apps/ios/Drivy/SchoolUI/SchoolPushCenter.swift`, `apps/ios/Drivy/Identity/IdentitySession.swift`, `apps/ios/Drivy/SchoolUI/SchoolRootView.swift` (accroche de cycle de vie seulement), `apps/ios/DrivyTests/SchoolPushCenterTests.swift` (nouveau) |
| T3 | Web : « J'ai un code » s'ouvre sans attendre `/me` ni la liste des écoles | interface | Fort : critère 1 de l'issue, réactivité perçue | Faible : deux composants d'entrée, aucun contrat | `apps/web/client/portal/entry/entry-page.tsx`, `schools-view.tsx`, `use-entry-session.ts`, `apps/web/test/` (modèle ou test de rendu selon l'outillage existant) |
| T4 | App iOS : un état d'attente nommé et borné par étape sur les quatre feuilles d'accès (accès, code, lien, ouverture), avec reprise si l'attente dépasse | interface | Moyen : critère 1 et acceptation 1 | Faible : vues et libellés seuls | `apps/ios/Drivy/SchoolJoinUI/SchoolAccessCodeView.swift`, `SchoolCodeJoinView.swift`, `SchoolJoinView.swift`, `SchoolOpeningView.swift`, `apps/ios/DrivyTests/NativeAccountTests.swift` |
| T5 | Web : dire ce que la déconnexion confirme — session fermée — et ce qu'elle ne confirme pas — révocation distante — au lieu de les confondre | interface | Moyen : acceptation 5, ferme S7 à l'écran | Faible : une réponse BFF enrichie, un message | `apps/web/server/app.ts`, `apps/web/client/protocol.ts`, `apps/web/client/portal/entry/use-entry-session.ts`, `apps/web/client/portal/entry/entry-frame.tsx`, `apps/web/test/protocol-session.test.ts`, `apps/web/test/bff.test.ts` |
| T6 | Lier l'intention d'ouverture au compte dès l'admission et non au premier envoi (refuser un rejeu sous un autre sujet) | logique | Moyen : ferme S5 | Faible : une comparaison, un test ; à vérifier contre l'usage « lien transmis puis ouvert par un autre opérateur » | `apps/web/server/opening-routes.ts`, `apps/web/server/session.ts`, `apps/web/test/school-opening-bff.test.ts` |

Deux tâches restent hors de ce découpage faute de place, à ouvrir ensuite : le brouillon d'accueil conservé dans le journal chiffré avant envoi (logique, `SchoolProfileWorkspace.swift` + `SchoolSelfProfileIntent.swift`, puis une tâche d'interface pour « reprendre/abandonner »), et le test manquant du parcours lien iOS (`SchoolJoinWorkspace`, `apps/ios/DrivyTests/`).

## Contrôle des citations

Chaque `fichier:ligne` de ce document a été vérifié par script (`node`, lecture seule, hors du dépôt : aucun fichier du dépôt n'a été ajouté pour ce contrôle). Deux passes : la première résout les **107** citations nommées (`fichier:ligne`, nom court résolu en chemin unique du dépôt) et vérifie que le fichier est indexé et que la ligne existe, en affichant son contenu pour relecture ; la seconde rattache les **60** plages écrites `:N-M` au dernier fichier nommé sur la même ligne et vérifie la borne haute. Résultat de la passe : **167 citations, 0 échec, 0 nom ambigu**. Une seule citation a été réécrite après la première exécution (une plage de lignes sans fichier nommé dans son voisinage immédiat, réécrite en `SchoolWorkspace.swift:911-925`).

Recherches Codebase Memory utilisées sur ce worktree (index `C-Users-jtoma-orca-workspaces-Drivy-lotc-audit-120`, mode `moderate`) :

- `list_projects` puis `index_repository` (aucun index préalable pour ce worktree) ;
- `search_graph` : `IdentitySession`, `SchoolAccessWorkspace`, `invalidateAccess`, `useEntrySession` ;
- `search_code` : `sessionEnding` — a établi les deux seuls appelants (`SchoolRootView.accountLanding:705`, `SchoolRootView.signOut:738`), base factuelle du § #74 ;
- `trace_path` : `IdentitySession.signOut` (appelants trouvés : tests seulement — les vues l'atteignent par fermeture, donc aucune arête).

## Ce qui reste à qualifier

- **Aucun test exécuté** dans cette passe : les verdicts reposent sur la lecture du code et sur les noms de tests existants. Une exécution réelle (vitest web/API sur PostgreSQL, `swift test`, tests d'interface sur runner Apple) reste à faire avant de considérer un critère « prouvé ».
- **Rien de physique** : latence réseau réelle, réception APNs, autorisation push accordée puis retirée, GPS, VoiceOver, batterie ne se constatent pas ici et ne sont donc pas affirmés.
- **Le parcours lien iOS** (`SchoolJoinWorkspace`) n'a aucun test : c'est la plus grosse lacune de preuve de cet audit.
- **S5 (intention d'ouverture sous un autre compte)** demandait un arbitrage produit : si un lien d'ouverture peut légitimement être transmis d'un opérateur à un autre, le garde doit porter sur le lien et non sur le compte ; si le lien appartient au compte qui l'a ouvert, T6 le rétablit. Arbitré et corrigé le 3 novembre 2026 : le lien appartient au compte qui l'a ouvert (`apps/web/test/school-opening-bff.test.ts`).
