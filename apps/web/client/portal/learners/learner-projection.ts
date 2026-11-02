/**
 * Local projection of the dossier intentions still followed by the command store (#116). Pure: no DOM, no network.
 *
 * A projection is a presentation, never a right. It never grants access (an assignment « à confirmer » opens nothing, a
 * restoration « à confirmer » keeps the dossier archived and read-only), never makes a formation official before the school's
 * receipt (a provisional line has no identifier of the school: no lesson can be booked on it), and a dossier being archived is
 * not erased from the directory: it stays, marked. Once the school confirmed, the row shows what was confirmed, unmarked, until
 * the next read replaces it.
 */
import type { PermitDraft, TrainingStatus } from '../../command-core';
import type { Assignment, Learner, Training } from '../../school-api';

interface Base { readonly tag: string; readonly operationId: string; readonly learnerId: string; readonly settledAt?: number }
export type LearnerIntention =
  | (Base & { readonly kind: 'training-create'; readonly offeringId: string; readonly startedOn: string })
  | (Base & { readonly kind: 'assignment-create'; readonly trainingId: string; readonly instructorId: string })
  | (Base & { readonly kind: 'assignment-end'; readonly trainingId: string; readonly assignmentId: string })
  | (Base & { readonly kind: 'training-transition'; readonly trainingId: string; readonly target: TrainingStatus; readonly label: string; readonly reason: string })
  | (Base & { readonly kind: 'permit-check'; readonly trainingId: string; readonly draft: PermitDraft })
  | (Base & { readonly kind: 'learner-archive'; readonly reason: string })
  | (Base & { readonly kind: 'learner-restore'; readonly reason: string });

export const PROVISIONAL = 'pending:';
export const isProvisional = (id: string) => id.startsWith(PROVISIONAL);

export const markLabels = {
  opening: 'Ouverture à confirmer', changing: 'Changement à confirmer', assigning: 'Affectation à confirmer', ending: 'Retrait à confirmer',
  checking: 'Contrôle à confirmer', archiving: 'Archivage à confirmer', restoring: 'Restauration à confirmer',
} as const;
export type Mark = keyof typeof markLabels;

/** Intentions that still show: the followed ones, and the confirmed ones until a read newer than their confirmation is on screen. */
export function visibleIntentions(intentions: readonly LearnerIntention[], followed: ReadonlySet<string>, readAt: number | undefined): LearnerIntention[] {
  return intentions.filter(intention => intention.settledAt !== undefined ? (readAt ?? 0) < intention.settledAt : followed.has(intention.operationId));
}

export interface ProjectedLearner { readonly learner: Learner; readonly mark: Mark | undefined }

/** The dossier as it is shown: archived only once the school said so; a pending archive or restoration is a mark, nothing else. */
export function projectLearner(learner: Learner, intentions: readonly LearnerIntention[]): ProjectedLearner {
  let projected = learner, mark: Mark | undefined;
  for (const intention of intentions) {
    if (intention.learnerId !== learner.id) continue;
    if (intention.kind === 'learner-archive') {
      if (intention.settledAt === undefined) mark = 'archiving'; else projected = { ...projected, archivedAt: new Date(intention.settledAt).toISOString() };
    } else if (intention.kind === 'learner-restore') {
      if (intention.settledAt === undefined) mark = 'restoring'; else projected = { ...projected, archivedAt: null };
    }
  }
  return { learner: projected, mark };
}

export interface ProjectedTrainings {
  readonly trainings: Training[];
  readonly marks: ReadonlyMap<string, Mark>;
  /** Ids of the formations that exist only as an intention: they cannot be opened, managed, nor used for a lesson. */
  readonly provisional: ReadonlySet<string>;
}

/** Formations of one dossier: a new one is a provisional line, a requested change a mark; the status itself only changes once confirmed. */
export function projectTrainings(confirmed: readonly Training[], intentions: readonly LearnerIntention[], learnerId: string): ProjectedTrainings {
  const trainings: Training[] = confirmed.filter(item => item.learnerId === learnerId).map(item => ({ ...item }));
  const marks = new Map<string, Mark>(), provisional = new Set<string>();
  for (const intention of intentions) {
    if (intention.learnerId !== learnerId) continue;
    if (intention.kind === 'training-create') {
      const id = `${PROVISIONAL}${intention.operationId}`;
      trainings.push({ id, schoolId: '', version: 0, learnerId, offeringId: intention.offeringId, status: 'ACTIVE', startedOn: intention.startedOn, closedOn: null });
      provisional.add(id);
      if (intention.settledAt === undefined) marks.set(id, 'opening');
    } else if (intention.kind === 'training-transition') {
      const index = trainings.findIndex(item => item.id === intention.trainingId);
      if (index < 0) continue;
      if (intention.settledAt === undefined) marks.set(intention.trainingId, 'changing');
      else trainings[index] = { ...trainings[index]!, status: intention.target };
    } else if (intention.kind === 'permit-check') {
      if (intention.settledAt === undefined && trainings.some(item => item.id === intention.trainingId)) marks.set(intention.trainingId, 'checking');
    }
  }
  return { trainings, marks, provisional };
}

export interface ProjectedAssignments {
  readonly assignments: Assignment[];
  readonly marks: ReadonlyMap<string, Mark>;
  readonly provisional: ReadonlySet<string>;
}

/** Instructors of one formation. Nothing here grants an instructor access to a dossier: that stays what the school's own list says. */
export function projectAssignments(confirmed: readonly Assignment[], intentions: readonly LearnerIntention[], trainingId: string, now: number): ProjectedAssignments {
  const assignments: Assignment[] = confirmed.filter(item => item.trainingId === trainingId).map(item => ({ ...item }));
  const marks = new Map<string, Mark>(), provisional = new Set<string>();
  for (const intention of intentions) {
    if (intention.kind === 'assignment-create' && intention.trainingId === trainingId) {
      const id = `${PROVISIONAL}${intention.operationId}`;
      assignments.push({ id, schoolId: '', version: 0, trainingId, instructorMembershipId: intention.instructorId, validFrom: new Date(intention.settledAt ?? now).toISOString(), validUntil: null });
      provisional.add(id);
      if (intention.settledAt === undefined) marks.set(id, 'assigning');
    } else if (intention.kind === 'assignment-end' && intention.trainingId === trainingId) {
      const index = assignments.findIndex(item => item.id === intention.assignmentId);
      if (index < 0) continue;
      if (intention.settledAt === undefined) marks.set(intention.assignmentId, 'ending');
      else assignments[index] = { ...assignments[index]!, validUntil: new Date(intention.settledAt).toISOString() };
    }
  }
  return { assignments, marks, provisional };
}

/** A dossier with a request still followed waits for it before the next one: the school orders what touches the same dossier. */
export const followedFor = (intentions: readonly LearnerIntention[], learnerId: string) =>
  intentions.some(intention => intention.learnerId === learnerId && intention.settledAt === undefined);
