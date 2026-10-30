import { afterEach, expect, test, vi } from 'vitest';
import { proposalsSchema } from '../../../formation-api';
import { setupDraftSchema, setupTemplatesSchema } from '../../../setup-model';
import { db, ids, previewSchool } from '../fixtures';
import type { PreviewRequest, PreviewTools } from '../family';
import { catalogueFamily } from './catalogue';
import { setupFamily } from './setup';
import { overviewFamily } from './overview';

const tools = {
  reply: (status: number, body: unknown) => Response.json(body, { status }),
  envelope: (data: unknown) => ({ data, requestId: ids.school, serverTime: '2026-10-29T20:00:00.000Z' }),
} as PreviewTools;
const request = (path: string): PreviewRequest => ({ method: 'GET', path, segments: path.split('/'), collection: path.split('/')[0],
  resourceId: path.split('/')[1], action: undefined, query: new URLSearchParams(), headers: new Headers(), body: {}, scenario: 'normal' });
const read = (path: string) => [catalogueFamily, setupFamily, overviewFamily].map(family => family.read?.(request(path), tools)).find(Boolean)!;
afterEach(() => { vi.unstubAllGlobals(); previewSchool.status = 'ACTIVE'; });

test('la lecture commune des modèles prépare l’école et conserve les références du catalogue', async () => {
  const response = read('setup-draft/templates');
  expect(response.status).toBe(200);
  const body = await response.json();
  const setup = setupTemplatesSchema.parse(body.data);
  const proposals = proposalsSchema.parse(body.data);
  expect(setup.privacy.noticeText).not.toBe('');
  expect(setup.profileFields.map(item => item.field)).toEqual(['firstName', 'lastName']);
  expect(setup.formations.map(item => item.categoryCode)).toEqual(['A', 'A1', 'B', 'BE']);
  expect(proposals.formations.find(item => item.categoryCode === 'B')?.change?.kind).toBe('PEDAGOGICAL');
  expect(proposals.formations.find(item => item.categoryCode === 'BE')?.change?.kind).toBe('REGULATORY');
});

test('la préparation lit un brouillon complet de la bonne école avant la famille aperçu', async () => {
  vi.stubGlobal('window', { location: { search: '?page=preparation' } });
  setupFamily.seed?.(db);
  const body = await read('setup-draft').json();
  const draft = setupDraftSchema.parse(body.data);
  expect(draft.id).toBe(ids.school);
  expect(draft.schoolId).toBe(ids.school);
  expect(draft.status).toBe('DRAFT');
  expect(previewSchool.status).toBe('DRAFT');
});
