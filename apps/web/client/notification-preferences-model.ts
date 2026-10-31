import { z } from 'zod';
import { RequestFailure } from './protocol.js';

/** Cours collectifs (#44) puis messagerie (#74) : un seul objet versionné côté serveur, deux groupes à l’écran. */
export const notificationKeys = [
  { key: 'courseOffers', label: 'Places et nouvelles sessions', group: 'courses' },
  { key: 'courseReminders', label: 'Rappels de cours', group: 'courses' },
  { key: 'courseChanges', label: 'Changements de cours', group: 'courses' },
  { key: 'courseStaffAlerts', label: 'Alertes pour l’équipe', group: 'courses' },
  { key: 'messagingPrivate', label: 'Messages privés', group: 'messages' },
  { key: 'messagingGeneral', label: 'Messages du général', group: 'messages' },
  { key: 'messagingMentions', label: 'Mentions', group: 'messages' },
] as const;
export const notificationSchema = z.object({ data: z.object({ version: z.number().int().positive(),
  courseOffers: z.boolean(), courseReminders: z.boolean(), courseChanges: z.boolean(), courseStaffAlerts: z.boolean(),
  messagingPrivate: z.boolean(), messagingGeneral: z.boolean(), messagingMentions: z.boolean() }) });
export type NotificationPreferences = z.infer<typeof notificationSchema>['data'];
export type Choices = Omit<NotificationPreferences, 'version'>;
const url = '/app/bff/me/notification-preferences';

export type SaveOutcome = { ok: true; value: NotificationPreferences }
  | { ok: false; conflict: true; kind: 'conflict' }
  | { ok: false; conflict: false; kind: 'uncertain' | 'rejected' | 'contextChanged'; status?: number };
/** PUT with the version read: a 412 means someone changed them elsewhere and nothing was written. */
export async function saveNotificationPreferences(choices: Choices, version: number, csrf: string, send: typeof fetch = fetch): Promise<SaveOutcome> {
  let response: Response;
  try {
    response = await send(url, { method: 'PUT', credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { Accept: 'application/json, application/problem+json', 'Content-Type': 'application/json', 'X-CSRF-Token': csrf, 'If-Match': `"${version}"` },
      signal: AbortSignal.timeout(25_000),
      body: JSON.stringify(choices) });
  } catch { return { ok: false, conflict: false, kind: 'uncertain' }; }
  if (response.status === 412) return { ok: false, conflict: true, kind: 'conflict' };
  const body: unknown = await response.json().catch(() => null);
  if (!response.ok) {
    const unknownResult = z.object({ code: z.enum(['SESSION_LOST_RESULT_UNKNOWN', 'RESULT_UNKNOWN', 'INVALID_RESPONSE']) }).safeParse(body).success;
    return { ok: false, conflict: false, kind: !unknownResult && response.status >= 400 && response.status < 500 && ![408,429].includes(response.status)
      ? 'rejected' : 'uncertain', status: response.status };
  }
  const parsed = notificationSchema.safeParse(body);
  return parsed.success && parsed.data.data.version > version && notificationKeys.every(({ key }) => parsed.data.data[key] === choices[key])
    ? { ok: true, value: parsed.data.data } : { ok: false, conflict: false, kind: 'uncertain' };
}

export async function load(send: typeof fetch = fetch): Promise<NotificationPreferences> {
  const response = await send(url, { credentials: 'same-origin', cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(25_000), headers: { Accept: 'application/json' } });
  if (!response.ok) throw new RequestFailure('PREFERENCES_UNAVAILABLE', response.status);
  return notificationSchema.parse(await response.json()).data;
}

