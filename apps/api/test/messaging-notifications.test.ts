import { describe, expect, it } from 'vitest';
import { decideMessagingNotification, isQueuedMessagingCategory, messagingNotificationInputs, messagingPushPayload, messagingSkipCode,
  queuedMessagingCategories, type MessagingNotificationSnapshot, type MessagingSnapshotRow } from '../src/messaging-notifications.js';

const snapshot = (): MessagingNotificationSnapshot => ({
  accountId: 'person-a', schoolId: 'school-a', conversationId: 'conversation-a',
  recipientEligible: true, eventAvailable: true, deviceBelongsToAccount: true,
  systemPermission: 'AUTHORIZED', conversationSilenced: false,
  preferences: { version: 7, pushEnabled: true, categories: { MESSAGING_PRIVATE: true, MESSAGING_GENERAL: true, MESSAGING_MENTION: true } }
});
const event = { accountId: 'person-a', schoolId: 'school-a', conversationId: 'conversation-a', kind: 'GENERAL' as const, mentionsRecipient: false };

describe('messaging notification contract for #44', () => {
  it('refuses absent preferences instead of creating optional opt-ins', () => {
    expect(decideMessagingNotification(event, { ...snapshot(), preferences: null })).toEqual({ allowed: false, reason: 'PREFERENCES_UNAVAILABLE' });
  });
  it('never crosses account, school or conversation contexts', () => {
    for (const field of ['accountId', 'schoolId', 'conversationId'] as const) {
      expect(decideMessagingNotification(event, { ...snapshot(), [field]: 'other' }).allowed).toBe(false);
    }
  });
  it('revalidates recipient, event and device before transport', () => {
    for (const field of ['recipientEligible', 'eventAvailable', 'deviceBelongsToAccount'] as const) {
      expect(decideMessagingNotification(event, { ...snapshot(), [field]: false }).allowed).toBe(false);
    }
  });
  it('silence and global refusal cannot be overridden by a mention', () => {
    const mentioned = { ...event, mentionsRecipient: true };
    expect(decideMessagingNotification(mentioned, { ...snapshot(), conversationSilenced: true }).allowed).toBe(false);
    const state = snapshot(); state.preferences!.pushEnabled = false;
    expect(decideMessagingNotification(mentioned, state).allowed).toBe(false);
  });
  it('chooses one mention category, never falls back to a general notification', () => {
    const state = snapshot(); state.preferences!.categories.MESSAGING_MENTION = false;
    expect(decideMessagingNotification({ ...event, mentionsRecipient: true }, state).allowed).toBe(false);
    expect(decideMessagingNotification({ ...event, mentionsRecipient: true }, snapshot())).toEqual({ allowed: true, category: 'MESSAGING_MENTION', preferenceVersion: 7 });
  });
  it('refuses an unknown system permission and missing category', () => {
    expect(decideMessagingNotification(event, { ...snapshot(), systemPermission: 'UNKNOWN' }).allowed).toBe(false);
    const state = snapshot(); delete state.preferences!.categories.MESSAGING_GENERAL;
    expect(decideMessagingNotification(event, state).allowed).toBe(false);
  });
  it('payload carries only technical identifiers for per-conversation cleanup and opening, with a generic title and no body', () => {
    const payload = messagingPushPayload({ ...event, messageId: 'message-a' }, { allowed: true, category: 'MESSAGING_GENERAL', preferenceVersion: 7 }, 12, { title: 'Nouveau message', body: '' });
    expect(payload).toEqual({ aps: { alert: { title: 'Nouveau message' }, sound: 'default', 'thread-id': 'messaging:school-a:conversation-a' },
      kind: 'MESSAGING', category: 'MESSAGING_GENERAL', schoolId: 'school-a', conversationId: 'conversation-a', messageId: 'message-a', sequence: 12 });
    expect(messagingPushPayload(event, { allowed: true, category: 'MESSAGING_GENERAL', preferenceVersion: 7 }, 12, { title: 'Drivy', body: 'Texte' }).aps.alert)
      .toEqual({ title: 'Drivy', body: 'Texte' });
    expect(() => messagingPushPayload(event, { allowed: true, category: 'MESSAGING_GENERAL', preferenceVersion: 7 }, 0, { title: '', body: '' })).toThrow();
  });
  it('selects the private category from the conversation kind without reading message content', () => {
    expect(decideMessagingNotification({ ...event, kind: 'PRIVATE' }, snapshot())).toEqual({ allowed: true, category: 'MESSAGING_PRIVATE', preferenceVersion: 7 });
    expect(decideMessagingNotification({ ...event, kind: 'PRIVATE' }, { ...snapshot(), preferences: { version: 7, pushEnabled: true, categories: { MESSAGING_PRIVATE: false } } }))
      .toEqual({ allowed: false, reason: 'CATEGORY_DISABLED' });
  });
});

