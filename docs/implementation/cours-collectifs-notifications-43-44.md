# Cours collectifs : notifications push et préférences (#43, #44), abonnement aux prochaines sessions (#40)

25 octobre 2026. Autorisé par le porteur le 24 octobre 2026 (infrastructure push et valeurs de file). Migration 045,
`apps/api/src/course-push.ts`, `course-worker.ts`, `notification-preferences.ts`. Aucun e-mail automatique.

## Valeurs de file approuvées

12 h pour répondre à une place proposée, échéance au plus tard 2 h avant la première séance, pas de proposition si moins
de 30 min possibles. Une école sans politique enregistrée a donc la file active (720 min). Une école qui a enregistré
une politique garde son choix, y compris « file désactivée ».

## Service des cours (`npm run course:worker`)

- Rôle PostgreSQL `drivy_course_worker` (sans BYPASSRLS), préparé par `apps/api/scripts/prepare-course-worker.sql`
  (exécuté sur le homelab le 25 octobre 2026, activation du service encore bloquée par la qualification). Variable `COURSE_WORKER_DATABASE_URL`.
- Toutes les 15 s : expiration des propositions échues et passage au suivant, outbox des cours transformée en
  notifications ciblées, rappels 24 h et 2 h aux inscrits, alerte de minimum au responsable 72 h avant (aucune
  annulation automatique), notifications périmées marquées EXPIRED.
- Envoi APNs (HTTP/2, jeton de fournisseur ES256) si `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`
  (`APNS_ENVIRONMENT`) sont fournis. Sans eux, rien n'est envoyé ; tout reste consultable dans l'app.
- Échec temporaire : 5 tentatives espacées, puis FAILED. Jeton refusé par Apple : appareil révoqué. Aucun appareil :
  SKIPPED. Un envoi ne vaut ni lecture ni acceptation.

## Ciblage

| Événement | Destinataires | Catégorie |
| --- | --- | --- |
| Place proposée | Le seul destinataire de la proposition | Places et nouvelles sessions |
| Nouvelle série publiée | Abonnés au type, pas déjà validés | Places et nouvelles sessions |
| Inscription, annulation, cours annulé, dates modifiées | Personnes concernées | Changements de cours |
| 24 h et 2 h avant une séance | Inscrits actifs | Rappels de cours |
| Minimum non atteint (72 h) | Responsable de la série | Alertes pour l'équipe |

## Préférences et appareils

- `GET/PUT /v1/me/notification-preferences` (If-Match) : 4 interrupteurs par personne, tous actifs par défaut.
- `PUT /v1/me/push-devices`, `POST /v1/me/push-devices/revoke` : le jeton n'est jamais relu par l'application.
- `GET /v1/schools/{id}/course-follows/me`, `PUT …/{typeId}`, `POST …/{typeId}/unfollow` : abonnement volontaire,
  sans inscription ni entrée en file.

## iOS

Autorisation demandée seulement après un geste explicite. Jeton envoyé après connexion, révoqué à la déconnexion.
Écran « Notifications » dans Mon profil. « Prévenir des prochaines sessions » sur la fiche d'un cours.

**Droit APNs activé dans le projet** : `apps/ios/Configuration/Device.entitlements` est référencé par
`CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]`. Le porteur possède un compte développeur payant. L'environnement de l'app
est lu dans son profil embarqué après signature. La signature iLoader, le topic effectif et la réception sur appareil
restent à qualifier. Une IPA non signée ne prouve pas ces points.

## Vérification

- 7 tests API (`course-notifications.integration.test.ts`), suite API complète 616/616 en local ; web 352/352.
- L'envoi APNs réel n'est pas testé : les tests utilisent un expéditeur simulé. Réception sur appareil : à faire avec
  les clés et un compte développeur.
