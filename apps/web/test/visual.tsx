import { createRoot } from 'react-dom/client';
import { useRef, useState } from 'react';
import '../client/styles.css';
import '../client/theme';
import { PreferencesPage, ThemeControl } from '../client/preferences';
import { CheckField, SelectField, TextField } from '../client/ui';
import { SchoolOpeningPage } from '../client/school-opening';
import '../client/school-opening.css';
import { ConsoleContext, type ConsoleContextValue } from '../client/console/context';
import { InvitationsSection, TeamSection } from '../client/console/people';
import { LearnersSection } from '../client/console/learners';
import { AgendaSection } from '../client/console/agenda';
import { TripsSection } from '../client/console/trips';
import { AvailabilitySection } from '../client/console/availability';
import { ConfigurationSection } from '../client/console/configuration';
import { ProfileFieldsSection } from '../client/console/profile-fields';
import { PrivacySection } from '../client/console/privacy';
import { OverviewSection } from '../client/console/overview';
import { ObservationThemesSection } from '../client/console/observation-themes';
import { ManagementConsole } from '../client/console/Console';
import { FormationsSection } from '../client/console/formations';
import { CurriculaSection, ProceduresSection, OfferingsSection } from '../client/console/catalog';
import { ProductsSection, TermsSection } from '../client/console/commerce';
import { App } from '../client/App';
import { setupSteps, type SetupDraft, type SetupTemplates, type SetupPreview } from '../client/setup-model';
import type { DataPolicy, TextProposals } from '../client/school-api';

