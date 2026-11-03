import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import { createCommand, type CommandKind, type SchoolCommand } from '../client/command-core.js';
import { commandConflictKeys, commandsConflict, wouldConflict } from '../client/command-conflicts.js';

const schoolId = randomUUID();
const other = randomUUID();
const instructorA = randomUUID();
const instructorB = randomUUID();
const learnerA = randomUUID();
const learnerB = randomUUID();

const create = (kind: CommandKind, input: { path?: string; body?: Record<string, unknown>; resourceId?: string; version?: number; scope?: string; school?: string; operationId?: string } = {}) =>
  createCommand({ schoolId: input.school ?? schoolId, kind, path: input.path ?? 'x', body: input.body ?? {},
    ...(input.resourceId ? { resourceId: input.resourceId, ifMatch: input.version ?? 1, resourceVersion: input.version ?? 1 } : { resourceVersion: 0 }),
    ...(input.scope ? { scope: input.scope } : {}), ...(input.operationId ? { operationId: input.operationId } : {}) });
const entry = (command: SchoolCommand | null, school = schoolId) => ({ meta: { schoolId: school }, command });

describe('Conflits : une opération n’attend que ce qu’elle partage', () => {
  test('deux invitations différentes, renvoi et révocation, s’exécutent côte à côte ; la même invitation reste ordonnée', () => {
    const idA = randomUUID(), idB = randomUUID();
    const resendA = create('resendInvitation', { path: `invitations/${idA}/resend`, resourceId: idA });
    const revokeB = create('revokeInvitation', { path: `invitations/${idB}/revoke`, resourceId: idB, body: { reason: 'Erreur' } });
    const revokeA = create('revokeInvitation', { path: `invitations/${idA}/revoke`, resourceId: idA, body: { reason: 'Erreur' } });
    expect(commandsConflict(resendA, revokeB)).toBe(false);
    expect(commandsConflict(resendA, revokeA)).toBe(true);
    expect(commandsConflict(revokeA, resendA)).toBe(true);
  });

  test('créer deux codes ne bloque pas, rejouer la même opération est refusé, deux créations pour la même adresse s’ordonnent', () => {
    const body = { delivery: 'CODE', roles: ['LEARNER'], trainings: [] };
    const first = create('createInvitation', { path: 'invitations', body }), second = create('createInvitation', { path: 'invitations', body });
    expect(commandsConflict(first, second)).toBe(false);
    // Un double appui représente la même intention : même opération.
    const again = create('createInvitation', { path: 'invitations', body, operationId: first.operationId });
    expect(commandsConflict(first, again)).toBe(true);
    const mail = (email: string) => create('createInvitation', { path: 'invitations', body: { delivery: 'EMAIL', email, roles: ['LEARNER'] } });
    expect(commandsConflict(mail('Eleve@Exemple.ch'), mail(' eleve@exemple.ch '))).toBe(true);
    expect(commandsConflict(mail('a@exemple.ch'), mail('b@exemple.ch'))).toBe(false);
    // Créer et renvoyer sont deux invitations différentes.
    const idA = randomUUID();
    expect(commandsConflict(first, create('resendInvitation', { path: `invitations/${idA}/resend`, resourceId: idA }))).toBe(false);
  });

  test('un changement d’accès bloque tout ; une demande restaurée sans contenu bloque tout jusqu’à son résultat', () => {
    const idA = randomUUID();
    const member = create('deactivateMember', { path: `members/${idA}/deactivate`, resourceId: idA });
    expect(commandsConflict(member, create('resendInvitation', { path: `invitations/${idA}/resend`, resourceId: idA }))).toBe(true);
    expect(commandsConflict(null, create('resendInvitation', { path: `invitations/${idA}/resend`, resourceId: idA }))).toBe(true);
    expect(wouldConflict([entry(null)], schoolId, { kind: 'resendInvitation', resourceId: idA })).toBe(true);
    // Une autre école n’attend rien.
    expect(wouldConflict([entry(null, other)], schoolId, { kind: 'resendInvitation', resourceId: idA })).toBe(false);
  });

  test('horaires et absences : un moniteur n’attend pas un autre, une règle n’attend pas une absence, mais la planification reste commune', () => {
    const rule = (instructor: string) => create('createAvailabilityRule', { path: 'availability-rules', body: { instructorMembershipId: instructor } });
    const absence = (instructor: string) => create('createClosure', { path: 'closures', body: { instructorMembershipId: instructor } });
    expect(commandsConflict(rule(instructorA), rule(instructorB))).toBe(false);
    expect(commandsConflict(rule(instructorA), rule(instructorA))).toBe(true);
    expect(commandsConflict(rule(instructorA), absence(instructorA))).toBe(false);
    expect(commandsConflict(absence(instructorA), absence(instructorA))).toBe(true);
    // Un retrait nomme son moniteur par la portée : le corps ne contient que le motif.
    const ruleId = randomUUID();
    const removal = create('removeAvailabilityRule', { path: `availability-rules/${ruleId}/remove`, resourceId: ruleId, scope: instructorA, body: { reason: 'Retirée' } });
    expect(commandsConflict(removal, rule(instructorA))).toBe(true);
    expect(commandsConflict(removal, rule(instructorB))).toBe(false);
    const lesson = create('createLesson', { path: 'lessons' });
    expect(commandsConflict(lesson, rule(instructorB))).toBe(true);
    expect(commandsConflict(absence(instructorA), lesson)).toBe(true);
    expect(commandConflictKeys(lesson)).toEqual(['planning']);
  });

  test('sans moniteur connu, une règle reste conservatrice comme avant', () => {
    const unknown = create('removeAvailabilityRule', { path: `availability-rules/${randomUUID()}/remove`, resourceId: randomUUID(), body: { reason: 'Retirée' } });
    expect(commandConflictKeys(unknown)).toEqual(['planning']);
    expect(commandsConflict(unknown, create('createAvailabilityRule', { path: 'availability-rules', body: { instructorMembershipId: instructorB } }))).toBe(true);
  });

  test('dossiers : un élève n’attend pas un autre, le même élève s’ordonne, la planification attend tous', () => {
    const training = (learner: string) => create('createTraining', { path: 'trainings', body: { learnerId: learner, offeringId: randomUUID() } });
    const trainingId = randomUUID();
    const assignment = (learner: string) => create('createAssignment', { path: `trainings/${trainingId}/assignments`, scope: learner, body: { instructorMembershipId: instructorA } });
    const archive = (learner: string) => create('archiveLearner', { path: `learners/${learner}/archive`, resourceId: learner, body: { reason: 'Départ' } });
    expect(commandsConflict(training(learnerA), assignment(learnerB))).toBe(false);
    expect(commandsConflict(training(learnerA), assignment(learnerA))).toBe(true);
    expect(commandsConflict(archive(learnerA), assignment(learnerA))).toBe(true);
    expect(commandsConflict(archive(learnerA), archive(learnerB))).toBe(false);
    expect(commandsConflict(archive(learnerA), create('createLesson', { path: 'lessons' }))).toBe(true);
    expect(commandsConflict(training(learnerA), create('setExamResult', { path: `exams/${randomUUID()}/result`, resourceId: randomUUID() }))).toBe(false);
  });

  test('les autres familles gardent leurs clés d’origine', () => {
    expect(commandConflictKeys(create('saveTariff', { path: 'formations/tariffs' }))).toEqual(['catalogue']);
    expect(commandConflictKeys(create('createCommercialTerms', { path: 'formations/terms' }))).toEqual(['catalogue']);
    expect(commandConflictKeys(create('createExam', { path: 'exams' }))).toEqual(['exams', 'planning']);
    expect(commandConflictKeys(create('updateSchool', { path: '' }))).toEqual(['school']);
    expect(commandConflictKeys(create('createTraining', { path: 'trainings' }))).toEqual(['learners', 'planning']);
    expect(commandConflictKeys(create('saveObservationThemes', { path: 'observation-themes' }))).toEqual(['observation-themes']);
  });
});

