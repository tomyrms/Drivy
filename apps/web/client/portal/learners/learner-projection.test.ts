import { describe, expect, it } from 'vitest';
import type { Assignment, Learner, Training } from '../../school-api';
import { followedFor, isProvisional, projectAssignments, projectLearner, projectTrainings, visibleIntentions, type LearnerIntention } from './learner-projection';

const learner = (patch: Partial<Learner> = {}): Learner => ({ id: 'l1', schoolId: 's', version: 4, personId: 'p', displayName: 'Camille Martin', contactEmail: null, contactPhone: null, archivedAt: null, ...patch });
const training = (id: string, patch: Partial<Training> = {}): Training => ({ id, schoolId: 's', version: 2, learnerId: 'l1', offeringId: 'o1', status: 'ACTIVE', startedOn: '2026-10-01', closedOn: null, ...patch });
const assignment = (id: string, patch: Partial<Assignment> = {}): Assignment => ({ id, schoolId: 's', version: 1, trainingId: 't1', instructorMembershipId: 'm1', validFrom: '2026-10-01T08:00:00.000Z', validUntil: null, ...patch });
const base = { learnerId: 'l1' };

describe('projection locale du dossier élève', () => {
  it('un archivage demandé reste une marque : le dossier n’est ni archivé ni effacé de la liste', () => {
    const intention: LearnerIntention = { ...base, tag: 'learner:l1', operationId: 'op-1', kind: 'learner-archive', reason: 'Départ' };
    const { learner: shown, mark } = projectLearner(learner(), [intention]);
    expect(mark).toBe('archiving');
    expect(shown.archivedAt).toBeNull();
  });

  it('une restauration demandée garde le dossier archivé : aucune modification n’est permise avant le reçu', () => {
    const archived = learner({ archivedAt: '2026-09-01T10:00:00.000Z' });
    const intention: LearnerIntention = { ...base, tag: 'learner:l1', operationId: 'op-2', kind: 'learner-restore', reason: 'Retour' };
    const { learner: shown, mark } = projectLearner(archived, [intention]);
    expect(mark).toBe('restoring');
    expect(shown.archivedAt).toBe('2026-09-01T10:00:00.000Z');
  });

  it('une fois confirmés, l’archivage et la restauration se voient sans marque jusqu’à la relecture', () => {
    const archiving: LearnerIntention = { ...base, tag: 'learner:l1', operationId: 'op-3', kind: 'learner-archive', reason: 'Départ', settledAt: Date.parse('2026-11-02T10:00:00Z') };
    expect(projectLearner(learner(), [archiving])).toMatchObject({ mark: undefined, learner: { archivedAt: '2026-11-02T10:00:00.000Z' } });
    const restoring: LearnerIntention = { ...base, tag: 'learner:l1', operationId: 'op-4', kind: 'learner-restore', reason: 'Retour', settledAt: 1 };
    expect(projectLearner(learner({ archivedAt: '2026-09-01T10:00:00.000Z' }), [restoring])).toMatchObject({ mark: undefined, learner: { archivedAt: null } });
  });

  it('ne touche pas un autre élève, même homonyme : l’identifiant décide', () => {
    const intention: LearnerIntention = { learnerId: 'l2', tag: 'learner:l2', operationId: 'op-5', kind: 'learner-archive', reason: 'Départ' };
    expect(projectLearner(learner({ displayName: 'Camille Martin' }), [intention]).mark).toBeUndefined();
  });
});

