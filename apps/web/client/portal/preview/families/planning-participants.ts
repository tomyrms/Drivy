import { ids, previewId, stamp, type FixtureRecord } from '../fixtures';
import type { PreviewRequest, PreviewTools } from '../family';

/**
 * Synthetic participants of the collective courses: enrolments, waiting list, attendance, on-site settlements and internal validation.
 * Follows the routes and refusals of the school API (`course-enrollments.ts`, `course-facts.ts`): four independent facts, a sheet returned by
 * each write, a payment never edited (a correction is a voiding that stays listed), a validation only once every required session is present.
 * Reachable only from the separate preview entry.
 */
export interface ParticipantsEnv { db(): Record<string, FixtureRecord[]>; at(days: number, time: string): string; policy: { offerResponseMinutes: number | null } }

let enrollments: FixtureRecord[] = [], waitlist: FixtureRecord[] = [], attendance: FixtureRecord[] = [], payments: FixtureRecord[] = [], completions: FixtureRecord[] = [];
let env: ParticipantsEnv;
const rights = { canTakeAttendance: true, canRecordPayment: true, canValidate: true };
const seriesOf = (id: string | undefined) => env.db()['course-series']?.find(item => item.id === id);
const learnerName = (id: string) => env.db().learners?.find(item => item.id === id)?.displayName ?? fakeNames.get(id) ?? 'Élève';
const fakeNames = new Map<string, string>();
let sequence = 0;
const nextId = () => previewId(9000 + ++sequence);

const enrollment = (seriesId: string, learnerId: string, patch: FixtureRecord = {}): FixtureRecord => ({ id: nextId(), schoolId: ids.school, seriesId, learnerId, version: 1, status: 'ACTIVE', source: 'STAFF',
  selfCancelDeadline: env.at(-1, '12:00'), createdAt: stamp, cancelledAt: null, cancelKind: null, cancelReason: null, learnerDisplayName: learnerName(learnerId), ...patch });

function requirementsOf(series: FixtureRecord, enrollmentId: string) {
  const required = (series.occurrences as FixtureRecord[]).filter(item => item.attendanceRequired);
  const present = required.filter(item => attendance.some(mark => mark.enrollmentId === enrollmentId && mark.occurrenceId === item.id && mark.status === 'PRESENT')).length;
  return { required: required.length, present, missing: required.length - present };
}
const activeCompletion = (series: FixtureRecord, learnerId: string) => completions.find(item => item.learnerId === learnerId && item.typeId === series.typeId && !item.revokedAt);

/** The sheet of a series, as the school returns it with every write. */
function sheetOf(seriesId: string): FixtureRecord {
  const series = seriesOf(seriesId)!;
  const rows = enrollments.filter(item => item.seriesId === seriesId).sort((a, b) => a.status.localeCompare(b.status) || String(a.createdAt).localeCompare(String(b.createdAt)) || a.id.localeCompare(b.id)).map(item => {
    const completion = activeCompletion(series, item.learnerId);
    return { enrollmentId: item.id, learnerId: item.learnerId, learnerDisplayName: item.learnerDisplayName, status: item.status, cancelledAt: item.cancelledAt,
      attendance: (series.occurrences as FixtureRecord[]).map(occurrence => {
        const mark = attendance.find(entry => entry.enrollmentId === item.id && entry.occurrenceId === occurrence.id);
        return { occurrenceId: occurrence.id, status: mark?.status ?? null, version: mark?.version ?? null, recordedAt: mark?.recordedAt ?? null };
      }),
      requirements: requirementsOf(series, item.id),
      payments: payments.filter(payment => payment.enrollmentId === item.id).map(({ enrollmentId: _owner, ...payment }) => payment),
      completion: completion ? { id: completion.id, validatedAt: completion.validatedAt, seriesId: completion.seriesId, revokedAt: null } : null };
  });
  return { series, rights, rows };
}
const withResource = (seriesId: string, id: string, version: number) => ({ ...sheetOf(seriesId), id, version });
const refreshSeats = (series: FixtureRecord) => {
  const taken = enrollments.filter(item => item.seriesId === series.id && item.status === 'ACTIVE').length;
  series.seatsTaken = taken; series.remainingSeats = Math.max(0, series.capacity - taken);
};
const started = (occurrence: FixtureRecord) => Date.parse(occurrence.startsAt) <= Date.now();

