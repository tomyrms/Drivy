import { useMemo, useRef, useState } from 'react';
import { z } from 'zod';
import { createCommand, type SchoolCommand } from '../../command-core';
import { refusalOutcome, type LaneResult } from '../../command-lane';
import { useCommandSnapshot } from '../../command-store';
import { attendanceBody, attendanceCell, courseErrorMessage, courseRosterSchema, courseSheetSchema, type AttendanceStatus, type CourseSeries, type CourseSheetRow } from '../../console/course-model';
import { useCommandLane, useConsole, useLoad, type Outcome } from '../../console/context';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { participantScope, projectParticipants, resumable, visibleIntentions, type Mark, type OverlaidRow, type ParticipantsIntention, type SheetOverlay } from './participants-projection';
const sheetEnvelope = z.object({ data: courseSheetSchema });
/** Codes after which what is on screen is stale: the row is read again before anything else is attempted. */
const rereadCodes = ['VERSION_CONFLICT', 'NOT_FOUND', 'COURSE_PAYMENT_VOIDED', 'COURSE_COMPLETION_REVOKED', 'COURSE_ALREADY_COMPLETED', 'COURSE_ENROLLMENT_CLOSED'];
const PARTICIPANT_BLOCKED = 'Une demande sur ce participant attend sa confirmation ; ses autres gestes suivent dans l’ordre.';
const ROSTER_BLOCKED = 'Une demande sur la planification attend sa confirmation ; l’inscription suivra.';

/** A refusal as it is shown: the school's own wording for a course fact, then the promise that nothing typed is lost. */
function refusalWith(result: Extract<LaneResult, { status: 'rejected' }>): NonNullable<Outcome> {
  const base = refusalOutcome(result);
  const message = courseErrorMessage(result.code);
  return message ? { ...base, message: `${message} Votre saisie est conservée.` } : base;
}

/** Feedback belongs to a task: a payment confirmed on a person never reads as news in the call or the validation of that same person. */
export const feedbackKey = (task: 'roster' | 'call' | 'payments' | 'completion', id: string) => `${task}:${id}`;

export interface RowFeedback { text: string; tone: 'pending' | 'error' | 'success' }
/** A gesture is either kept by the store (the form is released), refused on the spot (the form stays) or not ready. */
export type KeepResult = 'kept' | 'refused' | 'invalid';
/** A request the school refused after its form had been released: what was typed comes back on demand. */
export interface ParticipantsRefusal { readonly intention: ParticipantsIntention; readonly outcome: NonNullable<Outcome> }

const EMPTY_OVERLAY: SheetOverlay = new Map();
const EMPTY_MARKS: ReadonlyMap<string, readonly Mark[]> = new Map();
const EMPTY_ATTENDANCE: ReadonlyMap<string, AttendanceStatus> = new Map();
const EMPTY_PAYMENTS: ReadonlyMap<string, { amountCents: number; note: string | null }> = new Map();
const EMPTY_FOLLOWED: ReadonlySet<string> = new Set();

/**
 * The people of one published course: enrolments, waiting list, and the sheet (attendance, settlements, validation).
 * Every write goes through the shared command engine with the version that was read, one gesture at a time per participant:
 * two participants answer side by side, the same one stays ordered. The form is released as soon as the store keeps the
 * request, the row shows « À confirmer », and nothing is confirmed before the school's answer or its receipt.
 */
