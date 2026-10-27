import { describe, expect, test } from 'vitest';
import { applicableProducts, assignmentCovers, canEditPlannedLesson, initialLessonForm, lessonInterval, lessonLocalInstants, lessonWriteBody, planningTrainingLabel, type PlanningLesson, type PlanningProduct } from '../client/lesson-planning-model.js';
import { commandHeaders, createCommand, receiptMatches } from '../client/command-core.js';
import { commandConflictKeys, commandRefreshesSchool } from '../client/command-conflicts.js';
import { matchSchoolRoute } from '../server/school-routes.js';
import type { CommercialTerms } from '../client/school-api.js';

const id = (n: number) => `11111111-1111-4111-8111-${String(n).padStart(12, '0')}`;
const product: PlanningProduct = { id: id(1), schoolId: id(2), version: 2, productKey: 'conduite-b', label: 'Conduite', type: 'INDIVIDUAL_LESSON', categoryCode: 'B', durationMinutes: 45, unitLabel: 'leçon', unitPriceCents: 9500, validFrom: '2026-01-01', validUntil: null, termsVersionId: id(3), enabled: true, current: true, siteId: null };
const terms: CommercialTerms = { id: id(3), schoolId: id(2), version: 1, label: 'Conditions', termsText: 'Texte synthétique', validFrom: '2026-01-01', validUntil: null, approved: true, approvalReason: null, approvedAt: '2026-01-01T00:00:00Z' };
const lesson: PlanningLesson = { id: id(4), schoolId: id(2), version: 3, trainingId: id(5), learnerId: id(6), instructorMembershipId: id(7), learnerDisplayName: 'Élève', instructorDisplayName: 'Moniteur', plannedStart: '2027-01-12T08:00:00.000Z', plannedEnd: '2027-01-12T08:45:00.000Z', timeZone: 'Europe/Zurich', meetingPoint: 'Gare', status: 'PLANNED', actualStart: null, actualEnd: null, priceCentsSnapshot: 9000, bufferMinutesSnapshot: 10, commercialRevisionVersion: 1, commercialSelection: { mode: 'UNIT_PRICE', serviceProductVersionId: id(8), quantity: 1, entitlementLotId: null, acceptedTermsVersionId: id(9) } };
const now = Date.parse('2026-01-01T00:00:00Z');

