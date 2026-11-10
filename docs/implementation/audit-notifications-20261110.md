# Notifications fiables — lot G serveur (#429, #448), 10 novembre 2026

Périmètre : API des notifications, migration additive `20261110_push_delivery_event_identity.sql`, tests. Aucun Swift, aucune UI, aucune identité/profil, aucun déploiement. PostgreSQL réelle ; transport APNs remplacé par un expéditeur scripté : **aucune livraison sur appareil n'est revendiquée**.

## #429 — une notification logique par événement distinct

**Cause.** Pour `CourseSeriesCancelled` et `CourseSeriesRescheduled`, la clé de déduplication était `type:version`. Avec `UNIQUE(person_id, dedupe_key)`, deux séries annulées (ou replanifiées) à la même version, dans une même école ou dans deux écoles autorisées, donnaient la même clé : la seconde notification était perdue sans erreur.

**Correctif.** `drivy.course_notifications_tick()` (redéfinie, seul changement par rapport à 046) produit désormais `type:series_id:series_version` pour ces deux événements. La clé porte le type, la série (donc l'école, une série appartenant à une seule école) et la version. Rejouer le même événement redonne la même clé : `ON CONFLICT DO NOTHING` garde une seule notification.

**Transition.** Les événements de l'outbox déjà traités ne sont jamais relus ; aucune notification existante n'est modifiée ni supprimée ; les anciennes clés `type:version` restent telles quelles et ne servent plus que de trace. Aucune réémission massive : testé en compteur de lignes avant/après deux ticks. Un événement nouveau de même type et même version crée sa propre notification sans heurter l'ancienne.

**Identifiant de regroupement APNs.** `collapseIdFor` conserve la clé telle quelle jusqu'à 64 octets, sinon la condense par hachage (stable, distincte par clé) : les nouvelles clés avec UUID dépassent la limite.

## #448 — état d'envoi par destination

**Modèle.** Table `drivy.push_delivery` (PK `notification_id, device_id`). États : `PENDING` (reprise valide), puis terminaux `SENT` (accepté), `REJECTED` (erreur définitive, jeton invalide), `REVOKED` (appareil révoqué ou repris, droit ou préférence retirés), `EXPIRED` (échéance de la notification ou politique de reprise épuisée, `RETRY_EXHAUSTED` après 5 envois). Contrainte : `PENDING` ⇔ `completed_at` nul. RLS forcée ; le rôle du service lit, insère et ne met à jour que `status, attempts, failure_code, completed_at`. Un déclencheur ferme les destinations `PENDING` quand une notification quitte `PENDING` (ignorée, expirée, en échec), sans destination orpheline.

**Comportement (cours et messagerie, même moteur).**
- Les destinations sont créées au premier passage pour les appareils actifs ; un appareil enregistré ensuite ne reçoit pas une alerte ancienne.
- Seules les destinations `PENDING` sont reprises : A acceptée n'est jamais renvoyée, y compris après redémarrage du service (l'état vit en base).
- Avant chaque tentative : droits, préférences et événement revalidés (`push_revalidate`, instantané messagerie) ; appareil relu (révoqué ou repris par une autre personne → `REVOKED`, sans envoi).
- Un jeton invalide devient `REJECTED`, l'appareil est révoqué, les autres destinations continuent, aucune boucle.
- La notification reste `PENDING` avec attente exponentielle tant qu'une destination est `PENDING`. Close globale : `SENT` si au moins une destination est `SENT`, sinon `FAILED` (`APNS_UNAVAILABLE` si reprises épuisées, `NO_VALID_DEVICE` sinon).
- Une transaction par notification (ou groupe de messagerie). Si le transport lève après qu'un résultat est écrit, ce résultat est conservé et seule la suite est reprise ; sans résultat écrit, l'unité est annulée comme avant.
- Aucun jeton ni contenu dans les logs : l'état n'enregistre que des codes (`APNS_RETRY`, `INVALID_TOKEN`, `RETRY_EXHAUSTED`, `DEVICE_UNAVAILABLE`).

## Qualification

Base `drivy_test` PostgreSQL isolée (conteneur local). Nouveaux tests :
- `push-reliability-20261110.integration.test.ts` (16) : #429 série×2 annulation, ×2 replanification, deux écoles, rejeu, transition ; #448 cours : A/B avec redémarrage, aucune clôture prématurée, jeton invalide, épuisement, échec global, appareil révoqué/repris, préférence retirée, échéance, exception du transport, appareil tardif.
- `messaging-push-multidevice-448.integration.test.ts` (4) : chemin messagerie, mêmes scénarios clés.
- Résultat observé : 20/20 réussis après correction de tests (erreurs de fixture et d'ordre des destinations, pas du produit).

Suites voisines (push, notifications, messagerie, révocation d'appareil, `course-upgrade`) : réussies. `messaging-push-coalescing` : l'assistant de vieillissement vieillit aussi `push_delivery.completed_at`, assertions inchangées. `npx tsc --noEmit` et `npm run build` : sortie 0.

## Limites

- **NON EXÉCUTÉ** : `course-worker-process.integration.test.ts` exige Node 24 ; la machine fournit Node 26. Le « redémarrage » des tests est simulé par fermeture et réouverture du pool, non par un processus réel.
- Résiduel at-least-once : un crash entre l'envoi APNs accepté et l'écriture du résultat peut renvoyer à cet appareil une fois.
- La non-modification de l'ordre des destinations n'est pas contractuelle (ordre `created_at, device_id`).
- Aucun essai APNs réel, aucun déploiement, pas de campagne globale ; STATUS.md non touché.
