import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { ConsoleContext } from '/apps/web/client/console/context';
import { commandStore } from '/apps/web/client/command-store';
import { CourseEditor } from '/apps/web/client/portal/courses/course-editor';
import { CourseWorkspace } from '/apps/web/client/portal/courses/course-workspace';
import { LessonWorkspace } from '/apps/web/client/portal/agenda/lesson-workspace';
import type { LessonRefusal, LessonRestored } from '/apps/web/client/portal/agenda/lesson-intentions-model';
import { LearnerExams } from '/apps/web/client/portal/learners/learner-exams';
import { RulesFields } from '/apps/web/client/portal/formations/programme-fields';
import { rulesDraft, rulesPayload, rulesProblems, rulesChanged, rebaseRules, type RulesDraft } from '/apps/web/client/console/formation-model';
import { useLessonEditor } from '/apps/web/client/portal/agenda/use-lesson';
import { initialLessonForm } from '/apps/web/client/lesson-planning-model';
import '/apps/web/client/portal/portal.css';

// Fixture synthétique du reste du lot D (#437, #442, #443, #444, règles d'annulation #424) : vrais composants et hooks, API simulée, aucune donnée réelle.
const params = new URLSearchParams(location.search);
const surface = params.get('surface') ?? 'rules';
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
const draftId = '50000000-0000-4000-8000-0000000000d1';
const publishedId = '50000000-0000-4000-8000-0000000000e1';
const policyId = '90000000-0000-4000-8000-000000000002';
const offeringId = '90000000-0000-4000-8000-000000000001';
const serverTime = '2030-01-01T10:00:00Z';
const school = { id: schoolId, schoolId, version: 1, name: 'École synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE', modules: {} };
const membership = { membershipId, schoolId, schoolName: 'École synthétique', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 };
commandStore.scopeToAccess(schoolId, membershipId, 1);

const writes: any[] = [];
const reads: string[] = [];
let lessonOnServer: any = null;
let receipt: any = null;
/** Réponses des écritures, consommées dans l'ordre ; par défaut la réponse se perd (TypeError). */
const answers: any[] = [];
/** Statut des lectures d'un cours (503, 401, 403, 404) ; null = la lecture réussit. */
let courseReadFailure: number | null = null;

function reply(data: unknown, status: number, url: string) {
  const response = new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json' } });
  Object.defineProperty(response, 'url', { value: url });
  return response;
}
const envelope = (data: unknown) => ({ data, requestId, serverTime });
const future = (days: number, hour = 9) => new Date(Date.UTC(2031, 0, 1 + days, hour)).toISOString();
let exams = [{ id: examId, trainingId, kind: 'PRACTICAL', categoryCode: 'B', status: 'SCHEDULED', startsAt: '2031-02-01T09:00:00Z', timeZone: 'Europe/Zurich', location: 'Centre', escort: { instructorMembershipId: membershipId, startsAt: '2031-02-01T08:00:00Z', endsAt: '2031-02-01T11:00:00Z' },
  resultNote: '', resultRecordedAt: null, postponedToExamId: null, attempt: 1, needsResult: false, version: 1, createdAt: '2030-01-01T09:00:00Z' }];
const occurrenceOf = (id: string, day: number) => ({ id, position: 1, startsAt: future(day), endsAt: future(day, 11), timeZone: 'Europe/Zurich', instructorMembershipId: membershipId, instructorDisplayName: 'Moniteur synthétique', attendanceRequired: true });
const makeSeries = (id: string, status: string, patch: Record<string, unknown> = {}) => ({ id, schoolId, version: 1, status, typeId, typeTitle: 'Sensibilisation', title: 'Cours synthétique', description: '', location: 'Salle A', conditions: '',
  teachingLanguage: 'fr', responsibleMembershipId: membershipId, responsibleDisplayName: 'Moniteur synthétique', capacity: 10, seatsTaken: 0, remainingSeats: 10, minParticipants: null, policyVersion: 1, selfCancelHours: 24,
  selfCancellationDeadline: future(8), firstStartsAt: future(10), lastEndsAt: future(10, 11), totalMinutes: 120, publishedAt: status === 'DRAFT' ? null : '2030-01-01T09:00:00Z', occurrences: [occurrenceOf(`${id.slice(0, -1)}2`, 10)], canManage: true, ...patch });