export function seedParticipants(next: ParticipantsEnv) {
  env = next; enrollments = []; waitlist = []; attendance = []; payments = []; completions = []; sequence = 0;
  const learner = (index: number) => previewId(10 + index);
  const series = (id: number) => seriesOf(previewId(id))!;
  const mark = (item: FixtureRecord, occurrence: FixtureRecord, status: string, days: number) =>
    attendance.push({ enrollmentId: item.id, occurrenceId: occurrence.id, status, version: 1, recordedAt: env.at(days, '21:00') });
  const pay = (item: FixtureRecord, amountCents: number, days: number, note: string | null, voided?: string) =>
    payments.push({ id: nextId(), enrollmentId: item.id, amountCents, recordedAt: env.at(days, '18:30'), note, voidedAt: voided ? env.at(days + 1, '09:00') : null, voidReason: voided ?? null });

  // 700 (existing pilot course) and 730 (four weekly evenings): rosters with seats taken, nothing started yet.
  for (const index of [0, 1, 2]) enrollments.push(enrollment(previewId(700), learner(index)));
  for (const index of [0, 1, 2, 3, 4]) enrollments.push(enrollment(previewId(730), learner(index), index === 0 ? { source: 'SELF' } : {}));
  enrollments.push(enrollment(previewId(730), learner(5), { status: 'CANCELLED', version: 2, cancelledAt: env.at(-2, '10:00'), cancelKind: 'STAFF', cancelReason: 'Demande de l’élève' }));

  // 750: full, two required sessions already held, one optional to come; waiting list with a live and an expired offer.
  const small = series(750), [first, second] = small.occurrences as FixtureRecord[];
  const people = [0, 1, 2].map(index => enrollment(small.id, learner(index), { source: index === 1 ? 'SELF' : index === 2 ? 'OFFER' : 'STAFF' }));
  enrollments.push(...people);
  mark(people[0]!, first!, 'PRESENT', -14); mark(people[0]!, second!, 'PRESENT', -7);
  mark(people[1]!, first!, 'PRESENT', -14); mark(people[1]!, second!, 'ABSENT', -7);
  mark(people[2]!, first!, 'PRESENT', -14); mark(people[2]!, second!, 'PRESENT', -7);
  pay(people[0]!, 12000, -13, 'Espèces'); pay(people[0]!, 5000, -13, 'Saisie en double', 'Erreur de saisie'); pay(people[1]!, 12000, -13, null); pay(people[2]!, 12000, -12, 'Carte');
  completions.push({ id: nextId(), learnerId: people[2]!.learnerId, typeId: small.typeId, seriesId: small.id, validatedAt: env.at(-6, '09:00'), revokedAt: null });
  waitlist.push({ id: nextId(), seriesId: small.id, learnerId: learner(3), status: 'WAITING', queuedAt: env.at(-5, '10:00'), offerExpiresAt: null },
    { id: nextId(), seriesId: small.id, learnerId: learner(4), status: 'OFFERED', queuedAt: env.at(-4, '10:00'), offerExpiresAt: env.at(1, '10:00') },
    { id: nextId(), seriesId: small.id, learnerId: learner(5), status: 'OFFERED', queuedAt: env.at(-3, '10:00'), offerExpiresAt: env.at(-1, '10:00') });

  // 760: a large group with long names, one session held and half the call made.
  const group = series(760), [held] = group.occurrences as FixtureRecord[];
  const names = ['Alexandre-Maximilien de la Rochefoucauld-Montmorency', 'Anne-Sophie Müller-Hofstetter', 'Bruno Blanc', 'Chloé Dubois', 'Dimitri Papadopoulos', 'Éloïse Perrin', 'Fabrice Rochat', 'Giulia Moretti-Bernasconi',
    'Hugo Meier', 'Inès Favre', 'Jérémie Girard', 'Kévin Bonvin', 'Léa Chappuis', 'Mathilde Jaquet', 'Nicolas Gachet', 'Océane Pittet', 'Pierre-Yves Cuendet', 'Quentin Zbinden'];
  names.forEach((name, index) => {
    const id = previewId(2000 + index); fakeNames.set(id, name);
    const item = enrollment(group.id, id, { learnerDisplayName: name }); enrollments.push(item);
    if (index < 9) mark(item, held!, index % 5 === 3 ? 'ABSENT' : index % 7 === 4 ? 'EXCUSED' : 'PRESENT', -3);
  });
  for (const item of [...(env.db()['course-series'] ?? [])]) refreshSeats(item);
}

export function readParticipants(request: PreviewRequest, tools: PreviewTools): Response | undefined {
  if (request.collection !== 'course-series' || !request.resourceId) return undefined;
  const series = seriesOf(request.resourceId);
  if (!series) return undefined;
  if (request.action === 'sheet') return tools.reply(200, tools.envelope(sheetOf(series.id)));
  if (request.action === 'enrollments') {
    const items = enrollments.filter(item => item.seriesId === series.id);
    const waiting = waitlist.filter(item => item.seriesId === series.id).sort((a, b) => String(a.queuedAt).localeCompare(String(b.queuedAt)))
      .map((entry, index) => ({ id: entry.id, learnerId: entry.learnerId, learnerDisplayName: learnerName(entry.learnerId), position: index + 1, status: entry.status, queuedAt: entry.queuedAt, offerExpiresAt: entry.offerExpiresAt }));
    return tools.reply(200, tools.envelope({ items, waitlist: waiting }));
  }
  return undefined;
}

