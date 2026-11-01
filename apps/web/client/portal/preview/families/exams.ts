import { schoolTimeToInstant } from '../../../command-core';
import { dayAfter, db, ids, previewId, stamp, type FixtureRecord } from '../fixtures';
import type { PreviewFamily, PreviewRequest, PreviewTools } from '../family';

/**
 * Synthetic exams (#54): the rules of apps/api/src/exams.ts on the shared fixture store, reachable only from the separate preview entry.
 * A past date stays « à renseigner » (never a result); a postponement keeps the first attempt; an escort only needs an assigned instructor.
 */
const at = (days: number, time: string) => schoolTimeToInstant(`${dayAfter(days)}T${time}`, 'Europe/Zurich')!;
const exam = (number: number, trainingNumber: number, kind: string, status: string, startsAt: string, extra: FixtureRecord = {}): FixtureRecord => ({
  id: previewId(900 + number), schoolId: ids.school, trainingId: previewId(20 + trainingNumber), kind, categoryCode: 'B', status, startsAt, timeZone: 'Europe/Zurich',
  location: 'Centre d’examen de Lausanne', escort: null, resultNote: '', resultRecordedAt: ['PASSED', 'FAILED', 'ABSENT'].includes(status) ? stamp : null,
  postponedToExamId: null, version: 1, createdAt: stamp, ...extra });
const revisions: Record<string, FixtureRecord[]> = {};

function exams(trainingId: string) { return (db.exams ??= []).filter(item => item.trainingId === trainingId); }
function attempts(items: FixtureRecord[]) {
  const ranks = new Map<string, number>();
  for (const kind of ['THEORY', 'PRACTICAL']) {
    items.filter(item => item.kind === kind && item.status !== 'POSTPONED').sort((a, b) => a.startsAt.localeCompare(b.startsAt) || a.id.localeCompare(b.id))
      .forEach((item, index) => ranks.set(item.id, index + 1));
  }
  return ranks;
}
const view = (item: FixtureRecord, rank: number | undefined) => ({ ...item, attempt: rank ?? null, needsResult: item.status === 'SCHEDULED' && Date.parse(item.startsAt) <= Date.now() });
function state(trainingId: string) {
  const items = exams(trainingId), ranks = attempts(items);
  const summary = ['THEORY', 'PRACTICAL'].map(kind => {
    const own = items.filter(item => item.kind === kind);
    return { kind, passed: own.some(item => item.status === 'PASSED'), attempts: own.filter(item => item.status !== 'POSTPONED').length, scheduledExamId: own.find(item => item.status === 'SCHEDULED')?.id ?? null };
  });
  const candidates = db.members!.filter(member => member.status === 'ACTIVE' && member.roles.includes('INSTRUCTOR')).map(member => ({ membershipId: member.id, displayName: member.displayName }));
  return { trainingId, canManage: true, escortCandidates: candidates,
    exams: [...items].sort((a, b) => b.startsAt.localeCompare(a.startsAt)).map(item => view(item, ranks.get(item.id))), summary };
}
function list(filter: string, tools: PreviewTools) {
  const now = new Date().toISOString();
  const rows = (db.exams ?? []).filter(item => item.status === 'SCHEDULED' && (filter === 'PENDING_RESULT' ? item.startsAt <= now : item.startsAt > now));
  rows.sort((a, b) => filter === 'PENDING_RESULT' ? b.startsAt.localeCompare(a.startsAt) : a.startsAt.localeCompare(b.startsAt));
  const items = rows.map(item => {
    const training = db.trainings!.find(entry => entry.id === item.trainingId), learner = db.learners!.find(entry => entry.id === training?.learnerId);
    return { exam: view(item, attempts(exams(item.trainingId)).get(item.id)), learnerId: learner?.id ?? ids.learner, learnerDisplayName: learner?.displayName ?? '' };
  });
  return tools.reply(200, tools.envelope({ filter, items }));
}
function revise(item: FixtureRecord, action: string, reason: string) {
  (revisions[item.id] ??= []).unshift({ revision: item.version, action, status: item.status, startsAt: item.startsAt, timeZone: item.timeZone, location: item.location,
    resultNote: item.resultNote, actorMembershipId: ids.admin, reason, createdAt: new Date().toISOString() });
}
const outcome = (item: FixtureRecord) => ({ ...state(item.trainingId), id: item.id, version: item.version });
const schedule = (body: FixtureRecord) => ({ startsAt: body.startsAt, timeZone: body.timeZone, location: String(body.location ?? ''), escort: body.escort ?? null });