describe('projection locale des formations', () => {
  it('une formation à ouvrir est une ligne provisoire sans identifiant de l’école, jamais utilisable pour une leçon', () => {
    const intention: LearnerIntention = { ...base, tag: 'training:new', operationId: 'op-6', kind: 'training-create', offeringId: 'o2', startedOn: '2026-11-05' };
    const { trainings, marks, provisional } = projectTrainings([training('t1')], [intention], 'l1');
    expect(trainings.map(item => item.id)).toEqual(['t1', 'pending:op-6']);
    const added = trainings[1]!;
    expect(isProvisional(added.id)).toBe(true);
    expect(added).toMatchObject({ schoolId: '', version: 0, offeringId: 'o2', startedOn: '2026-11-05' });
    expect(provisional.has(added.id)).toBe(true);
    expect(marks.get(added.id)).toBe('opening');
  });

  it('un changement d’état demandé est une marque : le statut officiel ne change pas avant le reçu', () => {
    const intention: LearnerIntention = { ...base, tag: 'training:t1', operationId: 'op-7', kind: 'training-transition', trainingId: 't1', target: 'PAUSED', label: 'Mettre en pause', reason: 'Vacances' };
    const { trainings, marks } = projectTrainings([training('t1')], [intention], 'l1');
    expect(trainings[0]!.status).toBe('ACTIVE');
    expect(marks.get('t1')).toBe('changing');
    const settled = projectTrainings([training('t1')], [{ ...intention, settledAt: 10 }], 'l1');
    expect(settled.trainings[0]!.status).toBe('PAUSED');
    expect(settled.marks.size).toBe(0);
  });

  it('un contrôle de permis demandé marque sa formation sans rien conclure', () => {
    const intention: LearnerIntention = { ...base, tag: 'permit:t1', operationId: 'op-8', kind: 'permit-check', trainingId: 't1',
      draft: { physicalSeen: true, validUntil: '', decision: 'APPROVED', reason: '' } };
    const { trainings, marks } = projectTrainings([training('t1')], [intention], 'l1');
    expect(marks.get('t1')).toBe('checking');
    expect(trainings[0]).toMatchObject({ status: 'ACTIVE', version: 2 });
  });

  it('ne mélange pas les élèves et laisse les lectures de l’école intactes', () => {
    const confirmed = [training('t1'), training('t9', { learnerId: 'l2' })];
    const intention: LearnerIntention = { learnerId: 'l2', tag: 'training:new', operationId: 'op-9', kind: 'training-create', offeringId: 'o1', startedOn: '2026-11-05' };
    expect(projectTrainings(confirmed, [intention], 'l1').trainings.map(item => item.id)).toEqual(['t1']);
    const transition: LearnerIntention = { ...base, tag: 'training:t1', operationId: 'op-10', kind: 'training-transition', trainingId: 't1', target: 'CANCELLED', label: 'Annuler', reason: 'x', settledAt: 5 };
    projectTrainings(confirmed, [transition], 'l1');
    expect(confirmed[0]!.status).toBe('ACTIVE');
  });
});

describe('projection locale des affectations', () => {
  it('une affectation demandée est une ligne « à confirmer » sans id de l’école ni droit', () => {
    const intention: LearnerIntention = { ...base, tag: 'assignment:t1', operationId: 'op-11', kind: 'assignment-create', trainingId: 't1', instructorId: 'm2' };
    const { assignments, marks, provisional } = projectAssignments([assignment('a1')], [intention], 't1', 1000);
    expect(assignments.map(item => item.id)).toEqual(['a1', 'pending:op-11']);
    expect(assignments[1]).toMatchObject({ schoolId: '', version: 0, instructorMembershipId: 'm2', validUntil: null });
    expect(provisional.has('pending:op-11')).toBe(true);
    expect(marks.get('pending:op-11')).toBe('assigning');
  });

  it('un retrait demandé garde l’affectation ouverte, marquée : la révocation n’est pas présentée comme effective', () => {
    const intention: LearnerIntention = { ...base, tag: 'assignment:a1', operationId: 'op-12', kind: 'assignment-end', trainingId: 't1', assignmentId: 'a1' };
    const { assignments, marks } = projectAssignments([assignment('a1')], [intention], 't1', 1000);
    expect(assignments[0]!.validUntil).toBeNull();
    expect(marks.get('a1')).toBe('ending');
    const settled = projectAssignments([assignment('a1')], [{ ...intention, settledAt: Date.parse('2026-11-02T09:00:00Z') }], 't1', 1000);
    expect(settled.assignments[0]!.validUntil).toBe('2026-11-02T09:00:00.000Z');
    expect(settled.marks.size).toBe(0);
  });
});

describe('demandes encore suivies', () => {
  const intentions: LearnerIntention[] = [
    { ...base, tag: 'a', operationId: 'op-a', kind: 'learner-archive', reason: 'x' },
    { learnerId: 'l2', tag: 'b', operationId: 'op-b', kind: 'learner-archive', reason: 'x', settledAt: 100 },
  ];
  it('seules les demandes suivies, ou confirmées mais pas encore relues, restent visibles', () => {
    expect(visibleIntentions(intentions, new Set(['op-a']), 50).map(item => item.operationId)).toEqual(['op-a', 'op-b']);
    expect(visibleIntentions(intentions, new Set(['op-a']), 100).map(item => item.operationId)).toEqual(['op-a']);
    // Refusée ou abandonnée : plus suivie, elle ne laisse rien.
    expect(visibleIntentions(intentions, new Set(), 100)).toEqual([]);
  });
  it('un dossier avec une demande suivie fait attendre la suivante, pas un autre dossier', () => {
    expect(followedFor(intentions, 'l1')).toBe(true);
    expect(followedFor(intentions, 'l2')).toBe(false);
    expect(followedFor(intentions, 'l3')).toBe(false);
  });
});
