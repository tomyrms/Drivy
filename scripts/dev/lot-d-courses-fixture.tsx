import React, { useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { commandStore } from '/apps/web/client/command-store';
import { CourseSheet } from '/apps/web/client/portal/courses/course-sheet';
import { CourseEditor } from '/apps/web/client/portal/courses/course-editor';
import { useTariffLane, useTermsLane } from '/apps/web/client/portal/pricing/pricing-commands';
import { useProgrammeLane } from '/apps/web/client/portal/formations/formation-commands';
import '/apps/web/client/portal/portal.css';

// Fixture synthétique du lot D (#422 cours, #434 cours annulé, #430 participants) : vrais composants, API simulée, aucune donnée réelle.
const surface = new URLSearchParams(location.search).get('surface') ?? 'sheet';
const voidedMethods = new Set(['POST']);
const schoolId = '10000000-0000-4000-8000-000000000001';
const otherSchoolId = '10000000-0000-4000-8000-0000000000f1';
const personId = '10000000-0000-4000-8000-000000000002';
const membershipId = '10000000-0000-4000-8000-000000000003';
const requestId = '10000000-0000-4000-8000-000000000004';
const seriesId = '50000000-0000-4000-8000-000000000001';
const typeId = '50000000-0000-4000-8000-0000000000a1';
const occurrenceId = '50000000-0000-4000-8000-0000000000b1';
const ana = '60000000-0000-4000-8000-000000000001', bob = '60000000-0000-4000-8000-000000000002', cara = '60000000-0000-4000-8000-000000000003';
const payment = '70000000-0000-4000-8000-000000000001', completion = '70000000-0000-4000-8000-000000000002';
const serverTime = '2030-01-01T10:00:00Z';
const school = { id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE', modules: {} };
const membership = { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 };
commandStore.scopeToAccess(schoolId, membershipId, 1);

const occurrence = { id: occurrenceId, position: 1, startsAt: '2020-01-01T09:00:00Z', endsAt: '2020-01-01T11:00:00Z', timeZone: 'Europe/Zurich', instructorMembershipId: membershipId,
  instructorDisplayName: 'Moniteur synthétique', attendanceRequired: true };
const baseSeries = { id: seriesId, schoolId, version: 3, status: 'CANCELLED', typeId, typeTitle: 'Sensibilisation', title: 'Cours synthétique', description: '', location: 'Salle A', conditions: '',
  teachingLanguage: 'fr', responsibleMembershipId: membershipId, responsibleDisplayName: 'Moniteur synthétique', capacity: 10, seatsTaken: 1, remainingSeats: 9, minParticipants: null,
  policyVersion: 1, selfCancelHours: 24, selfCancellationDeadline: '2019-12-30T09:00:00Z', firstStartsAt: occurrence.startsAt, lastEndsAt: occurrence.endsAt, totalMinutes: 120,
  publishedAt: '2019-12-01T09:00:00Z', occurrences: [occurrence], canManage: true };
const requirements = { required: 1, present: 1, missing: 0 };
const rows = [
  { enrollmentId: ana, learnerId: ana, learnerDisplayName: 'Ana Annulée', status: 'CANCELLED', cancelledAt: '2020-01-01T10:00:00Z', requirements,
    attendance: [{ occurrenceId, status: 'PRESENT', version: 2, recordedAt: '2020-01-01T09:30:00Z' }],
    payments: [{ id: payment, amountCents: 5000, recordedAt: '2020-01-01T09:40:00Z', note: null, voidedAt: null, voidReason: null }],
    completion: { id: completion, validatedAt: '2020-01-01T10:30:00Z', seriesId, revokedAt: null } },
  { enrollmentId: cara, learnerId: cara, learnerDisplayName: 'Cara Sans Marque', status: 'CANCELLED', cancelledAt: '2020-01-01T10:00:00Z', requirements: { required: 1, present: 0, missing: 1 },
    attendance: [], payments: [], completion: null },
];
void bob;

const writes: any[] = [];
let held: (() => void) | null = null;
let mode: 'refuse' | 'ok' = 'refuse';
const futureOccurrence = { ...occurrence, startsAt: '2031-03-03T09:00:00Z', endsAt: '2031-03-03T11:00:00Z' };
let editSeries = { ...baseSeries, status: 'DRAFT', version: 1, publishedAt: null, seatsTaken: 0, remainingSeats: 10, firstStartsAt: futureOccurrence.startsAt, lastEndsAt: futureOccurrence.endsAt,
  selfCancellationDeadline: '2031-03-02T09:00:00Z', occurrences: [futureOccurrence] } as typeof baseSeries;
const catalogue = { schoolId, canManage: true, types: [{ id: typeId, schoolId, stableKey: null, title: 'Sensibilisation', description: '', version: 1, predefined: false }],
  policy: { version: 1, selfCancelHours: 24, offerResponseMinutes: null }, instructors: [{ membershipId, displayName: 'Moniteur synthétique' }] };

function reply(data: unknown, status: number, url: string) {
  const response = new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
  Object.defineProperty(response, 'url', { value: url });
  return response;
}
const envelope = (data: unknown) => ({ data, requestId, serverTime });
window.fetch = async (input: any, init?: RequestInit) => {
  const url = String(input instanceof URL ? input.href : input);
  const path = new URL(url, location.origin).pathname;
  const method = init?.method ?? 'GET';
  if (method !== 'GET') {
    const headers = Object.fromEntries(new Headers(init?.headers));
    writes.push({ method, path: path.replace(/^.*\/schools\/[^/]+\//, ''), body: init?.body ? JSON.parse(String(init.body)) : null, ifMatch: headers['if-match'] ?? null });
    await new Promise<void>(done => { held = done; });
    held = null;
    if (mode === 'refuse') return reply({ code: 'COURSE_PAYMENT_VOIDED' }, 409, url);
    if (path.endsWith(`/course-series/${seriesId}`)) {
      const body = JSON.parse(String(init?.body));
      editSeries = { ...editSeries, title: body.title ?? editSeries.title, location: body.location ?? editSeries.location, capacity: body.capacity ?? editSeries.capacity, version: editSeries.version + 1 };
      return reply(envelope(editSeries), 200, url);
    }
    return reply(envelope(path.includes('/formations/') ? { id: '80000000-0000-4000-8000-000000000001', versionId: '80000000-0000-4000-8000-000000000002' } : { series: baseSeries, rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true }, rows }), voidedMethods.has(method) ? 201 : 200, url);
  }
  if (path.endsWith('/sheet')) return reply(envelope({ series: baseSeries, rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true }, rows }), 200, url);
  if (path.endsWith('/enrollments')) return reply(envelope({ items: [], waitlist: [] }), 200, url);
  return reply(envelope({}), 200, url);
};

const drafts = new Map<string, unknown>();
const otherDrafts = new Map<string, unknown>();
const termsReference = { kind: 'TERMS', id: '80000000-0000-4000-8000-0000000000c1' };
/** Sonde : les trois hooks de commandes réels (tarifs, conditions, programmes) ; elle ne rend que le nombre de refus de chaque famille. */
const noRows: never[] = [];
function Lanes() {
  const tariff = useTariffLane(noRows);
  const terms = useTermsLane(termsReference as any);
  const programme = useProgrammeLane(noRows);
  (window as any).lanes = {
    tariff: () => tariff.save({ target: { kind: 'create' }, body: { name: 'Synthétique' }, draft: {}, success: 'ok', sharedTerms: false } as any),
    terms: () => terms.revise({ text: 'Conditions', body: { text: 'Conditions' }, success: 'ok', revised: () => {} }),
    programme: () => programme.save({ offeringKey: 'B', section: 'info', body: { offeringKey: 'B' }, draft: {}, success: 'ok' } as any),
  };
  return <p id="lanes">tarifs:{tariff.refusals.length} conditions:{terms.refusal ? 1 : 0} programmes:{programme.refusals.length}</p>;
}
function App() {
  const [shown, setShown] = useState(true);
  const [scope, setScope] = useState(schoolId);
  const [live, setLive] = useState(editSeries);
  const value = {
    schoolId: scope, school: { ...school, id: scope, schoolId: scope }, me: { personId, displayName: 'Administrateur synthétique', locale: 'fr', memberships: [] },
    membership: { ...membership, schoolId: scope }, canConfigureCatalog: true, routeQuery: {}, navigate: () => {}, reloadSchool: async () => {}, csrf: () => 'synthetic',
    refreshCsrf: async () => 'synthetic', login: () => {}, drafts: scope === schoolId ? drafts : otherDrafts, setNavigationGuard: () => {},
  };
  (window as any).fixture = {
    writes: () => writes, waiting: () => held !== null, release: () => held?.(), mode: (next: 'refuse' | 'ok') => { mode = next; },
    hide: () => setShown(false), show: () => setShown(true), otherSchool: () => setScope(otherSchoolId), ownSchool: () => setScope(schoolId),
    // Un autre administrateur modifie le cours ; la nouvelle version arrive comme une relecture.
    serverChange: (patch: Partial<typeof editSeries>) => { editSeries = { ...editSeries, ...patch, version: editSeries.version + 1 }; setLive(editSeries); },
  };
  const body = surface === 'lanes' ? <Lanes />
    : surface === 'editor'
    ? <CourseEditor series={live as any} catalogue={catalogue as any} canManage notice={null} onClose={() => {}} onDone={() => {}} onReread={() => {}} />
    : <CourseSheet series={baseSeries as any} catalogue={catalogue as any} occurrenceId={undefined} notice={null} onClose={() => {}} onChanged={() => {}} onReread={() => {}} />;
  return <ConsoleContext.Provider value={value as any}>
    <main className="portal-main" style={{ padding: 24 }}>{shown ? body : <p id="elsewhere">Autre page</p>}</main>
  </ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<App />);