describe('Catalogue : un agrégat par produit tarifaire et par jeu de conditions (#124)', () => {
  const tariff = (productKey: string | null) => create('saveTariff', { path: 'formations/tariffs', body: { mode: 'UPDATE' },
    ...(productKey ? { scope: productKey } : {}) });
  const terms = (termsVersionId: string | null) => create('reviseSharedTerms', { path: 'formations/terms/revise', body: { reviewAcknowledged: true },
    ...(termsVersionId ? { scope: termsVersionId } : {}) });

  test('deux produits indépendants ne s’attendent pas ; le même produit reste ordonné', () => {
    expect(commandConflictKeys(tariff('lesson-45'))).toEqual(['catalogue:product:lesson-45']);
    expect(commandsConflict(tariff('lesson-45'), tariff('exam-support'))).toBe(false);
    expect(commandsConflict(tariff('lesson-45'), tariff('lesson-45'))).toBe(true);
    expect(commandsConflict(tariff('LESSON-45'), tariff('lesson-45'))).toBe(true);
  });

  test('sans agrégat nommé, un tarif garde la famille entière : création et conditions partagées attendent tout le catalogue', () => {
    expect(commandConflictKeys(tariff(null))).toEqual(['catalogue']);
    expect(commandsConflict(tariff(null), tariff('lesson-45'))).toBe(true);
    expect(commandsConflict(tariff('lesson-45'), tariff(null))).toBe(true);
    // Un tarif qui touche des conditions partagées n'a qu'une clé à sa disposition : la famille, qui contient la révision.
    expect(commandsConflict(tariff(null), terms('terms-1'))).toBe(true);
  });

  test('une révision de conditions s’ordonne par jeu ; un tarif a ses propres conditions n’attend pas une révision', () => {
    expect(commandConflictKeys(terms('terms-1'))).toEqual(['catalogue:terms:terms-1', 'planning']);
    expect(commandsConflict(terms('terms-1'), terms('terms-1'))).toBe(true);
    // Le tarif qui partage ces conditions est envoyé sans portée (test précédent) ; celui qui a ses propres conditions, non.
    expect(commandsConflict(terms('terms-1'), tariff('lesson-45'))).toBe(false);
  });

  test('les relations existantes avec la planification et les accès ne changent pas', () => {
    const lesson = create('createLesson', { path: 'lessons' }), member = create('updateMember', { path: `members/${instructorA}`, resourceId: instructorA });
    // Avant #124 comme après : un tarif n'attend pas une leçon, une révision de conditions si (elle tombait dans « * »).
    expect(commandsConflict(tariff('lesson-45'), lesson)).toBe(false);
    expect(commandsConflict(terms('terms-1'), lesson)).toBe(true);
    // Un changement d'accès bloque toujours tout, tarif comme conditions.
    expect(commandsConflict(tariff('lesson-45'), member)).toBe(true);
    expect(commandsConflict(terms('terms-1'), member)).toBe(true);
  });
});