export const examsFamily: PreviewFamily = {
  name: 'exams',
  seed(store) {
    store.exams = [
      exam(1, 0, 'THEORY', 'PASSED', at(-40, '09:00'), { location: 'Centre d’examen de Renens', resultNote: '' }),
      exam(2, 0, 'PRACTICAL', 'FAILED', at(-14, '10:00'), { resultNote: 'Priorités à droite, regard dans les rétroviseurs' }),
      exam(3, 0, 'PRACTICAL', 'SCHEDULED', at(12, '10:30'), { escort: { instructorMembershipId: ids.instructor, startsAt: at(12, '09:30'), endsAt: at(12, '12:00') } }),
      exam(4, 1, 'THEORY', 'SCHEDULED', at(-1, '14:00')),
      exam(5, 3, 'THEORY', 'SCHEDULED', at(6, '08:30')),
    ];
  },
  read(request, tools) {
    if (request.collection === 'trainings' && request.action === 'exams' && request.resourceId) return tools.reply(200, tools.envelope(state(request.resourceId)));
    if (request.collection !== 'exams') return undefined;
    if (!request.resourceId) {
      const filter = request.query.get('filter');
      return filter === 'PENDING_RESULT' || filter === 'UPCOMING' ? list(filter, tools) : tools.reply(400, { code: 'INVALID_REQUEST' });
    }
    if (request.action === 'revisions') return tools.reply(200, tools.envelope({ examId: request.resourceId, items: revisions[request.resourceId] ?? [] }));
    return undefined;
  },
  write(request: PreviewRequest, tools) {
    const body = request.body;
    if (request.collection === 'trainings' && request.action === 'exams' && request.resourceId && request.method === 'POST') {
      const items = exams(request.resourceId);
      if (items.some(item => item.kind === body.kind && item.status === 'PASSED')) return tools.reply(409, { code: 'EXAM_ALREADY_PASSED' });
      if (items.some(item => item.kind === body.kind && item.status === 'SCHEDULED')) return tools.reply(409, { code: 'EXAM_ALREADY_SCHEDULED' });
      const created = { ...exam(db.exams!.length + 1, 0, body.kind, 'SCHEDULED', body.startsAt, schedule(body)), id: tools.nextId(), trainingId: request.resourceId };
      db.exams!.push(created); revise(created, 'CREATED', '');
      return tools.commit('createExam', outcome(created));
    }
    if (request.collection !== 'exams' || !request.resourceId) return undefined;
    const item = db.exams!.find(entry => entry.id === request.resourceId);
    if (!item) return tools.reply(404, { code: 'NOT_FOUND' });
    if (!tools.versionMatches(item)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    const reason = String(body.reason ?? '').trim();
    if (request.action === 'result') {
      if (item.status === 'POSTPONED') return tools.reply(409, { code: 'EXAM_CLOSED' });
      const correction = item.status !== 'SCHEDULED';
      if (!correction && Date.parse(item.startsAt) > Date.now()) return tools.reply(409, { code: 'EXAM_NOT_STARTED' });
      if (correction && !reason) return tools.reply(422, { code: 'EXAM_REASON_REQUIRED' });
      Object.assign(item, { status: body.result, resultNote: String(body.note ?? ''), resultRecordedAt: item.resultRecordedAt ?? new Date().toISOString(), version: item.version + 1 });
      revise(item, correction ? 'RESULT_CORRECTED' : 'RESULT_RECORDED', reason);
      return tools.commit('setExamResult', outcome(item));
    }
    if (request.action === 'update' || request.action === 'postpone') {
      if (item.status !== 'SCHEDULED') return tools.reply(409, { code: 'EXAM_CLOSED' });
      if (request.action === 'update') {
        Object.assign(item, schedule(body), { version: item.version + 1 }); revise(item, 'UPDATED', reason);
        return tools.commit('updateExam', outcome(item));
      }
      const next = { ...exam(db.exams!.length + 1, 0, item.kind, 'SCHEDULED', body.startsAt, schedule(body)), id: tools.nextId(), trainingId: item.trainingId };
      Object.assign(item, { status: 'POSTPONED', postponedToExamId: next.id, version: item.version + 1 });
      db.exams!.push(next); revise(item, 'POSTPONED', reason); revise(next, 'CREATED', '');
      return tools.commit('postponeExam', outcome(item));
    }
    return undefined;
  },
  refusalCode: request => request.collection === 'trainings' && request.action === 'exams' ? 'EXAM_ESCORT_CONFLICT' : request.collection === 'exams' ? 'EXAM_CLOSED' : undefined,
};