describe('planification individuelle du bureau', () => {
  test('le libellé métier est affiché sans clé technique de formation', () => {
    const training = { id: id(5), schoolId: id(2), version: 1, learnerId: id(6), offeringId: id(11), categoryCode: 'B', status: 'ACTIVE' as const, startedOn: null, closedOn: null };
    const offering = { id: id(11), schoolId: id(2), version: 1, offeringKey: `formation-${id(12)}`, label: 'Parcours accompagné', categoryCode: 'B', curriculumVersionId: id(13), policyVersionId: id(14), enabled: true, defaultDurationMinutes: 45, defaultPriceCents: 9500 };
    expect(planningTrainingLabel(training, offering)).toBe('Permis B · Parcours accompagné');
    expect(planningTrainingLabel(training, { ...offering, label: null })).toBe('Permis B');
  });
  test('heure inexistante refusée et heure répétée explicitement choisie', () => {
    expect(lessonLocalInstants('2027-03-28T02:30', lesson.timeZone)).toEqual([]);
    const options = lessonLocalInstants('2027-10-31T02:30', lesson.timeZone);
    expect(options).toEqual(['2027-10-31T00:30:00.000Z', '2027-10-31T01:30:00.000Z']);
    const form = { ...initialLessonForm(lesson), localStart: '2027-10-31T02:30', localChoice: '' };
    expect(lessonInterval(form, lesson.timeZone, now)).toBeNull();
    expect(lessonInterval({ ...form, localChoice: options[1]! }, lesson.timeZone, now)?.plannedStart).toBe(options[1]);
  });
  test('création sélectionne une vraie version et un prix pour la durée', () => {
    const form = { ...initialLessonForm(lesson), duration: '90' };
    const body = lessonWriteBody(form, lesson.timeZone, id(10), product, undefined, now);
    expect(body).toMatchObject({ trainingId: lesson.trainingId, bufferMinutes: 10, policyVersionId: id(10), agreedPriceCents: 19000,
      commercialSelection: { serviceProductVersionId: product.id, quantity: 2, acceptedTermsVersionId: terms.id, mode: 'UNIT_PRICE', entitlementLotId: null } });
  });
  test('déplacement conserve le contrat original, accord explicite obligatoire', () => {
    const form = { ...initialLessonForm(lesson), localStart: '2027-01-13T09:00' };
    expect(() => lessonWriteBody(form, lesson.timeZone, id(10), product, lesson, now)).toThrow(/accord/);
    const body = lessonWriteBody({ ...form, agreement: true }, lesson.timeZone, id(10), product, lesson, now);
    expect(body).not.toHaveProperty('commercialChange'); expect(body).not.toHaveProperty('agreedPriceCents'); expect(body).not.toHaveProperty('bufferMinutes'); expect(body).not.toHaveProperty('policyVersionId');
    expect(() => lessonWriteBody({ ...form, agreement: true, duration: '90' }, lesson.timeZone, id(10), product, lesson, now)).toThrow(/tarif explicite/);
  });
  test('changement commercial délibéré, motif et nouvelle version', () => {
    const form = { ...initialLessonForm(lesson), agreement: true, duration: '90', commercialChange: true };
    expect(() => lessonWriteBody(form, lesson.timeZone, id(10), product, lesson, now)).toThrow(/motif/);
    expect(lessonWriteBody({ ...form, reason: 'Durée demandée' }, lesson.timeZone, id(10), product, lesson, now)).toMatchObject({ commercialChange: { agreedPriceCents: 19000, expectedAccountVersion: null, reason: 'Durée demandée' } });
  });
  test('tarifs anciens, hors dates, autre permis, site et conditions non approuvées exclus', () => {
    expect(applicableProducts([product], [terms], 'B', '2027-01-12', 45)).toEqual([product]);
    for (const variant of [{ current: false }, { enabled: false }, { categoryCode: 'A' }, { siteId: id(99) }, { validUntil: '2026-12-31' }, { durationMinutes: 50 }]) {
      expect(applicableProducts([{ ...product, ...variant }], [terms], 'B', '2027-01-12', 45)).toEqual([]);
    }
    expect(applicableProducts([product], [{ ...terms, approved: false }], 'B', '2027-01-12', 45)).toEqual([]);
  });
  test('affectation actuelle couvre le rendez-vous entier et état commencé interdit au bureau', () => {
    const assignment = { id: id(10), schoolId: id(2), version: 1, trainingId: id(5), instructorMembershipId: id(7), validFrom: '2025-12-01T00:00:00Z', validUntil: null };
    expect(assignmentCovers(assignment, lesson.plannedStart, lesson.plannedEnd, now)).toBe(true);
    expect(assignmentCovers({ ...assignment, validUntil: '2027-01-12T08:30:00Z' }, lesson.plannedStart, lesson.plannedEnd, now)).toBe(false);
    expect(canEditPlannedLesson(lesson)).toBe(true);
    expect(canEditPlannedLesson({ ...lesson, actualStart: lesson.plannedStart })).toBe(false);
    expect(canEditPlannedLesson({ ...lesson, status: 'CANCELLED' })).toBe(false);
  });
  test.each(['createLesson', 'moveLesson', 'cancelLesson'] as const)('%s suit son opération et son agrégat planning', kind => {
    const command = createCommand({ schoolId: lesson.schoolId, kind, path: 'lessons', body: {}, resourceVersion: kind === 'createLesson' ? 0 : 3, ...(kind !== 'createLesson' ? { resourceId: lesson.id, ifMatch: 3 } : {}) });
    const receipt = { operationId: command.operationId, commandType: { createLesson: 'CREATE_LESSON', moveLesson: 'MOVE_LESSON', cancelLesson: 'CANCEL_LESSON' }[kind], resourceType: 'Lesson', resourceId: lesson.id, resourceVersion: 4, committedAt: lesson.plannedStart };
    expect(receiptMatches(command, receipt)).toBe(true);
    expect(receiptMatches(command, { ...receipt, commandType: 'CREATE_COURSE_SERIES' })).toBe(false);
    expect(commandHeaders(command, 'csrf')['Idempotency-Key']).toBe(command.operationId);
    if (kind !== 'createLesson') expect(commandHeaders(command, 'csrf')['If-Match']).toBe('"3"');
    expect(commandConflictKeys(command)).toEqual(['planning']); expect(commandRefreshesSchool(kind)).toBe(false);
  });
  test('BFF ouvre seulement disponibilité/create/move/cancel et impose versions et paramètres bornés', () => {
    const base = `/schools/${lesson.schoolId}/lessons`;
    expect(matchSchoolRoute('POST', base, '')?.route.bodyLimit).toBe(8192);
    for (const action of ['move', 'cancel']) expect(matchSchoolRoute('POST', `${base}/${lesson.id}/${action}`, '')?.route.ifMatch).toBe(true);
    const query = `?trainingId=${lesson.trainingId}&instructorMembershipId=${lesson.instructorMembershipId}&plannedStart=2027-01-12T08:00:00Z&plannedEnd=2027-01-12T08:45:00Z&timeZone=Europe%2FZurich&bufferMinutes=10&excludeLessonId=${lesson.id}`;
    expect(matchSchoolRoute('GET', `${base}/availability`, query)).toBeDefined();
    for (const suffix of ['&bufferMinutes=10', '&q=private', '&reason=private']) expect(matchSchoolRoute('GET', `${base}/availability`, query + suffix)).toBeUndefined();
    expect(matchSchoolRoute('GET', `${base}/availability`, query.replace('bufferMinutes=10', 'bufferMinutes=241'))).toBeUndefined();
    for (const path of ['start-now', `${lesson.id}/start`, `${lesson.id}/finish`, `${lesson.id}/captures`]) expect(matchSchoolRoute('POST', `${base}/${path}`, '')).toBeUndefined();
  });
});
