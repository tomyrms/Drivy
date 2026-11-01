import { commandSpecs, type SchoolCommand } from '../../command-core';
import { db, ids, previewId, previewMe, previewSchool, courseCatalogue, progress, reports, stamp, type FixtureRecord } from './fixtures';
import { previewFamilies } from './families';
import type { PreviewRequest, PreviewTools } from './family';

export type PreviewScenario = 'normal' | 'refused' | 'slow' | 'lost-reply' | 'conflict';
let scenario: PreviewScenario = 'normal';
let sequence = 1000;
const results = new Map<string, { status: number; body: unknown }>();
// Personal notification choices of the synthetic account (#333).
const notifications = { version: 1, courseOffers: true, courseReminders: true, courseChanges: true, courseStaffAlerts: false,
  messagingPrivate: true, messagingGeneral: false, messagingMentions: true };
const receipts = new Map<string, unknown>();
const nextId = () => previewId(++sequence);
const envelope = (data: unknown) => ({ data: structuredClone(data), requestId: nextId(), serverTime: new Date().toISOString() });
const list = (items: unknown[]) => envelope({ items, nextCursor: null });
export const setPreviewScenario = (value: PreviewScenario) => { scenario = value; };
for (const family of previewFamilies) family.seed?.(db);

/** Separate synthetic origin, deny by default: no request ever delegates to a real API. */
export function installPreviewTransport() {
  window.fetch = (async (input: URL | RequestInfo, init?: RequestInit) => {
    const url = new URL(input instanceof Request ? input.url : String(input), location.href);
    const reply = (status: number, body: unknown) => {
      const response = new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });
      Object.defineProperty(response, 'url', { value: url.href }); return response;
    };
    const prefix = `/app/bff/schools/${ids.school}`;
    if (url.origin === location.origin && url.pathname.startsWith('/app/bff/') && !url.pathname.startsWith('/app/bff/schools/')) {
      let parsed: FixtureRecord = {};
      try { parsed = init?.body ? JSON.parse(String(init.body)) : {}; } catch { return reply(400, { code: 'INVALID_REQUEST' }); }
      const bffRequest = { method: init?.method ?? 'GET', path: url.pathname.slice('/app/bff/'.length), query: url.searchParams, headers: new Headers(init?.headers), body: parsed, scenario };
      for (const family of previewFamilies) {
        const answer = await family.bff?.(bffRequest, { reply, nextId }); if (answer) return answer;
      }
    }
    // Personal routes of the synthetic account only: session, identity and notification choices.
    if (url.origin === location.origin && ['/app/bff/session', '/app/bff/me', '/app/bff/me/notification-preferences'].includes(url.pathname)) {
      if (url.pathname === '/app/bff/session') return reply(200, { authenticated: true, csrfToken: 'synthetic-preview', invitationPending: false, reauthenticationRequired: false, user: { displayName: previewMe.displayName, emailVerified: true } });
      if (url.pathname === '/app/bff/me') return reply(200, { data: previewMe });
      if ((init?.method ?? 'GET') === 'GET') return reply(200, { data: { ...notifications } });
      const submitted = scenario;
      await new Promise(resolve => setTimeout(resolve, submitted === 'slow' ? 6000 : 500));
      if (submitted === 'refused') return reply(409, { code: 'PREFERENCES_REJECTED' });
      if (submitted === 'conflict' || new Headers(init?.headers).get('If-Match') !== `"${notifications.version}"`) return reply(412, { code: 'VERSION_CONFLICT' });
      Object.assign(notifications, JSON.parse(String(init?.body ?? '{}')), { version: notifications.version + 1 });
      if (submitted === 'lost-reply') throw new TypeError('Synthetic response lost');
      return reply(200, { data: { ...notifications } });
    }
    if (url.origin !== location.origin || !(url.pathname === prefix || url.pathname.startsWith(`${prefix}/`))) return reply(403, { code: 'PREVIEW_NETWORK_BLOCKED' });
    const path = url.pathname.slice(prefix.length).replace(/^\//, '');
    const [collection, resourceId, action] = path.split('/');
    const query = url.searchParams;
    const method = init?.method ?? 'GET';
    const headers = new Headers(init?.headers);
    const operationId = headers.get('Idempotency-Key');
    const aliases: Record<string, string> = { 'catalog-policy-versions': 'policy-versions', 'service-product-versions': 'service-products', 'commercial-terms-versions': 'commercial-terms', 'instructor-assignments': 'assignments' };
    const items = db[aliases[collection ?? ''] ?? collection ?? ''];
    const target = items?.find(item => item.id === resourceId);
    const learner = db.learners!.find(item => item.id === resourceId);
    const training = db.trainings!.find(item => item.id === resourceId);
    const segments = path ? path.split('/') : [];
    const request = (body: FixtureRecord): PreviewRequest => ({ method, path, segments, collection, resourceId, action, query, headers, body, scenario });
    const versionMatches = (record: FixtureRecord | undefined) => !!record && headers.get('If-Match') === `"${record.version}"`;
    let lost = false;
    const commit = (kind: SchoolCommand['kind'], record: FixtureRecord) => {
      const spec = commandSpecs[kind], response = envelope(record);
      results.set(operationId!, { status: spec.expectedStatus, body: response });
      receipts.set(operationId!, { operationId, commandType: spec.operationType, resourceType: spec.resourceType, resourceId: record.id,
        resourceVersion: record.version, committedAt: new Date().toISOString() });
      if (lost) throw new TypeError('Synthetic response lost');
      return reply(spec.expectedStatus, response);
    };
    const tools: PreviewTools = { reply, envelope, list, commit, versionMatches, nextId };
    if (method === 'GET') {
      if (collection !== 'operations') for (const family of previewFamilies) {
        const answer = family.read?.(request({}), tools); if (answer) return answer;
      }
      if (!path) return reply(200, envelope(previewSchool));
      if (collection === 'operations') return receipts.has(resourceId!) ? reply(200, envelope(receipts.get(resourceId!))) : reply(404, { code: 'NOT_FOUND' });
      if (path === 'course-catalogue') return reply(200, envelope(courseCatalogue));
      if (path === 'lessons/availability') return reply(200, envelope({ available: scenario !== 'conflict', reasonCode: scenario === 'conflict' ? 'SLOT_CONFLICT' : null }));
      if (path === 'recording-choices') return reply(200, envelope({ items: [] }));
      if (path === 'readiness') return reply(200, envelope({ schoolId: ids.school, configurationVersion: 1, computedAt: stamp, activationReady: true, activationBlockers: [], capabilities: ['CAN_USE_WORKSPACE', 'CAN_PLAN_LESSON'].map(capability => ({ capability, ready: true, blockers: [] })) }));
      if (learner && action === 'action-readiness') return reply(200, envelope({ learnerId: learner.id, action: 'PLAN_LESSON', ready: learner.profileReadiness === 'READY', blockers: learner.profileReadiness === 'READY' ? [] : [{ code: 'PROFILE_ACTION_REQUIRED', field: 'birthDate', message: 'Date de naissance requise.' }] }));
      if (learner && action === 'administrative-profile') return reply(200, envelope(db.profiles!.find(item => item.learnerId === learner.id)));
      if (learner && action === 'course-facts') return reply(200, envelope({ schoolId: ids.school, learnerId: learner.id, completions: [], enrollments: [] }));
      if (training && action === 'assignments') return reply(200, list(db.assignments!.filter(item => item.trainingId === training.id)));
      if (training && action === 'permit-checks') return reply(200, list(db.permits!.filter(item => item.trainingId === training.id)));
      if (training && action === 'progress') return reply(200, envelope(progress(training.id)));
      if (collection === 'lessons' && target && action === 'reports') return reply(200, list(reports(target.id)));
      if (items && !resourceId) {
        const filtered = items.filter(item => ['learnerId', 'trainingId', 'instructorMembershipId'].every(key => !query.has(key) || item[key] === query.get(key))
          && (!query.has('from') || String(item.plannedEnd ?? item.lastEndsAt ?? item.endsAt ?? '9999') > query.get('from')!)
          && (!query.has('to') || String(item.plannedStart ?? item.firstStartsAt ?? item.startsAt ?? '') < query.get('to')!));
        return reply(200, collection === 'course-series' ? envelope({ items: filtered }) : list(filtered));
      }
      if (target && !action) return reply(200, envelope(target));
      return reply(404, { code: 'NOT_FOUND' });
    }
    if (method === 'POST' && path === 'metrics/exports') {
      let exported: FixtureRecord = {};
      try { exported = JSON.parse(String(init?.body ?? '{}')); } catch { return reply(400, { code: 'INVALID_REQUEST' }); }
      for (const family of previewFamilies) {
        const answer = family.download?.({ ...request(exported), scenario }, tools); if (answer) return answer;
      }
    }
    if (!operationId) return reply(400, { code: 'IDEMPOTENCY_KEY_REQUIRED' });
    const prior = results.get(operationId); if (prior) return reply(prior.status, prior.body);
    const submittedScenario = scenario;
    lost = submittedScenario === 'lost-reply';
    await new Promise(resolve => setTimeout(resolve, submittedScenario === 'slow' ? 5000 : 650));
    let body: FixtureRecord;
    try { body = JSON.parse(String(init?.body ?? '{}')); } catch { return reply(400, { code: 'INVALID_REQUEST' }); }
    const writeRequest = { ...request(body), scenario: submittedScenario };
    if (submittedScenario === 'refused') {
      const familyCode = previewFamilies.map(family => family.refusalCode?.(writeRequest)).find(Boolean);
      return reply(409, { code: familyCode ?? (collection === 'members' ? 'LAST_ADMIN' : 'PLANNING_CONFLICT') });
    }
    if (submittedScenario === 'conflict') return reply(412, { code: 'VERSION_CONFLICT' });
    for (const family of previewFamilies) {
      const answer = family.write?.(writeRequest, tools); if (answer) return answer;
    }
    if (collection === 'members' && target && (method === 'PATCH' || action === 'deactivate')) {
      if (!versionMatches(target)) return reply(412, { code: 'VERSION_CONFLICT' });
      if (!String(body.reason ?? '').trim()) return reply(400, { code: 'INVALID_REQUEST' });
      if (target.roles.includes('ADMIN') && (action === 'deactivate' || !body.roles?.includes('ADMIN')) && !db.members!.some(item => item.id !== target.id && item.status === 'ACTIVE' && item.roles.includes('ADMIN'))) return reply(409, { code: 'LAST_ADMIN' });
      if (action === 'deactivate') target.status = 'INACTIVE'; else { target.roles = body.roles; target.grants = body.grants; }
      target.version++; target.accessEpoch++;
      return commit(action === 'deactivate' ? 'deactivateMember' : 'updateMember', target);
    }
    if (collection === 'learners' && learner && ['archive', 'restore'].includes(action ?? '')) {
      if (!versionMatches(learner)) return reply(412, { code: 'VERSION_CONFLICT' });
      learner.archivedAt = action === 'archive' ? new Date().toISOString() : null; learner.version++;
      return commit(action === 'archive' ? 'archiveLearner' : 'restoreLearner', learner);
    }
    if (collection === 'learners' && learner && action === 'administrative-profile' && method === 'PATCH') {
      const profile = db.profiles!.find(item => item.learnerId === learner.id);
      if (!versionMatches(profile)) return reply(412, { code: 'VERSION_CONFLICT' });
      Object.assign(profile!, body); profile!.version++; learner.profileReadiness = 'READY';
      return commit('updateAdministrativeProfile', profile!);
    }
    if (collection === 'trainings' && !resourceId && method === 'POST') {
      const item = { id: nextId(), schoolId: ids.school, version: 1, learnerId: body.learnerId, offeringId: body.offeringId, categoryCode: 'B', status: 'ACTIVE', startedOn: body.startedOn, closedOn: null };
      db.trainings!.push(item); return commit('createTraining', item);
    }
    if (training && action === 'transition') {
      if (!versionMatches(training)) return reply(412, { code: 'VERSION_CONFLICT' });
      training.status = body.targetStatus; training.version++; training.closedOn = body.closedOn ?? null;
      return commit('transitionTraining', training);
    }
    if (training && action === 'assignments' && path.split('/').length === 3) {
      const item = { id: nextId(), schoolId: ids.school, version: 1, trainingId: training.id, instructorMembershipId: body.instructorMembershipId, validFrom: body.validFrom ?? new Date().toISOString(), validUntil: null };
      db.assignments!.push(item); training.version++; return commit('createAssignment', item);
    }
    if (training && action === 'assignments' && path.endsWith('/end')) {
      const assignment = db.assignments!.find(item => item.id === path.split('/')[3] && item.trainingId === training.id);
      if (!versionMatches(assignment)) return reply(412, { code: 'VERSION_CONFLICT' });
      assignment!.version++; assignment!.validUntil = body.validUntil ?? new Date().toISOString(); return commit('endAssignment', assignment!);
    }
    if (training && action === 'permit-checks') {
      if (!versionMatches(training)) return reply(412, { code: 'VERSION_CONFLICT' });
      const item = { id: nextId(), schoolId: ids.school, version: 1, trainingId: training.id, documentId: null, physicalSeen: body.physicalSeen, categoryCode: body.categoryCode,
        validUntil: body.validUntil, decision: body.decision, reviewerMembershipId: ids.admin, reviewedAt: new Date().toISOString(), reason: body.reason ?? null, isExpired: false };
      db.permits!.push(item); training.version++; return commit('recordPermitCheck', item);
    }
    if (collection === 'lessons' && method === 'POST' && !resourceId) {
      const linkedTraining = db.trainings!.find(item => item.id === body.trainingId);
      const linkedLearner = db.learners!.find(item => item.id === linkedTraining?.learnerId);
      if (!linkedTraining || !linkedLearner) return reply(404, { code: 'TRAINING_NOT_FOUND' });
      const item = { ...body, id: nextId(), schoolId: ids.school, version: 1, learnerId: linkedLearner.id, learnerDisplayName: linkedLearner.displayName,
        instructorDisplayName: db.members!.find(item => item.id === body.instructorMembershipId)?.displayName ?? '', status: 'PLANNED', actualStart: null, actualEnd: null,
        permitWarning: false, currentPublishedRevisionId: null, priceCentsSnapshot: body.agreedPriceCents, bufferMinutesSnapshot: body.bufferMinutes, commercialRevisionVersion: 1 };
      db.lessons!.push(item); return commit('createLesson', item);
    }
    if (collection === 'lessons' && target && method === 'POST' && (action === 'move' || action === 'cancel')) {
      if (!versionMatches(target)) return reply(412, { code: 'VERSION_CONFLICT' });
      if (action === 'cancel') target.status = 'CANCELLED'; else {
        Object.assign(target, { plannedStart: body.plannedStart, plannedEnd: body.plannedEnd, instructorMembershipId: body.instructorMembershipId, meetingPoint: body.meetingPoint });
        if (body.commercialChange) { target.commercialSelection = body.commercialChange.commercialSelection; target.priceCentsSnapshot = body.commercialChange.agreedPriceCents; target.commercialRevisionVersion++; }
      }
      target.version++; return commit(action === 'cancel' ? 'cancelLesson' : 'moveLesson', target);
    }
    return reply(404, { code: 'PREVIEW_ACTION_UNAVAILABLE' });
  }) as typeof fetch;
}
