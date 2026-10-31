/** Décision d'alerte de messagerie (#44, #74), consommée par le service d'envoi commun (`course-push.ts`).
 * Ce n'est ni un second stockage de préférences ni un transport : la file `push_notification` et la table versionnée
 * `notification_preference` restent la seule source. Le service d'envoi relit un instantané frais et faisant autorité
 * (`drivy.push_messaging_snapshot`) immédiatement avant l'envoi ; un ALLOW mis en cache n'autorise jamais un envoi ultérieur.
 * Décisions : docs/implementation/messaging-notifications-74.md.
 */
export type MessagingNotificationCategory = 'MESSAGING_PRIVATE' | 'MESSAGING_GENERAL' | 'MESSAGING_MENTION';
export interface MessagingNotificationEvent {
  accountId: string;
  schoolId: string;
  conversationId: string;
  /** Un sondage est un message : il suit la catégorie de sa conversation (décision du 31 octobre 2026). */
  kind: 'PRIVATE' | 'GENERAL';
  mentionsRecipient: boolean;
  messageId?: string;
}
export interface MessagingNotificationSnapshot {
  accountId: string;
  schoolId: string;
  conversationId: string;
  recipientEligible: boolean;
  eventAvailable: boolean;
  deviceBelongsToAccount: boolean;
  systemPermission: 'AUTHORIZED' | 'DENIED' | 'UNKNOWN';
  conversationSilenced: boolean;
  preferences: {
    version: number;
    pushEnabled: boolean;
    categories: Partial<Record<MessagingNotificationCategory, boolean>>;
  } | null;
}
export type MessagingNotificationDecision =
  | { allowed: true; category: MessagingNotificationCategory; preferenceVersion: number }
  | { allowed: false; reason: 'CONTEXT_MISMATCH' | 'ACCESS_REVOKED' | 'EVENT_UNAVAILABLE' | 'DEVICE_UNAVAILABLE' | 'PREFERENCES_UNAVAILABLE' | 'PUSH_DISABLED' | 'SILENCED' | 'CATEGORY_DISABLED' };

/** APNs payload for an allowed messaging event (#103). Technical identifiers only: no text, name or secret.
 * `thread-id` groups alerts per school+conversation; `conversationId`/`schoolId`/`sequence` let the app
 * remove exactly the delivered alerts of one conversation up to its confirmed read sequence and open the right conversation.
 * An empty alert body is omitted: the lock screen shows a generic title only. */
export function messagingPushPayload(event: MessagingNotificationEvent, decision: Extract<MessagingNotificationDecision, { allowed: true }>,
  sequence: number, alert: { title: string; body: string }) {
  if (!Number.isSafeInteger(sequence) || sequence < 1) throw new Error('INVALID_SEQUENCE');
  return {
    aps: { alert: { title: alert.title, ...(alert.body ? { body: alert.body } : {}) }, sound: 'default', 'thread-id': `messaging:${event.schoolId}:${event.conversationId}` },
    kind: 'MESSAGING', category: decision.category,
    schoolId: event.schoolId, conversationId: event.conversationId, ...(event.messageId ? { messageId: event.messageId } : {}), sequence
  };
}

export function decideMessagingNotification(event: MessagingNotificationEvent, state: MessagingNotificationSnapshot): MessagingNotificationDecision {
  if (event.accountId !== state.accountId || event.schoolId !== state.schoolId || event.conversationId !== state.conversationId) return { allowed: false, reason: 'CONTEXT_MISMATCH' };
  if (!state.recipientEligible) return { allowed: false, reason: 'ACCESS_REVOKED' };
  if (!state.eventAvailable) return { allowed: false, reason: 'EVENT_UNAVAILABLE' };
  if (!state.deviceBelongsToAccount || state.systemPermission !== 'AUTHORIZED') return { allowed: false, reason: 'DEVICE_UNAVAILABLE' };
  const preferences = state.preferences;
  if (!preferences || !Number.isSafeInteger(preferences.version) || preferences.version < 1) return { allowed: false, reason: 'PREFERENCES_UNAVAILABLE' };
  if (preferences.pushEnabled !== true) return { allowed: false, reason: 'PUSH_DISABLED' };
  if (state.conversationSilenced) return { allowed: false, reason: 'SILENCED' };
  // One category per logical event. A disabled mention never falls back to GENERAL.
  const category: MessagingNotificationCategory = event.mentionsRecipient ? 'MESSAGING_MENTION'
    : event.kind === 'PRIVATE' ? 'MESSAGING_PRIVATE' : 'MESSAGING_GENERAL';
  if (preferences.categories[category] !== true) return { allowed: false, reason: 'CATEGORY_DISABLED' };
  return { allowed: true, category, preferenceVersion: preferences.version };
}

