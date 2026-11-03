import { describe, expect, it } from 'vitest';
import { activeCompletion, attendanceCell, type CourseSheet, type CourseSheetRow } from '../../console/course-model';
import { groupSettledCents, settledCents } from './participants-model';
import {
  cellKey, markLabels, mergeSheet, participantScope, projectParticipants, resumeOf, visibleIntentions, type ParticipantsIntention, type SheetRead,
} from './participants-projection';

/** Synthetic people only: two enrolments and one course, nothing taken from a real school. */
const series = { id: 's-1', schoolId: 'school-1', version: 1, title: 'Cours de secourisme', occurrences: [] } as unknown as CourseSheet['series'];
const row = (id: string, patch: Partial<CourseSheetRow> = {}): CourseSheetRow => ({
  enrollmentId: id, learnerId: `learner-${id}`, learnerDisplayName: `Élève ${id.toUpperCase()}`, status: 'ACTIVE', cancelledAt: null,
  attendance: [], requirements: { required: 2, present: 2, missing: 0 }, payments: [], completion: null, ...patch,
});
const cell = (occurrenceId: string, status: 'PRESENT' | 'ABSENT' | 'EXCUSED' | null) =>
  ({ occurrenceId, status, version: status ? 1 : null, recordedAt: status ? '2026-11-02T19:00:00Z' : null });
const payment = (id: string, amountCents: number) => ({ id, amountCents, recordedAt: '2026-11-02T18:00:00Z', note: null, voidedAt: null, voidReason: null });
const sheet = (rows: CourseSheetRow[]): CourseSheet => ({ series, rights: { canTakeAttendance: true, canRecordPayment: true, canValidate: true }, rows });
const read = (rows: CourseSheetRow[], generation = 0): SheetRead => ({ sheet: sheet(rows), generation });

const attendanceAsked = (enrollmentId: string, status: 'PRESENT' | 'ABSENT' = 'ABSENT'): ParticipantsIntention => ({
  kind: 'attendance', tag: `call:${enrollmentId}`, operationId: `op-attendance-${enrollmentId}`, enrollmentId, occurrenceId: 'o-1', status,
});
const paymentAsked = (enrollmentId: string, amountCents = 12_050): ParticipantsIntention => ({
  kind: 'payment', tag: `payments:${enrollmentId}`, operationId: `op-payment-${enrollmentId}`, enrollmentId, amountCents, note: 'Espèces',
});