describe('Faits de cours : un participant n’attend pas un autre (#99, lot E)', () => {
  const series = randomUUID();
  const scoped = (participant: string) => `${series}:${participant}`;
  const participantA = randomUUID(), participantB = randomUUID();
  const attendance = (participant: string) => create('recordCourseAttendance', {
    path: `course-enrollments/${randomUUID()}/attendance/${randomUUID()}`, resourceId: randomUUID(), body: { status: 'PRESENT' }, scope: scoped(participant) });
  const payment = (participant: string) => create('recordCoursePayment', { path: `course-enrollments/${randomUUID()}/payments`, body: { amountCents: 12_000, note: null }, scope: scoped(participant) });
  const validate = (participant: string) => create('validateCourse', { path: `course-enrollments/${randomUUID()}/validate`, body: { note: null }, scope: scoped(participant) });
  const revoke = (participant: string) => create('revokeCourseCompletion', {
    path: `course-completions/${randomUUID()}/revoke`, resourceId: randomUUID(), body: { reason: 'Erreur de saisie' }, scope: scoped(participant) });
  const voidPayment = (participant: string) => create('voidCoursePayment', {
    path: `course-payments/${randomUUID()}/void`, resourceId: randomUUID(), body: { reason: 'Erreur de saisie' }, scope: scoped(participant) });
  const unscoped = () => create('recordCoursePayment', { path: `course-enrollments/${randomUUID()}/payments`, body: { amountCents: 12_000, note: null } });

  test('deux participants sont indépendants ; le même participant reste ordonné quel que soit le geste', () => {
    expect(commandConflictKeys(attendance(participantA))).toEqual([`course-facts:${series}:${participantA}`]);
    expect(commandsConflict(attendance(participantA), payment(participantB))).toBe(false);
    expect(commandsConflict(attendance(participantA), validate(participantA))).toBe(true);
    expect(commandsConflict(payment(participantA), voidPayment(participantA))).toBe(true);
    expect(commandsConflict(revoke(participantA), attendance(participantA))).toBe(true);
    // Une autre série, même personne : deux cours distincts ne s'attendent pas.
    const otherSeries = create('recordCourseAttendance', { path: `course-enrollments/${randomUUID()}/attendance/${randomUUID()}`, resourceId: randomUUID(),
      body: { status: 'ABSENT' }, scope: `${randomUUID()}:${participantA}` });
    expect(commandsConflict(attendance(participantA), otherSeries)).toBe(false);
  });

  test('sans participant nommé, la famille reste conservatrice', () => {
    expect(commandConflictKeys(unscoped())).toEqual(['course-facts']);
    expect(commandsConflict(unscoped(), attendance(participantB))).toBe(true);
    expect(commandsConflict(attendance(participantA), unscoped())).toBe(true);
    expect(commandsConflict(unscoped(), unscoped())).toBe(true);
    expect(wouldConflict([entry(attendance(participantA))], schoolId, { kind: 'recordCoursePayment' })).toBe(true);
    expect(wouldConflict([entry(attendance(participantA))], schoolId, { kind: 'recordCoursePayment', scope: scoped(participantB) })).toBe(false);
  });

  test('les relations existantes avec la planification et les accès ne changent pas', () => {
    const lesson = create('createLesson', { path: 'lessons' });
    const enrolment = create('staffEnrollCourse', { path: `course-series/${randomUUID()}/enrollments`, body: { learnerId: learnerA } });
    const reschedule = create('rescheduleCourseSeries', { path: `course-series/${randomUUID()}/reschedule`, resourceId: randomUUID(), body: {} });
    expect(commandsConflict(attendance(participantA), lesson)).toBe(false);
    expect(commandsConflict(lesson, attendance(participantA))).toBe(false);
    expect(commandsConflict(attendance(participantA), enrolment)).toBe(false);
    expect(commandsConflict(attendance(participantA), reschedule)).toBe(false);
    // Un changement d'accès bloque toujours tout, faits de cours compris.
    expect(commandsConflict(attendance(participantA), create('updateMember', { path: `members/${instructorA}`, resourceId: instructorA }))).toBe(true);
    expect(commandsConflict(attendance(participantA), create('deactivateMember', { path: `members/${instructorA}/deactivate`, resourceId: instructorA }))).toBe(true);
    // Deux gestes sans agrégat nommé s'ordonnent comme avant.
    expect(commandsConflict(create('recordCoursePayment', { path: `course-enrollments/${randomUUID()}/payments`, body: { amountCents: 1, note: null } }),
      create('recordCoursePayment', { path: `course-enrollments/${randomUUID()}/payments`, body: { amountCents: 2, note: null } }))).toBe(true);
  });
});
