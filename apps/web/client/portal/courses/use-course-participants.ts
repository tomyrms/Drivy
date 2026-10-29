import { useEffect, useMemo, useRef, useState } from 'react';
import { z } from 'zod';
import { createCommand, type SchoolCommand } from '../../command-core';
import { attendanceBody, attendanceCell, courseErrorMessage, courseRosterSchema, courseSheetSchema, type AttendanceStatus, type CourseSeries, type CourseSheet, type CourseSheetRow } from '../../console/course-model';
import { useCommandRunner, useConsole, useLoad } from '../../console/context';
import { RequestFailure } from '../../protocol';
import { readSchool } from '../../school-api';
import { intentKey, readIsCurrent } from './participants-model';

const sheetEnvelope = z.object({ data: courseSheetSchema });
/** Codes after which what is on screen is stale: the row is read again before anything else is attempted. */
const rereadCodes = ['VERSION_CONFLICT', 'NOT_FOUND', 'COURSE_PAYMENT_VOIDED', 'COURSE_COMPLETION_REVOKED', 'COURSE_ALREADY_COMPLETED', 'COURSE_ENROLLMENT_CLOSED'];

export interface RowFeedback { text: string; tone: 'pending' | 'error' | 'success' }
export type SendResult = { status: 'confirmed' } | { status: 'pending' } | { status: 'rejected'; message: string };

/**
 * The people of one published course: enrolments, waiting list, and the sheet (attendance, settlements, validation).
 * Every write goes through the shared command engine with the version that was read; the sheet a write returns is shown
 * until a read that started after it arrives, so a slow older read never brings back an earlier state.
 */
