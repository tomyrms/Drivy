import { schoolTimeToInstant } from '../../../command-core';
import { dayAfter, db, ids, previewId, stamp, type FixtureRecord } from '../fixtures';
import type { PreviewFamily } from '../family';

/**
 * Synthetic requests from the learner on a lesson (#52): a request never touches the lesson. It stops being pending as soon as the
 * lesson it asked about is no longer the planned one (moved, cancelled), as the server does. Only the refusal has its own command here.
 */
const at = (days: number, time: string) => schoolTimeToInstant(`${dayAfter(days)}T${time}`, 'Europe/Zurich')!;
const request = (number: number, lessonNumber: number, kind: string, note: string, extra: FixtureRecord = {}): FixtureRecord => ({
  id: previewId(950 + number), lessonId: previewId(80 + lessonNumber), kind, status: 'PENDING', note, mine: false, late: false, deadlineAt: null, cancellationHours: 24,
  policyVersionId: ids.policy, resolvedAt: null, resolutionNote: null, version: 1, createdAt: stamp, lessonVersion: 1, ...extra });

function status(item: FixtureRecord) {
  if (item.status !== 'PENDING') return item.status;
  const lesson = db.lessons!.find(entry => entry.id === item.lessonId);
  return !lesson || lesson.status !== 'PLANNED' || lesson.version !== item.lessonVersion ? 'ACCEPTED' : 'PENDING';
}
const view = (item: FixtureRecord) => { const { lessonVersion: _unused, ...rest } = item; return { ...rest, status: status(item) }; };
function state(lessonId: string) {
  const items = (db['lesson-change-requests'] ??= []).filter(item => item.lessonId === lessonId).sort((a, b) => b.createdAt.localeCompare(a.createdAt) || b.id.localeCompare(a.id));
  const pending = items.some(item => status(item) === 'PENDING');
  return { lessonId, requests: items.map(view),
    conditions: { policyVersionId: ids.policy, policyVersion: 1, cancellationPolicyText: 'Prévenez l’école au moins 24 heures avant le début.', cancellationHours: 24, lateAction: 'CONTACT',
      deadlineAt: at(0, '09:00'), late: false, canRequest: false, blockedReason: pending ? 'REQUEST_PENDING' : 'NOT_LEARNER' } };
}

export const lessonRequestsFamily: PreviewFamily = {
  name: 'lesson-requests',
  seed(store) {
    store['lesson-change-requests'] = [
      request(1, 0, 'RESCHEDULE', 'Plutôt mercredi après 16 h, ou jeudi toute la journée.'),
      request(2, 2, 'CANCEL', 'Je suis malade, je ne pourrai pas conduire.', { late: true, createdAt: at(-1, '20:30') }),
    ];
  },
  read(req, tools) {
    if (req.collection === 'lessons' && req.action === 'change-requests' && req.resourceId) return tools.reply(200, tools.envelope(state(req.resourceId)));
    if (req.collection !== 'lesson-change-requests' || req.resourceId) return undefined;
    const items = (db['lesson-change-requests'] ?? []).filter(item => status(item) === 'PENDING').map(item => {
      const lesson = db.lessons!.find(entry => entry.id === item.lessonId)!;
      return { request: view(item), lesson: { id: lesson.id, plannedStart: lesson.plannedStart, plannedEnd: lesson.plannedEnd, timeZone: lesson.timeZone, version: lesson.version,
        instructorMembershipId: lesson.instructorMembershipId, learnerId: lesson.learnerId, learnerDisplayName: lesson.learnerDisplayName } };
    }).sort((a, b) => a.lesson.plannedStart.localeCompare(b.lesson.plannedStart));
    return tools.reply(200, tools.envelope({ items }));
  },
  write(req, tools) {
    if (req.collection !== 'lesson-change-requests' || !req.resourceId || req.action !== 'refuse' || req.method !== 'POST') return undefined;
    const item = (db['lesson-change-requests'] ?? []).find(entry => entry.id === req.resourceId);
    if (!item) return tools.reply(404, { code: 'NOT_FOUND' });
    if (!tools.versionMatches(item)) return tools.reply(412, { code: 'VERSION_CONFLICT' });
    if (status(item) !== 'PENDING') return tools.reply(409, { code: 'LESSON_CHANGE_REQUEST_CLOSED' });
    Object.assign(item, { status: 'REFUSED', resolutionNote: req.body.note ?? null, resolvedAt: new Date().toISOString(), version: item.version + 1 });
    return tools.commit('refuseLessonChangeRequest', { ...state(item.lessonId), id: item.id, version: item.version });
  },
  refusalCode: req => req.collection === 'lesson-change-requests' ? 'LESSON_CHANGE_REQUEST_CLOSED' : undefined,
};