/** Catégories de la file `push_notification.category` portées par la messagerie, et leur catégorie de contrat. */
export const queuedMessagingCategories = {
  MESSAGE_PRIVATE: 'MESSAGING_PRIVATE',
  MESSAGE_GENERAL: 'MESSAGING_GENERAL',
  MESSAGE_MENTION: 'MESSAGING_MENTION'
} as const satisfies Record<string, MessagingNotificationCategory>;
export type QueuedMessagingCategory = keyof typeof queuedMessagingCategories;
export function isQueuedMessagingCategory(category: string): category is QueuedMessagingCategory {
  return Object.hasOwn(queuedMessagingCategories, category);
}

/** Ligne de `drivy.push_messaging_snapshot` : des faits, aucune décision et aucune donnée de message. */
export interface MessagingSnapshotRow {
  conversation_kind: string | null;
  mentions_recipient: boolean;
  recipient_eligible: boolean;
  event_available: boolean;
  conversation_silenced: boolean;
  preference_version: number;
  pref_private: boolean;
  pref_general: boolean;
  pref_mentions: boolean;
}
export interface QueuedMessagingNotification {
  person_id: string;
  school_id: string;
  conversation_id: string;
  message_id: string | null;
}

/** Assemble l'événement et l'instantané du contrat à partir de la ligne en file et des faits relus.
 * Aucun interrupteur général n'existe dans les préférences : `pushEnabled` vaut vrai, chaque catégorie se refuse seule.
 * Le serveur ne lit pas l'autorisation système d'iOS : l'app n'enregistre un jeton qu'une fois cette autorisation accordée,
 * donc un appareil actif vaut « autorisé » ; un refus ultérieur dans Réglages reste appliqué par iOS lui-même. */
export function messagingNotificationInputs(queued: QueuedMessagingNotification, row: MessagingSnapshotRow, hasActiveDevice: boolean):
  { event: MessagingNotificationEvent; snapshot: MessagingNotificationSnapshot } {
  const event: MessagingNotificationEvent = {
    accountId: queued.person_id, schoolId: queued.school_id, conversationId: queued.conversation_id,
    kind: row.conversation_kind === 'PRIVATE' ? 'PRIVATE' : 'GENERAL', mentionsRecipient: row.mentions_recipient,
    ...(queued.message_id ? { messageId: queued.message_id } : {})
  };
  return {
    event,
    snapshot: {
      accountId: queued.person_id, schoolId: queued.school_id, conversationId: queued.conversation_id,
      recipientEligible: row.recipient_eligible, eventAvailable: row.event_available,
      deviceBelongsToAccount: hasActiveDevice, systemPermission: hasActiveDevice ? 'AUTHORIZED' : 'UNKNOWN',
      conversationSilenced: row.conversation_silenced,
      preferences: { version: row.preference_version, pushEnabled: true,
        categories: { MESSAGING_PRIVATE: row.pref_private, MESSAGING_GENERAL: row.pref_general, MESSAGING_MENTION: row.pref_mentions } }
    }
  };
}

/** Code conservé dans `push_notification.failure_code` pour une alerte non envoyée (même vocabulaire que les cours). */
export function messagingSkipCode(reason: Extract<MessagingNotificationDecision, { allowed: false }>['reason']): string {
  switch (reason) {
    case 'ACCESS_REVOKED': return 'RECIPIENT_INELIGIBLE';
    case 'DEVICE_UNAVAILABLE': return 'NO_DEVICE';
    case 'PREFERENCES_UNAVAILABLE': return 'PREFERENCE_UNAVAILABLE';
    case 'PUSH_DISABLED':
    case 'CATEGORY_DISABLED': return 'PREFERENCE_DISABLED';
    case 'SILENCED': return 'SILENCED';
    case 'EVENT_UNAVAILABLE':
    case 'CONTEXT_MISMATCH': return 'EVENT_OBSOLETE';
  }
}
