import { z } from 'zod';

export const notificationKeys = [
  { key: 'courseOffers', label: 'Places et nouvelles sessions' },
  { key: 'courseReminders', label: 'Rappels de cours' },
  { key: 'courseChanges', label: 'Changements de cours' },
  { key: 'courseStaffAlerts', label: 'Alertes pour l’équipe' },
] as const;
export const notificationSchema = z.object({ data: z.object({ version: z.number().int().positive(),
  courseOffers: z.boolean(), courseReminders: z.boolean(), courseChanges: z.boolean(), courseStaffAlerts: z.boolean() }) });
export type NotificationPreferences = z.infer<typeof notificationSchema>['data'];
export type Choices = Omit<NotificationPreferences, 'version'>;
const url = '/app/bff/me/notification-preferences';

export type SaveOutcome = { ok: true; value: NotificationPreferences } | { ok: false; conflict: boolean };
/** PUT with the version read: a 412 means someone changed them elsewhere and nothing was written. */
export async function saveNotificationPreferences(choices: Choices, version: number, csrf: string, send: typeof fetch = fetch): Promise<SaveOutcome> {
  let response: Response;
  try {
    response = await send(url, { method: 'PUT', credentials: 'same-origin', cache: 'no-store', redirect: 'error',
      headers: { Accept: 'application/json, application/problem+json', 'Content-Type': 'application/json', 'X-CSRF-Token': csrf, 'If-Match': `"${version}"` },
      body: JSON.stringify(choices) });
  } catch { return { ok: false, conflict: false }; }
  if (response.status === 412) return { ok: false, conflict: true };
  if (!response.ok) return { ok: false, conflict: false };
  const parsed = notificationSchema.safeParse(await response.json().catch(() => null));
  return parsed.success ? { ok: true, value: parsed.data.data } : { ok: false, conflict: false };
}

export async function load(): Promise<NotificationPreferences> {
  const response = await fetch(url, { credentials: 'same-origin', cache: 'no-store', redirect: 'error', headers: { Accept: 'application/json' } });
  if (!response.ok) throw new Error(String(response.status));
  return notificationSchema.parse(await response.json()).data;
}

