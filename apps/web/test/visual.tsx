import { createRoot } from 'react-dom/client';
import '../client/styles.css';
import reviewStyles from '../client/styles.css?raw';
import { ConsoleContext, type ConsoleContextValue } from '../client/console/context';
import { InvitationsSection, TeamSection } from '../client/console/people';
import { LearnersSection } from '../client/console/learners';
import { AgendaSection } from '../client/console/agenda';
import { TripsSection } from '../client/console/trips';
import { AvailabilitySection } from '../client/console/availability';
import { ConfigurationSection } from '../client/console/configuration';
import { ProfileFieldsSection } from '../client/console/profile-fields';
import { OverviewSection } from '../client/console/overview';
import { ManagementConsole } from '../client/console/Console';

const uuid = () => crypto.randomUUID();
const schoolId = uuid(), meId = uuid(), lucId = uuid(), marieId = uuid(), offerB = uuid(), offerBOld = uuid(), offerA = uuid();
const learnerA = uuid(), learnerB = uuid(), trainingA = uuid(), curriculumB = uuid(), comp1 = uuid(), comp2 = uuid(), lessonDone = uuid();
const stamp = '2026-09-29T08:00:00.000Z';
const member = (id: string, displayName: string, roles: string[], status = 'ACTIVE') => ({ id, schoolId, version: 1, personId: uuid(), displayName, status, roles, grants: id === marieId ? ['permit_review', 'MANAGE_LEARNER_ARCHIVES'] : [], accessEpoch: 1 });
const offering = (id: string, offeringKey: string, version: number, enabled: boolean, categoryCode: string) => ({ id, schoolId, version, offeringKey, categoryCode, curriculumVersionId: curriculumB, policyVersionId: uuid(), enabled, defaultDurationMinutes: 45, defaultPriceCents: 9500 });
const db: Record<string, any> = {
  members: [member(lucId, 'Luc Martin', ['ADMIN', 'INSTRUCTOR']), member(marieId, 'Marie Dupont', ['INSTRUCTOR']), member(uuid(), 'Paul Suspendu', ['INSTRUCTOR'], 'SUSPENDED'), member(uuid(), 'Éloïse Élève', ['LEARNER'])],
  offerings: [offering(offerBOld, 'b-standard', 1, true, 'B'), offering(offerB, 'b-standard', 2, true, 'B'), offering(offerA, 'a-standard', 1, true, 'A')],
  invitations: [
    { id: uuid(), schoolId, version: 1, delivery: 'CODE', maskedEmail: null, roles: ['LEARNER'], status: 'PENDING', expiresAt: '2026-10-04T08:00:00.000Z', training: { offeringId: offerB, instructorMembershipId: marieId } },
  ] as Record<string, unknown>[],
  learners: [
    { id: learnerA, schoolId, version: 3, personId: uuid(), displayName: 'Éloïse Müller', contactEmail: 'eloise@example.test', contactPhone: null, archivedAt: null, profileReadiness: 'ACTION_REQUIRED' },
    { id: learnerB, schoolId, version: 1, personId: uuid(), displayName: 'Bruno Blanc', contactEmail: null, contactPhone: null, archivedAt: null, profileReadiness: 'READY' },
  ],
  trainings: [{ id: trainingA, schoolId, version: 5, learnerId: learnerA, offeringId: offerB, categoryCode: 'B', status: 'ACTIVE', startedOn: '2026-09-01', closedOn: null }],
  assignments: [{ id: uuid(), schoolId, version: 1, trainingId: trainingA, instructorMembershipId: marieId, validFrom: '2026-09-01T08:00:00.000Z', validUntil: null }],
  permits: [] as Record<string, unknown>[],
  curricula: [{ id: curriculumB, schoolId, version: 1, categoryCode: 'B', revision: 1, approved: true, competencies: [
    { id: comp1, key: 'demarrer', label: 'Démarrer et s’arrêter', description: 'x', sortOrder: 1 }, { id: comp2, key: 'ronds-points', label: 'Ronds-points', description: 'x', sortOrder: 2 }] }],
  lessons: [
    { id: lessonDone, schoolId, version: 2, trainingId: trainingA, learnerId: learnerA, instructorMembershipId: marieId, plannedStart: '2026-09-28T07:00:00.000Z', plannedEnd: '2026-09-28T08:00:00.000Z', timeZone: 'Europe/Zurich', meetingPoint: 'Gare', status: 'COMPLETED', permitWarning: false, currentPublishedRevisionId: uuid() },
    { id: uuid(), schoolId, version: 1, trainingId: trainingA, learnerId: learnerA, instructorMembershipId: marieId, plannedStart: '2026-09-30T13:00:00.000Z', plannedEnd: '2026-09-30T14:00:00.000Z', timeZone: 'Europe/Zurich', meetingPoint: 'Parking de l’école', status: 'PLANNED', permitWarning: true, currentPublishedRevisionId: null },
  ],
};
const codes = ['K7Q4-MX2P', 'R2ZN-8HTC', 'B9WD-4LEA'];
const envelope = (data: unknown) => ({ data, requestId: uuid(), serverTime: stamp });
const log: string[] = [];
(window as unknown as { __log: string[] }).__log = log;

