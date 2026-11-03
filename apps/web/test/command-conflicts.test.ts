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
    expect(commandConflictKeys(create('createExam', { path: 'exams' }))).toEqual(['exams', 'planning']);
    expect(commandConflictKeys(create('updateSchool', { path: '' }))).toEqual(['school']);
    expect(commandConflictKeys(create('createTraining', { path: 'trainings' }))).toEqual(['learners', 'planning']);
    expect(commandConflictKeys(create('saveObservationThemes', { path: 'observation-themes' }))).toEqual(['observation-themes']);
  });
});