describe('Projection des participants : un fait demandé n’est jamais un fait confirmé', () => {
  it('une présence demandée marque la ligne et laisse la valeur confirmée lisible', () => {
    const confirmed = read([row('a', { attendance: [cell('o-1', 'PRESENT')] })]);
    const projected = projectParticipants(confirmed, new Map(), [attendanceAsked('a')]);
    expect(projected.marks.get('a')).toEqual(['attendance']);
    expect(projected.attendance.get(cellKey('a', 'o-1'))).toBe('ABSENT');
    // La feuille garde ce que l'école a confirmé : aucun statut n'est inventé ni remplacé par la demande.
    expect(attendanceCell(projected.sheet.rows[0]!, 'o-1').status).toBe('PRESENT');
    expect(projected.followed.has('a')).toBe(true);
    expect(markLabels.attendance).toBe('Présence à confirmer');
  });

  it('un règlement demandé montre le montant voulu et n’entre jamais dans un total confirmé', () => {
    const confirmed = read([row('a', { payments: [payment('p-1', 2_000)] }), row('b')]);
    const projected = projectParticipants(confirmed, new Map(), [paymentAsked('a')]);
    expect(projected.payments.get('a')).toEqual({ amountCents: 12_050, note: 'Espèces' });
    expect(projected.marks.get('a')).toEqual(['payment']);
    // Le total compté ne retient que les règlements confirmés, entiers en centimes.
    expect(settledCents(projected.sheet.rows[0]!)).toBe(2_000);
    expect(groupSettledCents(projected.sheet.rows)).toBe(2_000);
    expect(Number.isInteger(projected.payments.get('a')!.amountCents)).toBe(true);
  });

  it('une validation demandée est une marque, jamais une attestation ; un retrait demandé ne retire rien', () => {
    const validated = row('a', { completion: { id: 'c-1', validatedAt: '2026-11-02T19:00:00Z', seriesId: 's-1', revokedAt: null } });
    const asking = projectParticipants(read([row('b')]), new Map(), [{ kind: 'completion', tag: 'completion:b', operationId: 'op-2', enrollmentId: 'b' }]);
    expect(asking.marks.get('b')).toEqual(['validating']);
    expect(activeCompletion(asking.sheet.rows[0]!)).toBeNull();
    const revoking = projectParticipants(read([validated]), new Map(),
      [{ kind: 'completion-revoke', tag: 'completion:a', operationId: 'op-3', enrollmentId: 'a', completionId: 'c-1', reason: 'Erreur' }]);
    expect(revoking.marks.get('a')).toEqual(['revoking']);
    // La validation confirmée reste lisible tant que l'école n'a pas répondu.
    expect(activeCompletion(revoking.sheet.rows[0]!)?.id).toBe('c-1');
  });

  it('un règlement annulé demandé et une annulation d’inscription demandée marquent sans changer le fait', () => {
    const confirmed = read([row('a', { payments: [payment('p-1', 2_000)] })]);
    const voiding = projectParticipants(confirmed, new Map(),
      [{ kind: 'payment-void', tag: 'payments:a', operationId: 'op-4', enrollmentId: 'a', paymentId: 'p-1', reason: 'Erreur' }]);
    expect(voiding.marks.get('a')).toEqual(['voiding']);
    expect(groupSettledCents(voiding.sheet.rows)).toBe(2_000);
    expect(markLabels.voiding).toBe('Annulation à confirmer');
    const cancelled = projectParticipants(confirmed, new Map(),
      [{ kind: 'enrollment-cancel', tag: 'roster:a', operationId: 'op-5', enrollmentId: 'a', reason: 'Départ' }]);
    expect(cancelled.marks.get('a')).toEqual(['cancelling']);
    // L'inscription reste active tant que l'école n'a pas répondu.
    expect(cancelled.sheet.rows[0]!.status).toBe('ACTIVE');
    expect(cancelled.followed.has('a')).toBe(true);
  });

  it('une réponse complète tardive n’efface ni la ligne ni la marque d’un autre participant', () => {
    // B a répondu en premier (ordre 1) ; A répond ensuite (ordre 2) et porte une copie plus ancienne de B.
    const staleB = row('b');
    const paidB = row('b', { payments: [payment('p-9', 5_000)] });
    const calledA = row('a', { attendance: [cell('o-1', 'PRESENT')] });
    const overlay = new Map([['b', { row: paidB, order: 1 }], ['a', { row: calledA, order: 2 }]]);
    const projected = projectParticipants(read([row('a'), staleB]), overlay, [paymentAsked('b')]);
    const rows = new Map(projected.sheet.rows.map(item => [item.enrollmentId, item]));
    expect(groupSettledCents([rows.get('b')!])).toBe(5_000);
    expect(attendanceCell(rows.get('a')!, 'o-1').status).toBe('PRESENT');
    expect(staleB.payments).toEqual([]);
    expect(projected.marks.get('b')).toEqual(['payment']);
    expect(projected.followed).toEqual(new Set(['b']));
  });

  it('une lecture commencée après la réponse remplace la ligne ; une lecture plus ancienne ne la remplace pas', () => {
    const answered = row('a', { attendance: [cell('o-1', 'PRESENT')] });
    const overlay = new Map([['a', { row: answered, order: 3 }]]);
    const older = row('a', { attendance: [cell('o-1', 'ABSENT')] });
    expect(attendanceCell(mergeSheet(read([older], 2), overlay).rows[0]!, 'o-1').status).toBe('PRESENT');
    expect(attendanceCell(mergeSheet(read([older], 3), overlay).rows[0]!, 'o-1').status).toBe('ABSENT');
    // Une ligne absente de la lecture n'est pas ressuscitée par une réponse plus ancienne qu'elle.
    expect(mergeSheet(read([], 3), overlay).rows).toEqual([]);
    expect(mergeSheet(read([], 2), overlay).rows.map(item => item.enrollmentId)).toEqual(['a']);
  });
});

