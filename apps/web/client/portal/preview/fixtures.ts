import { civilDateIn } from '../../agenda-model';
import { schoolTimeToInstant } from '../../command-core';
import type { ConsoleContextValue } from '../../console/context';

/** Synthetic data only. This module is reachable only from the separate preview entry. */
export const previewId = (number: number) => `31100000-0000-4000-8000-${String(number).padStart(12, '0')}`;
export const ids = { school: previewId(1), person: previewId(2), admin: previewId(3), instructor: previewId(4),
  learner: previewId(10), training: previewId(20), offering: previewId(30), curriculum: previewId(40), policy: previewId(50),
  terms: previewId(60), product: previewId(70), lesson: previewId(80), report: previewId(90), profilePolicy: previewId(100) };
export const today = civilDateIn('Europe/Zurich');
export function dayAfter(days: number) { const date = new Date(`${today}T12:00:00Z`); date.setUTCDate(date.getUTCDate() + days); return date.toISOString().slice(0, 10); }
const at = (days: number, time: string) => schoolTimeToInstant(`${dayAfter(days)}T${time}`, 'Europe/Zurich')!;
export const stamp = at(-10, '09:00');
export const previewSchool: ConsoleContextValue['school'] = { id: ids.school, schoolId: ids.school, version: 1, name: 'École du Léman', timeZone: 'Europe/Zurich', status: 'ACTIVE', contactEmail: 'ecole@example.test', contactPhone: null, configurationVersion: 1,
  modules: { gpsEnabled: false, packsEnabled: false, collectiveCoursesEnabled: true, courseOffersVisibleByDefault: false } };
export const previewMembership: ConsoleContextValue['membership'] = { membershipId: ids.admin, schoolId: ids.school, schoolName: previewSchool.name,
  roles: ['ADMIN', 'INSTRUCTOR'], grants: ['permit_review', 'MANAGE_LEARNER_ARCHIVES', 'CONFIGURE_CATALOG', 'REVIEW_REGULATORY_PROFILE', 'MANAGE_COURSES', 'TAKE_ATTENDANCE', 'VALIDATE_REQUIREMENT'], accessEpoch: 1 };
export const previewMe: ConsoleContextValue['me'] = { personId: ids.person, displayName: 'Luc Martin', version: 1, memberships: [previewMembership] };