const seriesStore: Record<string, any> = { [draftId]: makeSeries(draftId, 'DRAFT'), [publishedId]: makeSeries(publishedId, 'PUBLISHED') };
const trainingRow = { id: trainingId, schoolId, version: 1, learnerId, offeringId, categoryCode: 'B', status: 'ACTIVE', startedOn: '2030-01-01', closedOn: null };
const list = (items: unknown[], url: string) => reply(envelope({ items, nextCursor: null }), 200, url);

window.fetch = async (input: any, init?: RequestInit) => {
  const url = String(input instanceof URL ? input.href : input);
  const path = new URL(url, location.origin).pathname;
  const method = init?.method ?? 'GET';
  const relative = path.replace(/^.*\/schools\/[^/]+\//, '');
  if (method !== 'GET') {
    const headers = Object.fromEntries(new Headers(init?.headers));
    writes.push({ method, path: relative, body: init?.body ? JSON.parse(String(init.body)) : null, ifMatch: headers['if-match'] ?? null });
    const next = answers.shift();
    if (!next || next === 'lost') throw new TypeError('Failed to fetch'); // la réponse se perd : l'école a peut-être écrit
    return reply(next.body, next.status, url);
  }
  reads.push(relative);
  if (path.includes('/operations/')) return receipt ? reply(envelope(receipt), 200, url) : reply({ code: 'NOT_FOUND' }, 404, url);
  if (path.endsWith(`/trainings/${trainingId}/exams`)) {
    return reply(envelope({ trainingId, canManage: true, escortCandidates: [{ membershipId, displayName: 'Moniteur synthétique' }], exams,
      summary: [{ kind: 'THEORY', passed: false, attempts: 0, scheduledExamId: null }, { kind: 'PRACTICAL', passed: false, attempts: 0, scheduledExamId: examId }] }), 200, url);
  }
  const course = /course-series\/([^/?]+)$/.exec(path);
  if (course) {
    if (courseReadFailure) return reply({ code: courseReadFailure === 503 ? 'SERVICE_UNAVAILABLE' : 'FORBIDDEN' }, courseReadFailure, url);
    return seriesStore[course[1]!] ? reply(envelope(seriesStore[course[1]!]), 200, url) : reply({ code: 'NOT_FOUND' }, 404, url);
  }
  if (path.endsWith(`/lessons/${lessonId}`)) return reply(envelope(lessonOnServer), 200, url);
  if (path.endsWith('/lessons/availability')) return reply(envelope({ available: true, reasonCode: null }), 200, url);
  if (path.endsWith('/learners')) return list([{ id: learnerId, schoolId, version: 1, personId, displayName: 'Élève synthétique', contactEmail: null, contactPhone: null, archivedAt: null }], url);
  if (path.endsWith('/members')) return list([{ id: membershipId, schoolId, version: 1, personId, displayName: 'Moniteur synthétique', status: 'ACTIVE', roles: ['ADMIN', 'INSTRUCTOR'], grants: [], accessEpoch: 1 }], url);
  if (path.endsWith('/offerings')) return list([{ id: offeringId, schoolId, version: 1, offeringKey: 'b', categoryCode: 'B', curriculumVersionId: typeId, policyVersionId: policyId, enabled: true, defaultDurationMinutes: 60, defaultPriceCents: 9000 }], url);
  if (path.endsWith('/policy-versions')) return list([{ id: policyId, schoolId, version: 1, categoryCode: 'B', procedureText: 'Déroulement', cancellationPolicyText: 'Annulation', cancellationRules: null, sourceUrls: [], approved: true, approvedAt: serverTime }], url);
  if (path.endsWith('/service-products') || path.endsWith('/commercial-terms') || path.includes('lesson-change-requests') || path.endsWith('/assignments') && !path.includes(trainingId)) return list([], url);
  if (path.endsWith('/trainings')) return list([trainingRow], url);
  if (path.endsWith(`/trainings/${trainingId}/assignments`)) return list([{ id: policyId, schoolId, version: 1, trainingId, instructorMembershipId: membershipId, validFrom: '2020-01-01T00:00:00Z', validUntil: null }], url);
  return reply(envelope({}), 200, url);
};

const lessonBase = {
  id: lessonId, schoolId, version: 1, trainingId, learnerId, instructorMembershipId: membershipId, plannedStart: future(10), plannedEnd: future(10, 10), timeZone: 'Europe/Zurich',
  meetingPoint: 'Gare', status: 'PLANNED', actualStart: null, actualEnd: null, learnerDisplayName: 'Élève synthétique', instructorDisplayName: 'Moniteur synthétique',
  priceCentsSnapshot: 9000, bufferMinutesSnapshot: 0, commercialSelection: { mode: 'UNIT_PRICE', serviceProductVersionId: '40000000-0000-4000-8000-000000000001', quantity: 1, entitlementLotId: null, acceptedTermsVersionId: '40000000-0000-4000-8000-000000000002' },
  commercialRevisionVersion: 1,
};
lessonOnServer = lessonBase;
const catalogue = { learners: [], members: [], offerings: [], policies: [], products: [], terms: [], truncated: false };
const courseCatalogue = { schoolId, canManage: true, types: [{ id: typeId, schoolId, stableKey: null, title: 'Sensibilisation', description: '', version: 1, predefined: false }],
  policy: { version: 1, selfCancelHours: 24, offerResponseMinutes: null }, instructors: [{ membershipId, displayName: 'Moniteur synthétique' }] };

function LessonProbe() {
  const state = useLessonEditor({ original: lessonBase as any, learnerId, catalogue: catalogue as any, onQueued: () => {}, onRefused: () => {} });
  (window as any).lesson = state;
  return <p id="lesson">version:{state.original?.version} lieu:{state.form.meetingPoint} tampon:{state.form.buffer} début:{state.form.localStart} motif:{state.form.reason} accord:{String(state.form.agreement)} relu:{String(state.rebased)}</p>;
}
/** La reprise après remontage : la leçon relue est déjà en V2 alors que la saisie a été commencée sur V1 (base et version voyagent avec l'intention). */
function LessonResumeProbe() {
  const v1 = initialLessonForm(lessonBase as any, learnerId);
  const v2 = { ...lessonBase, version: 2, bufferMinutesSnapshot: 15, ...(params.get('v2') === 'conflict' ? { meetingPoint: 'Marché' } : {}) };
  const draft: any = { learnerId, trainingId, instructorMembershipId: membershipId, learnerDisplayName: 'Élève synthétique', instructorDisplayName: 'Moniteur synthétique', meetingPoint: 'Parc',
    timeZone: 'Europe/Zurich', plannedStart: lessonBase.plannedStart, plannedEnd: lessonBase.plannedEnd, form: { ...v1, meetingPoint: 'Parc', reason: 'Demande', agreement: true }, baseForm: params.get('base') === 'unknown' ? null : v1, baseVersion: 1 };
  const restored: any = { lessonId, draft, outcome: { code: 'VERSION_CONFLICT', title: 'Leçon modifiée', message: 'La leçon a changé.' } };
  const state = useLessonEditor({ original: v2 as any, learnerId, catalogue: catalogue as any, restored, onQueued: () => {}, onRefused: () => {} });
  (window as any).lesson = state;
  return <p id="lesson">version:{state.original?.version} lieu:{state.form.meetingPoint} tampon:{state.form.buffer} motif:{state.form.reason} accord:{String(state.form.agreement)} relu:{String(state.rebased)} probleme:{state.problem}</p>;
}
/**
 * Le trajet réel d'un déplacement refusé : LessonWorkspace, le vrai formulaire, la vraie voie de commandes. Seuls `refuse` et `resume` sont recopiés
 * de `useAgenda` (refuseLesson / resume) : l'agenda complet n'est pas monté.
 */
function LessonFlow() {
  const [refusals, setRefusals] = useState<LessonRefusal[]>([]);
  const [restored, setRestored] = useState<LessonRestored | null>(null);
  const resume = (refusal: LessonRefusal) => {
    setRefusals(items => items.filter(item => item !== refusal));
    if (refusal.intention.kind === 'lesson-cancel') return;
    setRestored({ lessonId: refusal.intention.kind === 'lesson-create' ? null : refusal.intention.lessonId, draft: refusal.intention.draft, outcome: refusal.outcome });
  };
  return <LessonWorkspace lessonId={lessonId} onClose={() => {}} onSaved={() => {}} onDossier={() => {}} restored={restored} moving={false} refusals={refusals}
    onQueued={() => setRestored(null)} onRefused={refusal => setRefusals(items => [...items, refusal])} onClearRestored={() => setRestored(null)} onResumeRefusal={resume}
    onDismissRefusal={refusal => setRefusals(items => items.filter(item => item !== refusal))} />;
}
function CourseFlow() {
  const initial = params.get('course');
  const [courseId, setCourseId] = useState<string | null>(initial === 'draft' ? draftId : initial === 'published' ? publishedId : null);
  const [shown] = useState<string[]>([]);
  (window as any).flow = { courseId: () => courseId, shown: () => shown, changed: 0 };
  const loaded = { status: 'ready' as const, data: courseCatalogue, error: null, reload: () => {} };
  return <CourseWorkspace courseId={courseId} occurrenceId={undefined} catalogue={loaded as any} onClose={() => {}}
    onShow={id => { shown.push(id); setCourseId(id); }} onChanged={() => { (window as any).flow.changed++; }} />;
}
function RulesProbe() {
  const variant = params.get('base') ?? 'hours';
  const rules = variant === 'hours' ? { cancellationHours: 24, lateAction: 'CONTACT' as const } : variant === 'nofee' ? { cancellationHours: null, lateAction: 'NO_FEE' as const }
    : variant === 'contact-null' ? { cancellationHours: null, lateAction: 'CONTACT' as const } : null;
  const base = { procedureText: 'Déroulement', cancellationPolicyText: 'Annulation 24 h avant.', sourceUrls: [] as string[], cancellationRules: rules };
  const [draft, setDraft] = useState<RulesDraft>(() => rulesDraft(base));
  (window as any).rules = { payload: () => rulesPayload(draft), valid: () => rulesProblems(draft).valid, changed: () => rulesChanged(draft, base),
    rebase: (next: any) => setDraft(current => rebaseRules(current, next)), draft: () => draft };
  return <RulesFields draft={draft} onChange={setDraft} disabled={false} showErrors={false} example={null} />;
}
function ExamsProbe() {
  const [status, setStatus] = useState(params.get('status') ?? 'COMPLETED');
  (window as any).setTrainingStatus = setStatus;
  const state: any = { current: { id: learnerId, archivedAt: null }, trainingsOf: () => [{ id: trainingId, status }], title: () => 'Permis B', name: () => 'Moniteur synthétique' };
  return <LearnerExams state={state} openFormations={() => {}} />;
}
function CreateProbe() {
  const [attached, setAttached] = useState('');
  (window as any).created = () => attached;
  return <><CourseEditor series={null} catalogue={courseCatalogue as any} canManage notice={null} onClose={() => {}} onDone={() => {}} onCreated={setAttached} onReread={() => {}} />
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
    writes: () => writes, reads: () => reads, serverLesson: (patch: any) => { lessonOnServer = { ...lessonOnServer, ...patch }; },
    serverSeries: (id: string, patch: any) => { seriesStore[id] = { ...seriesStore[id], ...patch }; },
    answer: (next: any) => { answers.push(next); }, failCourseReads: (status: number | null) => { courseReadFailure = status; },
    receipt: (next: any) => { receipt = next; }, verify: () => commandStore.verify(schoolId), createdId, draftId, publishedId, exams: () => exams,
    makeSeries, future, envelope,
  };
  const body = surface === 'lesson' ? <LessonProbe /> : surface === 'lessonflow' ? <LessonFlow /> : surface === 'lessonresume' ? <LessonResumeProbe /> : surface === 'course' ? <CourseFlow /> : surface === 'exams' ? <ExamsProbe />
    : surface === 'create' ? <CreateProbe /> : <RulesProbe />;
  return <ConsoleContext.Provider value={value as any}><main className="portal-main" style={{ padding: 24 }}>{ready && body}</main></ConsoleContext.Provider>;
}
createRoot(document.getElementById('root')!).render(<App />);