describe('Refus et reprise', () => {
  it('un refus retire l’intention : plus de marque, les autres lignes gardent leurs faits confirmés', () => {
    const confirmed = read([row('a', { payments: [payment('p-1', 2_000)] }), row('b')]);
    const refused = projectParticipants(confirmed, new Map(), []);
    expect(refused.marks.size).toBe(0);
    expect(refused.followed.size).toBe(0);
    expect(groupSettledCents(refused.sheet.rows)).toBe(2_000);
    expect(refused.sheet.rows.map(item => item.enrollmentId)).toEqual(['a', 'b']);
  });

  it('une intention suivie reste visible ; une intention confirmée s’efface devant une lecture plus récente', () => {
    const asked: ParticipantsIntention = attendanceAsked('a');
    expect(visibleIntentions([asked], new Set(['op-attendance-a']), undefined)).toEqual([asked]);
    expect(visibleIntentions([asked], new Set(), undefined)).toEqual([]);
    const settled: ParticipantsIntention = { ...asked, settledAt: 1_000 };
    expect(visibleIntentions([settled], new Set(), 500)).toEqual([settled]);
    expect(visibleIntentions([settled], new Set(), 1_000)).toEqual([]);
    expect(projectParticipants(read([row('a')]), new Map(), [settled]).marks.size).toBe(0);
  });

  it('la saisie refusée est rendue : montant et motif, jamais une valeur inventée', () => {
    const paid = paymentAsked('a', 7_300);
    expect(resumeOf(paid)).toEqual({ kind: 'payment', enrollmentId: 'a', amountCents: 7_300, note: 'Espèces' });
    expect(resumeOf({ kind: 'payment-void', tag: 'payments:a', operationId: 'op', enrollmentId: 'a', paymentId: 'p-1', reason: 'Erreur de saisie' }))
      .toEqual({ kind: 'void', enrollmentId: 'a', paymentId: 'p-1', reason: 'Erreur de saisie' });
    expect(resumeOf({ kind: 'completion-revoke', tag: 'completion:a', operationId: 'op', enrollmentId: 'a', completionId: 'c-1', reason: 'Motif' }))
      .toEqual({ kind: 'revoke', enrollmentId: 'a', completionId: 'c-1', reason: 'Motif' });
    expect(resumeOf({ kind: 'enrollment-cancel', tag: 'roster:a', operationId: 'op', enrollmentId: 'a', reason: 'Départ' }))
      .toEqual({ kind: 'cancel', enrollmentId: 'a', reason: 'Départ' });
    expect(resumeOf({ kind: 'enrollment-create', tag: 'roster:enroll:l', operationId: 'op', enrollmentId: 'l', learnerId: 'l' }))
      .toEqual({ kind: 'enroll', learnerId: 'l' });
    // Une présence ou une validation n'a rien de saisi : pas de notice de reprise pour elles.
    expect(resumeOf(attendanceAsked('a'))).toBeNull();
    expect(resumeOf({ kind: 'completion', tag: 'completion:a', operationId: 'op', enrollmentId: 'a' })).toBeNull();
  });

  it('l’agrégat d’un fait de cours nomme la série et le participant', () => {
    expect(participantScope('s-1', 'e-a')).toBe('s-1:e-a');
    expect(participantScope('s-1', 'e-a')).not.toBe(participantScope('s-1', 'e-b'));
    expect(participantScope('s-2', 'e-a')).not.toBe(participantScope('s-1', 'e-a'));
  });
});
