# Lot A iOS : planification (#109), préférences de planification (#110, natif), invitations (#121, natif)

2 novembre 2026. Branche `claude/lot-a-ios-planif`, base `0312e768` (master). Natif seulement : le web de l'administration (disponibilités, absences, invitations) appartient à un autre lot. Aucun déploiement, aucune PR, aucune campagne de tests lancée (l'IPA d'essai prouve seulement la compilation).

Ce document commence par l'audit case par case, écrit avant tout changement de code. La section « Réalisé » à la fin est complétée au fil des commits.

## Cadre lu

- Garde-fous du dépôt : droits relus au serveur, aucun succès avant écriture durable, peu de texte à l'écran, aucun secret dans les journaux.
- Déjà livré (`reactivite-lots-20261028.md`, `reactivite-native-106-107-119-20261026.md`) : file par domaine dans le coffre chiffré (`SchoolCommandDomain` : `.teaching`, `.invitations`, `.planningPreferences`), reçus AP72. STATUS : « planification optimiste (#108-#110) non faite ».
- Seul le coffre `EncryptedSchoolCommandOutbox` conserve une intention avant émission. Une demande ne quitte le coffre que par un reçu valide (`PendingSchoolCommand.matches`), un refus définitif du serveur, ou l'abandon explicite d'une demande que l'école déclare ne pas connaître (404 du reçu).

## #109 — Créer, déplacer et annuler une leçon

Code audité : `SchoolPlanningWorkspace.swift` (`submit`, `transmit`, `verify`, `retry`, `reloadConfirmedLesson`, `canMutate`, `canRetry`), `SchoolPlanningView.swift`, `SchoolPlanningClient.send`, tests `SchoolPlanningBookingTests`, `SchoolPendingRequestResolutionTests`, `SchoolPlanningAvailabilityTests`.

| Case d'acceptation | Constat dans le code | Verdict |
| --- | --- | --- |
| Latence 15 s : retour visuel immédiat | `submit` pose `pending` avant tout `await`, puis `transmit` passe `isBusy` ; la feuille affiche « Confirmation par l'école… » et le bouton un indicateur. Le libellé ne dit pas laquelle des trois actions est en cours. | Immédiat, libellé à préciser (« Planification / Déplacement / Annulation en cours ») |
| Latence 15 s : consultation possible | « Fermer » est désactivé tant que `isBusy`, et `interactiveDismissDisabled` aussi : la feuille est verrouillée pendant l'envoi. Aucune représentation provisoire dans l'agenda (#108 non livré). | Écart réel, voir « Décision » |
| Latence 15 s : demande retrouvable | Intention écrite dans le coffre chiffré avant l'émission. Rouvrir une feuille de planification relit `pending(for:domain: .teaching)` et propose Vérifier / Réessayer / Abandonner. Aucun repère hors de cette feuille. | Retrouvable, sans repère passif |
| Double appui sans doublon | `canMutate` est faux dès que `pending != nil` ; `submit` exige `canMutate`. Un second appui, même concurrent, ne produit pas de seconde commande ; le coffre refuse de toute façon une seconde commande du même domaine. Aucun test dédié. | Correct par construction, test à écrire |
| Deux utilisateurs, même créneau | Le client n'écrit « enregistré » qu'après le reçu valide puis la relecture de la leçon ; `confirmedLesson` n'est jamais rempli par une demande incertaine ou refusée. Refus de créneau : `needsReload`, aucune leçon exposée. Tests existants `unknownOrRejectedBookingNeverExposesALesson`, `rejectedBookingRequiresReloadBeforeAnotherConfirmation` (SLOT_CONFLICT). | Prouvé par tests existants |
| Réponse perdue après commit | `send` ne retire rien du coffre sans reçu ; sans reçu l'écriture reste « à vérifier », jamais refusée (`aWriteWhoseProofIsMissingStaysQueued…`). `verify()` règle ensuite la demande. Pas de test qui enchaîne réponse perdue, vérification, puis absence d'un deuxième POST. | Correct, test d'enchaînement à écrire |
| Déplacement deux fois | La seconde écriture porte une version périmée : 412 `VERSION_CONFLICT` devient `.conflict` (refus définitif, `needsReload`). Pas de test dédié au déplacement. | Test à écrire |
| Annulation concurrente | Leçon déjà fermée : `LESSON_CLOSED` / `LESSON_STARTED` ont un libellé. Pas de test dédié. | Test à écrire |
| GET échoué après confirmation | `reloadConfirmedLesson` ne rend jamais la commande incertaine : `writeConfirmed` reste vrai, `confirmedLesson` nil, message « La leçon est enregistrée, mais sa fiche n'a pas pu être chargée », reprise par la relecture seule. Testés : 403 et version plus ancienne. Panne passagère non testée. | Correct, test de panne passagère à écrire |
| Reprise après relance | `load()` lit `pending` sans l'émettre ; tout renvoi est un geste de l'utilisateur (`retry`). Aucun rejeu automatique n'existe. Test d'absence d'écriture au chargement à écrire. | Correct, test à écrire |
| Changement d'école ou de compte | `canRetry` exige `pending.scope == scope` (époque d'accès comprise) ; `pending(for:)` ne voit que l'école et la personne du coffre ; `invalidate()` vide l'état. Note « Tes accès ont changé. La demande initiale reste conservée. » | Correct, test d'une portée différente à écrire |
| Expiration : ne pas rejouer une réservation périmée | `canRetry` ne regarde pas l'horaire : une création ou un déplacement dont `plannedStart` est passé reste renvoyable. Le serveur le refuserait, mais le client ne doit pas le proposer comme un simple « Réessayer ». | Écart réel à corriger |
| Refus qui garde les saisies | `load()` ne réinitialise ni `startsAt`, ni `meetingPoint`, ni la durée, ni l'élève, ni la formation, ni le moniteur ; seul l'accord (`agreementConfirmed`) est redemandé. Non testé. | Correct, test à écrire |
| Cohérence agenda / Aujourd'hui / dossier | `.drivyLessonsDidChange` est publié après reçu ; la leçon relue n'est jamais démarrée (`confirmedMoveExposesTheRereadServerVersionAndNeverAutoStarts`). Le rendu des trois écrans ne se prouve pas sans appareil. | Partiellement prouvé, rendu NOT_EXECUTED |
| Aucun démarrage GPS, aucun état financier fabriqué | Création et déplacement n'appellent jamais la capture ; le prix affiché est celui de la sélection confirmée par l'utilisateur, jamais un résultat. | Prouvé par lecture et test existant |

### Décision pour #109

- À faire : libellés d'avancement propres aux trois actions ; refus de proposer le renvoi d'une création ou d'un déplacement dont l'horaire est passé (il reste vérifiable et abandonnable) ; tests des critères testables listés ci-dessus.
- Non fait, par prudence : libérer la feuille dès que la demande est conservée, avec une ligne provisoire dans l'agenda. Cela demande un propriétaire de la demande qui survive à la feuille (aujourd'hui le modèle est détenu par la vue qui présente la feuille, et six hôtes différents la présentent, dont la capture en direct qui ferme le trajet sur la preuve d'une annulation). Sans compilateur ni appareil, c'est le changement le plus fragile du lot ; il reste à cadrer avec #108.

## #110 — Préférences de planification (natif)

Code audité : `SchoolPlanningSettingsView.swift` (`SchoolPlanningSettingsWorkspace`), `SchoolPlanningPreferencePresentation.swift`, tests `SchoolPlanningDefaultsTests`.

Périmètre natif réel : seulement deux préférences personnelles, la formation et le tarif par défaut. L'app n'a ni écran d'horaires, ni d'absences, ni de durée ou de tampon par défaut ; les disponibilités du moniteur sont lues dans la feuille de planification (lecture seule, renvoi vers le web). Conformément au ticket, aucune de ces fonctions n'est ajoutée au natif. Les cases sur les lignes provisoires d'horaires et d'absences relèvent du web.

| Case d'acceptation | Constat dans le code | Verdict |
| --- | --- | --- |
| Modification visible immédiatement, statut approprié, aucune opération bloquée par une sauvegarde lente | Les deux sélecteurs sont grisés tant que `isBusy` ou `pending != nil`. Pendant un envoi lent, l'utilisateur ne peut plus rien changer. Le statut passe par le bouton occupé et la demande en attente. | Écart réel : sélecteurs bloqués pendant l'envoi |
| Deux changements rapides et réactualisation concurrente convergent, aucun effacement de saisie | Avant envoi : `load(keepingEdits:)` garde la saisie (tests `settingsRetainEdits…`, `aLateDefaultsReadDoesNotEraseNewLocalChoices`). Après un envoi réussi : `load` compare la version enregistrée (ancienne) à la version relue (la nôtre) ; si la saisie a changé entre-temps, il signale à tort « Les préférences ont changé à l'école ». | Écart réel : faux conflit après notre propre écriture |
| Réponse ancienne ne doit pas écraser un réglage suivant | `send` relit avec `keepingEdits: draft != draftAtSend` : la saisie postérieure est gardée, mais elle déclenche le faux conflit ci-dessus. | Même écart |
| Reprise après coupure sans nouvelle clé accidentelle ; demandes périmées à réévaluer | Intention et corps exacts dans le coffre (domaine `.planningPreferences`), même `operationId` et même `If-Match` au renvoi ; `verify()` par reçu AP72 ; 404 : l'école ne la connaît pas, abandon explicite. Un conflit de version (412) retire la demande et relit. | Prouvé par tests existants et lecture |
| Préférence provisoire : préremplit une saisie sans valider une réservation | La feuille de planification lit les préférences confirmées du serveur (`defaults(schoolID:membershipID:)`), jamais le brouillon local. | Prouvé par lecture et test `planningPrefillsCurrentInstructor…` |
| Agenda / préremplissage cohérents sans considérer une intention comme disponibilité confirmée | Une préférence ne touche aucune disponibilité ; le créneau est revérifié par le serveur à chaque réservation. | Prouvé par lecture |
| Ouvrir fictivement un créneau après suppression locale d'une absence | Sans objet côté natif : aucune absence ne s'édite dans l'app. | Hors périmètre natif |
| Conversions fuseau, DST, chevauchements, changement de moniteur | Pas de saisie d'horaire dans ces réglages. La feuille de planification garde ses tests existants (fuseau, tampon, affectation). | Hors périmètre de ces réglages |

### Décision pour #110

- À faire : laisser les sélecteurs actifs pendant l'envoi ; à la réponse, adopter la valeur confirmée comme référence (version du reçu) pour que la saisie postérieure reste un brouillon sans faux conflit ; tests (choix pendant l'envoi conservé, version avancée ailleurs toujours signalée).
- Non fait : fermer la feuille pendant l'envoi (le modèle appartient à la vue). Le web (lignes provisoires d'horaires et d'absences, bannière « À confirmer ») est à un autre agent.

