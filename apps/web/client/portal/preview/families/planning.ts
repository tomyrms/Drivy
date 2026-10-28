import { schoolTimeToInstant } from '../../../command-core';
import { dayAfter, ids, previewId, stamp, type FixtureRecord } from '../fixtures';
import type { PreviewFamily, PreviewRequest, PreviewTools } from '../family';

/**
 * Synthetic planning family: instructor hours and absences, collective courses (types, series, sessions, policy).
 * Mirrors the real routes and refusals of the school API (`lesson-setup.ts`, `courses.ts`, `course-enrollments.ts`) closely enough
 * for the rebuilt pages; it never decides a right and is reachable only from the separate preview entry.
 */
const zone = 'Europe/Zurich';
const at = (days: number, time: string) => schoolTimeToInstant(`${dayAfter(days)}T${time}`, zone)!;
const awareness = previewId(710), firstAid = previewId(711);
const marie = ids.instructor, simon = previewId(6), luc = ids.admin;

let store: Record<string, FixtureRecord[]> = {};
const policy = { version: 1, selfCancelHours: 24, offerResponseMinutes: 720 as number | null };
const types: FixtureRecord[] = [
  { id: awareness, schoolId: null, stableKey: 'AWARENESS', title: 'Sensibilisation', description: '', version: 1, predefined: true },
  { id: firstAid, schoolId: null, stableKey: 'FIRST_AID', title: 'Premiers secours', description: '', version: 1, predefined: true },
];
const memberName = (id: string) => store.members?.find(item => item.id === id)?.displayName ?? '';

interface Session { startsAt: string; endsAt: string; instructorMembershipId: string; attendanceRequired: boolean; id?: string }
/** Derived fields of a series are recomputed from its sessions, the way the school returns them. */
function describe(base: FixtureRecord, sessions: readonly Session[], nextId: () => string): FixtureRecord {
  const ordered = [...sessions].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt));
  const first = ordered[0]!, last = ordered.at(-1)!;
  const seatsTaken = base.seatsTaken ?? 0;
  return { ...base, schoolId: ids.school, typeTitle: types.find(item => item.id === base.typeId)?.title ?? '', responsibleDisplayName: memberName(base.responsibleMembershipId),
    seatsTaken, remainingSeats: Math.max(0, base.capacity - seatsTaken), policyVersion: policy.version, selfCancelHours: policy.selfCancelHours,
    selfCancellationDeadline: new Date(Date.parse(first.startsAt) - policy.selfCancelHours * 3_600_000).toISOString(),
    firstStartsAt: first.startsAt, lastEndsAt: last.endsAt, totalMinutes: ordered.reduce((sum, item) => sum + Math.round((Date.parse(item.endsAt) - Date.parse(item.startsAt)) / 60_000), 0),
    canManage: true,
    occurrences: ordered.map((item, index) => ({ id: item.id ?? nextId(), position: index + 1, startsAt: item.startsAt, endsAt: item.endsAt, timeZone: zone,
      instructorMembershipId: item.instructorMembershipId, instructorDisplayName: memberName(item.instructorMembershipId), attendanceRequired: item.attendanceRequired })) };
}
const session = (days: number, from: string, to: string, instructor: string, attendanceRequired = true): Session => ({ startsAt: at(days, from), endsAt: at(days, to), instructorMembershipId: instructor, attendanceRequired });