// A JSON-shaped store makes mutations observable across the three pilots, without another production store.
export type FixtureRecord = Record<string, any>;
export const db: Record<string, FixtureRecord[]> = {
  members: [
    { id: ids.admin, personId: ids.person, displayName: 'Luc Martin', roles: ['ADMIN', 'INSTRUCTOR'], grants: [...previewMembership.grants], status: 'ACTIVE', accessEpoch: 1 },
    { id: ids.instructor, personId: previewId(5), displayName: 'Marie Dupont', roles: ['INSTRUCTOR'], grants: ['permit_review', 'TAKE_ATTENDANCE'], status: 'ACTIVE', accessEpoch: 1 },
    { id: previewId(6), personId: previewId(7), displayName: 'Simon Favre', roles: ['INSTRUCTOR'], grants: [], status: 'ACTIVE', accessEpoch: 1 },
  ].map(item => ({ ...item, schoolId: ids.school, version: 1 })),
  learners: ['Éloïse Müller', 'Bruno Blanc', 'Jade Perrin', 'Sami Dubois', 'Léa Rochat', 'Noah Meier'].map((displayName, index) => ({ id: previewId(10 + index), schoolId: ids.school,
    version: 1, personId: previewId(210 + index), displayName, contactEmail: index === 0 ? 'eloise@example.test' : null, contactPhone: null,
    archivedAt: null, profileReadiness: index === 2 ? 'ACTION_REQUIRED' : 'READY' })),
  trainings: Array.from({ length: 6 }, (_, index) => ({ id: previewId(20 + index), schoolId: ids.school, version: 1, learnerId: previewId(10 + index), offeringId: ids.offering,
    categoryCode: 'B', status: 'ACTIVE', startedOn: dayAfter(-30), closedOn: null })),
  offerings: [{ id: ids.offering, schoolId: ids.school, version: 1, offeringKey: 'b-standard', categoryCode: 'B', label: 'Permis B', curriculumVersionId: ids.curriculum,
    policyVersionId: ids.policy, enabled: true, defaultDurationMinutes: 45, defaultPriceCents: 9500 }],
  curricula: [{ id: ids.curriculum, schoolId: ids.school, version: 1, categoryCode: 'B', revision: 1, approved: true,
    competencies: ['Préparer le véhicule', 'Démarrer et s’arrêter', 'Observer et anticiper', 'Adapter son allure', 'Franchir les intersections', 'Manœuvrer'].map((label, index) => ({ id: previewId(300 + index), key: `skill-${index}`, label, description: '', sortOrder: index })) }],
  assignments: Array.from({ length: 6 }, (_, index) => ({ id: previewId(400 + index), schoolId: ids.school, version: 1, trainingId: previewId(20 + index), instructorMembershipId: index === 3 ? ids.admin : ids.instructor, validFrom: stamp, validUntil: null })),
  permits: Array.from({ length: 6 }, (_, index) => ({ id: previewId(420 + index), schoolId: ids.school, version: 1, trainingId: previewId(20 + index), documentId: null,
    physicalSeen: true, categoryCode: 'B', validUntil: dayAfter(300), decision: 'APPROVED', reviewerMembershipId: ids.admin, reviewedAt: stamp, reason: null, isExpired: false })),
  'policy-versions': [{ id: ids.policy, schoolId: ids.school, version: 1, categoryCode: 'B', procedureText: 'Conditions pédagogiques synthétiques pour cet aperçu.', cancellationPolicyText: 'Prévenez votre école en cas d’empêchement.', sourceUrls: [], approved: true, approvedAt: stamp }],
  'commercial-terms': [{ id: ids.terms, schoolId: ids.school, version: 1, label: 'Conditions de l’école', termsText: 'Conditions synthétiques : le règlement de la leçon est effectué auprès de l’école.', validFrom: dayAfter(-60), validUntil: null, approved: true, approvalReason: 'Aperçu', approvedAt: stamp }],
  'service-products': [{ id: ids.product, schoolId: ids.school, version: 1, productKey: 'conduite-b', label: 'Leçon de conduite', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45,
    unitLabel: 'leçon', unitPriceCents: 9500, validFrom: dayAfter(-60), validUntil: null, termsVersionId: ids.terms, enabled: true, current: true, siteId: null }],
  lessons: [[0, '09:00'], [0, '10:30'], [1, '09:00'], [1, '14:00'], [2, '11:00'], [-2, '09:00']].map(([offset, time], index) => {
    const start = at(Number(offset), String(time)); const learnerIndex = index === 5 ? 0 : index % 4;
    return { id: previewId(80 + index), schoolId: ids.school, version: 1, trainingId: previewId(20 + learnerIndex), learnerId: previewId(10 + learnerIndex),
      learnerDisplayName: ['Éloïse Müller', 'Bruno Blanc', 'Jade Perrin', 'Sami Dubois'][learnerIndex], instructorMembershipId: ids.instructor, instructorDisplayName: 'Marie Dupont',
      plannedStart: start, plannedEnd: new Date(Date.parse(start) + 45 * 60000).toISOString(), timeZone: 'Europe/Zurich', meetingPoint: index % 2 ? 'Gare de Lausanne' : 'Devant l’école',
      status: index === 5 ? 'COMPLETED' : 'PLANNED', actualStart: index === 5 ? start : null, actualEnd: index === 5 ? new Date(Date.parse(start) + 45 * 60000).toISOString() : null,
      permitWarning: false, currentPublishedRevisionId: index === 5 ? ids.report : null, priceCentsSnapshot: 9500, bufferMinutesSnapshot: 10, commercialRevisionVersion: 1,
      commercialSelection: { mode: 'UNIT_PRICE', serviceProductVersionId: ids.product, quantity: 1, entitlementLotId: null, acceptedTermsVersionId: ids.terms } };
  }),
  'availability-rules': [{ id: previewId(500), schoolId: ids.school, version: 1, instructorMembershipId: ids.instructor, weekdays: [1, 2, 3, 4, 5], localStart: '08:00', localEnd: '18:00', validFrom: dayAfter(-60), validUntil: null }],
  closures: [], captures: [], invitations: [],
  profiles: Array.from({ length: 6 }, (_, index) => ({ id: previewId(600 + index), schoolId: ids.school, version: 1, learnerId: previewId(10 + index), policyVersionId: ids.profilePolicy })),
  'course-series': [{ id: previewId(700), schoolId: ids.school, version: 1, status: 'PUBLISHED', typeId: previewId(710), typeTitle: 'Sensibilisation', title: 'Sensibilisation du soir',
    description: 'Anticipation des dangers et partage de la route.', location: 'Salle de formation', conditions: 'Apporter son permis d’élève.', teachingLanguage: 'fr',
    responsibleMembershipId: ids.admin, responsibleDisplayName: 'Luc Martin', capacity: 10, seatsTaken: 3, remainingSeats: 7, minParticipants: null, policyVersion: 1,
    selfCancelHours: 24, selfCancellationDeadline: at(0, '18:00'), firstStartsAt: at(1, '18:00'), lastEndsAt: at(1, '20:00'), totalMinutes: 120, publishedAt: stamp, canManage: true,
    occurrences: [{ id: previewId(701), position: 1, startsAt: at(1, '18:00'), endsAt: at(1, '20:00'), timeZone: 'Europe/Zurich', instructorMembershipId: ids.admin, instructorDisplayName: 'Luc Martin', attendanceRequired: true }] }],
};
export const courseCatalogue = { schoolId: ids.school, canManage: true, types: [{ id: previewId(710), schoolId: null, stableKey: 'AWARENESS', title: 'Sensibilisation', description: '', version: 1, predefined: true }],
  policy: { version: 1, selfCancelHours: 24, offerResponseMinutes: 720 }, instructors: db.members!.map(item => ({ membershipId: item.id, displayName: item.displayName })) };
export function progress(trainingId: string) { return { trainingId, computedAt: stamp, unobservedCompetencyIds: [previewId(304), previewId(305)],
  items: db.curricula![0]!.competencies.slice(0, 4).map((item: FixtureRecord, index: number) => ({ competencyId: item.id, label: item.label, level: index < 2 ? 'INDEPENDENT' : 'GUIDED', context: 'En circulation', observedAt: stamp, sourceLessonId: previewId(85), sourceRevisionId: ids.report })) }; }
export function reports(lessonId: string) { return lessonId === previewId(85) ? [{ id: ids.report, schoolId: ids.school, version: 1, lessonId, sequence: 1, authorMembershipId: ids.instructor, publishedAt: stamp,
  workedOn: 'Démarrage en côte et circulation en ville', observationText: 'Bonne maîtrise du véhicule. Les contrôles avant changement de direction gagnent en régularité.',
  nextStep: 'Travailler l’anticipation à l’approche des intersections.', correctionReason: null, observations: [{ competencyId: previewId(302), level: 'GUIDED', context: 'En circulation' }] }] : []; }
