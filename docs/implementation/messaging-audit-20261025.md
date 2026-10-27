# Audit statique du chemin réel Messages (25 octobre 2026)

Ce qui a été lu : SchoolRootView, MessagingDevelopmentEntry, MessagingInboxView, MessagingConversationView, l'API `apps/api/src/messaging*.ts`. Aucun compilateur Swift local : rien n'est validé sur appareil.

| Fonctionnalité | État | Référence |
|---|---|---|
| Confirmation retirer/réintégrer un membre | CORRIGÉ da89cc5. Deux `confirmationDialog` étaient attachés à la même List et seul le dernier se présentait de façon fiable. Il n'en reste qu'un, piloté par un enum | MessagingThreadViews.swift:7-25, 93 |
| Bulle : « Supprimer pour tout le monde » et « Réagir » (VoiceOver) | CORRIGÉ da89cc5, même cause | MessagingThreadViews.swift:213, 269 |
| Suggestions de mention | CORRIGÉ 5d8bd96. Après l'insertion de `@Nom `, le panneau restait ouvert sur « Aucun participant » | MessagingMentionToken.swift:14 |
| Chargement liste et fil | CORRIGÉ f8543d0. Un seul drapeau `loading` : un rafraîchissement de la liste pendant l'ouverture d'un fil (ou l'inverse) était ignoré en silence | MessagingWorkspace.swift:55, 140 |
| Photo du pair | OK : `peerPersonId` est renvoyé par GET /conversations (aucun schéma de réponse ne le filtre), le photoLoader passe par SchoolWorkspace.loadPhoto | messaging.ts:109, SchoolRootView.swift:654 |
| Aperçus de la liste | LIMITE : l'historique scellé n'est rempli qu'au déchiffrement, donc après l'ouverture de la conversation sur cet appareil. Une conversation jamais ouverte n'a pas d'aperçu et passe en fin de tri | MessagingWorkspace.swift:412 |
| Mentions envoyées | OK : `mentionPersonIds` part dans le POST et est contrôlé par le serveur | MessagingHTTPTransport.swift:127, messaging-routes.ts:19 |
| Alerte de mention | BLOQUÉ : elle dépend de la migration 20261025, qui n'est pas appliquée sur le homelab | migrations/20261025_messaging_mention_push.sql |
| Push messagerie générique | ABSENT : `decideMessagingNotification` et `messagingPushPayload` ne sont appelées nulle part. Aucun push n'est envoyé pour un nouveau message | messaging-notifications.ts:36, 46 |
| Lecture (#103) | OK statiquement : `atBottom` vaut vrai à l'ouverture et `.task(id:)` se relance quand `lastReadableSequence` arrive | MessagingConversationView.swift:94 |