/** Writes below `course-series/:id/enrollments`, `course-enrollments`, `course-payments` and `course-completions`; undefined for anything else. */
export function writeParticipants(request: PreviewRequest, tools: PreviewTools): Response | undefined {
  const { collection, resourceId, action, body, segments } = request;
  if (collection === 'course-series' && action === 'enrollments') return enroll(resourceId!, body, tools);
  if (collection === 'course-enrollments') {
    const item = enrollments.find(entry => entry.id === resourceId);
    if (!item) return tools.reply(404, { code: 'NOT_FOUND' });
    const series = seriesOf(item.seriesId)!;
    if (action === 'staff-cancel') return staffCancel(item, series, body, tools);
    if (action === 'attendance') return recordAttendance(item, series, segments[3], body, tools);
    if (action === 'payments') return recordPayment(item, body, tools);
    if (action === 'validate') return validate(item, series, tools);
  }
  if (collection === 'course-payments' && action === 'void') return voidPayment(resourceId!, body, tools);
  if (collection === 'course-completions' && action === 'revoke') return revoke(resourceId!, body, tools);
  return undefined;
}

export function participantsRefusal(request: PreviewRequest): string | undefined {
  if (request.collection === 'course-series' && request.action === 'enrollments') return 'COURSE_SCHEDULE_CONFLICT';
  if (request.collection === 'course-enrollments') return ({ 'staff-cancel': 'COURSE_ENROLLMENT_CLOSED', attendance: 'COURSE_ACCESS_REQUIRED', payments: 'COURSE_ACCESS_REQUIRED', validate: 'COURSE_REQUIREMENTS_MISSING' } as Record<string, string>)[request.action ?? ''];
  if (request.collection === 'course-payments') return 'COURSE_PAYMENT_VOIDED';
  if (request.collection === 'course-completions') return 'COURSE_COMPLETION_REVOKED';
  return undefined;
}

function enroll(seriesId: string, body: FixtureRecord, tools: PreviewTools): Response {
  const series = seriesOf(seriesId);
  if (!series) return tools.reply(404, { code: 'NOT_FOUND' });
  if (series.status !== 'PUBLISHED') return tools.reply(409, { code: 'COURSE_NOT_OPEN' });
  if (!env.db().learners?.some(item => item.id === body.learnerId)) return tools.reply(404, { code: 'NOT_FOUND' });
  if (Date.parse(series.firstStartsAt) <= Date.now()) return tools.reply(409, { code: 'COURSE_STARTED' });
  if (enrollments.some(item => item.seriesId === seriesId && item.learnerId === body.learnerId && item.status === 'ACTIVE')) return tools.reply(409, { code: 'COURSE_ALREADY_ENROLLED' });
  if (series.seatsTaken >= series.capacity) return tools.reply(409, { code: 'COURSE_FULL' });
  const busy = (env.db().lessons ?? []).some(lesson => lesson.learnerId === body.learnerId && lesson.status === 'PLANNED'
    && (series.occurrences as FixtureRecord[]).some(item => Date.parse(item.startsAt) < Date.parse(lesson.plannedEnd) && Date.parse(lesson.plannedStart) < Date.parse(item.endsAt)));
  if (busy) return tools.reply(409, { code: 'COURSE_SCHEDULE_CONFLICT' });
  const item = enrollment(seriesId, body.learnerId, { id: tools.nextId(), createdAt: new Date().toISOString(), selfCancelDeadline: series.selfCancellationDeadline });
  enrollments.push(item); waitlist = waitlist.filter(entry => !(entry.seriesId === seriesId && entry.learnerId === body.learnerId));
  refreshSeats(series);
  return tools.commit('staffEnrollCourse', item);
}

