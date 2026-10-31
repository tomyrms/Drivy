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
4. **Aucun faux « lu »** : recevoir ou envoyer une alerte ne modifie aucune position de lecture. Un message déjà lu sur un autre appareil n'est plus alerté.
5. **Autorisation iOS** : l'app n'enregistre un jeton qu'une fois l'autorisation système accordée. Le serveur traite donc un appareil actif comme « autorisé » ; sans appareil actif il n'envoie rien (`NO_DEVICE`).

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

## Limites connues

- **Pas de regroupement anti-rafale côté serveur** : une alerte par message (une par message mentionnant, une par message privé ou du général activé). Seul `thread-id` regroupe l'affichage sur iOS, et les 15 minutes de validité bornent le rattrapage. Un regroupement (compteur par conversation, fenêtre glissante) demanderait un moteur d'agrégation dans la file ; il n'est pas fait.
- Le général peut compter beaucoup de membres : sa catégorie étant désactivée par défaut, la file n'écrit une ligne que pour ceux qui l'ont activée et qui ont un appareil.
- **Réception APNs réelle non vérifiée** : les tests utilisent un collecteur local, jamais APNs. Aucune preuve de réception sur appareil (STATUS.md).
- Les alertes de messagerie sont désactivées pour les écoles hors qualification comme la messagerie elle-même : aucun message n'existe, donc aucune alerte.

## Déploiement

Ordre : migration et API (le service d'envoi relit les nouvelles colonnes), puis web, puis app. Une API ancienne ignore les nouvelles catégories et saute leurs lignes (`course_push_revalidate` refuse les catégories inconnues). Le web et l'app lisent les trois nouveaux champs : ils exigent l'API à jour.
