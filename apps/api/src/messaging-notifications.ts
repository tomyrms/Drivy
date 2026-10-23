/** Consumer contract for #44, not another preferences store or a push transport.
 * The common notification worker must obtain a fresh, authoritative snapshot immediately
 * before delivery. A cached ALLOW is not an authorization to send later.
 * Category names are proposed until #44 integrates them. No UI switches are exposed here.
 */
export type MessagingNotificationCategory = 'MESSAGING_PRIVATE' | 'MESSAGING_GENERAL' | 'MESSAGING_MENTION' | 'MESSAGING_POLL';
export interface MessagingNotificationEvent {
  accountId: string;
  schoolId: string;
  conversationId: string;
  kind: 'PRIVATE' | 'GENERAL' | 'POLL';
  mentionsRecipient: boolean;
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
    : event.kind === 'PRIVATE' ? 'MESSAGING_PRIVATE' : event.kind === 'POLL' ? 'MESSAGING_POLL' : 'MESSAGING_GENERAL';
  if (preferences.categories[category] !== true) return { allowed: false, reason: 'CATEGORY_DISABLED' };
  return { allowed: true, category, preferenceVersion: preferences.version };
}