export function useCourseParticipants(series: CourseSeries) {
  const { schoolId, me, membership } = useConsole();
  const scope = `${schoolId}/${me.personId}/${membership.membershipId}/${membership.accessEpoch}/${series.id}`;
  const runner = useCommandRunner();
  const writeGeneration = useRef(0);
  const attempts = useRef(new Map<string, string>());
  const inFlight = useRef(false);
  const sheetRead = useLoad(async () => {
    const generation = writeGeneration.current;
    const sheet = await readSchool(schoolId, `course-series/${series.id}/sheet`, courseSheetSchema);
    if (sheet.series.id !== series.id || sheet.series.schoolId !== schoolId) throw new RequestFailure('INVALID_RESPONSE');
    return { sheet, generation };
  }, [schoolId, series.id, series.version], undefined, `course-sheet-view/${series.id}`);
  const rosterRead = useLoad(async () => {
    if (!series.canManage) return { items: [], waitlist: [], restricted: true };
    return { ...(await readSchool(schoolId, `course-series/${series.id}/enrollments`, courseRosterSchema)), restricted: false };
  }, [schoolId, series.id, series.version, series.canManage], undefined, `course-roster/${series.id}`);
  const [fresh, setFresh] = useState<{ scope: string; sheet: CourseSheet } | null>(null);
  useEffect(() => { if (sheetRead.data && readIsCurrent(sheetRead.data.generation, writeGeneration.current)) setFresh(null); }, [sheetRead.data]);
  const sheet: CourseSheet | undefined = fresh?.scope === scope ? fresh.sheet : sheetRead.data?.sheet;
  const [feedback, setFeedback] = useState<Record<string, RowFeedback>>({});
  const timers = useRef(new Map<string, number>());
  useEffect(() => () => { for (const timer of timers.current.values()) window.clearTimeout(timer); }, []);
  const note = (rowId: string, value: RowFeedback | null) => {
    window.clearTimeout(timers.current.get(rowId));
    setFeedback(previous => { const next = { ...previous }; if (value) next[rowId] = value; else delete next[rowId]; return next; });
    if (value?.tone === 'success') timers.current.set(rowId, window.setTimeout(() => note(rowId, null), 4000));
  };
  const locked = runner.busy || Boolean(runner.pending);
  const sorted = useMemo(() => [...(sheet?.series.occurrences ?? [])].sort((a, b) => a.position - b.position), [sheet]);

  /** One command. The result says what happened; the row it concerns shows the same thing, in words. */
  async function send(kind: SchoolCommand['kind'], path: string, body: Record<string, unknown>, resourceId: string | undefined, resourceVersion: number, success: string, rowId: string,
    options: { ifMatch?: number; returnsSheet?: boolean; roster?: boolean } = {}): Promise<SendResult> {
    if (locked || inFlight.current) return { status: 'pending' };
    inFlight.current = true;
    try {
      note(rowId, { text: 'Enregistrement…', tone: 'pending' });
      const key = intentKey(scope, kind, path, body);
      const previous = attempts.current.get(key);
      const command = createCommand({ schoolId, kind, path, body, resourceVersion, ...(resourceId ? { resourceId } : {}), ...(options.ifMatch !== undefined ? { ifMatch: options.ifMatch } : {}), ...(previous ? { operationId: previous } : {}) });
      attempts.current.set(key, command.operationId);
      const result = await runner.run(command, success);
      if (result.status === 'pending') { note(rowId, { text: 'Résultat en cours de vérification', tone: 'pending' }); return { status: 'pending' }; }
      attempts.current.delete(key);
      if (result.status === 'rejected') {
        const message = courseErrorMessage(result.code) ?? result.message;
        if (!result.needsLogin) runner.clearOutcome();
        note(rowId, { text: message, tone: 'error' });
        if (rereadCodes.includes(result.code)) { sheetRead.reload(); rosterRead.reload(); }
        return { status: 'rejected', message };
      }
      runner.clearOutcome();
      note(rowId, { text: success, tone: 'success' });
      if (options.returnsSheet !== false) {
        const parsed = sheetEnvelope.safeParse(result.body);
        writeGeneration.current += 1;
        if (parsed.success) setFresh({ scope, sheet: parsed.data.data }); else sheetRead.reload();
      }
      if (options.roster) rosterRead.reload();
      return { status: 'confirmed' };
    } finally { inFlight.current = false; }
  }

  const mark = (row: CourseSheetRow, occurrenceId: string, status: AttendanceStatus) => {
    const cell = attendanceCell(row, occurrenceId);
    const body = attendanceBody(cell, status);
    if (!body) return Promise.resolve<SendResult>({ status: 'confirmed' });
    return send('recordCourseAttendance', `course-enrollments/${row.enrollmentId}/attendance/${occurrenceId}`, body, row.enrollmentId, cell.version ?? 0, 'Présence enregistrée.', row.enrollmentId);
  };
  const enroll = (learnerId: string) => send('staffEnrollCourse', `course-series/${series.id}/enrollments`, { learnerId }, undefined, 0, 'Élève inscrit.', `enroll:${learnerId}`, { returnsSheet: false, roster: true });
  const cancelEnrollment = (enrollment: { id: string; version: number }, reason: string) =>
    send('staffCancelCourseEnrollment', `course-enrollments/${enrollment.id}/staff-cancel`, { reason }, enrollment.id, enrollment.version, 'Inscription annulée.', enrollment.id, { ifMatch: enrollment.version, returnsSheet: false, roster: true });
  const pay = (row: CourseSheetRow, amountCents: number, note: string | null) =>
    send('recordCoursePayment', `course-enrollments/${row.enrollmentId}/payments`, { amountCents, note }, undefined, 0, 'Règlement enregistré.', row.enrollmentId);
  const voidPayment = (row: CourseSheetRow, paymentId: string, reason: string) =>
    send('voidCoursePayment', `course-payments/${paymentId}/void`, { reason }, paymentId, 1, 'Saisie annulée.', row.enrollmentId);
  const validate = (row: CourseSheetRow) =>
    send('validateCourse', `course-enrollments/${row.enrollmentId}/validate`, { note: null }, undefined, 0, 'Cours validé.', row.enrollmentId);
  const revoke = (row: CourseSheetRow, completionId: string, reason: string) =>
    send('revokeCourseCompletion', `course-completions/${completionId}/revoke`, { reason }, completionId, 1, 'Validation retirée.', row.enrollmentId);
  return { sheetRead, rosterRead, sheet, occurrences: sorted, runner, locked, feedback, mark, enroll, cancelEnrollment, pay, voidPayment, validate, revoke,
    reread: () => { sheetRead.reload(); rosterRead.reload(); } };
}
export type CourseParticipants = ReturnType<typeof useCourseParticipants>;