function reply(status: number, body: unknown, url: string) {
  return { status, ok: status < 400, url, headers: new Headers({ 'content-type': 'application/json' }), json: async () => body };
}
window.fetch = (async (input: URL | string, init?: RequestInit) => {
  const url = new URL(String(input)); const path = url.pathname.split(`/${schoolId}`)[1]?.replace(/^\//, '') ?? '';
  const method = init?.method ?? 'GET'; const body = init?.body ? JSON.parse(String(init.body)) : null;
  await new Promise(resolve => setTimeout(resolve, 120));
  if (method === 'GET') {
    if (url.pathname.endsWith('/bff/session')) return reply(200, { authenticated: true, csrfToken: 'synthetic-review', invitationPending: false, user: { displayName: 'Luc Martin', emailVerified: true } }, url.href);
    if (url.pathname.endsWith('/bff/me')) return reply(200, { data: { ...value.me, memberships: [value.membership] } }, url.href);
    if (path === '') return reply(200, envelope(value.school), url.href);
    if (path === 'readiness') return reply(200, envelope({ schoolId, configurationVersion: 1, computedAt: stamp, activationReady: true, activationBlockers: [], capabilities: ['CAN_USE_WORKSPACE', 'CAN_PLAN_LESSON', 'CAN_CAPTURE'].map(capability => ({ capability, ready: true, blockers: [] })) }), url.href);
    if (path === 'data-policy') return reply(200, envelope({ schoolId, version: 1, status: 'APPROVED', noticeText: 'Texte synthétique de revue.', retentionText: 'Politique synthétique de revue.', contactEmail: 'ecole@example.test', approvedAt: stamp }), url.href);
    if (/^trainings\/[^/]+\/assignments$/.test(path)) return reply(200, envelope({ items: db.assignments, nextCursor: null }), url.href);
    if (/^trainings\/[^/]+\/permit-checks$/.test(path)) return reply(200, envelope({ items: db.permits, nextCursor: null }), url.href);
    if (/^trainings\/[^/]+\/progress$/.test(path)) return reply(200, envelope({ trainingId: trainingA, computedAt: stamp, unobservedCompetencyIds: [comp2], items: [{ competencyId: comp1, label: 'Démarrer et s’arrêter', level: 'GUIDED', context: 'Parking', observedAt: stamp, sourceLessonId: lessonDone, sourceRevisionId: uuid() }] }), url.href);
    if (/^lessons\/[^/]+\/reports$/.test(path)) return reply(200, envelope({ items: [{ id: uuid(), schoolId, version: 1, lessonId: lessonDone, sequence: 1, authorMembershipId: marieId, publishedAt: stamp, workedOn: 'Démarrage en côte', observationText: 'Bonne maîtrise du point de patinage.', nextStep: 'Ronds-points', correctionReason: null, observations: [{ competencyId: comp1, level: 'GUIDED', context: 'Parking' }] }], nextCursor: null }), url.href);
    const list = path === 'lessons' ? db.lessons.filter((lesson: any) => (!url.searchParams.get('instructorMembershipId') || lesson.instructorMembershipId === url.searchParams.get('instructorMembershipId')) && (!url.searchParams.get('trainingId') || lesson.trainingId === url.searchParams.get('trainingId')) && (!url.searchParams.get('from') || lesson.plannedEnd > url.searchParams.get('from')!) && (!url.searchParams.get('to') || lesson.plannedStart < url.searchParams.get('to')!)) : db[path.replace('availability-rules', 'availability').replace('closures', 'closures')] ?? [];
    return reply(200, envelope({ items: list, nextCursor: null }), url.href);
  }
  log.push(`${method} ${path} ${JSON.stringify(body)} if-match=${(init?.headers as Record<string, string>)?.['If-Match'] ?? ''}`);
  if ((method === 'PATCH' && path.startsWith('members/')) || path.endsWith('/deactivate')) {
    if (!(window as any).__reauthed) return reply(401, { code: 'REAUTH_REQUIRED' }, url.href);
    const target = db.members.find((item: any) => path.includes(item.id)); if (path.endsWith('/deactivate')) target.status = 'INACTIVE'; else { target.roles = body.roles; target.grants = body.grants; } target.version++;
    return reply(200, envelope(target), url.href);
  }
  if (method === 'POST' && path === 'invitations') {
    const item: Record<string, unknown> = { id: uuid(), schoolId, version: 1, delivery: 'CODE', maskedEmail: null, roles: ['LEARNER'], status: 'PENDING', expiresAt: '2026-10-06T08:00:00.000Z', trainings: body.trainings, training: body.trainings?.[0] ?? body.training };
    db.invitations.push(item);
    return reply(201, envelope({ ...item, code: codes[0] }), url.href);
  }
  if (path.endsWith('/transition')) { const t = db.trainings[0]; t.version++; t.status = body.targetStatus; return reply(200, envelope(t), url.href); }
  if (path.endsWith('/end')) { db.assignments[0].version++; db.assignments[0].validUntil = stamp; return reply(200, envelope(db.assignments[0]), url.href); }
  if (path.endsWith('/archive')) { const l = db.learners.find((item: any) => path.includes(item.id)); l.version++; l.archivedAt = stamp; return reply(200, envelope(l), url.href); }
  if (path.endsWith('/permit-checks')) { const permit = { id: uuid(), schoolId, version: 1, trainingId: trainingA, documentId: null, physicalSeen: body.physicalSeen, categoryCode: body.categoryCode, validUntil: body.validUntil, decision: body.decision, reviewerMembershipId: marieId, reviewedAt: stamp, reason: body.reason, isExpired: false }; db.permits.push(permit); db.trainings[0].version++; return reply(200, envelope(permit), url.href); }
  if (path === 'modules') { value.school.version++; value.school.modules.gpsEnabled = body.gpsEnabled; return reply(200, envelope(value.school), url.href); }
  return reply(404, { code: 'NOT_FOUND' }, url.href);
}) as typeof fetch;

const value: ConsoleContextValue = {
  schoolId, me: { personId: meId, displayName: 'Luc Martin', version: 1, memberships: [] },
  membership: { membershipId: marieId, schoolId, schoolName: 'École Synthétique', roles: ['ADMIN', 'INSTRUCTOR'], grants: ['permit_review', 'MANAGE_LEARNER_ARCHIVES'], accessEpoch: 1 },
  school: { id: schoolId, schoolId, version: 1, name: 'École Synthétique', timeZone: 'Europe/Zurich', status: 'ACTIVE', contactEmail: 'a@b.ch', contactPhone: null, configurationVersion: 1,
    modules: { gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false } },
  canConfigureCatalog: true, reloadSchool: async () => {}, csrf: () => 'csrf', refreshCsrf: async () => 'csrf', navigate: section => log.push(`navigate ${section}`), login: options => log.push(`login ${JSON.stringify(options ?? {})}`),
};
const page = new URLSearchParams(location.search).get('page');
// Visual review only: apply the actual light tokens independently of the host OS.
if (new URLSearchParams(location.search).get('scheme') === 'light') {
  const theme = document.createElement('style');
  theme.textContent = reviewStyles.match(/:root\s*\{[\s\S]*?\}/)?.[0] ?? '';
  document.head.append(theme);
}
const pages: Record<string, () => JSX.Element> = { learners: LearnersSection, agenda: AgendaSection, trips: TripsSection, team: TeamSection, availability: AvailabilitySection, config: ConfigurationSection, profile: ProfileFieldsSection, overview: OverviewSection };
const Page = pages[page ?? ''] ?? InvitationsSection;
const shell = new URLSearchParams(location.search).get('shell') === '1';
if (shell) {
  const sections: Record<string, string> = { overview: '', learners: 'eleves', agenda: 'agenda', trips: 'trajets', team: 'equipe', availability: 'disponibilites', config: 'configuration', profile: 'champs-profil' };
  window.history.replaceState(null, '', `/app/gestion/${schoolId}/${sections[page ?? 'overview'] ?? 'invitations'}`);
}
createRoot(document.getElementById('root')!).render(
  shell ? <ManagementConsole /> : <ConsoleContext.Provider value={value}><div className="console-shell"><main className="console-main"><Page /></main></div></ConsoleContext.Provider>);