## #121 — Invitations et codes (natif)

Code audité : `SchoolInvitationWorkspace.swift`, `SchoolInvitationsView.swift`, `SchoolInvitationClient.swift`, tests `SchoolInvitationWorkspaceTests`, `SchoolInvitationCodeTests`, `SchoolInvitationClientTests`. Périmètre natif réel : création d'un code élève (l'invitation par e-mail n'est plus proposée, mais reste lisible, renvoyable et révocable).

| Case d'acceptation | Constat dans le code | Verdict |
| --- | --- | --- |
| Retour visuel immédiat sous latence, sans faux membre ni code temporaire | Création : bouton « Création… ». Renvoi : « Création… » (code) ou rien de plus que le bouton occupé (e-mail). Révocation : bouton occupé. Aucune ligne locale, aucun membre, aucun lien, aucun code inventé : `issuedCode` ne vient que de la réponse. Pas de libellé « Renvoi en cours » / « Révocation en cours » sur la ligne ni dans le détail (le web l'a depuis #189). | Garde-fous respectés, libellés d'avancement natifs à ajouter |
| Réponse perdue et double appui : ni doublon ni e-mail non demandé | Intention écrite dans le coffre avant l'émission, mêmes octets et même clé au renvoi (`uncertainCreationSurvivesRecreationAndRetriesIdenticalBytes…`). `mayEdit` est faux dès `pending != nil` ou `isBusy` ; le coffre refuse deux commandes d'invitation à la fois. Aucun renvoi automatique : « Nouveau code » ou « Renvoyer » sont des gestes confirmés. | Prouvé par tests existants |
| Invitation acceptée ou expirée pendant l'opération converge sans ressusciter un lien révoqué | Le serveur arbitre ; le client vérifie `result.status` (révoquée pour une révocation, en attente sinon) et la version avant d'accepter la réponse ; `aLatePageCannotUndoAConfirmedRevocation` couvre une page tardive. | Prouvé par tests existants |
| Refus garde formulaire et destinataire, homonymes par identifiant | Après refus d'une première tentative, la demande quitte le coffre, `needsReload` est levé, les choix de permis et de moniteur sont conservés (`selectedOfferingIDs` recoupés avec la relecture, jamais vidés). Les moniteurs homonymes portent une référence courte (`HomonymReference`) et sont choisis par identifiant. | Prouvé par lecture, un test de conservation à écrire |
| Changement de compte et relance ne divulguent ni ne rejouent les secrets d'une autre portée | `invalidate()` et le refus d'accès vident `issuedCode`, `codeRecovery` et les listes ; un code n'est jamais écrit dans le coffre (la réponse seule le porte) ; `canRetryPending` exige la même portée. Tests `changedScopeBlocksResend…`, `accessRevocationPurges…`. | Prouvé par tests existants |
| Éviter qu'une opération bloque tout l'annuaire | La lecture, la recherche, le filtre et la sélection restent utilisables pendant une opération ; « Afficher la suite » et « Fermer » sont désactivés pendant l'envoi, et toute action d'écriture l'est tant qu'une demande est en cours (le coffre sérialise le domaine invitations). | Acceptable, conservé |
| Copier ou partager seulement avec la valeur réellement retournée | `InvitationCodeResultView` ne reçoit que `issuedCode`, effacé à la fermeture. | Prouvé par lecture |

### Décision pour #121

- À faire : état d'avancement natif sur la ligne et dans le détail (« Renvoi en cours », « Révocation en cours », « Création en cours » pour la demande conservée), jamais d'« Envoyé » avant la preuve ; test de la projection d'avancement (une seule invitation concernée, aucun état sur les autres).
- Non fait : libérer l'écran de création pendant l'envoi (même obstacle que #109) ; un seul envoi à la fois reste la règle du domaine invitations.

## Réalisé

À compléter commit par commit.
