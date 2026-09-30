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
import { FormationsSection } from '../client/console/formations';
import { CurriculaSection, ProceduresSection, OfferingsSection } from '../client/console/catalog';
import { ProductsSection, TermsSection } from '../client/console/commerce';
import { App } from '../client/App';

const parameters = new URLSearchParams(location.search);
const page = parameters.get('page');
const reviewState = parameters.get('state');
const uuid = () => crypto.randomUUID();
const schoolId = uuid(), meId = uuid(), lucId = uuid(), marieId = uuid(), offerB = uuid(), offerBOld = uuid(), offerA = uuid();
const learnerA = uuid(), learnerB = uuid(), trainingA = uuid(), curriculumB = uuid(), comp1 = uuid(), comp2 = uuid(), lessonDone = uuid();
const curriculumA = uuid(), policyA = uuid(), policyB = uuid(), termsId = uuid();
const noticeId = uuid();
const stamp = '2026-09-29T08:00:00.000Z';
const member = (id: string, displayName: string, roles: string[], status = 'ACTIVE') => ({ id, schoolId, version: 1, personId: uuid(), displayName, status, roles, grants: id === marieId ? ['permit_review', 'MANAGE_LEARNER_ARCHIVES', 'CONFIGURE_CATALOG'] : [], accessEpoch: 1 });
const offering = (id: string, offeringKey: string, version: number, enabled: boolean, categoryCode: string) => ({ id, schoolId, version, offeringKey, categoryCode, curriculumVersionId: categoryCode === 'A' ? curriculumA : curriculumB, policyVersionId: categoryCode === 'A' ? policyA : policyB, enabled, defaultDurationMinutes: 45, defaultPriceCents: 9500 });
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
    { id: comp1, key: 'demarrer', label: 'Démarrer et s’arrêter', description: 'Préparer le véhicule, observer et démarrer en sécurité.', sortOrder: 1 }, { id: comp2, key: 'ronds-points', label: 'Ronds-points', description: 'Adapter son allure, observer les priorités et annoncer sa sortie.', sortOrder: 2 }] },
    { id: curriculumA, schoolId, version: 1, categoryCode: 'A', revision: 1, approved: true, competencies: [{ id: uuid(), key: 'equilibre', label: 'Maîtriser l’équilibre', description: 'Exemple de compétence moto.', sortOrder: 1 }] }],
  'policy-versions': [{ id: policyA, categoryCode: 'A' }, { id: policyB, categoryCode: 'B' }].map(item => ({ ...item, schoolId, version: 1, procedureText: 'Parcours pédagogique synthétique.', cancellationPolicyText: 'Texte synthétique pour la revue.', sourceUrls: [], approved: true, approvedAt: stamp })),
  'commercial-terms': [{ id: termsId, schoolId, version: 1, label: 'Conditions de l’école', termsText: 'Conditions synthétiques pour la revue.', validFrom: '2026-01-01', validUntil: null, approved: true, approvalReason: 'Revue locale', approvedAt: stamp }],
  'service-products': [
    { id: uuid(), schoolId, version: 1, productKey: 'conduite-b', label: 'Leçon de conduite', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45, unitLabel: 'leçon', unitPriceCents: 9500, validFrom: '2026-01-01', validUntil: null, termsVersionId: termsId, enabled: true },
    { id: uuid(), schoolId, version: 2, productKey: 'conduite-b', label: 'Leçon de conduite', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45, unitLabel: 'leçon', unitPriceCents: 10000, validFrom: '2026-09-01', validUntil: null, termsVersionId: termsId, enabled: true },
    { id: uuid(), schoolId, version: 1, productKey: 'conduite-a', label: 'Leçon moto', type: 'INDIVIDUAL_LESSON', categoryCode: 'A', durationMinutes: 45, unitLabel: 'leçon', unitPriceCents: 9000, validFrom: '2026-01-01', validUntil: null, termsVersionId: termsId, enabled: true },
  ],
  lessons: [
    { id: lessonDone, schoolId, version: 2, trainingId: trainingA, learnerId: learnerA, instructorMembershipId: marieId, plannedStart: '2026-09-28T07:00:00.000Z', plannedEnd: '2026-09-28T08:00:00.000Z', timeZone: 'Europe/Zurich', meetingPoint: 'Gare', status: 'COMPLETED', permitWarning: false, currentPublishedRevisionId: uuid() },
    { id: uuid(), schoolId, version: 1, trainingId: trainingA, learnerId: learnerA, instructorMembershipId: marieId, plannedStart: '2026-09-30T13:00:00.000Z', plannedEnd: '2026-09-30T14:00:00.000Z', timeZone: 'Europe/Zurich', meetingPoint: 'Parking de l’école', status: 'PLANNED', permitWarning: true, currentPublishedRevisionId: null },
  ],
  availability: [{ id: uuid(), schoolId, version: 1, instructorMembershipId: marieId, weekdays: [1, 2, 3, 4, 5], localStart: '08:00', localEnd: '17:00', validFrom: '2026-09-01', validUntil: null }],
  closures: [{ id: uuid(), schoolId, version: 1, instructorMembershipId: marieId, startsAt: '2026-10-02T10:00:00.000Z', endsAt: '2026-10-02T12:00:00.000Z', reason: 'Formation continue' }],
  captures: [{ id: uuid(), schoolId, lessonId: lessonDone, learnerId: learnerA, learnerName: 'Éloïse Müller', instructorName: 'Marie Dupont', instructorMembershipId: marieId,
    authorizedAt: '2026-09-28T07:03:00.000Z', stoppedAt: '2026-09-28T07:55:00.000Z', cutoffAt: null, lessonPlannedStart: '2026-09-28T07:00:00.000Z', lessonTimeZone: 'Europe/Zurich', captureState: 'STOPPED', syncState: 'SYNCED' }],
  'profile-field-policies': [{ id: uuid(), schoolId, version: 1, status: 'PUBLISHED', effectiveFrom: '2026-09-01T00:00:00.000Z', noticeVersionId: noticeId, approvedByMembershipId: lucId,
    fields: ['firstName', 'lastName'].map(field => ({ field, requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier la personne.' })) }],
};
if (parameters.get('stress') === '1') {
  db.learners[0].displayName = 'Éloïse-Marie de Montmollin-Châteauneuf';
  db.members[1].displayName = 'Marie-Christine Dupré de Villeneuve';
  db['service-products'][1].label = 'Leçon de perfectionnement et préparation à l’examen pratique';
  db['commercial-terms'][0].label = 'Conditions de formation, de réservation et d’annulation des leçons';
  db.curricula[0].competencies[0].label = 'Préparer le véhicule, démarrer en côte et s’arrêter en sécurité';
  db.captures[0].learnerName = db.learners[0].displayName;
  db.captures[0].instructorName = db.members[1].displayName;
  for (let index = 0; index < 18; index++) db.learners.push({ ...db.learners[1], id: uuid(), personId: uuid(), displayName: `Dossier synthétique ${String(index + 1).padStart(2, '0')}` });
}
if (reviewState === 'empty') for (const key of Object.keys(db)) db[key] = [];
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
    if (url.pathname.endsWith('/bff/session')) return reply(200, { authenticated: page !== 'signin', csrfToken: 'synthetic-review', invitationPending: page === 'invitation', user: { displayName: 'Luc Martin', email: 'luc@example.test', emailVerified: true } }, url.href);
    if (url.pathname.endsWith('/bff/me')) return reply(200, { data: { ...value.me, memberships: [value.membership] } }, url.href);
    if (path === '') return reply(200, envelope(value.school), url.href);
    if (reviewState === 'error') return reply(503, { code: 'SERVICE_UNAVAILABLE' }, url.href);
    const readiness = { schoolId, configurationVersion: 1, computedAt: stamp, activationReady: true, activationBlockers: [], capabilities: ['CAN_USE_WORKSPACE', 'CAN_PLAN_LESSON', 'CAN_CAPTURE'].map(capability => ({ capability, ready: true, blockers: [] })) };
    if (path === 'readiness') return reply(200, envelope(readiness), url.href);
    if (path === 'setup') return reply(200, envelope({ schoolId, version: 1, status: 'COMPLETED', currentStep: 'REVIEW', completedSteps: ['IDENTITY', 'DATA'], lastSavedAt: stamp, readiness }), url.href);
    if (path === 'data-policy') return reply(200, envelope({ schoolId, version: 1, status: 'APPROVED', noticeVersionId: noticeId, noticeText: 'Les informations de votre profil servent au suivi de votre formation. Seuls les membres autorisés de l’école peuvent les consulter.', retentionText: 'L’école conserve les informations nécessaires au suivi pédagogique et traite les demandes de suppression auprès du contact ci-dessous.', contactEmail: 'ecole@example.test', approvedAt: stamp }), url.href);
    if (/^trainings\/[^/]+\/assignments$/.test(path)) return reply(200, envelope({ items: db.assignments, nextCursor: null }), url.href);
    if (/^trainings\/[^/]+\/permit-checks$/.test(path)) return reply(200, envelope({ items: db.permits, nextCursor: null }), url.href);
    if (/^trainings\/[^/]+\/progress$/.test(path)) return reply(200, envelope({ trainingId: trainingA, computedAt: stamp, unobservedCompetencyIds: [comp2], items: [{ competencyId: comp1, label: 'Démarrer et s’arrêter', level: 'GUIDED', context: 'Parking', observedAt: stamp, sourceLessonId: lessonDone, sourceRevisionId: uuid() }] }), url.href);
    if (/^lessons\/[^/]+\/reports$/.test(path)) return reply(200, envelope({ items: [{ id: uuid(), schoolId, version: 1, lessonId: lessonDone, sequence: 1, authorMembershipId: marieId, publishedAt: stamp, workedOn: 'Démarrage en côte', observationText: 'Bonne maîtrise du point de patinage.', nextStep: 'Ronds-points', correctionReason: null, observations: [{ competencyId: comp1, level: 'GUIDED', context: 'Parking' }] }], nextCursor: null }), url.href);
    const list = path === 'lessons' ? db.lessons.filter((lesson: any) => (!url.searchParams.get('instructorMembershipId') || lesson.instructorMembershipId === url.searchParams.get('instructorMembershipId')) && (!url.searchParams.get('trainingId') || lesson.trainingId === url.searchParams.get('trainingId')) && (!url.searchParams.get('from') || lesson.plannedEnd > url.searchParams.get('from')!) && (!url.searchParams.get('to') || lesson.plannedStart < url.searchParams.get('to')!)) : db[path.replace('availability-rules', 'availability').replace('closures', 'closures')] ?? [];
    return reply(200, envelope({ items: list, nextCursor: null }), url.href);
  }
  if (url.pathname.endsWith('/bff/invitation/preview')) return reply(200, { confirmation: 'synthetic-confirmation', data: { invitationId: uuid(), schoolId, schoolName: value.school.name, roles: ['LEARNER'], maskedEmail: 'l***@example.test', expiresAt: '2026-10-06T08:00:00.000Z', notice: { version: 1, noticeText: 'Les informations de votre profil servent au suivi de votre formation.', retentionText: 'L’école conserve les informations nécessaires au suivi pédagogique.', contactEmail: 'ecole@example.test' } } }, url.href);
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
  membership: { membershipId: marieId, schoolId, schoolName: 'École Synthétique', roles: ['ADMIN', 'INSTRUCTOR'], grants: reviewState === 'readonly' ? [] : ['permit_review', 'MANAGE_LEARNER_ARCHIVES', 'CONFIGURE_CATALOG'], accessEpoch: 1 },
  school: { id: schoolId, schoolId, version: 1, name: 'École Synthétique', timeZone: 'Europe/Zurich', status: parameters.get('status') === 'draft' ? 'DRAFT' : 'ACTIVE', contactEmail: 'ecole@example.test', contactPhone: null, configurationVersion: 1,
    modules: { gpsEnabled: true, packsEnabled: false, collectiveCoursesEnabled: false, courseOffersVisibleByDefault: false } },
  canConfigureCatalog: reviewState !== 'readonly', reloadSchool: async () => {}, csrf: () => 'csrf', refreshCsrf: async () => 'csrf', navigate: section => log.push(`navigate ${section}`), login: options => log.push(`login ${JSON.stringify(options ?? {})}`),
};
if (parameters.get('stress') === '1') {
  value.school.name = 'École de conduite de la région du Lac et des Préalpes';
  value.membership.schoolName = value.school.name;
}
// Visual review only: apply the actual light tokens independently of the host OS.
if (new URLSearchParams(location.search).get('scheme') === 'light') {
  const theme = document.createElement('style');
  theme.textContent = reviewStyles.match(/:root\s*\{[\s\S]*?\}/)?.[0] ?? '';
  document.head.append(theme);
}
const pages: Record<string, () => JSX.Element> = { learners: LearnersSection, agenda: AgendaSection, trips: TripsSection, team: TeamSection, availability: AvailabilitySection, config: ConfigurationSection, profile: ProfileFieldsSection, overview: OverviewSection, formations: FormationsSection,
  curricula: CurriculaSection, procedures: ProceduresSection, offerings: OfferingsSection, products: ProductsSection, terms: TermsSection };
const Page = pages[page ?? ''] ?? InvitationsSection;
const shell = new URLSearchParams(location.search).get('shell') === '1';
if (shell) {
  const sections: Record<string, string> = { home: '', overview: 'apercu', formations: 'formations', learners: 'eleves', agenda: 'agenda', trips: 'trajets', team: 'equipe', availability: 'disponibilites', config: 'configuration', profile: 'champs-profil', curricula: 'referentiels', procedures: 'procedures', offerings: 'offres', products: 'prestations', terms: 'conditions' };
  window.history.replaceState(null, '', `/app/gestion/${schoolId}/${sections[page ?? 'overview'] ?? 'invitations'}`);
}
const entry = ['signin', 'account', 'invitation'].includes(page ?? '');
if (entry) window.history.replaceState(null, '', page === 'invitation' ? '/app/invitation' : '/app/');
createRoot(document.getElementById('root')!).render(
  entry ? <App invitationLink={{ token: null, error: false }} /> : shell ? <ManagementConsole /> : <ConsoleContext.Provider value={value}><div className="console-shell"><main className="console-main"><Page /></main></div></ConsoleContext.Provider>);
