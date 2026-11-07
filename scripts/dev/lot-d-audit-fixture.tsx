import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { commandStore } from '/apps/web/client/command-store';
import { createCommand } from '/apps/web/client/command-core';
import { AvailabilityPilot } from '/apps/web/client/portal/availability/schedule-page';
import '/apps/web/client/portal/portal.css';

// Fixture synthétique du lot D (#422 horaires, #430 reprise des horaires) : vrais composants, API simulée, aucune donnée réelle.
const schoolId = '10000000-0000-4000-8000-000000000001';
const otherSchoolId = '10000000-0000-4000-8000-0000000000f1';
const personId = '10000000-0000-4000-8000-000000000002';
const membershipId = '10000000-0000-4000-8000-000000000003';
const requestId = '10000000-0000-4000-8000-000000000004';
const ruleId = '30000000-0000-4000-8000-000000000001';
const serverTime = '2030-01-01T10:00:00Z';
const school = { id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE', modules: {} };
const membership = { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 };

let rule = { id: ruleId, schoolId, version: 1, instructorMembershipId: membershipId, weekdays: [1], localStart: '08:00', localEnd: '17:00', validFrom: '2020-01-01', validUntil: null as string | null };
const members = [{ id: membershipId, schoolId, version: 1, personId, displayName: 'Moniteur synthétique', status: 'ACTIVE', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 }];
const writes: any[] = [];
let held: { release: () => void } | null = null;
let outcome: 'conflict' | 'ok' = 'conflict';

function reply(data: unknown, status: number, url: string) {
  const response = new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
  Object.defineProperty(response, 'url', { value: url });
  return response;
}
const envelope = (data: unknown) => ({ data, requestId, serverTime });
const page = (items: unknown[]) => envelope({ items, nextCursor: null });
window.fetch = async (input: any, init?: RequestInit) => {
  const url = String(input instanceof URL ? input.href : input);
  const path = new URL(url, location.origin).pathname;
  const method = init?.method ?? 'GET';
  if (method === 'PUT' && path.endsWith(`/availability-rules/${ruleId}`)) {
    const headers = Object.fromEntries(new Headers(init?.headers));
    writes.push({ body: JSON.parse(String(init?.body)), ifMatch: headers['if-match'] ?? null });
    await new Promise<void>(done => { held = { release: done }; });
    held = null;
    if (outcome === 'conflict') return reply({ code: 'VERSION_CONFLICT' }, 412, url);
    rule = { ...rule, ...(writes.at(-1).body as object), version: rule.version + 1 } as typeof rule;
    return reply(envelope(rule), 200, url);
  }
  if (method === 'POST' && path.endsWith('/closures')) return reply(envelope({ id: '40000000-0000-4000-8000-000000000001', schoolId, version: 1, instructorMembershipId: membershipId,
    startsAt: '2031-01-01T08:00:00Z', endsAt: '2031-01-01T09:00:00Z', reason: null }), 201, url);
  if (path.endsWith('/members')) return reply(page(members), 200, url);
  if (path.endsWith('/availability-rules')) return reply(page([rule]), 200, url);
  if (path.endsWith('/closures')) return reply(page([]), 200, url);
  return reply(envelope({}), 200, url);
};
commandStore.scopeToAccess(schoolId, membershipId, 1);

/** Un autre administrateur modifie l'horaire ; une confirmation d'absence fait relire le planning, comme en production. */
async function externalChange(patch: Partial<typeof rule>) {
  rule = { ...rule, ...patch, version: rule.version + 1 };
  const command = createCommand({ schoolId, kind: 'createClosure', path: 'closures', resourceVersion: 0,
    body: { instructorMembershipId: membershipId, startsAt: '2031-01-01T08:00:00Z', endsAt: '2031-01-01T09:00:00Z' }, scope: membershipId });
  await commandStore.submit(command, 'synthetic');
}

const drafts = new Map<string, unknown>();
function App() {
  const [shown, setShown] = useState(true);
  const [scope, setScope] = useState(schoolId);
  const value = {
    schoolId: scope, school: { ...school, id: scope, schoolId: scope }, me: { personId, displayName: 'Administrateur synthétique', locale: 'fr', memberships: [] },
    membership: { ...membership, schoolId: scope }, canConfigureCatalog: true, routeQuery: {}, navigate: () => {}, reloadSchool: async () => {}, csrf: () => 'synthetic',
    refreshCsrf: async () => 'synthetic', login: () => {}, drafts: scope === schoolId ? drafts : new Map(), setNavigationGuard: () => {},
  };
  (window as any).fixture = {
    writes: () => writes, waiting: () => held !== null, release: () => held?.release(), outcome: (next: 'conflict' | 'ok') => { outcome = next; },
    externalChange, serverChange: (patch: Partial<typeof rule>) => { rule = { ...rule, ...patch, version: rule.version + 1 }; }, rule: () => rule, hide: () => setShown(false), show: () => setShown(true), otherSchool: () => setScope(otherSchoolId), ownSchool: () => setScope(schoolId),
    journalKeys: () => [...drafts.keys()],
  };
  return <ConsoleContext.Provider value={value as any}>
    <main className="portal-main" style={{ padding: 24 }}>{shown ? <AvailabilityPilot /> : <p id="elsewhere">Autre page</p>}</main>
  </ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<App />);
