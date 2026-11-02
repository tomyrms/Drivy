import { z } from 'zod';

/**
 * Demandes de l'élève sur sa leçon (#52), côté gestion web. Règles pures, sans DOM ni réseau : le serveur reste le seul juge.
 * Une demande ne change ni la leçon ni son créneau ; le personnel la refuse, ou l'accepte en déplaçant ou en annulant la leçon.
 */
const id = z.string().uuid();
const timestamp = z.string().datetime({ offset: true });

export type LessonChangeKind = 'RESCHEDULE' | 'CANCEL';
export const LESSON_CHANGE_NOTE_LIMIT = 1000;

export const lessonChangeRequestSchema = z.object({
  id, lessonId: id, kind: z.enum(['RESCHEDULE', 'CANCEL']), status: z.enum(['PENDING', 'ACCEPTED', 'REFUSED', 'WITHDRAWN', 'SUPERSEDED']), note: z.string(),
  mine: z.boolean(), late: z.boolean().nullable(), deadlineAt: timestamp.nullable(), cancellationHours: z.number().int().nullable(), policyVersionId: id.nullable(),
  resolvedAt: timestamp.nullable(), resolutionNote: z.string().nullable(), version: z.number().int().positive(), createdAt: timestamp,
});
export type LessonChangeRequest = z.infer<typeof lessonChangeRequestSchema>;

export const lessonChangeStateSchema = z.object({
  lessonId: id,
  conditions: z.object({ cancellationPolicyText: z.string(), cancellationHours: z.number().int().nullable(), deadlineAt: timestamp.nullable(), late: z.boolean().nullable(),
    canRequest: z.boolean(), blockedReason: z.string().nullable() }).passthrough(),
  requests: z.array(lessonChangeRequestSchema).max(20),
});
export type LessonChangeState = z.infer<typeof lessonChangeStateSchema>;

export const lessonChangeInboxSchema = z.object({
  items: z.array(z.object({
    request: lessonChangeRequestSchema,
    lesson: z.object({ id, plannedStart: timestamp, plannedEnd: timestamp, timeZone: z.string(), version: z.number().int().positive(), instructorMembershipId: id, learnerId: id, learnerDisplayName: z.string() }),
  })).max(100),
});
export type LessonChangeInboxItem = z.infer<typeof lessonChangeInboxSchema>['items'][number];

/** La demande en attente d'une leçon : il n'y en a jamais plus d'une. */
export const pendingRequest = (state: Pick<LessonChangeState, 'requests'> | null | undefined): LessonChangeRequest | null =>
  state?.requests.find(request => request.status === 'PENDING') ?? null;

export const requestTitle = (kind: LessonChangeKind) => kind === 'CANCEL' ? 'L’élève demande l’annulation' : 'L’élève demande un déplacement';
export const requestShort = (kind: LessonChangeKind) => kind === 'CANCEL' ? 'Annulation demandée' : 'Déplacement demandé';

/** « Hors délai » seulement quand l'école a fixé un délai et qu'il est dépassé : rien n'est supposé sans délai connu. */
export const lateLabel = (request: Pick<LessonChangeRequest, 'late'>): string | null => request.late === true ? 'Hors délai' : null;

export interface RefuseDraft { note: string }
export function refuseProblems(draft: RefuseDraft): { note?: string } {
  return [...draft.note].length > LESSON_CHANGE_NOTE_LIMIT ? { note: `${LESSON_CHANGE_NOTE_LIMIT} caractères au plus.` } : {};
}
export function refuseBody(draft: RefuseDraft) {
  if (Object.keys(refuseProblems(draft)).length) return null;
  const note = draft.note.trim();
  return { note: note || null };
}

/** Pour l'acceptation par un déplacement ou une annulation : l'identifiant n'est joint que si la demande porte sur cette action. */
export function acceptingRequestId(request: LessonChangeRequest | null, action: 'MOVE' | 'CANCEL'): string | undefined {
  if (!request || request.status !== 'PENDING') return undefined;
  return (action === 'MOVE') === (request.kind === 'RESCHEDULE') ? request.id : undefined;
}
