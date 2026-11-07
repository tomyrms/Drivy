import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { MeasureDetail } from '/apps/web/client/portal/pilotage/measure-detail';
import '/apps/web/client/portal/portal.css';

// Fixture synthétique du détail F06 (#432, #433) : aucune donnée réelle, aucune école réelle.
const schoolId = '10000000-0000-4000-8000-000000000001';
const personId = '10000000-0000-4000-8000-000000000002';
const membershipId = '10000000-0000-4000-8000-000000000003';
const requestId = '10000000-0000-4000-8000-000000000004';
const serverTime = '2030-01-01T10:00:00Z';
const mode = new URLSearchParams(location.search).get('mode') ?? 'corrections';
const school = { id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE', modules: {} };
const consoleValue = {
  schoolId, school, me: { personId, displayName: 'Administrateur synthétique', locale: 'fr', memberships: [] },
  membership: { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN'], grants: [], accessEpoch: 1 },
  canConfigureCatalog: true, routeQuery: {}, navigate: () => {}, reloadSchool: async () => {}, csrf: () => 'synthetic',
  refreshCsrf: async () => 'synthetic', login: () => {}, drafts: new Map(), setNavigationGuard: () => {},
};
const period = { choice: { kind: 'month' }, from: '2030-01-01', toExclusive: '2030-02-01', lastDay: '2030-01-31', days: 31 } as any;
const line = (n: number, cents: number) => ({
  kind: 'COURSE_PAYMENT', id: `20000000-0000-4000-8000-00000000000${n}`, eventAt: '2030-01-10T09:00:00Z', status: 'VOIDED', amountCents: cents,
  courseTypeLabel: `Ligne ${n}`, learnerLabel: `Élève ${n}`,
});
const cardWithParts = mode === 'corrections'
  ? { value: 0, unit: 'cents', coverage: { status: 'COMPLETE', reasons: [] }, lineCount: 2, parts: { voidedEntries: 0, laterCorrections: 2, laterCorrectionsCents: 4500 } }
  : { value: 9000, unit: 'cents', coverage: { status: 'COMPLETE', reasons: [] }, lineCount: 3, parts: { voidedEntries: 2, laterCorrections: 1, laterCorrectionsCents: 1000 } };

const reads: string[] = [];
let held: (() => void) | null = null;
function reply(data: unknown, url: string) {
  const response = new Response(JSON.stringify(data), { status: 200, headers: { 'content-type': 'application/json' } });
  Object.defineProperty(response, 'url', { value: url });
  return response;
}
const envelope = (data: unknown) => ({ data, requestId, serverTime });
window.fetch = async (input: any) => {
  const url = String(input instanceof URL ? input.href : input);
  const u = new URL(url, location.origin);
  if (u.pathname.endsWith('/metrics/definitions')) return reply(envelope({ definitionsVersion: '1', measures: [
    { id: 'F06', domain: 'finance', unit: 'cents', label: 'Paiements annulés', formula: 'synthétique', snapshot: false, details: true }] }), url);
  if (u.pathname.endsWith('/metrics/details')) {
    const part = u.searchParams.get('part') ?? '', cursor = u.searchParams.get('cursor');
    reads.push(`${part}${cursor ? ':' + cursor : ''}`);
    if (mode === 'corrections') return reply(envelope({ schoolId, measure: 'F06', timeZone: 'Europe/Zurich', computedAt: serverTime, period: { from: '2030-01-01', toExclusive: '2030-02-01' },
      total: { lineCount: 2, amountCents: 4500 }, drift: null, lines: [line(1, 3000), line(2, 1500)], page: { limit: 50, nextCursor: null } }), url);
    if (part === 'a' && !cursor) return reply(envelope({ schoolId, measure: 'F06', timeZone: 'Europe/Zurich', computedAt: serverTime, period: { from: '2030-01-01', toExclusive: '2030-02-01' },
      total: { lineCount: 2, amountCents: 9000 }, drift: null, lines: [line(1, 4000)], page: { limit: 50, nextCursor: 'curseur-a' } }), url);
    if (part === 'a') {
      await new Promise<void>(done => { held = done; });
      return reply(envelope({ schoolId, measure: 'F06', timeZone: 'Europe/Zurich', computedAt: serverTime, period: { from: '2030-01-01', toExclusive: '2030-02-01' },
        total: { lineCount: 2, amountCents: 9000 }, drift: null, lines: [line(3, 5000)], page: { limit: 50, nextCursor: null } }), url);
    }
    return reply(envelope({ schoolId, measure: 'F06', timeZone: 'Europe/Zurich', computedAt: serverTime, period: { from: '2030-01-01', toExclusive: '2030-02-01' },
      total: { lineCount: 1, amountCents: 1000 }, drift: null, lines: [line(2, 1000)], page: { limit: 50, nextCursor: null } }), url);
  }
  if (u.pathname.endsWith('/metrics')) return reply(envelope({ schoolId, domain: 'finance', timeZone: 'Europe/Zurich', computedAt: serverTime, dataSince: null,
    period: { from: '2030-01-01', toExclusive: '2030-02-01', days: 31 }, scope: { kind: 'school' }, measures: { F06: cardWithParts } }), url);
  return reply(envelope({}), url);
};

function App() {
  const [part, setPart] = useState<'a' | 'b' | undefined>(undefined);
  (window as any).fixture = { reads: () => reads, release: () => { held?.(); held = null; }, waiting: () => held !== null };
  return <ConsoleContext.Provider value={consoleValue as any}>
    <main className="portal-main" style={{ padding: 24 }}>
      <MeasureDetail measure="F06" part={part} period={period} filters={{}} scopeLabel="École" canExport={false} onBack={() => {}} onPart={setPart} />
    </main>
  </ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<App />);
