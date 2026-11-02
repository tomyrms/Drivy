import { describe, expect, test } from 'vitest';
import { randomUUID } from 'node:crypto';
import {
  acceptingRequestId, lateLabel, lessonChangeInboxSchema, lessonChangeStateSchema, pendingRequest, refuseBody, refuseProblems, requestShort, requestTitle,
  type LessonChangeRequest,
} from '../client/lesson-change-model.js';

const request = (patch: Partial<LessonChangeRequest> = {}): LessonChangeRequest => ({
  id: randomUUID(), lessonId: randomUUID(), kind: 'RESCHEDULE', status: 'PENDING', note: 'Plutôt jeudi', mine: false, late: false, deadlineAt: null, cancellationHours: 24,
  policyVersionId: randomUUID(), resolvedAt: null, resolutionNote: null, version: 1, createdAt: '2030-03-01T08:00:00.000Z', ...patch,
});

describe('Demandes de l’élève : lecture du contrat de l’API', () => {
  test('l’état d’une leçon et la boîte du personnel se lisent tels que le serveur les rend', () => {
    const one = request();
    const state = { lessonId: one.lessonId, requests: [one], conditions: { policyVersionId: null, policyVersion: null, cancellationPolicyText: '', cancellationHours: null, lateAction: null,
      deadlineAt: null, late: null, canRequest: false, blockedReason: 'REQUEST_PENDING' } };
    expect(lessonChangeStateSchema.parse(state).requests).toHaveLength(1);
    expect(() => lessonChangeStateSchema.parse({ ...state, requests: [{ ...one, status: 'DONE' }] })).toThrow();
    const inbox = { items: [{ request: one, lesson: { id: one.lessonId, plannedStart: '2030-03-04T09:00:00.000Z', plannedEnd: '2030-03-04T09:50:00.000Z', timeZone: 'Europe/Zurich',
      version: 2, instructorMembershipId: randomUUID(), learnerId: randomUUID(), learnerDisplayName: 'Alice' } }] };
    expect(lessonChangeInboxSchema.parse(inbox).items[0]?.lesson.learnerDisplayName).toBe('Alice');
  });
});

describe('Demandes de l’élève : règles d’affichage et de réponse', () => {
  test('une seule demande en attente, les autres sont de l’historique', () => {
    const pending = request(), refused = request({ status: 'REFUSED' });
    expect(pendingRequest({ requests: [refused, pending] })?.id).toBe(pending.id);
    expect(pendingRequest({ requests: [refused] })).toBeNull();
    expect(pendingRequest(null)).toBeNull();
  });

  test('les libellés disent ce qui est demandé, jamais ce qui est fait', () => {
    expect(requestTitle('CANCEL')).toBe('L’élève demande l’annulation');
    expect(requestTitle('RESCHEDULE')).toBe('L’élève demande un déplacement');
    expect(requestShort('CANCEL')).toBe('Annulation demandée');
    expect(requestShort('RESCHEDULE')).not.toMatch(/déplacée|annulée/);
  });

  test('« Hors délai » seulement quand l’école a fixé un délai dépassé', () => {
    expect(lateLabel({ late: true })).toBe('Hors délai');
    expect(lateLabel({ late: false })).toBeNull();
    expect(lateLabel({ late: null })).toBeNull();
  });

  test('l’identifiant de la demande n’est joint qu’à l’action qu’elle demande', () => {
    const move = request({ kind: 'RESCHEDULE' }), cancel = request({ kind: 'CANCEL' });
    expect(acceptingRequestId(move, 'MOVE')).toBe(move.id);
    expect(acceptingRequestId(move, 'CANCEL')).toBeUndefined();
    expect(acceptingRequestId(cancel, 'CANCEL')).toBe(cancel.id);
    expect(acceptingRequestId(cancel, 'MOVE')).toBeUndefined();
    expect(acceptingRequestId(request({ status: 'REFUSED' }), 'MOVE')).toBeUndefined();
    expect(acceptingRequestId(null, 'CANCEL')).toBeUndefined();
  });

  test('le motif de refus est facultatif, limité, et vide il part en null', () => {
    expect(refuseBody({ note: '  ' })).toEqual({ note: null });
    expect(refuseBody({ note: ' Créneau déjà pris ' })).toEqual({ note: 'Créneau déjà pris' });
    expect(refuseProblems({ note: 'x'.repeat(1001) }).note).toMatch(/1000/);
    expect(refuseBody({ note: 'x'.repeat(1001) })).toBeNull();
  });
});
