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

## Demandes de leçon et examens

Troisième extension de la même file (#43/#44), ajoutée le 3 novembre 2026 par la migration additive
`20261103_lesson_exam_push.sql`. Aucun second moteur, aucun second stockage : mêmes préférences versionnées, même
revalidation juste avant l'envoi, même service `processPushBatch`. La mise en file se fait dans la transaction de
l'écriture durable (jamais avant, jamais dans un second appel), avec une clé de déduplication par personne et par
événement.

| Événement | Catégorie | Destinataire | Préférence | `valid_until` |
| --- | --- | --- | --- | --- |
| Demande de l'élève sur une leçon (déplacement ou annulation) | `LESSON_REQUEST` | Moniteur actif de la leçon ; sans moniteur actif, administrateurs actifs de l'école | `lessonRequests` | min(début prévu de la leçon, maintenant + 24 h) |
| Demande acceptée ou refusée | `LESSON_REQUEST_ANSWER` | Élève demandeur | `lessonRequests` | maintenant + 24 h |
| Examen saisi (échéance, fuseau, lieu) | `EXAM` | Élève de la formation | `examUpdates` | maintenant + 24 h |
| Date, heure ou lieu modifiés (`update` ou `postpone`, seulement si l'un change) | `EXAM` | Élève de la formation | `examUpdates` | maintenant + 24 h |
| Résultat enregistré ou corrigé | `EXAM` | Élève de la formation | `examUpdates` | maintenant + 24 h |

- **Textes génériques**, identiques à la règle #74 : « Nouvelle demande » / « Un élève attend votre réponse. »,
  « Demande traitée » / « Votre demande a reçu une réponse. », « Examen planifié » / « Un examen a été ajouté. »,
  « Examen modifié » / « La date ou le lieu d’un examen a changé. », « Résultat d’examen » / « Un résultat est
  disponible. ». Aucun nom, aucune note, aucun motif, aucun lieu, aucun résultat (réussi, échoué, absent) dans le
  titre, le corps, la charge APNs ni les journaux. La charge porte `aps.alert` et `category`, rien d'autre.
- **Auteur jamais notifié** de sa propre action : l'élève qui demande ne reçoit pas sa demande, le moniteur qui répond
  ne reçoit pas sa réponse, le personnel qui saisit un examen ne reçoit pas l'alerte de l'élève.
- **Retrait par l'élève** : aucune notification, ni au moniteur ni à l'élève.
- **Relecture juste avant l'envoi** (`course_push_revalidate`, étendue) : préférence encore active, adhésion du
  destinataire encore active dans l'école, et événement encore d'actualité. Une demande retirée, une leçon commencée
  ou annulée avant l'envoi donnent `EVENT_OBSOLETE` ; un destinataire sorti de l'école donne
  `RECIPIENT_INELIGIBLE` ; une préférence coupée donne `PREFERENCE_DISABLED`. Un examen disparu donne
  `EVENT_OBSOLETE`. Un envoi réussi ne vaut ni lecture ni acceptation.
- **Préférences** : `lessonRequests` et `examUpdates`, booléens actifs par défaut, colonnes `lesson_requests` et
  `exam_updates`. Comme les champs de messagerie, facultatifs en écriture (une ancienne app ou un ancien onglet qui
  ne les mentionne pas les laisse inchangés) et toujours présents en lecture. L'API ne connaît que la personne
  connectée : ni lecture ni écriture des choix d'un tiers. Extension de contrat :
  `apps/api/contracts/notification-preferences.json`.
- **Clients** : le modèle web (`notification-preferences-model.ts`) et le relais BFF acceptent et retransmettent les
  deux champs sans interrupteur ni écran ; l'app iOS ignore les champs qu'elle ne connaît pas et n'envoie que les siens,
  donc elle ne réinitialise rien. Aucun changement Swift n'a été nécessaire.

Non vérifié : la réception APNs réelle (expéditeur simulé dans les tests, iLoader et clés Apple non disponibles), et
les écrans (interrupteurs web et iOS, ouverture d'un écran depuis une alerte) qui relèvent d'un worker d'interface.

## Préférences et appareils

- `GET/PUT /v1/me/notification-preferences` (If-Match) : quatre interrupteurs de cours, trois de messagerie
  (`messagingPrivate`, `messagingGeneral`, `messagingMentions`, #74, voir `messaging-notifications-74.md`) et deux de
  demandes de leçon et d'examens (`lessonRequests`, `examUpdates`), tous actifs par défaut sauf le général. Même objet
  versionné, même `ETag`.
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

- 7 tests API (`course-notifications.integration.test.ts`) et 12 tests `lesson-exam-push.integration.test.ts` sur
  PostgreSQL réelle. Suites touchées (préférences, cours, demandes de leçon, examens, push, messagerie de la même file)
  relancées ensemble : 133/133. Web : `typecheck` vert, `test:unit` 773 réussis et 1 échec attendu déclaré `test.fails`.
- Suite API complète en local : 987/989. Les deux échecs sont `g1c` F02 (SMTP réel), faute de Mailpit local : le
  message reste `QUEUED`. Aucun rapport avec ce chantier, qui ne touche ni l'invitation ni son transport.
- L'envoi APNs réel n'est pas testé : les tests utilisent un expéditeur simulé. Réception sur appareil : à faire avec
  les clés et un compte développeur.
