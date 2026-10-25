# Messagerie #104 : actions optimistes (lots A, B, C), 25 octobre 2026

Branche `claude/98-messagerie-refonte`, base `d87e7dc` (#100 à #103 présents). Aucun compilateur Swift local : le code est qualifié uniquement par la CI Apple (`refonte-ios.yml`, `unit_only`, `unit_test_scope=all`). Aucune mesure sur appareil, aucun résultat sous latence réelle.

## A. Inventaire des actions

| Action | Endpoint | Contrat | Idempotence | Présentation locale | Persistance de l'intention |
|---|---|---|---|---|---|
| Réaction | `PUT` / `DELETE …/messages/:id/reactions/:emoji` | état souhaité (`active`) | oui (`ON CONFLICT DO NOTHING` / `DELETE`) | immédiate, compteur projeté | mémoire |
| Épingle | `PUT` / `DELETE …/pin` | état souhaité | oui (`messaging_set_pinned`) | immédiate (bulle + bandeau) | mémoire |
| Vote | `PUT …/poll/votes` `{optionIndexes}` | ensemble de mes choix | oui (remplacement) | immédiate + « Vote en cours d'enregistrement » | mémoire |
| Supprimer pour moi | `DELETE …/messages/:id?scope=me` | état final | oui (`ON CONFLICT`, relecture si déjà masqué) | masquage immédiat | mémoire |
| Supprimer pour tous | `DELETE …?scope=everyone` | état final | oui (`deleted_at` déjà posé → retour) | « Suppression en cours », jamais « supprimé » avant relecture | mémoire |
| Clore un sondage | `POST …/poll/close` | action sensible | — | « Clôture en cours », pas d'optimisme | aucune |
| Rôle admin, retrait, réintégration | `PUT`/`DELETE …/general/admins|members/:personId` | action sensible | — | « En cours » sur la ligne, effet après relecture | aucune |
| Signalement | `POST …/reports` `clientReportId` | intention durable | oui (`ON CONFLICT clientReportId`) | inchangé : stockage protégé existant | `MessagingProtectedReports` |
| Sourdine | `PUT …/read-state` `mutedUntil` + `expectedVersion` | version attendue | conflit 409 si version obsolète | état local immédiat, synchro distincte | mémoire |
| Lecture | `PUT …/read-state` | borne monotone | oui | #103 inchangé (coalescé, monotone) | — |
| Envoi, réponse, sondage | `POST …/messages` `clientMessageId` | dédupliqué serveur | oui | bulle locale immédiate après mise en file durable ; envoi réseau non bloquant | `MessagingProtectedOutbox` |

### Envoi de messages (demande du porteur, 25 octobre)

- `sending` ne couvre que chiffrement + `outbox.put`. Le champ et l'aperçu de réponse sont vidés dès cette écriture durable ; en cas d'échec, le brouillon reste.
- `MessagingWorkspace.scheduleSend` : file FIFO par conversation, un seul envoi en vol. Un envoi précédent incertain ou hors connexion retient les suivants pour ne jamais inverser l'ordre serveur ; un refus explicite les libère.
- États de la bulle en attente : En attente → Envoi… → « Envoi lent… » (5 s) → « Non confirmé » + Réessayer (10 s). Hors connexion connu : « En attente de connexion » immédiat, départ automatique à la reconnexion. Refus (`membersChanged`, `conversationUnavailable`, …) : « Échec » + raison, contenu conservé dans la file protégée. `unavailable` / réponse perdue : incertain, jamais refus.
- Réessayer renvoie la même entrée (même `clientMessageId`, dédupliquée par le serveur).
- « Envoyé » (coche) seulement après l'accusé ; la bulle disparaît quand la relecture non bloquante contient `ack.serverMessageID`, le message serveur prend sa place sans trou.
- Le fil reste en bas : `queued.count` qui augmente fait défiler, puis `messages.last` de l'auteur.

## Socle (MessagingWorkspace)

- État confirmé : `messages` (pages serveur). Intentions : `pendingMutations: [MessagingMutationKey: MessagingPendingMutation]`, clé = conversation + message + type (+ emoji). Valeur = état souhaité, identifiant stable, début, statut `.sending/.slow/.unconfirmed/.offline/.uncertain/.confirmed`.
- Projection : `visibleMessages`, `message(_:in:)`, `pinnedMessages` appliquent les intentions par-dessus l'état serveur (`MessagingMutationProjection`). Ajout de « moi » sans doublon : la confirmation ne compte jamais deux fois.
- Une relecture ou une pagination remplace l'état serveur seulement. Une intention en vol n'est jamais retirée par une relecture. Hors vol, elle est retirée quand le serveur reflète l'état souhaité (et qu'elle est confirmée ou incertaine). Une intention confirmée mais toujours absente du serveur après 30 s (`confirmationGrace`, autre appareil plus récent) cède à l'état serveur.
- Choix documenté : après l'accusé, l'intention reste jusqu'à ce qu'une relecture la reflète. Aucun clignotement.
- Refus explicite (`stateConflict`, `conversationUnavailable`, `membersChanged`) : seule cette intention est retirée, erreur sur la bulle (`messaging.mutation.rejected`). `accessChanged`/`contextChanged` : `recordFailure` efface toutes les intentions, rien n'est rejoué sous un autre scope (et `submit` refuse si le scope courant a changé).
- Réponse perdue ou `unavailable` : `.uncertain`, jamais un refus. « Réessayer » renvoie le même état souhaité. Aucun renvoi automatique à l'échéance des minuteries.
- Hors connexion connu (`MessagingConnectivity` → `setNetworkAvailable`) : `.offline` immédiat, sans minuterie, renvoi à la reconnexion et à `refreshVisible`.
- Minuteries `MessagingMutationLatency` (5 s / 10 s par défaut, injectables) : indication seulement.
- `perform()` ne bloque plus sur `loadMessages` : la relecture part en arrière-plan. Une relecture demandée pendant une autre est relancée après.

## B. Réactions

`toggleReaction` lit la projection, pose l'intention puis envoie l'état souhaité. Une seule requête en vol par clé. Si l'utilisateur change d'avis, la boucle renvoie le dernier état souhaité à la réponse (correction finale, ordre garanti sur une même cible). Capsule : opacité réduite après 5 s, suffixe VoiceOver « en cours de synchronisation » / « modification non confirmée » / « en attente de connexion ». #102 conservé : le menu se ferme, la réaction locale arrive 250 ms après.

## C. Généralisation

Épingle, vote, suppression (pour moi / pour tous) passent par le même moteur. Sourdine : `displayedMutedUntil` affiche la demande locale, l'état serveur reprend la main après réponse ou échec (erreur dans `actionError`). Actions sensibles : `operationsInProgress`, aucun effet annoncé avant confirmation.

## Limites

- Intentions en mémoire seulement : perdues à la fermeture de l'app, l'état serveur fait foi au retour. `MessagingProtectedOutbox` ne stocke que des `MessagingPending` chiffrés (messages) ; l'étendre demandait une migration du stockage scellé, hors de ce lot.
- Les autres appareils voient le changement après transmission effective.
- Pas de version par cible côté serveur : la sérialisation par clé et la correction finale remplacent les versions. Deux appareils du même compte peuvent encore se croiser, le dernier écrit l'emporte.
- Tests unitaires avec doubles (`MessagingOptimisticMutationTests`) ; aucune recette réseau 1/5/15 s ni capture (lot D).