function staffCancel(item: FixtureRecord, series: FixtureRecord, body: FixtureRecord, tools: PreviewTools): Response {
  if (!tools.versionMatches(item)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  if (item.status !== 'ACTIVE') return tools.reply(409, { code: 'COURSE_ENROLLMENT_CLOSED' });
  if (!String(body.reason ?? '').trim()) return tools.reply(422, { code: 'COURSE_REASON_REQUIRED' });
  Object.assign(item, { status: 'CANCELLED', cancelledAt: new Date().toISOString(), cancelKind: 'STAFF', cancelReason: String(body.reason).trim(), version: item.version + 1 });
  refreshSeats(series);
  // The freed seat goes to the first person waiting, as an offer with a deadline: nobody is placed on a seat by this screen.
  const waiting = waitlist.find(entry => entry.seriesId === series.id && entry.status === 'WAITING');
  if (waiting && env.policy.offerResponseMinutes !== null) Object.assign(waiting, { status: 'OFFERED', offerExpiresAt: new Date(Date.now() + env.policy.offerResponseMinutes * 60_000).toISOString() });
  return tools.commit('staffCancelCourseEnrollment', item);
}

function recordAttendance(item: FixtureRecord, series: FixtureRecord, occurrenceId: string | undefined, body: FixtureRecord, tools: PreviewTools): Response {
  const occurrence = (series.occurrences as FixtureRecord[]).find(entry => entry.id === occurrenceId);
  if (!occurrence) return tools.reply(404, { code: 'NOT_FOUND' });
  if (item.status !== 'ACTIVE') return tools.reply(409, { code: 'COURSE_ENROLLMENT_CLOSED' });
  if (!started(occurrence)) return tools.reply(409, { code: 'COURSE_OCCURRENCE_NOT_STARTED' });
  const existing = attendance.find(entry => entry.enrollmentId === item.id && entry.occurrenceId === occurrence.id);
  if ((existing?.version ?? null) !== (body.expectedVersion ?? null)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  const version = (existing?.version ?? 0) + 1;
  if (existing) Object.assign(existing, { status: body.status, version, recordedAt: new Date().toISOString() });
  else attendance.push({ enrollmentId: item.id, occurrenceId: occurrence.id, status: body.status, version, recordedAt: new Date().toISOString() });
  return tools.commit('recordCourseAttendance', withResource(series.id, item.id, version));
}

function recordPayment(item: FixtureRecord, body: FixtureRecord, tools: PreviewTools): Response {
  if (item.status !== 'ACTIVE') return tools.reply(409, { code: 'COURSE_ENROLLMENT_CLOSED' });
  if (!Number.isSafeInteger(body.amountCents) || body.amountCents < 0) return tools.reply(400, { code: 'INVALID_REQUEST' });
  const payment = { id: tools.nextId(), enrollmentId: item.id, amountCents: body.amountCents, recordedAt: new Date().toISOString(), note: body.note ?? null, voidedAt: null, voidReason: null };
  payments.push(payment);
  return tools.commit('recordCoursePayment', withResource(item.seriesId, payment.id, 1));
}

function voidPayment(paymentId: string, body: FixtureRecord, tools: PreviewTools): Response {
  const payment = payments.find(entry => entry.id === paymentId);
  if (!payment) return tools.reply(404, { code: 'NOT_FOUND' });
  if (payment.voidedAt) return tools.reply(409, { code: 'COURSE_PAYMENT_VOIDED' });
  if (!String(body.reason ?? '').trim()) return tools.reply(422, { code: 'COURSE_REASON_REQUIRED' });
  Object.assign(payment, { voidedAt: new Date().toISOString(), voidReason: String(body.reason).trim() });
  return tools.commit('voidCoursePayment', withResource(enrollments.find(entry => entry.id === payment.enrollmentId)!.seriesId, paymentId, 2));
}

function validate(item: FixtureRecord, series: FixtureRecord, tools: PreviewTools): Response {
  if (item.status !== 'ACTIVE') return tools.reply(409, { code: 'COURSE_ENROLLMENT_CLOSED' });
  if (activeCompletion(series, item.learnerId)) return tools.reply(409, { code: 'COURSE_ALREADY_COMPLETED' });
  const requirements = requirementsOf(series, item.id);
  if (requirements.required === 0) return tools.reply(409, { code: 'COURSE_NO_REQUIRED_OCCURRENCE' });
  if (requirements.missing > 0) return tools.reply(409, { code: 'COURSE_REQUIREMENTS_MISSING' });
  const completion = { id: tools.nextId(), learnerId: item.learnerId, typeId: series.typeId, seriesId: series.id, validatedAt: new Date().toISOString(), revokedAt: null };
  completions.push(completion);
  return tools.commit('validateCourse', withResource(series.id, completion.id, 1));
}

function revoke(completionId: string, body: FixtureRecord, tools: PreviewTools): Response {
  const completion = completions.find(entry => entry.id === completionId);
  if (!completion?.seriesId) return tools.reply(404, { code: 'NOT_FOUND' });
  if (completion.revokedAt) return tools.reply(409, { code: 'COURSE_COMPLETION_REVOKED' });
  if (!String(body.reason ?? '').trim()) return tools.reply(422, { code: 'COURSE_REASON_REQUIRED' });
  Object.assign(completion, { revokedAt: new Date().toISOString(), revokeReason: String(body.reason).trim() });
  return tools.commit('revokeCourseCompletion', withResource(completion.seriesId, completionId, 2));
}
