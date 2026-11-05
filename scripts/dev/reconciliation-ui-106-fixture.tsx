import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { SchoolSettingsPilot } from '/apps/web/client/portal/settings/school-page';
import { commandStore } from '/apps/web/client/command-store';
import '/apps/web/client/portal/portal.css';
const schoolId = '10000000-0000-4000-8000-000000000001';
const personId = '10000000-0000-4000-8000-000000000002';
const membershipId = '10000000-0000-4000-8000-000000000003';
const requestId = '10000000-0000-4000-8000-000000000004';
const serverTime = '2030-01-01T10:00:00Z';
const school = {
  id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'DRAFT',
  contactEmail: 'ecole@example.invalid', contactPhone: null, configurationVersion: 1,
  modules: { gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false },
};
const me = { personId, displayName: 'Administrateur synthétique', locale: 'fr', memberships: [] };
const membership = { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN'], grants: [], accessEpoch: 1 };
const consoleValue = {
  schoolId, school, me, membership, canConfigureCatalog: true, routeQuery: {}, navigate: () => {},
  reloadSchool: async () => {}, csrf: () => 'synthetic', refreshCsrf: async () => 'synthetic', login: () => {},
  drafts: new Map(), setNavigationGuard: () => {},
};


let durable = { ...school, status: 'ACTIVE' };
let release: (() => void) | null = null;
let failRead = false;
let receipt = false;
const writes: any[] = [];
function reply(data: unknown, status = 200, url: string) { const response = new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } }); Object.defineProperty(response, 'url', { value: url }); return response; }
function envelope(data: unknown) { return { data, requestId, serverTime }; }
window.fetch = async (input, init) => {
 const url = String(input);
 const respond = (data: unknown, status = 200) => reply(data, status, url);
 const path = new URL(url, location.origin).pathname;
 if (init?.method === 'PATCH') {
   writes.push({ body: JSON.parse(String(init.body)), headers: Object.fromEntries(new Headers(init.headers)) });
   await new Promise<void>(done => { release = done; });
   durable = { ...durable, ...writes.at(-1).body, name: 'Nom confirmé', version: durable.version + 1 };
   if (receipt) return respond({ code: 'API_UNAVAILABLE' }, 503);
   return respond(envelope(durable));
 }
 if (path.includes('/operations/')) return respond(envelope({ operationId: path.split('/').at(-1), commandType: 'UPDATE_SCHOOL', resourceType: 'School', resourceId: schoolId, resourceVersion: durable.version, committedAt: serverTime }));
 if (path.endsWith('/readiness')) return respond(envelope({ schoolId, configurationVersion: 1, computedAt: serverTime, activationReady: true, activationBlockers: [], capabilities: [] }));
 if (failRead) return respond({ code: 'API_UNAVAILABLE' }, 503);
 return respond(envelope(durable));
};
commandStore.scopeToAccess(schoolId, membershipId, 1);
function App() {
 const [current, setCurrent] = useState(durable);
 const [epoch, setEpoch] = useState(1);
 (window as any).fixture = {
  writes: () => writes, waiting: () => !!release,
  release: () => { release?.(); release = null; },
  refresh: () => setCurrent({ ...durable }),
  receipt: () => { receipt = true; failRead = true; },
  retry: () => { failRead = false; },
  verify: () => commandStore.verify(schoolId),
  scope: () => { commandStore.scopeToAccess(schoolId, membershipId, epoch + 1); setEpoch(epoch + 1); },
 };
 return <ConsoleContext.Provider value={{ ...consoleValue, school: current, membership: { ...membership, accessEpoch: epoch }, reloadSchool: async () => {}, routeQuery: { focus: 'school-name' } } as any}>
 <main className="portal-main" style={{ padding: 24 }}><SchoolSettingsPilot /></main>
 </ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<App />);
