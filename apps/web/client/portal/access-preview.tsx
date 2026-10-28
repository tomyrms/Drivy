import { createRoot } from 'react-dom/client';
import { useRef, useState } from 'react';
import { z } from 'zod';
import { ConsoleContext, type ConsoleContextValue } from '../console/context';
import { ScopedReadCache } from '../console/load-model';
import { commandStore, useCommandSnapshot } from '../command-store';
import { PortalFrame } from './frame';
import { AccessPilot } from './access/access-page';
import { Button } from '../components/ui/button';
import { Alert, AlertTitle, AlertDescription } from '../components/ui/alert';
import type { Role } from '../protocol';
import './portal.css';

declare const __DRIVY_PREVIEW_SHA__: string;
z.config({ jitless: true });
const schoolId = '31100000-0000-4000-8000-000000000001';
const personId = '31100000-0000-4000-8000-000000000002';
const adminId = '31100000-0000-4000-8000-000000000003';
const memberId = '31100000-0000-4000-8000-000000000004';
const params = new URLSearchParams(location.search);
let simulateRefusal = params.get('state') === 'error';
const members = [
  { id: adminId, schoolId, personId, displayName: 'Luc Martin', version: 1, status: 'ACTIVE', roles: ['ADMIN', 'INSTRUCTOR'] as Role[], grants: [] as string[], accessEpoch: 1 },
  { id: memberId, schoolId, personId: '31100000-0000-4000-8000-000000000005', displayName: 'Marie Dupont', version: 1, status: 'ACTIVE', roles: ['INSTRUCTOR'] as Role[], grants: ['permit_review', 'TAKE_ATTENDANCE'], accessEpoch: 1 },
];
const school = { id: schoolId, schoolId, version: 1, name: 'École du Léman', timeZone: 'Europe/Zurich', status: 'ACTIVE', contactEmail: 'ecole@example.test', contactPhone: null, configurationVersion: 1,
  modules: { gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false } };
const envelope = (data: unknown) => ({ data, requestId: crypto.randomUUID(), serverTime: new Date().toISOString() });
const results = new Map<string, unknown>();
/** This entry never delegates fetch: no real account, API or command can be reached. */
window.fetch = (async (input: URL | RequestInfo, init?: RequestInit) => {
  const url = new URL(input instanceof Request ? input.url : String(input), location.href);
  const reply = (status: number, data: unknown) => {
    const response = new Response(JSON.stringify(data), { status, headers: { 'Content-Type': 'application/json' } });
    Object.defineProperty(response, 'url', { value: url.href }); return response;
  };
  if (url.origin !== location.origin || !url.pathname.startsWith(`/app/bff/schools/${schoolId}/`)) return reply(403, { code: 'PREVIEW_NETWORK_BLOCKED' });
  const path = url.pathname.split(`/schools/${schoolId}/`)[1];
  const method = init?.method ?? 'GET';
  if (method === 'GET' && path === 'members') return reply(200, envelope({ items: structuredClone(members), nextCursor: null }));
  const headers = new Headers(init?.headers);
  const operationId = headers.get('Idempotency-Key');
  if (operationId && results.has(operationId)) return reply(200, results.get(operationId));
  if (method === 'PATCH' && path?.startsWith('members/') || method === 'POST' && path?.endsWith('/deactivate')) {
    await new Promise(resolve => setTimeout(resolve, 1100));
    if (simulateRefusal) return reply(409, { code: 'LAST_ADMIN' });
    const member = members.find(item => item.id === path?.split('/')[1]);
    if (!member || headers.get('If-Match') !== `"${member.version}"`) return reply(412, { code: 'VERSION_CONFLICT' });
    const body = JSON.parse(String(init?.body ?? '{}'));
    if (!String(body.reason ?? '').trim()) return reply(400, { code: 'INVALID_REQUEST' });
    if (method === 'PATCH') { member.roles = body.roles; member.grants = body.grants; } else member.status = 'INACTIVE';
    member.version++; member.accessEpoch++;
    const response = envelope(structuredClone(member));
    if (operationId) results.set(operationId, response);
    return reply(200, response);
  }
  return reply(404, { code: 'NOT_FOUND' });
}) as typeof fetch;
commandStore.scopeToPerson(personId);
commandStore.scopeToAccess(schoolId, adminId, 1);

function Preview() {
  const [refusal, setRefusal] = useState(simulateRefusal);
  const [selection, setSelection] = useState(params.get('self') === '1' ? adminId : memberId);
  const drafts = useRef(new Map<string, unknown>());
  const cache = useRef(new ScopedReadCache());
  const snapshot = useCommandSnapshot();
  const value: ConsoleContextValue = {
    schoolId, school, me: { personId, displayName: 'Luc Martin', version: 1, memberships: [] },
    membership: { membershipId: adminId, schoolId, schoolName: school.name, roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 },
    canConfigureCatalog: true, csrf: () => 'synthetic-preview', refreshCsrf: async () => 'synthetic-preview', reloadSchool: async () => {},
    navigate: () => {}, login: () => {}, routeQuery: { selection }, setRouteQuery: query => setSelection(query.selection ?? memberId), drafts: drafts.current, readCache: cache.current,
  };
  return <ConsoleContext.Provider value={value}><PortalFrame active="equipe" onNavigate={() => {}} schoolName={school.name} userName="Luc Martin" build={__DRIVY_PREVIEW_SHA__}>
    {snapshot.entries.size > 0 && <Alert><AlertTitle id="pending-title" tabIndex={-1}>Confirmation de l’aperçu</AlertTitle><AlertDescription>{[...snapshot.entries.values()].some(entry => entry.phase === 'sending') ? 'Enregistrement simulé en cours…' : 'Résultat non confirmé.'}</AlertDescription></Alert>}
    <AccessPilot initialEdit={params.get('mode') !== 'read'} />
    <div className="preview-controls"><span>Aperçu interactif · aucun compte réel</span><Button variant="ghost" onClick={() => { simulateRefusal = !refusal; setRefusal(!refusal); }} aria-pressed={refusal}>{refusal ? 'Refus simulé activé' : 'Simuler un refus'}</Button><Button variant="ghost" onClick={() => location.reload()}>Réinitialiser</Button></div>
  </PortalFrame></ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<Preview />);
