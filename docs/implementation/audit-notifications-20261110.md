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
- Avant CHAQUE envoi, la première destination de chaque alerte comprise (une alerte du même groupe de messagerie a pu attendre l'envoi d'une autre depuis la lecture de ses faits) : droits, préférences, échéance et événement revalidés (`push_revalidate` pour les cours, instantané messagerie) ; appareil relu juste avant son envoi, jamais depuis un instantané pris avant la boucle (révoqué ou repris par une autre personne → `REVOKED`, sans envoi). Si l'autorisation est perdue, la notification est close et ses destinations restantes avec elle. C'est un contrôle par tentative, pas un contrôle préalable de toute la liste ; un intervalle incompressible subsiste entre la relecture et l'envoi réseau.
- Un jeton invalide devient `REJECTED`, l'appareil est révoqué, les autres destinations continuent, aucune boucle. La révocation est gardée par version : elle n'a lieu que si jeton, personne, environnement et `last_seen_at` (modifié à chaque réenregistrement, y compris même personne avec nouveau secret) sont ceux lus avant l'envoi ; une réponse tardive ne révoque pas un enregistrement renouvelé. Les destinations sont traitées par `device_id` croissant : deux notifications concurrentes verrouillent les appareils communs dans le même ordre (pas d'interblocage).
- La notification reste `PENDING` avec attente exponentielle tant qu'une destination est `PENDING`. Close globale : `SENT` si au moins une destination est `SENT`, sinon `FAILED` (`APNS_UNAVAILABLE` si reprises épuisées, `NO_VALID_DEVICE` sinon).
- Une transaction par notification (ou groupe de messagerie). Si le transport lève après qu'un résultat est écrit, ce résultat est conservé et seule la suite est reprise ; sans résultat écrit, l'unité est annulée comme avant.
- Aucun jeton ni contenu dans les logs : l'état n'enregistre que des codes (`APNS_RETRY`, `INVALID_TOKEN`, `RETRY_EXHAUSTED`, `DEVICE_UNAVAILABLE`).

## Qualification

Base `drivy_test` PostgreSQL 17 réelle (conteneur local `drivy-audit-planning-pg`), runtime **Node v24.22.2** (archive extraite localement, placée en tête du `PATH`, `process.version` vérifié).

Commandes et résultats observés :
- `npx tsc --noEmit` et `npx tsc -p tsconfig.build.json --noEmit` : sortie 0.
- `npx vitest run` sur les 14 fichiers : `push-reliability-20261110`, `course-notifications`, `course-push-failure`, `course-push-revalidation`, `course-push-transport`, `lesson-exam-push`, `messaging-mention-push`, `messaging-message-push`, `messaging-notifications`, `messaging-push-a55`, `messaging-push-coalescing`, `messaging-push-multidevice-448`, `push-device-revocation`, `course-worker-process` : **14 fichiers réussis, 170 tests réussis, 1 ignoré** (aucun échec).
- Après ajout des tests de concurrence de la messagerie : `messaging-push-multidevice-448` + `messaging-push-coalescing` : 16/16 réussis, `tsc --noEmit` sortie 0 (cette dernière exécution est ciblée, non une nouvelle suite globale).
- `course-worker-process.integration.test.ts` (processus réel, PostgreSQL isolée créée par son harnais) : réussi sous Node 24. Son test **SIGTERM** reste ignoré sous Windows (`it.skipIf(!posix)`, Windows ne livre pas SIGTERM) : **NON EXÉCUTÉ**, à qualifier sur POSIX.

Tests de concurrence (transport suspendu sur le premier envoi, autre connexion qui modifie la base, puis relâchement) :
- cours (`push-reliability-20261110`) : appareil révoqué, appareil réattribué, préférence retirée, adhésion révoquée, échéance dépassée (le temps passe : la ligne est verrouillée par le service), INVALID_TOKEN tardif sur enregistrement renouvelé (2 variantes), deux instances du service sur les mêmes appareils avec barrière (pas d'interblocage, deux `FAILED` avec `attempts` 1) ;
- messagerie (`messaging-push-multidevice-448`) : appareil révoqué, réattribué, préférence retirée, INVALID_TOKEN tardif sur enregistrement renouvelé ; **deux alertes déjà entamées du même groupe** (retour 2/2) : l'envoi de la première est suspendu, la préférence est retirée, puis libération → un seul envoi au total, aucune destination en attente, alertes closes (`SKIPPED`/`PREFERENCE_DISABLED`). Contrôle négatif : avec la revalidation de la première destination désactivée, ce test échoue (2 envois au lieu de 1).
- Retour 2/2 (même correction pour une alerte fraîche choisie après des reprises) : `attemptDeliveries` revalide avant chaque destination sans état `awaited`.
- Validation ciblée Node v24.22.2 : `tsc --noEmit` 0, `tsc -p tsconfig.build.json --noEmit` 0 ; `messaging-push-multidevice-448` + `messaging-push-coalescing` + `push-reliability-20261110` : 3 fichiers, 41 tests réussis. Aucune suite globale relancée.

## Limites

- **At-least-once exact.** Les résultats par appareil sont écrits dans la transaction de l'unité mais ne sont durables qu'au `COMMIT` de cette unité (une notification, ou un groupe de messagerie). Un arrêt brutal du processus (ou une perte de connexion) entre l'envoi accepté d'un appareil et ce `COMMIT` — y compris pendant l'attente des appareils suivants — annule l'unité et peut renvoyer une seconde fois à un appareil déjà accepté. Le test « exception du transport » prouve la conservation du résultat par le `catch` suivi du `COMMIT`, pas la survie à un crash de processus au milieu du lot. Aucun harnais de crash ni garantie exactly-once ne sont fournis ; l'exigence de l'issue est le redémarrage normal.
- Le « redémarrage » des tests de ce lot est la fermeture et la réouverture du pool ; seul `course-worker-process` utilise un vrai processus.
- Entre la relecture d'autorisation et l'envoi réseau, une modification concurrente reste possible (contrôle par tentative, non atomique).
- Aucun essai APNs réel, aucun déploiement, pas de campagne globale ; STATUS.md non touché.
