import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { commandStore } from '/apps/web/client/command-store';
import { CourseEditor } from '/apps/web/client/portal/courses/course-editor';
import { LearnerExams } from '/apps/web/client/portal/learners/learner-exams';
import { RulesFields } from '/apps/web/client/portal/formations/programme-fields';
import { rulesDraft, rulesPayload, rulesProblems, rulesChanged, type RulesDraft } from '/apps/web/client/console/formation-model';
import { useLessonEditor } from '/apps/web/client/portal/agenda/use-lesson';
import '/apps/web/client/portal/portal.css';

// Fixture synthétique du reste du lot D (#437, #442, #444, règles d'annulation #424) : vrais composants et hooks, API simulée, aucune donnée réelle.
const surface = new URLSearchParams(location.search).get('surface') ?? 'rules';
const schoolId = '10000000-0000-4000-8000-000000000001';
const personId = '10000000-0000-4000-8000-000000000002';
const membershipId = '10000000-0000-4000-8000-000000000003';
const requestId = '10000000-0000-4000-8000-000000000004';
const learnerId = '20000000-0000-4000-8000-000000000001';
const trainingId = '20000000-0000-4000-8000-000000000002';
const examId = '20000000-0000-4000-8000-000000000003';
const lessonId = '30000000-0000-4000-8000-000000000001';
const createdId = '50000000-0000-4000-8000-0000000000c1';
const typeId = '50000000-0000-4000-8000-0000000000a1';
const serverTime = '2030-01-01T10:00:00Z';
const school = { id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE', modules: {} };
const membership = { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 };
commandStore.scopeToAccess(schoolId, membershipId, 1);

const writes: any[] = [];
const reads: string[] = [];
let lessonOnServer: any = null;
let receipt: any = null;

function reply(data: unknown, status: number, url: string) {
  const response = new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
  Object.defineProperty(response, 'url', { value: url });
  return response;
}
const envelope = (data: unknown) => ({ data, requestId, serverTime });
const future = (days: number, hour = 9) => new Date(Date.UTC(2031, 0, 1 + days, hour)).toISOString();
let exams = [{ id: examId, trainingId, kind: 'PRACTICAL', categoryCode: 'B', status: 'SCHEDULED', startsAt: '2031-02-01T09:00:00Z', timeZone: 'Europe/Zurich', location: 'Centre', escort: { instructorMembershipId: membershipId, startsAt: '2031-02-01T08:00:00Z', endsAt: '2031-02-01T11:00:00Z' },
  resultNote: '', resultRecordedAt: null, postponedToExamId: null, attempt: 1, needsResult: false, version: 1, createdAt: '2030-01-01T09:00:00Z' }];
window.fetch = async (input: any, init?: RequestInit) => {
  const url = String(input instanceof URL ? input.href : input);
  const parsed = new URL(url, location.origin);
  const path = parsed.pathname;
  const method = init?.method ?? 'GET';
  if (method !== 'GET') {
    writes.push({ method, path: path.replace(/^.*\/schools\/[^/]+\//, ''), body: init?.body ? JSON.parse(String(init.body)) : null });
    // La réponse se perd : l'école a peut-être écrit.
    throw new TypeError('Failed to fetch');
  }
  reads.push(path.replace(/^.*\/schools\/[^/]+\//, ''));
  if (path.includes('/operations/')) return receipt ? reply(envelope(receipt), 200, url) : reply({ code: 'NOT_FOUND' }, 404, url);
  if (path.endsWith(`/trainings/${trainingId}/exams`)) {
    return reply(envelope({ trainingId, canManage: true, escortCandidates: [{ membershipId, displayName: 'Moniteur synthétique' }], exams,
      summary: [{ kind: 'THEORY', passed: false, attempts: 0, scheduledExamId: null }, { kind: 'PRACTICAL', passed: false, attempts: 0, scheduledExamId: examId }] }), 200, url);
  }
  if (path.endsWith(`/lessons/${lessonId}`)) return reply(envelope(lessonOnServer), 200, url);
  if (path.endsWith('/trainings') || path.endsWith('/assignments')) return reply(envelope({ items: [], nextCursor: null }), 200, url);
  return reply(envelope({}), 200, url);
};

const lessonBase = {
  id: lessonId, schoolId, version: 1, trainingId, learnerId, instructorMembershipId: membershipId, plannedStart: future(10), plannedEnd: future(10, 10), timeZone: 'Europe/Zurich',
  meetingPoint: 'Gare', status: 'PLANNED', actualStart: null, actualEnd: null, learnerDisplayName: 'Élève synthétique', instructorDisplayName: 'Moniteur synthétique',
  priceCentsSnapshot: 9000, bufferMinutesSnapshot: 0, commercialSelection: { mode: 'UNIT_PRICE', serviceProductVersionId: '40000000-0000-4000-8000-000000000001', quantity: 1, entitlementLotId: null, acceptedTermsVersionId: '40000000-0000-4000-8000-000000000002' },
  commercialRevisionVersion: 1,
};
const catalogue = { learners: [], members: [], offerings: [], policies: [], products: [], terms: [], truncated: false };

function LessonProbe() {
  const state = useLessonEditor({ original: lessonBase as any, learnerId, catalogue: catalogue as any, onQueued: () => {}, onRefused: () => {} });
  (window as any).lesson = state;
  return <p id="lesson">version:{state.original?.version} lieu:{state.form.meetingPoint} tampon:{state.form.buffer} début:{state.form.localStart} motif:{state.form.reason} accord:{String(state.form.agreement)} relu:{String(state.rebased)}</p>;
}
function RulesProbe() {
  const [draft, setDraft] = useState<RulesDraft>(() => rulesDraft({ procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 24 h avant.', sourceUrls: [], cancellationRules: { cancellationHours: 24, lateAction: 'CONTACT' } }));
  const base = { procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 24 h avant.', sourceUrls: [] as string[], cancellationRules: { cancellationHours: 24, lateAction: 'CONTACT' as const } };
  (window as any).rules = { payload: () => rulesPayload(draft), valid: () => rulesProblems(draft).valid, changed: () => rulesChanged(draft, base) };
  return <RulesFields draft={draft} onChange={setDraft} disabled={false} showErrors={false} example={null} />;
}
function ExamsProbe() {
  const [status, setStatus] = useState('COMPLETED');
  (window as any).setTrainingStatus = setStatus;
  const state: any = { current: { id: learnerId, archivedAt: null }, trainingsOf: () => [{ id: trainingId, status }], title: () => 'Permis B', name: () => 'Moniteur synthétique' };
  return <LearnerExams state={state} openFormations={() => {}} />;
}
function CreateProbe() {
  const [attached, setAttached] = useState('');
  const emptyCatalogue = { schoolId, canManage: true, types: [{ id: typeId, schoolId, stableKey: null, title: 'Sensibilisation', description: '', version: 1, predefined: false }],
    policy: { version: 1, selfCancelHours: 24, offerResponseMinutes: null }, instructors: [{ membershipId, displayName: 'Moniteur synthétique' }] };
  (window as any).created = () => attached;
  return <><CourseEditor series={null} catalogue={emptyCatalogue as any} canManage notice={null} onClose={() => {}} onDone={() => {}} onCreated={setAttached} onReread={() => {}} />
    <p id="attached">rattaché:{attached}</p></>;
}
function App() {
  const [ready, setReady] = useState(false);
  useEffect(() => setReady(true), []);
  const value = {
    schoolId, school, me: { personId, displayName: 'Administrateur synthétique', locale: 'fr', memberships: [] }, membership, canConfigureCatalog: true, routeQuery: {}, navigate: () => {},
    reloadSchool: async () => {}, csrf: () => 'synthetic', refreshCsrf: async () => 'synthetic', login: () => {}, drafts: new Map(), setNavigationGuard: () => {},
  };
  (window as any).fixture = {
    writes: () => writes, reads: () => reads, serverLesson: (patch: any) => { lessonOnServer = { ...lessonBase, ...patch }; },
    receipt: (next: any) => { receipt = next; }, verify: () => commandStore.verify(schoolId), createdId, exams: () => exams,
  };
  const body = surface === 'lesson' ? <LessonProbe /> : surface === 'exams' ? <ExamsProbe /> : surface === 'create' ? <CreateProbe /> : <RulesProbe />;
  return <ConsoleContext.Provider value={value as any}><main className="portal-main" style={{ padding: 24 }}>{ready && body}</main></ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<App />);