/** Local clock reading of an instant in the school zone. */
function local(instant: string) {
  const parts = new Intl.DateTimeFormat('en-GB', { timeZone: zone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).formatToParts(new Date(instant));
  const get = (type: string) => parts.find(part => part.type === type)!.value;
  const date = `${get('year')}-${get('month')}-${get('day')}`;
  return { date, clock: `${get('hour')}:${get('minute')}`, weekday: (new Date(`${date}T12:00:00Z`).getUTCDay() + 6) % 7 + 1 };
}
const covers = (rules: readonly FixtureRecord[], lesson: FixtureRecord) => {
  const start = local(lesson.plannedStart), end = local(lesson.plannedEnd);
  return rules.some(rule => rule.weekdays.includes(start.weekday) && rule.localStart <= start.clock && end.clock <= rule.localEnd
    && rule.validFrom <= start.date && (rule.validUntil === null || start.date <= rule.validUntil));
};
const plannedLessons = (instructor: string) => (store.lessons ?? []).filter(item => item.status === 'PLANNED' && !item.actualStart && item.instructorMembershipId === instructor && Date.parse(item.plannedEnd) > Date.now());
/** Same rule as the school: a change is refused when it leaves a planned appointment outside the opening hours it relied on. */
const breaksBookings = (instructor: string, before: readonly FixtureRecord[], after: readonly FixtureRecord[]) => plannedLessons(instructor).some(lesson => covers(before, lesson) && !covers(after, lesson));
const rulesOf = (instructor: string) => (store['availability-rules'] ?? []).filter(item => item.instructorMembershipId === instructor);
const overlapsRange = (items: readonly { startsAt: string; endsAt: string }[], start: string, end: string) => items.some(item => Date.parse(item.startsAt) < Date.parse(end) && Date.parse(start) < Date.parse(item.endsAt));
const lessonRanges = (instructor: string) => plannedLessons(instructor).map(item => ({ startsAt: item.plannedStart as string, endsAt: item.plannedEnd as string }));

export const planningFamily: PreviewFamily = {
  name: 'planning',
  seed(db) {
    store = db;
    // Marie: two ranges a day, a Saturday opening from next fortnight and ended hours. Simon and Luc: other weeks.
    const rules = db['availability-rules']!;
    Object.assign(rules[0]!, { weekdays: [1, 2, 3, 4, 5], localStart: '08:00', localEnd: '12:00', validFrom: dayAfter(-60), validUntil: null });
    const rule = (number: number, instructor: string, weekdays: number[], localStart: string, localEnd: string, validFrom: string, validUntil: string | null) =>
      ({ id: previewId(number), schoolId: ids.school, version: 1, instructorMembershipId: instructor, weekdays, localStart, localEnd, validFrom, validUntil });
    rules.push(rule(501, marie, [1, 2, 3, 4, 5], '13:30', '18:00', dayAfter(-60), null), rule(502, marie, [6], '09:00', '12:00', dayAfter(14), dayAfter(70)),
      rule(503, marie, [1, 2, 3], '18:00', '20:30', dayAfter(-120), dayAfter(-15)), rule(504, simon, [2, 4], '09:00', '12:00', dayAfter(-30), null),
      rule(505, simon, [2, 4], '13:00', '17:00', dayAfter(-30), null), rule(506, luc, [1, 3, 5], '08:00', '17:00', dayAfter(-30), null));
    const closure = (number: number, instructor: string, startsAt: string, endsAt: string, reason: string | null) =>
      ({ id: previewId(number), schoolId: ids.school, version: 1, instructorMembershipId: instructor, startsAt, endsAt, reason });
    db.closures!.push(closure(510, marie, at(10, '08:00'), at(12, '18:00'), 'Congé annuel'), closure(511, simon, at(3, '13:00'), at(3, '17:00'), 'Formation continue'),
      closure(512, marie, at(-20, '08:00'), at(-19, '18:00'), null));
    // Courses: one draft, one published with seats taken over four weeks, one cancelled. The existing published course keeps its id.
    let sequence = 0;
    const next = () => previewId(8000 + ++sequence);
    const series = db['course-series']!;
    series.push(
      describe({ id: previewId(720), version: 1, status: 'DRAFT', typeId: firstAid, title: 'Premiers secours — soirées', description: 'Gestes de premiers secours pour les futurs conducteurs.', location: 'Salle de formation',
        conditions: '', teachingLanguage: 'fr', responsibleMembershipId: luc, capacity: 12, minParticipants: 4, publishedAt: null },
      [session(20, '18:00', '21:00', luc), session(27, '18:00', '21:00', marie)], next),
      describe({ id: previewId(730), version: 1, status: 'PUBLISHED', typeId: awareness, title: 'Sensibilisation — cycle d’automne', description: 'Quatre soirées pour comprendre les risques de la route.', location: 'Salle de formation',
        conditions: 'Apporter son permis d’élève.', teachingLanguage: 'fr', responsibleMembershipId: luc, capacity: 12, minParticipants: null, seatsTaken: 5, publishedAt: stamp },
      [session(3, '18:00', '20:00', luc), session(10, '18:00', '20:00', luc), session(17, '18:00', '20:00', marie), session(24, '18:00', '20:00', luc, false)], next),
      describe({ id: previewId(740), version: 2, status: 'CANCELLED', typeId: firstAid, title: 'Premiers secours — groupe B', description: '', location: 'Salle de formation',
        conditions: '', teachingLanguage: 'de', responsibleMembershipId: luc, capacity: 8, minParticipants: null, seatsTaken: 0, publishedAt: stamp },
      [session(5, '09:00', '12:00', luc)], next));
    // The existing pilot course also needs identifiers for its derived fields.
    Object.assign(series[0]!, describe(series[0]!, series[0]!.occurrences, next));
  },
  read(request, tools) {
    if (request.path !== 'course-catalogue') return undefined;
    const instructors = (store.members ?? []).filter(item => item.status === 'ACTIVE' && item.roles.includes('INSTRUCTOR')).map(item => ({ membershipId: item.id, displayName: item.displayName }));
    return tools.reply(200, tools.envelope({ schoolId: ids.school, canManage: true, types, policy, instructors }));
  },
  write(request, tools) {
    const { collection } = request;
    if (collection === 'availability-rules') return writeRule(request, tools);
    if (collection === 'closures') return writeClosure(request, tools);
    if (collection === 'course-types') return writeType(request, tools);
    if (collection === 'course-series') return writeSeries(request, tools);
    if (collection === 'course-policy') return writePolicy(request, tools);
    return undefined;
  },
  refusalCode(request) {
    if (request.collection === 'availability-rules' || request.collection === 'closures') return 'EXISTING_BOOKINGS';
    if (request.collection === 'course-types') return 'COURSE_TYPE_EXISTS';
    if (request.collection === 'course-series') return request.action === 'cancel' ? 'COURSE_NOT_PUBLISHED' : 'COURSE_INSTRUCTOR_CONFLICT';
    return undefined;
  },
};

function writeRule(request: PreviewRequest, tools: PreviewTools): Response {
  const { body, resourceId, action, method } = request;
  const rules = store['availability-rules']!;
  const draft = () => ({ instructorMembershipId: body.instructorMembershipId, weekdays: [...body.weekdays].sort(), localStart: body.localStart, localEnd: body.localEnd, validFrom: body.validFrom, validUntil: body.validUntil ?? null });
  if (!resourceId && method === 'POST') {
    if (!(body.localEnd > body.localStart)) return tools.reply(422, { code: 'INVALID_INTERVAL' });
    const item = { id: tools.nextId(), schoolId: ids.school, version: 1, ...draft() };
    rules.push(item);
    return tools.commit('createAvailabilityRule', item);
  }
  const rule = rules.find(item => item.id === resourceId);
  if (!rule) return tools.reply(404, { code: 'NOT_FOUND' });
  if (!tools.versionMatches(rule)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  const others = rulesOf(rule.instructorMembershipId).filter(item => item !== rule);
  if (action === 'remove') {
    if (breaksBookings(rule.instructorMembershipId, rulesOf(rule.instructorMembershipId), others)) return tools.reply(409, { code: 'EXISTING_BOOKINGS' });
    rules.splice(rules.indexOf(rule), 1);
    return tools.commit('removeAvailabilityRule', { ...rule, version: rule.version + 1 });
  }
  if (method === 'PUT') {
    if (!(body.localEnd > body.localStart)) return tools.reply(422, { code: 'INVALID_INTERVAL' });
    if (body.instructorMembershipId !== rule.instructorMembershipId) return tools.reply(422, { code: 'INVALID_REQUEST' });
    const changed = { ...rule, ...draft(), version: rule.version };
    if (breaksBookings(rule.instructorMembershipId, rulesOf(rule.instructorMembershipId), [...others, changed])) return tools.reply(409, { code: 'EXISTING_BOOKINGS' });
    Object.assign(rule, draft()); rule.version++;
    return tools.commit('updateAvailabilityRule', rule);
  }
  return tools.reply(404, { code: 'PREVIEW_ACTION_UNAVAILABLE' });
}

function writeClosure(request: PreviewRequest, tools: PreviewTools): Response {
  const { body, resourceId, action } = request;
  const closures = store.closures!;
  if (!resourceId) {
    if (Date.parse(body.endsAt) <= Date.parse(body.startsAt)) return tools.reply(422, { code: 'INVALID_INTERVAL' });
    if (overlapsRange(lessonRanges(body.instructorMembershipId), body.startsAt, body.endsAt)) return tools.reply(409, { code: 'EXISTING_BOOKINGS' });
    const item = { id: tools.nextId(), schoolId: ids.school, version: 1, instructorMembershipId: body.instructorMembershipId, startsAt: body.startsAt, endsAt: body.endsAt, reason: body.reason ?? null };
    closures.push(item);
    return tools.commit('createClosure', item);
  }
  const item = closures.find(entry => entry.id === resourceId);
  if (!item || action !== 'remove') return tools.reply(404, { code: 'NOT_FOUND' });
  if (!tools.versionMatches(item)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  closures.splice(closures.indexOf(item), 1);
  return tools.commit('removeClosure', { ...item, version: item.version + 1 });
}

function writeType(request: PreviewRequest, tools: PreviewTools): Response {
  const { body } = request;
  const title = String(body.title ?? '').trim();
  if (!title) return tools.reply(400, { code: 'INVALID_REQUEST' });
  if (types.some(item => item.title.trim().toLocaleLowerCase('fr-CH') === title.toLocaleLowerCase('fr-CH'))) return tools.reply(409, { code: 'COURSE_TYPE_EXISTS' });
  const item = { id: tools.nextId(), schoolId: ids.school, stableKey: null, title, description: String(body.description ?? '').trim(), version: 1, predefined: false };
  types.push(item);
  return tools.commit('createCourseType', item);
}

function writePolicy(request: PreviewRequest, tools: PreviewTools): Response {
  const { body } = request;
  if (!tools.versionMatches(policy)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  policy.selfCancelHours = body.selfCancelHours; policy.offerResponseMinutes = body.offerResponseMinutes ?? null; policy.version++;
  return tools.commit('saveCoursePolicy', { id: ids.school, schoolId: ids.school, version: policy.version });
}

/** Sessions of a request body, checked like the school does before it writes. Null with the refusal to answer when invalid. */
function checkedSessions(body: FixtureRecord, tools: PreviewTools, ownId?: string): { sessions: Session[] } | { refusal: Response } {
  const sessions: Session[] = body.occurrences ?? [];
  if (!sessions.length) return { refusal: tools.reply(422, { code: 'COURSE_OCCURRENCES_REQUIRED' }) };
  const ordered = [...sessions].sort((a, b) => Date.parse(a.startsAt) - Date.parse(b.startsAt));
  for (let index = 1; index < ordered.length; index++) if (Date.parse(ordered[index]!.startsAt) < Date.parse(ordered[index - 1]!.endsAt)) return { refusal: tools.reply(422, { code: 'COURSE_OCCURRENCES_OVERLAP' }) };
  for (const item of ordered) {
    if (!(Date.parse(item.endsAt) > Date.parse(item.startsAt))) return { refusal: tools.reply(422, { code: 'INVALID_INTERVAL' }) };
    if (overlapsRange(lessonRanges(item.instructorMembershipId), item.startsAt, item.endsAt)) return { refusal: tools.reply(409, { code: 'COURSE_SCHEDULE_CONFLICT' }) };
    const busy = (store['course-series'] ?? []).some(other => other.id !== ownId && other.status === 'PUBLISHED'
      && overlapsRange(other.occurrences.filter((entry: FixtureRecord) => entry.instructorMembershipId === item.instructorMembershipId), item.startsAt, item.endsAt));
    if (busy) return { refusal: tools.reply(409, { code: 'COURSE_INSTRUCTOR_CONFLICT' }) };
  }
  return { sessions };
}

function writeSeries(request: PreviewRequest, tools: PreviewTools): Response {
  const { body, resourceId, action, method } = request;
  const all = store['course-series']!;
  const base = () => ({ typeId: body.typeId, title: body.title, description: body.description, location: body.location, conditions: body.conditions,
    teachingLanguage: body.teachingLanguage ?? null, responsibleMembershipId: body.responsibleMembershipId, capacity: body.capacity, minParticipants: body.minParticipants ?? null });
  if (!resourceId) {
    if (!types.some(item => item.id === body.typeId)) return tools.reply(422, { code: 'COURSE_TYPE_UNKNOWN' });
    const checked = checkedSessions(body, tools);
    if ('refusal' in checked) return checked.refusal;
    const item = describe({ id: tools.nextId(), version: 1, status: 'DRAFT', seatsTaken: 0, publishedAt: null, ...base() }, checked.sessions, tools.nextId);
    all.push(item);
    return tools.commit('createCourseSeries', item);
  }
  const item = all.find(entry => entry.id === resourceId);
  if (!item) return tools.reply(404, { code: 'NOT_FOUND' });
  if (!tools.versionMatches(item)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
  const replace = (next: FixtureRecord) => { Object.assign(item, next, { version: item.version + 1 }); return item; };
  if (method === 'PUT' && !action) {
    if (item.status !== 'DRAFT') return tools.reply(409, { code: 'COURSE_NOT_DRAFT' });
    const checked = checkedSessions(body, tools, item.id);
    if ('refusal' in checked) return checked.refusal;
    return tools.commit('updateCourseSeries', replace(describe({ ...item, ...base() }, checked.sessions, tools.nextId)));
  }
  if (action === 'publish') {
    if (item.status !== 'DRAFT') return tools.reply(409, { code: 'COURSE_NOT_DRAFT' });
    if (Date.parse(item.firstStartsAt) <= Date.now()) return tools.reply(422, { code: 'COURSE_IN_PAST' });
    return tools.commit('publishCourseSeries', replace({ status: 'PUBLISHED', publishedAt: new Date().toISOString() }));
  }
  if (action === 'capacity') {
    if (item.status !== 'PUBLISHED') return tools.reply(409, { code: 'COURSE_NOT_PUBLISHED' });
    if (body.capacity < item.seatsTaken) return tools.reply(409, { code: 'COURSE_CAPACITY_BELOW_TAKEN' });
    if (item.minParticipants !== null && body.capacity < item.minParticipants) return tools.reply(422, { code: 'COURSE_CAPACITY_BELOW_MINIMUM' });
    return tools.commit('changeCourseCapacity', replace({ capacity: body.capacity, remainingSeats: body.capacity - item.seatsTaken }));
  }
  if (action === 'cancel') {
    if (item.status !== 'PUBLISHED') return tools.reply(409, { code: 'COURSE_NOT_PUBLISHED' });
    if (!String(body.reason ?? '').trim()) return tools.reply(400, { code: 'COURSE_REASON_REQUIRED' });
    return tools.commit('cancelCourseSeries', replace({ status: 'CANCELLED' }));
  }
  if (action === 'reschedule') {
    if (item.status !== 'PUBLISHED') return tools.reply(409, { code: 'COURSE_NOT_PUBLISHED' });
    const given: FixtureRecord[] = body.occurrences ?? [];
    if (given.length !== item.occurrences.length) return tools.reply(422, { code: 'COURSE_OCCURRENCE_COUNT' });
    const sessions: Session[] = [];
    for (const entry of item.occurrences as FixtureRecord[]) {
      const next = given.find(candidate => candidate.position === entry.position);
      if (!next) return tools.reply(422, { code: 'COURSE_OCCURRENCE_COUNT' });
      sessions.push({ id: entry.id, startsAt: next.startsAt, endsAt: next.endsAt, instructorMembershipId: next.instructorMembershipId, attendanceRequired: entry.attendanceRequired });
    }
    const checked = checkedSessions({ occurrences: sessions }, tools, item.id);
    if ('refusal' in checked) return checked.refusal;
    return tools.commit('rescheduleCourseSeries', replace(describe(item, checked.sessions, tools.nextId)));
  }
  return tools.reply(404, { code: 'PREVIEW_ACTION_UNAVAILABLE' });
}