// Test-runner boot data is memory-only and is never loaded by the production entry.
const reviewWindow = window as unknown as { __reviewBoot?: { parameters: string; snapshot?: any }; __reviewSnapshot?: () => unknown; __releaseSchoolRead?: () => void; __schoolReadWaiting?: boolean };
const parameters = new URLSearchParams(reviewWindow.__reviewBoot?.parameters ?? location.search);
const page = parameters.get('page');
const reviewState = parameters.get('state');
let fixtureSequence = 0;
const uuid = () => `11111111-1111-4111-8111-${String(++fixtureSequence).padStart(12, '0')}`;
const schoolId = uuid(), meId = uuid(), lucId = uuid(), marieId = uuid(), offerB = uuid(), offerBOld = uuid(), offerA = uuid();
const learnerA = uuid(), learnerB = uuid(), trainingA = uuid(), curriculumB = uuid(), comp1 = uuid(), comp2 = uuid(), lessonDone = uuid();
const curriculumA = uuid(), policyA = uuid(), policyB = uuid(), termsId = uuid();
const noticeId = uuid();
const stamp = '2026-09-29T08:00:00.000Z';
const setupTemplates: SetupTemplates = {
  version: 'visual-1',
  privacy: { id: 'visual-information', version: 'visual-1',
    noticeText: '[Nom de l’école] utilise Drivy pour gérer les dossiers, les rendez-vous et le suivi pédagogique. Les personnes habilitées de l’école accèdent aux données nécessaires à leur activité. L’élève retrouve les leçons réalisées, les observations partagées, les bilans et les objectifs ; les notes privées du moniteur ne lui sont pas montrées. Le suivi pédagogique peut être utilisé sans GPS. Pour une demande relative aux données : [contact données]. Complétez les destinataires et les pratiques propres à votre école : [à compléter].',
    retentionText: 'Décrivez les durées appliquées à vos dossiers, aux leçons, aux documents et aux trajets, ainsi que le traitement des demandes et des sauvegardes : [à compléter]. N’annoncez une suppression automatique que si elle est effectivement mise en œuvre.' },
  profileFields: ['firstName', 'lastName'].map(field => ({ field: field as 'firstName' | 'lastName', requirement: 'REQUIRED', stage: 'JOIN', purposeCode: 'IDENTIFICATION', explanation: 'Identifier votre dossier dans l’école.' })),
  formations: ['A', 'A1', 'B', 'BE'].map(categoryCode => ({ id: `visual-${categoryCode}`, version: 'visual-1', categoryCode, label: `Permis ${categoryCode}`, durationMinutes: 45,
    competencies: ['Préparer la conduite', 'Observer et anticiper', 'Placement et trajectoire', 'Adapter son allure', 'Franchir les intersections', 'Manœuvrer'].map((label, sortOrder) => ({ key: `competence-${sortOrder}`, label, sortOrder, description: 'Exemple pédagogique à adapter aux pratiques de l’école.' })),
    procedureText: 'Avant la première leçon, l’école examine le dossier et les justificatifs utiles. Le moniteur définit avec l’élève les objectifs de travail, adapte les exercices et consigne le suivi pédagogique. Cette proposition doit être adaptée aux pratiques de l’école.' })),
};
const setupReady = parameters.get('setup') === 'ready';
const requestedStep = parameters.get('step');
const setupDraft: SetupDraft = { id: schoolId, schoolId, version: 1, status: 'DRAFT',
  currentStep: setupSteps.find(step => step === requestedStep) ?? 'IDENTITY', updatedAt: stamp, updatedByMembershipId: marieId, appliedAt: null,
  content: { selectedSections: ['IDENTITY', 'PRIVACY', 'PROFILE', ...(setupReady ? ['CATALOGUE' as const] : [])],
    identity: { name: 'École Synthétique', timeZone: 'Europe/Zurich', contactEmail: 'ecole@example.test', contactPhone: null },
    privacy: { noticeText: setupReady ? 'L’école utilise Drivy pour gérer les dossiers et le suivi pédagogique. Seuls les membres autorisés consultent les informations utiles à la formation.' : '',
      retentionText: setupReady ? 'Durées de conservation synthétiques pour cette revue locale. Les demandes sont traitées par le contact de l’école.' : '', contactEmail: 'ecole@example.test', templateId: null, templateVersion: null },
    profile: { fields: structuredClone(setupTemplates.profileFields), effectiveFrom: null },
    formations: setupReady ? [{ id: uuid(), apply: true, categoryCode: 'B', label: 'Permis B', templateId: 'visual-B', templateVersion: 'visual-1',
      competencies: structuredClone(setupTemplates.formations[2]!.competencies), procedureText: setupTemplates.formations[2]!.procedureText,
      cancellationPolicyText: 'Conditions d’annulation synthétiques pour la revue.', sourceUrls: [], durationMinutes: 45, priceCents: 9500,
      termsText: 'Conditions du tarif synthétiques pour la revue.', validFrom: '2026-10-13', existingOfferingId: null }] : [] },
};
function setupPreview(activate: boolean): SetupPreview {
  const issues: SetupPreview['issues'] = [];
  const add = (field: string, message: string) => issues.push({ field, message, code: 'SETUP_FIELD_REQUIRED' });
  const content = setupDraft.content;
  if (content.selectedSections.includes('IDENTITY') && !content.identity.name.trim()) add('identity.name', 'Indiquez le nom de l’école.');
  if (content.selectedSections.includes('PRIVACY')) for (const field of ['noticeText', 'retentionText'] as const) {
    if (!content.privacy[field].trim() || content.privacy[field].includes('[à compléter]')) add(`privacy.${field}`, 'Remplacez les éléments à compléter avant de confirmer.');
  }
  if (content.selectedSections.includes('CATALOGUE')) content.formations.forEach((formation, index) => {
    if (!formation.apply) return;
    if (formation.priceCents === null) add(`formations.${index}.priceCents`, 'Saisissez le prix réel de la leçon.');
    if (!formation.termsText.trim()) add(`formations.${index}.termsText`, 'Complétez les conditions de cette prestation.');
    if (!formation.cancellationPolicyText.trim()) add(`formations.${index}.cancellationPolicyText`, 'Complétez les conditions d’annulation.');
  });
  return { schoolId, draftVersion: setupDraft.version, schoolVersion: value.school.version, configurationVersion: value.school.configurationVersion,
    activate, reviewDigest: `synthetic-${setupDraft.version}`, ready: issues.length === 0, issues, selectedSections: content.selectedSections,
    content: structuredClone(content), effects: activate ? [] : content.selectedSections.includes('PRIVACY') ? ['Les autorisations GPS en cours prennent fin.'] : [] };
}
let policyState: DataPolicy = { schoolId, version: 1, status: 'APPROVED', noticeVersionId: noticeId, noticeText: 'Les informations de votre profil servent au suivi de votre formation. Seuls les membres autorisés de l’école peuvent les consulter.', retentionText: 'L’école conserve les informations nécessaires au suivi pédagogique et traite les demandes de suppression auprès du contact ci-dessous.', contactEmail: 'ecole@example.test', approvedAt: stamp };
const textProposals: TextProposals = {
  dataPolicy: { noticeText: policyState.noticeText, retentionText: policyState.retentionText, contactEmail: 'ecole@example.test' },
  profileFields: [...setupTemplates.profileFields, { field: 'contactPhone', requirement: 'OPTIONAL', stage: 'OPTIONAL', purposeCode: 'LESSON_CONTACT', explanation: 'Pour vous prévenir d’un changement de leçon.' }],
  procedure: { procedureText: 'Texte synthétique sur le déroulement des leçons, à relire par l’école.', cancellationPolicyText: 'Conditions synthétiques d’annulation à adapter.' },
  commercialTerms: { label: 'Conditions de l’école', termsText: 'Conditions commerciales synthétiques à relire par l’école.' },
};
const member = (id: string, displayName: string, roles: string[], status = 'ACTIVE') => ({ id, schoolId, version: 1, personId: uuid(), displayName, status, roles, grants: id === marieId ? ['permit_review', 'MANAGE_LEARNER_ARCHIVES', 'CONFIGURE_CATALOG'] : [], accessEpoch: 1 });
const offering = (id: string, offeringKey: string, version: number, enabled: boolean, categoryCode: string) => ({ id, schoolId, version, offeringKey, categoryCode, curriculumVersionId: categoryCode === 'A' ? curriculumA : curriculumB, policyVersionId: categoryCode === 'A' ? policyA : policyB, enabled, defaultDurationMinutes: 45, defaultPriceCents: 9500 });
const db: Record<string, any> = {
  members: [member(lucId, 'Luc Martin', ['ADMIN', 'INSTRUCTOR']), member(marieId, 'Marie Dupont', ['INSTRUCTOR']), member(uuid(), 'Paul Suspendu', ['INSTRUCTOR'], 'SUSPENDED'), member(uuid(), 'Éloïse Élève', ['LEARNER'])],
  offerings: [offering(offerBOld, 'b-standard', 1, true, 'B'), offering(offerB, 'b-standard', 2, true, 'B'), offering(offerA, 'a-standard', 1, true, 'A')],
  invitations: [
    { id: uuid(), schoolId, version: 1, delivery: 'CODE', maskedEmail: null, roles: ['LEARNER'], status: 'PENDING', expiresAt: '2026-10-04T08:00:00.000Z', training: { offeringId: offerB, instructorMembershipId: marieId } },
    { id: uuid(), schoolId, version: 1, delivery: 'EMAIL', maskedEmail: 'm***@example.test', roles: ['INSTRUCTOR'], status: 'PENDING', expiresAt: '2026-10-20T08:00:00.000Z' },
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
  const names = ['Camille Rochat', 'Nathan Morel', 'Jade Perrin', 'Sami Dubois', 'Léa Favre', 'Hugo Schneider', 'Clara Dufour', 'Noah Meier', 'Inès Martin', 'Luca Bernard', 'Zoé Girard', 'Louis Blanc', 'Mila Aubert', 'Adam Richard', 'Emma Berger', 'Raphaël Bonnet', 'Anna Rey', 'Gabriel Mercier'];
  for (const [index, displayName] of names.entries()) {
    const learnerId = uuid();
    db.learners.push({ ...db.learners[1], id: learnerId, personId: uuid(), displayName });
    const motorcycle = index % 4 === 0;
    db.trainings.push({ ...db.trainings[0], id: uuid(), learnerId, offeringId: motorcycle ? offerA : offerB, categoryCode: motorcycle ? 'A' : 'B', status: index % 7 === 0 ? 'PAUSED' : 'ACTIVE' });
  }
}
if (parameters.get('volume') === '1') {
  const names = ['Alex Emery', 'Alice Monnier', 'Arthur Simon', 'Camille Rochat', 'Chloé Keller', 'Daniel Weber', 'Elena Rossi', 'Elias Petit', 'Eva Laurent', 'Félix Dubois', 'Julia Müller', 'Léon Robert', 'Lucas Humbert', 'Nina Perrin', 'Oscar Meyer', 'Sarah Rey'];
  for (const [index, displayName] of names.entries()) db.learners.push({ ...db.learners[1], id: uuid(), personId: uuid(), displayName,
    contactEmail: `eleve-volume-${index + 1}@example.test`, contactPhone: null });
  const homonyms = db.learners.filter((item: any) => item.displayName === 'Camille Rochat');
  homonyms.forEach((item: any, index: number) => { item.contactEmail = `camille.${index + 1}@example.test`; });
}
const outsideLearner = { ...db.learners[1], id: uuid(), personId: uuid(), displayName: 'Diane Horizon', contactEmail: 'diane@example.test' };
const missingLearnerId = uuid();
const findLearner = (id: string) => db.learners.find((item: any) => item.id === id) ?? (id === outsideLearner.id ? outsideLearner : undefined);
if (reviewState === 'empty') for (const key of Object.keys(db)) db[key] = [];
if (parameters.get('policy') === 'unadopted') {
  policyState = { ...policyState, status: 'DRAFT', noticeText: '', retentionText: '', approvedAt: null, noticeVersionId: null };
  db['profile-field-policies'] = [];
}
// Signalements : le catalogue du contrat (douze affichés sur dix-huit à l'origine), versionné comme le serveur.
const themeCatalogue: [string, string, boolean][] = [['vehicle', 'Maîtrise du véhicule', true], ['observation', 'Observation et contrôles', true], ['right-priority', 'Priorité à droite', true],
  ['signage', 'Signalisation', true], ['give-way', 'Céder le passage', true], ['intersections', 'Intersections et giratoires', true], ['speed', 'Vitesse', true],
  ['placement', 'Placement sur la chaussée', true], ['manoeuvres', 'Manœuvres', true], ['motorway', 'Autoroute', true], ['anticipation', 'Anticipation', true],
  ['indicators', 'Clignotants', true], ['following-distance', 'Distance de sécurité', false], ['braking', 'Freinage', false], ['lane-change', 'Changement de voie', false],
  ['moving-off', 'Démarrage', false], ['bends', 'Virages', false], ['eco-driving', 'Éco-conduite', false]];
const themeState = { version: 1, themes: themeCatalogue.map(([key]) => ({ key, visible: themeCatalogue.find(item => item[0] === key)![2] })) };
const themesProjection = () => ({ id: schoolId, schoolId, version: themeState.version, canManage: reviewState !== 'readonly',
  themes: themeState.themes.map(({ key, visible }) => { const index = themeCatalogue.findIndex(item => item[0] === key);
    return { key, title: themeCatalogue[index]![1], competencyKeys: [key], visible, defaultVisible: themeCatalogue[index]![2], defaultPosition: index }; }) });
const codes = ['K7Q4-MX2P', 'R2ZN-8HTC', 'B9WD-4LEA'];
const envelope = (data: unknown) => ({ data, requestId: uuid(), serverTime: stamp });
const log: string[] = [];
(window as unknown as { __log: string[] }).__log = log;
const reads: string[] = [];
(window as unknown as { __reads: string[] }).__reads = reads;
const administrativeProfile = { id: uuid(), schoolId, version: 1, learnerId: learnerA, policyVersionId: db['profile-field-policies'][0]?.id ?? noticeId };
let schoolConflictOnce = reviewState === 'conflict-once';
let savedSchoolReadGate: Promise<void> | null = null;

function reply(status: number, body: unknown, url: string) {
  return { status, ok: status < 400, url, headers: new Headers({ 'content-type': 'application/json' }), json: async () => body };
}
window.fetch = (async (input: URL | string, init?: RequestInit) => {
  const url = new URL(String(input)); const path = url.pathname.split(`/${schoolId}`)[1]?.replace(/^\//, '') ?? '';
  const method = init?.method ?? 'GET'; const body = init?.body ? JSON.parse(String(init.body)) : null;
  await new Promise(resolve => setTimeout(resolve, reviewState === 'slow' && path === 'lessons' ? 1500 : 120));
  if (method === 'GET') {
    reads.push(path);
    if (url.pathname.endsWith('/bff/session')) return reply(200, { authenticated: page !== 'signin', csrfToken: 'synthetic-review', invitationPending: page === 'invitation', user: { displayName: 'Luc Martin', email: 'luc@example.test', emailVerified: true } }, url.href);
    if (url.pathname.endsWith('/bff/opening')) return reply(200, { pending: true, uncertain: false }, url.href);
    if (url.pathname.endsWith('/bff/operator/school-opening-links')) return reply(200, { data: { items: [{ id: uuid(), status: 'AVAILABLE', createdAt: stamp, expiresAt: '2026-10-20T08:00:00.000Z', usedAt: null, revokedAt: null }] } }, url.href);
    if (url.pathname.endsWith('/bff/me')) return reply(200, { data: { ...value.me, memberships: [value.membership] } }, url.href);
    if (path === '') {
      if (savedSchoolReadGate) { reviewWindow.__schoolReadWaiting = true; await savedSchoolReadGate; reviewWindow.__schoolReadWaiting = false; savedSchoolReadGate = null; }
      return reply(200, envelope(value.school), url.href);
    }
    if (reviewState === 'error') return reply(503, { code: 'SERVICE_UNAVAILABLE' }, url.href);
    if (path === parameters.get('fail') || (reviewState === 'directory-error' && path === 'learners')) return reply(503, { code: 'SERVICE_UNAVAILABLE' }, url.href);
    if (/^learners\/[^/]+$/.test(path)) {
      const learner = findLearner(path.split('/')[1]!);
      return learner ? reply(200, envelope(learner), url.href) : reply(404, { code: 'LEARNER_NOT_FOUND' }, url.href);
    }
    if (/^members\/[^/]+$/.test(path)) {
      const member = db.members.find((item: any) => item.id === path.split('/')[1]);
      return member ? reply(200, envelope(member), url.href) : reply(404, { code: 'MEMBERSHIP_NOT_FOUND' }, url.href);
    }
    const readiness = { schoolId, configurationVersion: 1, computedAt: stamp, activationReady: true, activationBlockers: [], capabilities: ['CAN_USE_WORKSPACE', 'CAN_PLAN_LESSON', 'CAN_CAPTURE'].map(capability => ({ capability, ready: true, blockers: [] })) };
    if (path === 'observation-themes') return reply(200, envelope(themesProjection()), url.href);
    if (path === 'readiness') return reply(200, envelope(readiness), url.href);
    if (path === 'invitation-options') return reply(200, envelope({ emailInvitationsAvailable: parameters.get('email') === '1', codeInvitationsAvailable: true }), url.href);
    if (path === 'setup-draft') return reply(200, envelope(structuredClone(setupDraft)), url.href);
    if (path === 'setup-draft/templates') return reply(200, envelope(setupTemplates), url.href);
    if (path === 'setup-draft/preview') return reply(200, envelope(setupPreview(url.searchParams.get('activate') === 'true')), url.href);
    if (path === 'setup-draft/next-actions') return reply(200, envelope({ schoolId, planningReady: true, actions: parameters.has('first-lesson') ? [
      { code: 'FIRST_LEARNER_REQUIRED', label: 'Inviter votre premier élève', section: 'invitations', query: { audience: 'learners' } },
    ] : [] }), url.href);
    if (path === 'setup') return reply(200, envelope({ schoolId, version: 1, status: 'COMPLETED', currentStep: 'REVIEW', completedSteps: ['IDENTITY', 'DATA'], lastSavedAt: stamp, readiness }), url.href);
    if (path === 'data-policy') return reply(200, envelope(policyState), url.href);
    if (path === 'text-proposals') return reply(200, envelope(textProposals), url.href);
    if (/^learners\/[^/]+\/action-readiness$/.test(path)) {
      const learner = findLearner(path.split('/')[1]!);
      return reply(200, envelope({ learnerId: learner?.id ?? path.split('/')[1], action: 'PLAN_LESSON', ready: learner?.profileReadiness === 'READY', blockers: learner?.profileReadiness === 'READY' ? [] : [{ code: 'PROFILE_ACTION_REQUIRED', field: 'birthDate', message: 'Date de naissance requise.' }] }), url.href);
    }
    if (/^learners\/[^/]+\/administrative-profile$/.test(path)) return reply(200, envelope(administrativeProfile), url.href);
    if (path === 'data-policy/impact') {
      if (parameters.get('impact') === 'slow') await new Promise(resolve => setTimeout(resolve, 1200));
      if (parameters.get('impact') === 'error') return reply(503, { code: 'SERVICE_UNAVAILABLE' }, url.href);
      return reply(200, envelope(parameters.get('impact') === 'zero' ? { gpsAgreements: 0, activeCaptures: 0 } : { gpsAgreements: 3, activeCaptures: 1 }), url.href);
    }
    if (/^trainings\/[^/]+\/assignments$/.test(path)) return reply(200, envelope({ items: db.assignments, nextCursor: null }), url.href);
    if (/^trainings\/[^/]+\/permit-checks$/.test(path)) return reply(200, envelope({ items: db.permits, nextCursor: null }), url.href);
    if (/^trainings\/[^/]+\/progress$/.test(path)) return reply(200, envelope({ trainingId: trainingA, computedAt: stamp, unobservedCompetencyIds: [comp2], items: [{ competencyId: comp1, label: 'Démarrer et s’arrêter', level: 'GUIDED', context: 'Parking', observedAt: stamp, sourceLessonId: lessonDone, sourceRevisionId: uuid() }] }), url.href);
    if (/^lessons\/[^/]+\/reports$/.test(path)) return reply(200, envelope({ items: [{ id: uuid(), schoolId, version: 1, lessonId: lessonDone, sequence: 1, authorMembershipId: marieId, publishedAt: stamp, workedOn: 'Démarrage en côte', observationText: 'Bonne maîtrise du point de patinage.', nextStep: 'Ronds-points', correctionReason: null, observations: [{ competencyId: comp1, level: 'GUIDED', context: 'Parking' }] }], nextCursor: null }), url.href);
    const list = path === 'lessons' ? db.lessons.filter((lesson: any) => (!url.searchParams.get('instructorMembershipId') || lesson.instructorMembershipId === url.searchParams.get('instructorMembershipId')) && (!url.searchParams.get('trainingId') || lesson.trainingId === url.searchParams.get('trainingId')) && (!url.searchParams.get('from') || lesson.plannedEnd > url.searchParams.get('from')!) && (!url.searchParams.get('to') || lesson.plannedStart < url.searchParams.get('to')!))
      : path === 'trainings' && url.searchParams.has('learnerId') ? db.trainings.filter((training: any) => training.learnerId === url.searchParams.get('learnerId'))
      : db[path.replace('availability-rules', 'availability').replace('closures', 'closures')] ?? [];
    return reply(200, envelope({ items: list, nextCursor: null }), url.href);
  }
  if (url.pathname.endsWith('/bff/invitation/preview')) return reply(200, { confirmation: 'synthetic-confirmation', data: { invitationId: uuid(), schoolId, schoolName: value.school.name, roles: ['LEARNER'], maskedEmail: 'l***@example.test', expiresAt: '2026-10-06T08:00:00.000Z', notice: { version: 1, noticeText: 'Les informations de votre profil servent au suivi de votre formation.', retentionText: 'L’école conserve les informations nécessaires au suivi pédagogique.', contactEmail: 'ecole@example.test' } } }, url.href);
  if (url.pathname.endsWith('/bff/opening/preview')) return reply(200, { data: { status: 'AVAILABLE', expiresAt: '2026-10-20T08:00:00.000Z' } }, url.href);
  log.push(`${method} ${path} ${JSON.stringify(body)} if-match=${(init?.headers as Record<string, string>)?.['If-Match'] ?? ''}`);
  if (method === 'PATCH' && path === '') {
    if (schoolConflictOnce) { schoolConflictOnce = false; value.school.version++; value.school.contactPhone = '+41 21 555 00 00'; return reply(412, { code: 'VERSION_CONFLICT' }, url.href); }
    if (reviewState === 'mutation-error') return reply(409, { code: 'INVALID_REQUEST' }, url.href);
    if (reviewState === 'conflict' || (init?.headers as Record<string, string>)?.['If-Match'] !== `"${value.school.version}"`) return reply(412, { code: 'VERSION_CONFLICT' }, url.href);
    Object.assign(value.school, { name: body.name, contactEmail: body.contactEmail, contactPhone: body.contactPhone, version: value.school.version + 1 });
    if (reviewState === 'slow-school-after-save') savedSchoolReadGate = new Promise(resolve => { reviewWindow.__releaseSchoolRead = resolve; });
    value.membership.schoolName = value.school.name;
    return reply(200, envelope(value.school), url.href);
  }
  if (method === 'PATCH' && /^learners\/[^/]+\/administrative-profile$/.test(path)) {
    if (reviewState === 'mutation-error') return reply(409, { code: 'PROFILE_POLICY_CHANGED' }, url.href);
    Object.assign(administrativeProfile, body); administrativeProfile.version++; db.learners[0].version++; db.learners[0].profileReadiness = 'READY';
    return reply(200, envelope(administrativeProfile), url.href);
  }
  if (path === 'setup-draft' || path === 'setup-draft/complete') {
    if (reviewState === 'conflict') return reply(412, { code: 'VERSION_CONFLICT' }, url.href);
    if (reviewState === 'mutation-error') return reply(503, { code: 'SERVICE_UNAVAILABLE' }, url.href);
    if ((init?.headers as Record<string, string>)?.['If-Match'] !== `"${setupDraft.version}"`) return reply(412, { code: 'VERSION_CONFLICT' }, url.href);
    if (method === 'PUT' && path === 'setup-draft') {
      setupDraft.version++; setupDraft.content = structuredClone(body.content); setupDraft.currentStep = body.currentStep;
      setupDraft.updatedAt = stamp; setupDraft.status = 'DRAFT'; setupDraft.appliedAt = null;
      return reply(200, envelope(structuredClone(setupDraft)), url.href);
    }
    if (method === 'POST' && path === 'setup-draft/complete') {
      if (!setupPreview(body.activate).ready) return reply(409, { code: 'SETUP_INCOMPLETE' }, url.href);
      setupDraft.version++; setupDraft.status = 'APPLIED'; setupDraft.appliedAt = stamp;
      value.school.version++; value.school.configurationVersion++;
      if (body.activate) value.school.status = 'ACTIVE';
      return reply(200, envelope({ id: schoolId, schoolId, version: setupDraft.version }), url.href);
    }
  }
  if (method === 'PUT' && path === 'data-policy') {
    if ((init?.headers as Record<string, string>)?.['If-Match'] !== `"${policyState.version}"`) return reply(412, { code: 'VERSION_CONFLICT' }, url.href);
    policyState = { ...policyState, ...body, version: policyState.version + 1, status: 'APPROVED', approvedAt: stamp, noticeVersionId: uuid() };
    if (body.publishProposedFields) db['profile-field-policies'].push({ id: uuid(), schoolId, version: 1, status: 'PUBLISHED', effectiveFrom: stamp, noticeVersionId: policyState.noticeVersionId, approvedByMembershipId: marieId, fields: structuredClone(textProposals.profileFields) });
    value.school.version++;
    return reply(200, envelope(policyState), url.href);
  }
  if (method === 'POST' && path === 'profile-field-policies') {
    if ((init?.headers as Record<string, string>)?.['If-Match'] !== `"${value.school.version}"`) return reply(412, { code: 'VERSION_CONFLICT' }, url.href);
    const item = { id: uuid(), schoolId, version: 1, status: body.publishNow ? 'PUBLISHED' : 'DRAFT', effectiveFrom: stamp, noticeVersionId: body.noticeVersionId, approvedByMembershipId: body.publishNow ? marieId : null, fields: body.fields };
    if (body.publishNow) db['profile-field-policies'].forEach((existing: any) => { existing.status = 'RETIRED'; });
    db['profile-field-policies'].push(item); value.school.version++;
    return reply(201, envelope(item), url.href);
  }
  if (method === 'POST' && path === 'service-products') {
    const version = Math.max(0, ...db['service-products'].filter((item: any) => item.productKey === body.productKey).map((item: any) => item.version)) + 1;
    const item = { ...body, id: uuid(), schoolId, version };
    db['service-products'].push(item);
    return reply(201, envelope(item), url.href);
  }
  if (method === 'PUT' && path === 'observation-themes') {
    // ?state=conflict : quelqu'un d'autre enregistre avant nous (412) ; ?state=forbidden : le droit a été retiré (403).
    if (reviewState === 'conflict') { themeState.version++; themeState.themes = [...themeState.themes].reverse(); return reply(412, { code: 'VERSION_CONFLICT' }, url.href); }
    if (reviewState === 'forbidden') return reply(403, { code: 'OBSERVATION_THEMES_ACCESS_REQUIRED' }, url.href);
    if ((init?.headers as Record<string, string>)?.['If-Match'] !== `"${themeState.version}"`) return reply(412, { code: 'VERSION_CONFLICT' }, url.href);
    themeState.version++; themeState.themes = body.themes;
    return reply(200, envelope(themesProjection()), url.href);
  }
  if (reviewState === 'mutation-error') return reply(409, { code: 'PLANNING_CONFLICT' }, url.href);
  if ((method === 'PATCH' && path.startsWith('members/')) || path.endsWith('/deactivate')) {
    if (!(window as any).__reauthed) return reply(401, { code: 'REAUTH_REQUIRED' }, url.href);
    const target = db.members.find((item: any) => path.includes(item.id)); if (path.endsWith('/deactivate')) target.status = 'INACTIVE'; else { target.roles = body.roles; target.grants = body.grants; } target.version++;
    return reply(200, envelope(target), url.href);
  }
  if (method === 'POST' && path === 'invitations') {
    const byCode = body.delivery === 'CODE';
    if (!byCode && parameters.get('email') !== '1') return reply(409, { code: 'INVITATION_DELIVERY_UNAVAILABLE' }, url.href);
    const item: Record<string, unknown> = { id: uuid(), schoolId, version: 1, delivery: byCode ? 'CODE' : 'EMAIL', maskedEmail: byCode ? null : 'm***@example.test', roles: body.roles, status: 'PENDING', expiresAt: '2026-10-20T08:00:00.000Z', trainings: body.trainings, training: body.trainings?.[0] ?? body.training };
    db.invitations.push(item);
    return reply(201, envelope(byCode ? { ...item, code: codes[0] } : item), url.href);
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
if (parameters.get('role') === 'learner') value.membership.roles = ['LEARNER'];
if (parameters.get('role') === 'instructor') value.membership.roles = ['INSTRUCTOR'];
const saved = reviewWindow.__reviewBoot?.snapshot;
if (saved) {
  Object.assign(db, saved.db); Object.assign(value.school, saved.school); Object.assign(value.membership, saved.membership);
  Object.assign(themeState, saved.themeState); Object.assign(administrativeProfile, saved.administrativeProfile);
  if (saved.setupDraft) Object.assign(setupDraft, saved.setupDraft);
  policyState = saved.policyState;
  fixtureSequence = Math.max(fixtureSequence, saved.fixtureSequence ?? 0);
}
reviewWindow.__reviewSnapshot = () => structuredClone({ db, school: value.school, membership: value.membership, themeState, administrativeProfile, policyState, setupDraft, fixtureSequence });
const pages: Record<string, () => JSX.Element> = { learners: LearnersSection, agenda: AgendaSection, trips: TripsSection, team: TeamSection, availability: AvailabilitySection, absences: () => <AvailabilitySection section="absences" />, config: ConfigurationSection, privacy: PrivacySection, profile: ProfileFieldsSection, overview: OverviewSection, themes: ObservationThemesSection, formations: FormationsSection,
  curricula: CurriculaSection, procedures: ProceduresSection, offerings: OfferingsSection, products: ProductsSection, terms: TermsSection };
const Page = pages[page ?? ''] ?? InvitationsSection;
const shell = parameters.get('shell') === '1';
if (shell && !/^\/app\/gestion\//.test(location.pathname) && location.pathname !== '/app/preferences' && !['preferences', 'opening', 'operator', 'controls'].includes(page ?? '')) {
  const sections: Record<string, string> = { home: '', overview: 'apercu', formations: 'formations', learners: 'eleves', agenda: 'agenda', trips: 'trajets', team: 'equipe', availability: 'disponibilites', absences: 'absences', config: 'configuration', privacy: 'confidentialite', profile: 'champs-profil', themes: 'signalements', curricula: 'referentiels', procedures: 'procedures', offerings: 'offres', products: 'prestations', terms: 'conditions' };
  const routeParameters = new URLSearchParams();
  if (page === 'agenda') routeParameters.set('week', '2026-09-28');
  if (page === 'invitations' && parameters.get('audience') === 'team') routeParameters.set('audience', 'team');
  if (page === 'learners' && parameters.get('selection') === 'outside') routeParameters.set('selection', outsideLearner.id);
  if (page === 'learners' && parameters.get('selection') === 'missing') routeParameters.set('selection', missingLearnerId);
  window.history.replaceState(null, '', `/app/gestion/${schoolId}/${sections[page ?? 'overview'] ?? 'invitations'}${routeParameters.size ? `?${routeParameters}` : ''}`);
}
const entry = ['signin', 'account', 'invitation'].includes(page ?? '');
if (entry) window.history.replaceState(null, '', page === 'invitation' ? '/app/invitation' : '/app/');
if (page === 'preferences') window.history.replaceState(null, '', '/app/preferences');
if (page === 'opening' || page === 'operator') window.history.replaceState(null, '', page === 'opening' ? '/app/ouvrir' : '/app/operateur');
createRoot(document.getElementById('root')!).render(
  page === 'controls' ? <ControlsReview /> : page === 'opening' || page === 'operator' ? <SchoolOpeningPage link={{ token: null, error: false }} operator={page === 'operator'} /> : location.pathname === '/app/preferences' ? <PreferencesPage /> : entry ? <App invitationLink={{ token: null, error: false }} /> : shell ? <ManagementConsole /> : <ConsoleContext.Provider value={value}><div className="console-shell"><main className="console-main"><Page /></main></div></ConsoleContext.Provider>);

/** Local component review only: these controls change fixture state and never submit a school command. */
function ControlsReview() {
  const [unchecked, setUnchecked] = useState(false), [checked, setChecked] = useState(true);
  const [days, setDays] = useState([true, false]), [confirmed, setConfirmed] = useState(false);
  const [email, setEmail] = useState(''), [category, setCategory] = useState(''), [submitted, setSubmitted] = useState(false);
  const form = useRef<HTMLFormElement>(null);
  const emailError = submitted && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) ? 'Indiquez une adresse e-mail valide.' : null;
  const categoryError = submitted && !category ? 'Choisissez une catégorie.' : null;
  return <div className="app-shell personal-preferences"><main className="main"><h1>Contrôles — revue locale</h1><div className="form-grid">
    <section className="settings-section"><div className="settings-section-heading"><h2>Cases à cocher</h2></div><div className="settings-section-body form-grid">
      <CheckField label="Case non cochée" checked={unchecked} onChange={setUnchecked} />
      <CheckField label="Case cochée" checked={checked} onChange={setChecked} />
      <fieldset className="fieldset"><legend>Jours choisis</legend>
        <CheckField label="Sélectionner tous les jours" checked={days.every(Boolean)} indeterminate={days.some(Boolean) && !days.every(Boolean)} onChange={value => setDays([value, value])} />
        {['Lundi', 'Mardi'].map((label, index) => <CheckField key={label} label={label} checked={days[index]!} onChange={value => setDays(current => current.map((day, i) => i === index ? value : day))} />)}
        <p role="status">{days.filter(Boolean).length} jours sélectionnés</p>
      </fieldset>
      <CheckField label="Case désactivée non cochée" checked={false} disabled onChange={setUnchecked} />
      <CheckField label="Case désactivée cochée" checked disabled onChange={setChecked} />
      <CheckField label="Case désactivée mixte" checked={false} indeterminate disabled onChange={setUnchecked} />
      <CheckField label="J’ai relu les choix de démonstration." description="Confirmation locale sans envoi." checked={confirmed} onChange={setConfirmed} variant="confirmation" />
    </div></section>
    <section className="settings-section"><div className="settings-section-heading"><h2>Saisie et clavier</h2></div><div className="settings-section-body form-grid">
      <ThemeControl />
      <form ref={form} className="form-grid" noValidate onSubmit={event => { event.preventDefault(); setSubmitted(true); window.requestAnimationFrame(() => form.current?.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus()); }}>
        <TextField label="E-mail de test" type="email" value={email} onChange={setEmail} error={emailError} />
        <SelectField label="Catégorie de test" value={category} onChange={setCategory} placeholder="Choisir" options={[{ value: 'A', label: 'Permis A' }, { value: 'B', label: 'Permis B' }]} error={categoryError} />
        <button type="submit" className="button primary">Vérifier la saisie</button>
        {submitted && !emailError && !categoryError && <p role="status">Saisie de test valide.</p>}
      </form>
    </div></section>
  </div></main></div>;
}
