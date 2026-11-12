# Épic #472, lot C (#476) : états par pièce, intentions dans le fil, visionneuse alimentée

## Décisions

- Ouverture : suivie par pièce (`openStates[messageID]`), plus de booléen global `opening`. Un second toucher sur la même pièce pendant l'ouverture est ignoré ; une autre pièce reste libre. Chaque ouverture porte un ticket et une époque ; la lecture tourne dans une `Task` conservée, annulée à la fermeture ou à `suspend()`. Un résultat tardif est ignoré.
- Visionneuse : `Preview.state` (`MessagingMediaViewerState`) passe de `loading` à `ready` ou `failed`. `retry-open` relance l'ouverture de la même pièce. Un changement de contexte ou d'accès ferme la visionneuse (`suspend()`).
- Intentions : `MessagingThreadProjection.items(... mediaPending:)` projette les intentions média dans le fil, avec l'identité d'affichage du `clientMessageID`. La bulle confirmée reste jusqu'à l'arrivée du vrai message (`reconcile`), sans doublon ni saut. L'association serveur vers client (`confirmedClientIDs`) est gardée pour la session.
- Phases : `sending`, `toVerify`, `failed(MessagingMediaRuntimeFailure)`, `confirmed(cleanupPending:)`. Un nettoyage local restant reste un succès. Aucun succès avant l'accusé durable.
- Reprise ciblée : bouton par bulle (`messaging.media.retry`), sérialisé derrière l'envoi en cours.
- Le bloc d'erreur du panneau du composeur n'affiche plus la liste des intentions ni « Actualiser les envois ».

## Interfaces

- `MessagingMediaOpenState`, `MessagingMediaOpenFailure`, `MessagingMediaIntentionPhase`, `MessagingMediaPendingEntry`, `MessagingMediaIntentionPresentation`, `MessagingMediaConfirmedIntention` (`MessagingMediaStates.swift`).
- Modèle : `openState(for:)`, `isOpening(_:)`, `open(_:title:stillVisible:)`, `closePreview()`, `phase(of:)`, `timelineEntries`, `reconcile(visibleMessageIDs:)`, `refreshPending()`. `Preview` devient `{ id, messageID, title, state }`.
- `MessagingMediaRuntime` inchangé.
- Identifiants ajoutés : `messaging.media.opening`, `messaging.media.open.error`, `messaging.media.open.retry`, `messaging.media.pending`, `messaging.media.pending.state`. Aucun retiré ni renommé.

## Reste

- Pas d'abandon d'une intention : le runtime figé n'expose pas de suppression durable.
- Bulle locale sans miniature ni citation de réponse ; indicateur indéterminé (aucune mesure d'octets).
- Rien compilé localement. Non essayé : appareil réel, VoiceOver, gestes réels.
- `removeSelection` n'annule plus une ouverture en cours (ligne `opening = false` retirée, zone du lot D).