export function useCourseParticipants(series: CourseSeries) {
  const { schoolId, me, membership, drafts } = useConsole();
  const scope = `${schoolId}/${me.personId}/${membership.membershipId}/${membership.accessEpoch}/${series.id}`;
  const { entries, revision } = useCommandSnapshot();
  const [refusals, setRefusals] = useState<ParticipantsRefusal[]>([]);
  const [overlay, setOverlay] = useState<{ scope: string; rows: Map<string, OverlaidRow> }>({ scope, rows: new Map() });
  const writeGeneration = useRef(0);
  // Memory only, in the console's drafts: renewed with the account, school, membership and access epoch; never written to browser storage.
  const draftsKey = `course-participants/${series.id}/intentions`;
  const stored = useRef<ParticipantsIntention[]>((drafts?.get(draftsKey) as ParticipantsIntention[] | undefined) ?? []);
  const [intentionList, setIntentionList] = useState<ParticipantsIntention[]>(stored.current);
  const change = (next: (list: ParticipantsIntention[]) => ParticipantsIntention[]) => {
    stored.current = next(stored.current);
    drafts?.set(draftsKey, stored.current);
    setIntentionList(stored.current);
  };
  const lane = useCommandLane(intent => {
    change(list => list.map(item => item.operationId === intent.operationId && item.settledAt === undefined ? { ...item, settledAt: Date.now() } : item));
    // A confirmation is news for a few seconds, not a permanent line under the person.
    window.setTimeout(() => lane.clearOutcome(intent.tag), 4000);
  });

  const sheetRead = useLoad(async () => {
    const generation = writeGeneration.current;
    const sheet = await readSchool(schoolId, `course-series/${series.id}/sheet`, courseSheetSchema);
    if (sheet.series.id !== series.id || sheet.series.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return { sheet, generation };
  }, [schoolId, series.id, series.version, revision], `${schoolId}/${series.id}`, `course-sheet-view/${series.id}`);
  const rosterRead = useLoad(async () => {
    if (!series.canManage) return { items: [], waitlist: [], restricted: true };
    return { ...(await readSchool(schoolId, `course-series/${series.id}/enrollments`, courseRosterSchema)), restricted: false };
  }, [schoolId, series.id, series.version, series.canManage, revision], `${schoolId}/${series.id}`, `course-roster/${series.id}`);

  // Requests the store follows for this school, and the intentions that still show next to what the school lists.
  const followedOperations = useMemo(() => new Set([...entries.values()].filter(entry => entry.meta.schoolId === schoolId).map(entry => entry.meta.operationId)), [entries, schoolId]);
  const intentions = useMemo(() => visibleIntentions(intentionList, followedOperations, sheetRead.readAt), [intentionList, followedOperations, sheetRead.readAt]);
  const overlayRows = overlay.scope === scope ? overlay.rows : EMPTY_OVERLAY;
  const projected = useMemo(() => sheetRead.data ? projectParticipants(sheetRead.data, overlayRows, intentions) : undefined,
    [sheetRead.data, overlayRows, intentions]);
  // Access failures clear useLoad's data. A previously confirmed local response must not keep exposing participants without rights.
  const sheet = projected?.sheet;
  const sorted = useMemo(() => [...(sheet?.series.occurrences ?? [])].sort((a, b) => a.position - b.position), [sheet]);

  // A refusal with something typed comes back as a notice; the others stay on the line they concern.
  const typedTags = useMemo(() => new Set(refusals.map(item => item.intention.tag)), [refusals]);
  const feedback = useMemo(() => {
    const rows: Record<string, RowFeedback> = {};
    for (const [tag, outcome] of lane.outcomes) {
      if (typedTags.has(tag) || outcome.tone === 'warning') continue;
      rows[tag] = { text: courseErrorMessage(outcome.code ?? '') ?? outcome.message, tone: outcome.tone === 'success' ? 'success' : 'error' };
    }
    return rows;
  }, [lane.outcomes, typedTags]);
  const needsLogin = useMemo(() => [...lane.outcomes.values()].find(outcome => outcome.needsLogin) ?? null, [lane.outcomes]);

  const participantOf = (enrollmentId: string) => participantScope(series.id, enrollmentId);
  const blockedFor = (enrollmentId: string) =>
    lane.blocked({ kind: 'recordCourseAttendance', scope: participantOf(enrollmentId) }) ? PARTICIPANT_BLOCKED : null;
  const planningBlocked = lane.blocked({ kind: 'staffEnrollCourse' }) ? ROSTER_BLOCKED : null;

  /**
   * Hands one command to the store. Refused on the spot: the form stays as it is. Kept: the form is released at once and the
   * line says « À confirmer »; a refusal comes back later through the notice, never as a confirmation.
   */
  function keep(command: SchoolCommand, success: string, tag: string, intention: ParticipantsIntention, kind: 'sheet' | 'roster'): KeepResult {
    lane.clearOutcome();
    const started = lane.run(command, success, tag);
    if (!started.admitted) { void started.result; return 'refused'; }
    change(list => [...list.filter(item => item.settledAt === undefined ? followedOperations.has(item.operationId) : (sheetRead.readAt ?? 0) < item.settledAt), intention]);
    void started.result.then(result => {
      if (result.status === 'rejected') {
        change(list => list.filter(item => item.operationId !== intention.operationId));
        if (resumable(intention)) setRefusals(list => [...list, { intention, outcome: refusalWith(result) }]);
        if (rereadCodes.includes(result.code)) { sheetRead.reload(); rosterRead.reload(); }
        return;
      }
      if (result.status !== 'confirmed') return;
      if (kind === 'roster') { rosterRead.reload(); return; }
      const parsed = sheetEnvelope.safeParse(result.body);
      const written = parsed.success ? parsed.data.data : null;
      if (!written || written.series.id !== series.id || written.series.schoolId !== schoolId) { sheetRead.reload(); return; }
      const order = ++writeGeneration.current;
      setOverlay(previous => {
        const rows = new Map(previous.scope === scope ? previous.rows : []);
        const row = written.rows.find(item => item.enrollmentId === intention.enrollmentId);
        if (row) rows.set(row.enrollmentId, { row, order });
        return { scope, rows };
      });
    });
    return 'kept';
  }

  const mark = (row: CourseSheetRow, occurrenceId: string, status: AttendanceStatus): KeepResult => {
    const cell = attendanceCell(row, occurrenceId);
    const body = attendanceBody(cell, status);
    if (!body) return 'invalid';
    const path = `course-enrollments/${row.enrollmentId}/attendance/${occurrenceId}`;
    const command = createCommand({ schoolId, kind: 'recordCourseAttendance', path, body, resourceVersion: cell.version ?? 0, resourceId: row.enrollmentId,
      scope: participantOf(row.enrollmentId) });
    const tag = feedbackKey('call', row.enrollmentId);
    return keep(command, 'Présence enregistrée.', tag,
      { kind: 'attendance', tag, operationId: command.operationId, enrollmentId: row.enrollmentId, occurrenceId, status }, 'sheet');
  };

  const enroll = (learnerId: string): KeepResult => {
    const path = `course-series/${series.id}/enrollments`;
    const body = { learnerId };
    const command = createCommand({ schoolId, kind: 'staffEnrollCourse', path, body, resourceVersion: 0 });
    const tag = feedbackKey('roster', `enroll:${learnerId}`);
    return keep(command, 'Élève inscrit.', tag,
      { kind: 'enrollment-create', tag, operationId: command.operationId, enrollmentId: learnerId, learnerId }, 'roster');
  };

  const cancelEnrollment = (enrollment: { id: string; version: number }, reason: string): KeepResult => {
    const path = `course-enrollments/${enrollment.id}/staff-cancel`;
    const body = { reason };
    const command = createCommand({ schoolId, kind: 'staffCancelCourseEnrollment', path, body, resourceVersion: enrollment.version, ifMatch: enrollment.version,
      resourceId: enrollment.id });
    const tag = feedbackKey('roster', enrollment.id);
    return keep(command, 'Inscription annulée.', tag,
      { kind: 'enrollment-cancel', tag, operationId: command.operationId, enrollmentId: enrollment.id, reason }, 'roster');
  };

  const pay = (row: CourseSheetRow, amountCents: number, note: string | null): KeepResult => {
    // Whole cents only: an amount that is not a safe integer is never turned into a settlement.
    if (!Number.isSafeInteger(amountCents) || amountCents < 0) return 'invalid';
    const path = `course-enrollments/${row.enrollmentId}/payments`;
    const body = { amountCents, note };
    const command = createCommand({ schoolId, kind: 'recordCoursePayment', path, body, resourceVersion: 0,
      scope: participantOf(row.enrollmentId) });
    const tag = feedbackKey('payments', row.enrollmentId);
    return keep(command, 'Règlement enregistré.', tag,
      { kind: 'payment', tag, operationId: command.operationId, enrollmentId: row.enrollmentId, amountCents, note }, 'sheet');
  };

  const voidPayment = (row: CourseSheetRow, paymentId: string, reason: string): KeepResult => {
    const path = `course-payments/${paymentId}/void`;
    const body = { reason };
    const command = createCommand({ schoolId, kind: 'voidCoursePayment', path, body, resourceVersion: 1, resourceId: paymentId,
      scope: participantOf(row.enrollmentId) });
    const tag = feedbackKey('payments', row.enrollmentId);
    return keep(command, 'Saisie annulée.', tag,
      { kind: 'payment-void', tag, operationId: command.operationId, enrollmentId: row.enrollmentId, paymentId, reason }, 'sheet');
  };

  const validate = (row: CourseSheetRow): KeepResult => {
    const path = `course-enrollments/${row.enrollmentId}/validate`;
    const body = { note: null };
    const command = createCommand({ schoolId, kind: 'validateCourse', path, body, resourceVersion: 0,
      scope: participantOf(row.enrollmentId) });
    const tag = feedbackKey('completion', row.enrollmentId);
    return keep(command, 'Cours validé.', tag,
      { kind: 'completion', tag, operationId: command.operationId, enrollmentId: row.enrollmentId }, 'sheet');
  };

  const revoke = (row: CourseSheetRow, completionId: string, reason: string): KeepResult => {
    const path = `course-completions/${completionId}/revoke`;
    const body = { reason };
    const command = createCommand({ schoolId, kind: 'revokeCourseCompletion', path, body, resourceVersion: 1, resourceId: completionId,
      scope: participantOf(row.enrollmentId) });
    const tag = feedbackKey('completion', row.enrollmentId);
    return keep(command, 'Validation retirée.', tag,
      { kind: 'completion-revoke', tag, operationId: command.operationId, enrollmentId: row.enrollmentId, completionId, reason }, 'sheet');
  };

  /** Takes a refused request up again: the typed content comes back in its dialog, nothing else changes. */
  const resume = (refusal: ParticipantsRefusal) => {
    setRefusals(list => list.filter(item => item !== refusal));
    lane.clearOutcome();
  };
  const dismiss = (refusal: ParticipantsRefusal) => setRefusals(list => list.filter(item => item !== refusal));

  return {
    sheetRead, rosterRead, sheet, occurrences: sorted,
    marks: projected?.marks ?? EMPTY_MARKS, attendanceMarks: projected?.attendance ?? EMPTY_ATTENDANCE,
    paymentMarks: projected?.payments ?? EMPTY_PAYMENTS,
    followedParticipants: projected?.followed ?? EMPTY_FOLLOWED,
    feedback, refusals, needsLogin, blockedFor, planningBlocked, resume, dismiss,
    mark, enroll, cancelEnrollment, pay, voidPayment, validate, revoke,
    reread: () => { sheetRead.reload(); rosterRead.reload(); },
  };
}
export type CourseParticipants = ReturnType<typeof useCourseParticipants>;
