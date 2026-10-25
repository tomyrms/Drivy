import { describe, expect, it } from 'vitest';
import { decideMessagingNotification, messagingPushPayload, type MessagingNotificationSnapshot } from '../src/messaging-notifications.js';

const snapshot = (): MessagingNotificationSnapshot => ({
  accountId: 'person-a', schoolId: 'school-a', conversationId: 'conversation-a',
  recipientEligible: true, eventAvailable: true, deviceBelongsToAccount: true,
  systemPermission: 'AUTHORIZED', conversationSilenced: false,
  preferences: { version: 7, pushEnabled: true, categories: { MESSAGING_PRIVATE: true, MESSAGING_GENERAL: true, MESSAGING_MENTION: true, MESSAGING_POLL: true } }
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
  it('payload carries only technical identifiers for per-conversation cleanup', () => {
    const payload = messagingPushPayload(event, { allowed: true, category: 'MESSAGING_GENERAL', preferenceVersion: 7 }, 12, { title: 'Drivy', body: 'Nouveau message' });
    expect(payload).toEqual({ aps: { alert: { title: 'Drivy', body: 'Nouveau message' }, sound: 'default', 'thread-id': 'messaging:school-a:conversation-a' },
      kind: 'MESSAGING', category: 'MESSAGING_GENERAL', schoolId: 'school-a', conversationId: 'conversation-a', sequence: 12 });
    expect(() => messagingPushPayload(event, { allowed: true, category: 'MESSAGING_GENERAL', preferenceVersion: 7 }, 0, { title: '', body: '' })).toThrow();
  });
  it('selects private and poll categories without reading message content', () => {
    expect(decideMessagingNotification({ ...event, kind: 'PRIVATE' }, snapshot())).toEqual({ allowed: true, category: 'MESSAGING_PRIVATE', preferenceVersion: 7 });
    expect(decideMessagingNotification({ ...event, kind: 'POLL' }, snapshot())).toEqual({ allowed: true, category: 'MESSAGING_POLL', preferenceVersion: 7 });
  });
});