describe('messaging notification worker inputs (#74)', () => {
  const queued = { person_id: 'person-a', school_id: 'school-a', conversation_id: 'conversation-a', message_id: 'message-a' };
  const row = (): MessagingSnapshotRow => ({ conversation_kind: 'GENERAL', mentions_recipient: false, recipient_eligible: true, event_available: true,
    conversation_silenced: false, preference_version: 3, pref_private: true, pref_general: false, pref_mentions: true });
  const decide = (overrides: Partial<MessagingSnapshotRow>, device = true) => {
    const { event, snapshot } = messagingNotificationInputs(queued, { ...row(), ...overrides }, device);
    return decideMessagingNotification(event, snapshot);
  };
  it('applies the defaults: private and mentions on, general off', () => {
    expect(decide({ conversation_kind: 'PRIVATE' })).toEqual({ allowed: true, category: 'MESSAGING_PRIVATE', preferenceVersion: 3 });
    expect(decide({ mentions_recipient: true })).toEqual({ allowed: true, category: 'MESSAGING_MENTION', preferenceVersion: 3 });
    expect(decide({})).toEqual({ allowed: false, reason: 'CATEGORY_DISABLED' });
    expect(decide({ pref_general: true })).toEqual({ allowed: true, category: 'MESSAGING_GENERAL', preferenceVersion: 3 });
  });
  it('a disabled mention never falls back to the general category', () => {
    expect(decide({ mentions_recipient: true, pref_mentions: false, pref_general: true })).toEqual({ allowed: false, reason: 'CATEGORY_DISABLED' });
  });
  it('treats an active registered device as authorized and none as unavailable', () => {
    expect(decide({ pref_general: true }, false)).toEqual({ allowed: false, reason: 'DEVICE_UNAVAILABLE' });
  });
  it('carries the conversation, silence and access facts through unchanged', () => {
    expect(decide({ conversation_silenced: true })).toEqual({ allowed: false, reason: 'SILENCED' });
    expect(decide({ recipient_eligible: false })).toEqual({ allowed: false, reason: 'ACCESS_REVOKED' });
    expect(decide({ event_available: false })).toEqual({ allowed: false, reason: 'EVENT_UNAVAILABLE' });
  });
  it('maps every refusal to a stored failure code and every queued category to its contract category', () => {
    expect(['ACCESS_REVOKED', 'EVENT_UNAVAILABLE', 'DEVICE_UNAVAILABLE', 'PREFERENCES_UNAVAILABLE', 'PUSH_DISABLED', 'SILENCED', 'CATEGORY_DISABLED', 'CONTEXT_MISMATCH']
      .map(reason => messagingSkipCode(reason as never))).toEqual(['RECIPIENT_INELIGIBLE', 'EVENT_OBSOLETE', 'NO_DEVICE', 'PREFERENCE_UNAVAILABLE',
      'PREFERENCE_DISABLED', 'SILENCED', 'PREFERENCE_DISABLED', 'EVENT_OBSOLETE']);
    expect(queuedMessagingCategories).toEqual({ MESSAGE_PRIVATE: 'MESSAGING_PRIVATE', MESSAGE_GENERAL: 'MESSAGING_GENERAL', MESSAGE_MENTION: 'MESSAGING_MENTION' });
    expect(['MESSAGE_PRIVATE', 'MESSAGE_GENERAL', 'MESSAGE_MENTION'].every(isQueuedMessagingCategory)).toBe(true);
    expect(['OFFER', 'CHANGE', 'toString', '__proto__'].some(isQueuedMessagingCategory)).toBe(false);
  });
});
