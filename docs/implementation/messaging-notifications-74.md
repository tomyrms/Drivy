# Messagerie : alertes de nouveaux messages, préférences et ouverture (#74)

Étend les préférences personnelles #44 et la file push des cours (#43). Aucun second stockage de préférences, aucun nouveau moteur d'envoi.
Mentions, non-lus, sourdine par conversation et nettoyage des alertes lues étaient déjà livrés (#101, #103) ; ce chantier ajoute les alertes de messages privés et du général, les préférences de messagerie de la personne et l'ouverture de la bonne conversation depuis une alerte.

## Décisions du 31 octobre 2026

- Trois catégories : **Privé**, **Général**, **Mentions**.
- Par défaut : messages privés **activés**, mentions **activées**, messages du général hors mention **désactivés**. Une ligne de préférence absente vaut ces valeurs.
- Les sondages suivent la catégorie de leur conversation (un sondage est un message). Les votes et les clôtures n'alertent pas : il n'y a donc pas de catégorie « sondage ».
- Titre générique « Nouveau message », corps vide. Une mention garde son titre déjà déployé (« Quelqu'un vous a mentionné »), générique lui aussi.
- Un refus d'autorisation dans les Réglages d'iOS reste prioritaire : le serveur ne peut ni le lire ni le contourner.
- Une mention n'ajoute pas d'alerte du général, et une mention refusée ne retombe jamais sur la catégorie du général.

## Ce qui part sur l'écran verrouillé

Titre fixe, corps absent. Aucun extrait, nom d'auteur, nom de conversation ni nom d'élève (la messagerie est chiffrée de bout en bout). La charge porte seulement des identifiants techniques :
`kind: MESSAGING`, `category` (`MESSAGING_PRIVATE`, `MESSAGING_GENERAL`, `MESSAGING_MENTION`), `schoolId`, `conversationId`, `messageId`, `sequence`, et `thread-id` = `messaging:<école>:<conversation>`.
Elle est construite par `messagingPushPayload` (`apps/api/src/messaging-notifications.ts`).

## Circuit côté API

1. **Mise en file** à l'acceptation d'un message : le déclencheur `drivy.push_message_enqueue` (migration `20261031_messaging_message_push.sql`) écrit une ligne `push_notification` par destinataire (lien ouvert, jamais l'auteur, jamais une personne mentionnée : elle reçoit l'alerte de mention du déclencheur existant). Il ne retient que les personnes dont la préférence de la catégorie est active (valeur par défaut comprise) et qui ont un appareil enregistré. Catégories de la file : `MESSAGE_PRIVATE`, `MESSAGE_GENERAL`, `MESSAGE_MENTION`.
2. **Relecture juste avant l'envoi**, dans le service d'envoi commun (`processPushBatch`, `apps/api/src/course-push.ts`) : `drivy.push_messaging_snapshot` rend des faits (adhésion active, retrait du général, attribution moniteur/élève, lien ouvert, message présent non supprimé et non lu, sourdine, préférences et leur version). `decideMessagingNotification` décide à partir de ces faits ; la ligne passe à `SKIPPED` avec un code (`PREFERENCE_DISABLED`, `SILENCED`, `RECIPIENT_INELIGIBLE`, `EVENT_OBSOLETE`, `NO_DEVICE`) sinon la charge part. Le service d'envoi n'a toujours aucun accès direct aux tables métier.
3. **Durée de vie** : une alerte de message périme au bout de 15 minutes (`valid_until`, aussi transmis à APNs). Une reprise tardive du service ne rejoue donc pas un arriéré de messages ; les alertes de mention déjà déployées n'ont pas d'échéance et ne changent pas.
4. **Regroupement à l'envoi** : une seule alerte part par personne et par conversation (voir la section suivante).
5. **Aucun faux « lu »** : recevoir ou envoyer une alerte ne modifie aucune position de lecture. Un message déjà lu sur un autre appareil n'est plus alerté.
6. **Autorisation iOS** : l'app n'enregistre un jeton qu'une fois l'autorisation système accordée. Le serveur traite donc un appareil actif comme « autorisé » ; sans appareil actif il n'envoie rien (`NO_DEVICE`).

## Révocation sans jeton

Ferme le cas #74 de l'audit #120 : quand la session iOS se termine sans déconnexion explicite (restauration échouée, renouvellement refusé, échec d'écriture du Trousseau), l'app n'a plus de jeton d'accès et ne peut pas appeler la route authentifiée. L'appareil reste pourtant inscrit et continue de recevoir des alertes génériques.

- **Secret propre à l'appareil.** `PUT /v1/me/push-devices` engendre 32 octets aléatoires (`crypto.randomBytes(32)`, base64url) et les rend **une seule fois** dans `data.revocationSecret`. La base ne conserve que leur empreinte de 32 octets dans `drivy.push_device.revocation_digest` (migration `20261103c_push_device_revocation.sql`) ; le rôle `drivy_app` n'a aucun droit de lecture sur cette colonne, et le secret n'est jamais réécrit ni relu.
- **Empreinte SHA-256, pas HMAC.** Le secret est engendré par le serveur avec 256 bits d'entropie et n'est jamais choisi par une personne : aucune attaque par dictionnaire ou précalcul n'est possible, donc une clé HMAC n'apporte rien. Les clés existantes (`CURSOR_SECRET`, `INVITATION_CODE_SECRET`) servent d'autres usages ; les réutiliser mélangerait deux domaines et ferait dépendre la révocation d'un secret qui n'a pas été prévu pour elle. L'empreinte est en outre inutilisable comme secret : la route hache ce qu'on lui présente, elle ne compare pas la valeur reçue à l'empreinte stockée.
- **Route anonyme.** `POST /v1/push-devices/revoke`, sans `Authorization`, corps strict `{token, revocationSecret}` (`bodyLimit` 1 Ko) : `drivy.push_device_revoke_anonymous` retrouve la ligne du jeton, compare l'empreinte octet par octet (XOR sur 32 octets, sans sortie anticipée sur le contenu) et, si elle correspond, pose `revoked_at` — le même effet que `push_device_revoke`. Elle ne lit aucun paramètre de session et ne touche ni `person_id`, ni le jeton, ni l'empreinte.
- **Réponse identique.** Toujours `200 {data:{revoked:true}}` : jeton inconnu, jeton déjà révoqué, mauvais secret, secret d'un autre jeton ou secret mal formé. Seuls le statut et la charge comptent ; `requestId` et `serverTime` restent propres à la requête, comme partout.
- **Frein.** `attempt-limiter.ts`, en mémoire du processus, avec deux compteurs sur 15 minutes : 30 échecs par IP et 10 par jeton (clés dérivées par SHA-256, ni IP ni jeton en clair dans le compteur). Le 11e / 31e essai refusé répond `429 PUSH_REVOCATION_ATTEMPTS` (« Trop de tentatives. Réessayez dans quelques minutes. »), un message neutre — le frein existant parle de codes d'invitation, ce que cette route ne traite pas. Un succès ne consomme pas le budget. Une erreur base rend `503` et ne compte pas comme un échec d'authentification.
- **Reprise d'un appareil.** Un nouvel enregistrement du même jeton remplace l'empreinte : l'ancien secret ne révoque plus rien, y compris quand un autre compte reprend l'appareil (`push_device_claim_secret`). La route authentifiée `POST /v1/me/push-devices/revoke` est inchangée et reste bornée au propriétaire.
- **Journaux.** Ni le jeton ni le secret n'apparaissent dans un journal : les routes push ne sont pas journalisées par l'API (seule la messagerie l'est), et le frein ne garde que des horodatages et des empreintes de clé. Le test le vérifie sur des journaux capturés.
- **Contrat.** Les routes push ne figurent pas dans l'OpenAPI canonique 3.11.0 : l'extension est décrite dans `apps/api/contracts/push-device-revocation.json` (enregistrement, commande anonyme, réponse), validée par le test d'intégration.
- **Hors périmètre de cette tâche.** L'app iOS (T2) n'appelle pas encore la route anonyme et ne conserve pas le secret au Trousseau ; le web n'est pas concerné. Aucune preuve de réception APNs réelle n'est apportée ici.
- **Limite assumée.** Le frein est en mémoire du processus : un redémarrage remet les compteurs à zéro, et plusieurs instances ne partagent pas leurs compteurs. C'est le même compromis que les autres routes anonymes ; le secret de 256 bits reste hors de portée d'une recherche exhaustive même sans frein.

## Préférences

`GET/PUT /v1/me/notification-preferences` (même objet versionné, même `If-Match`/`ETag`) porte désormais, en plus des quatre champs de cours :

| Champ | Défaut | Rôle |
|---|---|---|
| `messagingPrivate` | `true` | nouveaux messages d'une conversation privée |
| `messagingGeneral` | `false` | nouveaux messages du général hors mention |
| `messagingMentions` | `true` | messages qui mentionnent la personne |

- Colonnes `messaging_private` et `messaging_general` de `drivy.notification_preference` ; `messaging_mentions` existait depuis la migration `20261025`.
- Compatibilité : les trois champs sont facultatifs à l'écriture. Une app ou un navigateur antérieur qui n'envoie que les quatre champs de cours laisse les choix de messagerie inchangés. La réponse les porte toujours.
- Les préférences sont par personne, pour toutes ses écoles. L'API refuse la lecture et l'écriture des choix d'un tiers (elle ne connaît que la personne connectée).
- Il n'existe pas d'interrupteur général « tous les push » : chaque catégorie se refuse seule, et le refus système d'iOS reste le garde-fou global.

## Web

La page « Préférences personnelles » du portail (`apps/web/client/portal/account/preferences-page.tsx`) affiche deux groupes dans la même section Notifications : « Cours collectifs » (quatre interrupteurs existants) et « Messages » (Messages privés, Messages du général, Mentions). Le modèle (`notification-preferences-model.ts`) et le magasin à intentions indépendantes par champ (`notification-preferences-store.ts`) traitent les sept champs comme un seul objet versionné : une modification concurrente d'un champ ne réactive pas un autre choix. Le relais web (`/app/bff/me/notification-preferences`) accepte les trois champs de messagerie facultatifs et refuse toute autre clé.
La messagerie n'a pas de client web : ces choix s'appliquent aux alertes de l'app iPhone/iPad, pour les écoles où Messages est ouvert.

## App iPhone et iPad

- **Réglages** (`SchoolNotificationSettingsView`) : la section « Messages » affiche Messages privés, Messages du général et Mentions quand Messages est ouvert dans cette app et que l'API annonce les trois champs (`supportsMessaging`). Sinon aucun interrupteur de messagerie n'apparaît : pas de bouton pour une alerte inexistante. Les choix passent par le modèle existant (`SchoolNotificationSettingsModel`, intentions chiffrées sur l'appareil, un seul PUT à la fois, `If-Match`), sans second stockage. L'ancien journal et l'ancienne API restent lisibles : les champs de messagerie sont facultatifs en lecture comme en écriture.
- **Toucher une alerte** : `SchoolPushCenter` lit `kind`, `schoolId` et `conversationId` de la charge `MESSAGING` (`MessagingNotificationTarget`) en plus de `seriesId` pour les cours. L'accueil (`SchoolHomeView`) applique `MessagingNotificationOpening.outcome` :
  - école courante, hors trajet, Messages disponible : l'onglet Messages s'ouvre ;
  - alerte d'une autre école : refus expliqué, rien n'est ouvert ;
  - trajet GPS en cours : rien ne s'ouvre et la demande est oubliée (la consultation reste volontaire, la leçon continue) ;
  - app pas encore prête (démarrage à froid, connexion) : la demande attend, 120 secondes au plus.
- **Droits relus** : l'onglet Messages (`MessagingInboxView`) relit la liste des conversations auprès de l'école et n'ouvre que la conversation que l'école liste encore pour cette personne (pages suivantes comprises, 20 au plus). Le général, qui n'est listé qu'une fois ouvert, est ouvert par l'école elle-même et n'est retenu que si l'identifiant correspond. Sinon : « Cette conversation n'est plus accessible. » ; si la liste n'a pas pu être relue : « Impossible d'ouvrir la conversation pour le moment. »
- **Aucun faux « lu »** : toucher une alerte n'envoie aucune position de lecture ; la lecture suit l'ouverture normale du fil.
- Hors périmètre : suppression de l'alerte au premier plan et nettoyage des alertes lues restent ceux de #103.

## Regroupement anti-rafale (3 novembre 2026)

Critère de l'issue : « Pas de double alerte message + mention, ni rattrapage massif après reconnexion. » Le regroupement vit
dans le service d'envoi existant (`processPushBatch`, `apps/api/src/course-push.ts`), pas dans un second moteur : la file
`drivy.push_notification`, la revalidation `drivy.push_messaging_snapshot` et `decideMessagingNotification` restent seules
sources. Aucune table, colonne, fonction SQL, préférence, route ni charge n'a changé : **aucune migration n'a été nécessaire**.

- **Un envoi au plus par groupe** (personne, conversation). Le service liste les groupes dus, pose un verrou consultatif par
  groupe (`pg_try_advisory_xact_lock`, clé `messaging-push:<personne>:<conversation>`), puis verrouille dans la même
  transaction toutes les alertes `PENDING` dues de ce groupe. Un deuxième passage du service saute le groupe au lieu de
  l'attendre ; les autres personnes et conversations ne sont jamais bloquées.
- **Choix de l'alerte** : chaque alerte du groupe passe la revalidation existante, alerte par alerte. Une mention autorisée
  prime sur les messages ordinaires ; sinon c'est la plus récente autorisée qui part. Les autres alertes autorisées du
  groupe passent en `SKIPPED` avec `failure_code='COALESCED'`. Une alerte refusée garde son motif de refus existant
  (`PREFERENCE_DISABLED`, `SILENCED`, `RECIPIENT_INELIGIBLE`, `EVENT_OBSOLETE`, `NO_DEVICE`) et, si aucune ne passe, rien
  n'est envoyé.
- **Fenêtre de calme** : `MESSAGING_PUSH_QUIET_WINDOW_SECONDS = 60` (exportée par `apps/api/src/messaging-notifications.ts`).
  Si une alerte de messagerie a été `SENT` à la même personne pour la même conversation il y a moins de 60 secondes, les
  nouvelles ne partent pas : leur `available_at` est reporté à `sent_at + 60 s` et `attempts` n'est pas incrémenté. À
  l'échéance, elles sont regroupées en un seul envoi par la règle ci-dessus.
- **Échéance intacte** : une alerte expirée pendant le report (`valid_until` dépassé) est marquée `EXPIRED` et n'est jamais
  envoyée ; un message déjà lu ou supprimé, une préférence coupée ou une conversation en sourdine pendant le report
  produisent le même refus qu'avant, sans envoi.
- **Charge inchangée** : titre générique, corps vide, mêmes identifiants techniques, même `thread-id`
  (`messaging:<école>:<conversation>`) ; les alertes de cours gardent leur traitement une par une.

## Matrice de bout en bout (A55)

Audit du 3 novembre 2026 pour l'issue #74 (« V : à vérifier de bout en bout »). Le transport reste un **collecteur local**,
jamais APNs : tout ce qui est marqué « prouvé » l'est sur PostgreSQL réelle, pas sur un appareil. Trois mentions de
verdict sont utilisées :

- **Prouvé (test)** : un test nommé ci-dessous, exécuté dans la passe du 3 novembre 2026 (fichier + nom exact).
- **Prouvé (lecture)** : preuve par lecture du source, sans test automatisé ; ce n'est pas une exécution.
- **Partiel** : une partie du maillon est prouvée par test, l'autre seulement par lecture ou pas du tout ; le détail est dans la case.
- **Non prouvé** : aucune preuve ; la raison est donnée.

Les tests ajoutés sont dans `apps/api/test/messaging-push-a55.integration.test.ts` (9 tests, PostgreSQL réelle).

### Messages privés (MESSAGING_PRIVATE)

| Maillon | Preuve | Verdict |
|---|---|---|
| Événement serveur | Déclencheur `drivy.push_message_enqueue` (migration `20261031_messaging_message_push.sql`) ; `messaging-message-push.integration.test.ts` › « prévient le destinataire, jamais l'auteur, avec une charge générique et une seule fois » | Prouvé (test) |
| Préférence | File : même test › « ne met rien en file sans appareil enregistré ni lorsque la catégorie est refusée » ; envoi : `messaging-message-push` › « relit juste avant l'envoi : préférence refusée avant l'envoi » ; règle unitaire : `messaging-notifications.test.ts` › « selects the private category from the conversation kind without reading message content » | Prouvé (test) |
| Sourdine | `messaging-message-push` › « relit juste avant l'envoi : conversation en sourdine » (`SKIPPED/SILENCED`, aucun envoi) | Prouvé (test) |
| Droits revalidés juste avant l'envoi | Adhésion révoquée et attribution terminée : `messaging-message-push` › « relit juste avant l'envoi : compte désactivé dans l'école » et « attribution terminée » ; lien coupé : `messaging-push-a55` › « une conversation privée coupée après la mise en file n'expédie rien » (`RECIPIENT_INELIGIBLE`) ; message supprimé ou déjà lu : `EVENT_OBSOLETE` dans le même `it.each` | Prouvé (test) |
| Regroupement | `messaging-push-coalescing.integration.test.ts` › « une rafale de cinq messages privés ne produit qu'une alerte, les autres sont regroupées » ; report de 60 s : « un message moins de 60 s après un envoi est reporté sans consommer de tentative, puis regroupé » | Prouvé (test) |
| Charge APNs (aucun contenu) | `messaging-push-a55` › « les trois catégories ne transportent que des identifiants techniques » (clés exactes, titre seul, aucun base64 de contenu, aucun nom) ; `messaging-push-coalescing` › « la charge reste générique et sans contenu » | Prouvé (test) |
| Journaux du service d'envoi | `messaging-push-a55` › « le service d'envoi n'écrit aucune donnée de message dans ses journaux, même après un échec de transport » ; accès structurel : « le rôle du service d'envoi ne peut pas lire les tables de messagerie » (`drivy_course_worker` reçoit `42501` sur `messaging_message`, `messaging_conversation`, `messaging_member_link`) | Prouvé (test) |
| Inscription de l'appareil | `messaging-push-a55` › « un jeton enregistré deux fois reste unique et un jeton révoqué n'est plus utilisé » (deux `PUT /v1/me/push-devices`, une seule ligne) ; côté app, le jeton n'est envoyé qu'après autorisation système (`SchoolPushCenter.upload`) | Prouvé (test) pour le serveur ; Prouvé (lecture) pour l'app |
| Retrait de l'appareil | Même test : `POST /v1/me/push-devices/revoke` puis alerte en file `SKIPPED/NO_DEVICE`, aucun envoi ; `messaging-message-push` › « appareil retiré » | Prouvé (test) |
| Changement de compte sur le même appareil | `messaging-push-a55` › « un jeton repris par une autre personne cesse de servir la première » : `push_device_claim` réattribue le jeton, l'alerte déjà en file pour la première personne passe en `NO_DEVICE`, le jeton sert ensuite les alertes de la seconde | Prouvé (test) pour le serveur ; iOS non prouvé (voir « Trous constatés côté iOS ») |
| Ouverture de la bonne conversation | Analyse de la charge et décision d'onglet : `apps/ios/DrivyTests/SchoolNotificationTests.swift` › `readsTheSchoolAndConversationOfAMessagingAlert`, `aMessagingAlertOpensMessagesOnlyForTheCurrentSchoolOutsideATrip`, `theTouchedConversationIsKeptUntilItIsConsumed` (tests Swift, **non exécutés ici**) ; relecture des droits puis ouverture : `MessagingInboxView.openRequestedConversation` (`MessagingViews.swift`), **Prouvé (lecture)** seulement | Partiel : tests Swift non exécutés dans cette passe ; aucun test de la relecture serveur puis ouverture |
| Non-lus sans dépendre du push | `messaging.integration.test.ts` › « pages several messages, resumes in ascending order and persists own mute without false receipts » (`unreadCount` vient de l'état de lecture, aucun push en jeu) | Prouvé (test) |

### Général hors mention (MESSAGING_GENERAL)

| Maillon | Preuve | Verdict |
|---|---|---|
| Événement serveur | Déclencheur `drivy.push_message_enqueue` (branche `GENERAL`) ; `messaging-message-push.integration.test.ts` › « ne prévient personne par défaut pour le général, puis seulement ceux qui l'ont activé » | Prouvé (test) |
| Préférence | Même test (désactivée par défaut, active seulement après choix) ; `messaging-message-push` › « une préférence enregistrée par l'API gouverne les alertes suivantes » | Prouvé (test) |
| Sourdine | `messaging-push-a55` › « une conversation du général en sourdine après la mise en file n'expédie rien » (`SKIPPED/SILENCED`) | Prouvé (test) |
| Droits revalidés juste avant l'envoi | `messaging-message-push` › « retrait du général, adhésion perdue ou lien coupé : plus d'alerte » (`RECIPIENT_INELIGIBLE` après `DELETE /general/members/:id`) ; message déjà lu ou supprimé : même instantané `drivy.push_messaging_snapshot`, `EVENT_OBSOLETE` prouvé sur le privé dans « relit juste avant l'envoi : message déjà lu ailleurs » et « message supprimé pour tout le monde » | Prouvé (test) |
| Regroupement | `messaging-push-coalescing` › « une mention autorisée prime : mention et message du général ne font qu'une alerte de mention » et « deux conversations de la même personne restent deux alertes » ; deux messages du général regroupés : `messaging-push-a55` › « les trois catégories ne transportent que des identifiants techniques » (1 `SENT` + 1 `COALESCED`) | Prouvé (test) |
| Charge APNs (aucun contenu) | `messaging-push-a55` › « les trois catégories ne transportent que des identifiants techniques » ; la question d'un sondage n'existe pas côté serveur (`PollCreation { optionCount, multiple }`, `messaging.ts`), donc elle ne peut pas entrer dans une charge | Prouvé (test) |
| Journaux du service d'envoi | `messaging-push-a55` › « le service d'envoi n'écrit aucune donnée de message dans ses journaux, même après un échec de transport » | Prouvé (test) |
| Inscription de l'appareil | `messaging-push-a55` › « un jeton enregistré deux fois reste unique et un jeton révoqué n'est plus utilisé » ; `messaging-message-push` › « ne met rien en file sans appareil enregistré » | Prouvé (test) |
| Retrait de l'appareil | Même test de révocation (`NO_DEVICE`), et `messaging-message-push` › « appareil retiré » | Prouvé (test) |
| Changement de compte sur le même appareil | `messaging-push-a55` › « un jeton repris par une autre personne cesse de servir la première » (le second compte reçoit son alerte du général sur ce jeton) | Prouvé (test) pour le serveur ; iOS non prouvé (voir « Trous constatés côté iOS ») |
| Ouverture de la bonne conversation | Mêmes tests Swift que pour le privé (**non exécutés ici**) ; le général n'étant listé qu'une fois ouvert, `openRequestedConversation` le redemande à l'école et ne l'ouvre que si l'identifiant correspond (`MessagingViews.swift`) | Partiel : Prouvé (lecture) pour la relecture, tests Swift non exécutés |
| Non-lus sans dépendre du push | `messaging.integration.test.ts` › « pages several messages, resumes in ascending order and persists own mute without false receipts » | Prouvé (test) |

### Mentions (MESSAGING_MENTION)

| Maillon | Preuve | Verdict |
|---|---|---|
| Événement serveur | Déclencheur `drivy.messaging_mention_enqueue` (migration `20261025_messaging_mention_push.sql`) ; `messaging-mention-push.integration.test.ts` › « alerte uniquement les mentionnés hors auteur, sans contenu ni nom, une seule fois » | Prouvé (test) |
| Préférence | `messaging-mention-push` › « revalide avant envoi : préférence, sourdine, retrait du général et message supprimé » (`messaging_mentions=false` → `PREFERENCE_DISABLED`) ; pas de repli sur le général : `messaging-notifications.test.ts` › « a disabled mention never falls back to the general category » | Prouvé (test) |
| Sourdine | Même test de revalidation (`SILENCED`, aucun envoi) | Prouvé (test) |
| Droits revalidés juste avant l'envoi | Même test (retrait du général → `RECIPIENT_INELIGIBLE`) ; lien coupé : `messaging-push-a55` › « une mention dont le lien est coupé après la mise en file n'expédie rien » | Prouvé (test) |
| Regroupement | `messaging-push-coalescing` › « une mention autorisée prime : mention et message du général ne font qu'une alerte de mention » ; pas de doublon pour un même message : `messaging-push-a55` › « une mention ne laisse aucune alerte du général pour le même message » ; `messaging-message-push` › « une mention n'ajoute pas d'alerte du général et une mention refusée ne retombe pas sur le général » | Prouvé (test) |
| Charge APNs (aucun contenu) | `messaging-mention-push` (charge exacte, titre générique, corps vide) ; `messaging-push-a55` › « les trois catégories ne transportent que des identifiants techniques » | Prouvé (test) |
| Journaux du service d'envoi | `messaging-push-a55` › « le service d'envoi n'écrit aucune donnée de message dans ses journaux, même après un échec de transport » (le service d'envoi est commun aux trois catégories) | Prouvé (test) |
| Inscription de l'appareil | `messaging-push-a55` › « un jeton enregistré deux fois reste unique et un jeton révoqué n'est plus utilisé » (même table `push_device`, même route) | Prouvé (test) |
| Retrait de l'appareil | Même test (`NO_DEVICE`) ; `messaging-message-push` › « appareil retiré » | Prouvé (test) |
| Changement de compte sur le même appareil | `messaging-push-a55` › « un jeton repris par une autre personne cesse de servir la première » (la recherche d'appareil est commune aux trois catégories) | Prouvé (test) pour le serveur ; iOS non prouvé (voir « Trous constatés côté iOS ») |
| Ouverture de la bonne conversation | Mêmes tests Swift (**non exécutés ici**) ; la charge de mention porte `schoolId` et `conversationId` comme les autres, donc le même chemin d'ouverture | Partiel : Prouvé (lecture), tests Swift non exécutés |
| Non-lus sans dépendre du push | `messaging.integration.test.ts` › « pages several messages, resumes in ascending order and persists own mute without false receipts » (une mention est un message comme un autre) | Prouvé (test) |

### Ce qui reste non prouvé, et pourquoi

| Point | Raison |
|---|---|
| Réception APNs réelle (les trois catégories) | Aucun envoi vers Apple dans les tests : le transport est un collecteur local. L'IPA est non signée et installée par iLoader ; l'autorisation push et la remise par APNs ne peuvent pas être constatées ici. |
| Affichage réel sur écran verrouillé | Dépend de la réception APNs ; aucun simulateur ne prouve le rendu d'une alerte distante. |
| Ouverture effective de la conversation après une alerte | Les tests Swift couvrent l'analyse de la charge et la décision d'onglet ; la relecture de la liste puis l'ouverture (`MessagingInboxView.openRequestedConversation`) n'a pas de test. |
| Deux comptes réels sur deux appareils | Aucun appareil dans cet environnement, données synthétiques seulement et transport local. Le changement de compte est prouvé au niveau du jeton, pas sur un téléphone. |
| Autorisation iOS refusée puis réaccordée | Le serveur ne lit pas l'autorisation système ; il traite un appareil actif comme autorisé. Non vérifiable sans appareil. |

### Trous constatés côté iOS

1. **Fin de session sans déconnexion explicite — comblé côté app (#120), non compilé ici.** `SchoolPushCenter.sessionEnding()`
   n'était appelé que par les deux gestes de déconnexion de `SchoolRootView` (ligne « Se déconnecter » et bouton
   « Se reconnecter »). Quand `IdentitySession` passait `isAuthenticated` à `false` sans passer par `signOut()` — restauration
   échouée (`IdentitySession.restore`), renouvellement refusé, échec d'écriture du Trousseau — le jeton d'appareil restait
   **actif côté serveur**. Quatre points ont été ajoutés, sans nouvelle autorisation locale ni changement de la logique
   d'identité :
   - **Secret au Trousseau.** `PUT /v1/me/push-devices` rend `data.revocationSecret` une fois (`SchoolNotificationClient.register`
     le décode, facultatif : une API plus ancienne ne le renvoie pas). `SchoolPushCenter` le garde avec son jeton
     (`SchoolPushRevocationRecord`, `KeychainSchoolPushRevocationStore` : `kSecClassGenericPassword`,
     `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, aucune synchronisation iCloud), le remplace à chaque enregistrement
     et l'efface après une révocation confirmée. Ni jeton ni secret n'est journalisé : aucun journal n'a été ajouté.
   - **Route anonyme.** `SchoolNotificationClient.revokeAnonymously(token:secret:)` appelle `POST /v1/push-devices/revoke`
     sur la même base que l'API, **sans** en-tête `Authorization` et sans passer par « /me » ni par le renouvellement du
     jeton d'accès. À toute fin de session, la révocation authentifiée est tentée d'abord (comportement d'avant #120) ; si
     l'école ne reconnaît plus la session (`unauthorized`), le secret prend le relais. Tant que l'école n'a pas confirmé la
     révocation, l'enregistrement (jeton + secret) reste au Trousseau : sa présence **est** la marque d'une révocation due.
     Un nouvel essai part à la première transition d'identité (fin de restauration ou de connexion) et à chaque retour au
     premier plan, une fois par transition, hors session ouverte et hors restauration en cours : jamais de boucle.
   - **Accroches.** `IdentitySession.sessionEnded` est appelée aux trois passages à `false` (restauration échouée,
     renouvellement refusé, Trousseau en échec) ; elle est posée par `DrivyApp` **avant** `identity.restore()`, pour que
     l'échec de la restauration du lancement soit annoncé. Si une fin de session survient avant la pose, l'identité la
     retient et l'annonce dès que l'accroche est posée. Les deux gestes de déconnexion continuent de l'appeler avant
     `signOut()`, sans doublon. `SchoolRootView` reprend une révocation restée à faire après le verdict du lancement
     (`identitySettled`), à chaque fin de restauration ou de connexion sans session, et à chaque retour au premier plan
     hors session ; `resumePendingRevocation(identityIsBusy:)` refuse de partir pendant une session ouverte ou une
     restauration en cours.
   - **Tests.** `apps/ios/DrivyTests/SchoolPushCenterTests.swift` (nouveau) : secret conservé puis remplacé, secret effacé
     après succès, révocation authentifiée quand le jeton vaut, révocation anonyme sur les trois chemins d'identité,
     fin de session annoncée après la pose de l'accroche (restauration du lancement), secret présent au lancement sans
     session, reprise refusée pendant une session ouverte ou une restauration, retentative unique après une panne réseau,
     école plus ancienne sans secret (comportement inchangé), forme exacte de la requête anonyme. **Ces tests n'ont pas été
     compilés ni exécutés dans cette passe** (pas de chaîne Apple sur la machine de rédaction) : ils ne qualifient rien tant
     que la CI Apple ne les a pas passés, et aucune réception APNs réelle n'est apportée. Le frein `429
     PUSH_REVOCATION_ATTEMPTS` laisse la révocation en attente, comme une panne.
2. **Changement de compte sans déconnexion.** Si un autre compte se connecte sur le même appareil sans que le premier se soit
   déconnecté, la sécurité repose uniquement sur `push_device_claim` (le nouveau compte reprend le jeton à l'enregistrement),
   et un nouvel enregistrement remplace le secret de révocation de l'appareil. C'est prouvé côté serveur (test ci-dessus),
   mais aucun test iOS ne vérifie que `sessionStarted()` est bien appelé et que l'enregistrement aboutit avant qu'une alerte
   de l'ancien compte n'arrive. Non corrigé dans cette passe.

## Limites connues

- Le regroupement ne crée aucun compteur ni résumé : iOS affiche une alerte générique par conversation et par fenêtre de
  60 secondes. Rien n'est agrégé côté appareil au-delà du `thread-id` existant.
- Le général peut compter beaucoup de membres : sa catégorie étant désactivée par défaut, la file n'écrit une ligne que pour ceux qui l'ont activée et qui ont un appareil.
- **Réception APNs réelle non vérifiée** : les tests utilisent un collecteur local, jamais APNs. Aucune preuve de réception sur appareil (STATUS.md). Le regroupement est vérifié sur PostgreSQL réelle (rafale, mention, deux conversations, report de 60 s, expiration et préférence coupée pendant le report), pas sur un appareil.
- Les alertes de messagerie sont désactivées pour les écoles hors qualification comme la messagerie elle-même : aucun message n'existe, donc aucune alerte.
- **Matrice A55 et trou iOS** : la matrice de bout en bout ci-dessus nomme la preuve de chaque maillon. Deux points restent ouverts : la réception APNs réelle, et la qualification de la fin de session sans déconnexion explicite — comblée côté app (#120, voir « Trous constatés côté iOS ») mais non compilée ni exécutée ici.

## Déploiement

Ordre : migration et API (le service d'envoi relit les nouvelles colonnes), puis web, puis app. Une API ancienne ignore les nouvelles catégories et saute leurs lignes (`course_push_revalidate` refuse les catégories inconnues). Le web et l'app lisent les trois nouveaux champs : ils exigent l'API à jour.

Le regroupement anti-rafale du 3 novembre 2026 ne change ni le schéma, ni la charge, ni le contrat : il suffit de redéployer l'API et son service d'envoi (même image, processus `course:worker`), sans coordination avec le web ni l'app.
