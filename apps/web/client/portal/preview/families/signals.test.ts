import { expect, test } from 'vitest';
import { observationPreferencesSchema } from '../../../school-api';
import { ids, previewMembership } from '../fixtures';
import type { PreviewRequest, PreviewTools } from '../family';
import { signalsFamily } from './signals';

/** L'aperçu rejoue la matrice R08 : ce que l'écran montre est ce que le serveur accepterait, école libre ou imposée, administrateur ou moniteur. */
let version = 1;
const tools = {
  reply: (status: number, body: unknown) => Response.json(body, { status }),
  envelope: (data: unknown) => ({ data, requestId: ids.school, serverTime: '2026-11-12T10:00:00.000Z' }),
  versionMatches: (record: { version: number } | undefined) => !!record && `"${version}"` === `"${record.version}"`,
  commit: (_kind: string, record: unknown) => Response.json({ data: record }, { status: 200 }),
} as unknown as PreviewTools;
const call = (method: string, path: string, body: Record<string, unknown> = {}, ifMatch = version): Response | undefined => {
  version = ifMatch;
  const request: PreviewRequest = { method, path, segments: path.split('/'), collection: path.split('/')[0], resourceId: undefined, action: undefined,
    query: new URLSearchParams(), headers: new Headers(), body, scenario: 'normal' };
  return method === 'GET' ? signalsFamily.read?.(request, tools) : signalsFamily.write?.(request, tools);
};
const read = async () => { const response = (await call('GET', 'observation-preferences'))!; const body = await response.json(); return observationPreferencesSchema.parse(body.data); };
const setPolicy = async (allowed: boolean) => {
  const school = await (call('GET', 'observation-themes') as Response).json();
  call('PUT', 'observation-themes', { themes: school.data.themes.map((t: { key: string; visible: boolean }) => ({ key: t.key, visible: t.visible })), personalizationAllowed: allowed }, school.data.version);
};

test('la lecture respecte le schéma du contrat : dix-huit thèmes, palette filtrée, visibilité modifiable selon la politique', async () => {
  const data = await read();
  expect(data.themes).toHaveLength(18);
  expect(data.palette).toHaveLength(12);
  expect(data.themes.every(theme => theme.visibilityEditable)).toBe(true);
});

test('école libre : ordre, visibilité et mode s’enregistrent, la version avance, un If-Match périmé est refusé', async () => {
  let data = await read();
  const reversed = data.themes.map(theme => theme.key).reverse();
  const stale = call('PUT', 'observation-preferences', { order: reversed }, data.version + 5)!;
  expect(stale.status).toBe(412);
  const saved = call('PUT', 'observation-preferences', { order: reversed, mode: 'SMART' }, data.version)!;
  expect(saved.status).toBe(200);
  data = await read();
  expect(data.mode).toBe('SMART');
  expect(data.orderCustomized).toBe(true);
  expect(data.themes.map(theme => theme.key)).toEqual(reversed);
  const hidden = call('PUT', 'observation-preferences', { visibility: data.themes.map(theme => ({ key: theme.key, visible: theme.key !== 'speed' })) }, data.version)!;
  expect(hidden.status).toBe(200);
  expect((await read()).palette).not.toContain('speed');
});

test('école imposée : l’ordre part, la visibilité est refusée (403), rien n’est écrit', async () => {
  await setPolicy(false);
  let data = await read();
  expect(data.personalizationAllowed).toBe(false);
  expect(data.themes.every(theme => !theme.visibilityEditable)).toBe(true);
  const before = data.version;
  const refused = call('PUT', 'observation-preferences', { visibility: data.themes.map(theme => ({ key: theme.key, visible: true })) }, before)!;
  expect(refused.status).toBe(403);
  expect((await refused.json()).code).toBe('OBSERVATION_PERSONALIZATION_DISABLED');
  expect((await read()).version).toBe(before);
  const order = call('PUT', 'observation-preferences', { order: data.themes.map(theme => theme.key).reverse() }, before)!;
  expect(order.status).toBe(200);
  data = await read();
  expect(data.version).toBe(before + 1);
});

test('reset de présentation : administrateur toujours, moniteur seulement en école libre ; reset d’apprentissage pour tous', async () => {
  await setPolicy(false);
  const roles = previewMembership.roles;
  try {
    previewMembership.roles = ['INSTRUCTOR'];
    expect(call('POST', 'observation-preferences/presentation-reset', {}, (await read()).version)!.status).toBe(403);
    expect(call('POST', 'observation-preferences/learning-reset', {}, (await read()).version)!.status).toBe(200);
    expect((await read()).learning.generation).toBeGreaterThan(0);
    previewMembership.roles = ['ADMIN'];
    expect(call('POST', 'observation-preferences/presentation-reset', {}, (await read()).version)!.status).toBe(200);
    await setPolicy(true);
    previewMembership.roles = ['INSTRUCTOR'];
    expect(call('POST', 'observation-preferences/presentation-reset', {}, (await read()).version)!.status).toBe(200);
  } finally { previewMembership.roles = roles; }
});

test('un corps vide, l’ancien champ themes ou une clé inconnue donnent 400', async () => {
  const data = await read();
  expect(call('PUT', 'observation-preferences', {}, data.version)!.status).toBe(400);
  expect(call('PUT', 'observation-preferences', { themes: [] }, data.version)!.status).toBe(400);
  expect(call('PUT', 'observation-preferences', { order: ['inconnu'] }, data.version)!.status).toBe(400);
});
