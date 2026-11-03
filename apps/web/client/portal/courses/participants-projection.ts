/**
 * Local projection of the facts of one course's participants still followed by the command store (#99, lot E). Pure: no DOM,
 * no network. A projection is a presentation, never a fact: a presence asked for is marked « À confirmer » and the confirmed
 * value stays readable; a settlement asked for shows the wanted amount and never enters a confirmed total; a validation asked
 * for is a mark, never an attestation.
 *
 * Every one of these commands answers the whole sheet (`{series, rights, rows}`), not the row it changed. Two participants
 * therefore answer side by side, and a late answer must never erase the row another one already brought: each answer only
 * replaces the row it was asked for, and only until a read that started after it is on screen.
 */
import type { AttendanceStatus, CourseSheet, CourseSheetRow } from '../../console/course-model.js';

/** Aggregate of one course fact: the series and the participant it concerns. Two participants never wait for each other. */
export const participantScope = (seriesId: string, enrollmentId: string) => `${seriesId}:${enrollmentId}`;
/** One cell of the call: a presence concerns one participant at one session. */
export const cellKey = (enrollmentId: string, occurrenceId: string) => `${enrollmentId}:${occurrenceId}`;

interface Base {
  readonly tag: string;
  readonly operationId: string;
  /** Participant concerned; for an enrolment gesture, the learner waiting for a place. */
  readonly enrollmentId: string;
  readonly settledAt?: number;
}

export type ParticipantsIntention =
  | (Base & { readonly kind: 'attendance'; readonly occurrenceId: string; readonly status: AttendanceStatus })
  | (Base & { readonly kind: 'payment'; readonly amountCents: number; readonly note: string | null })
  | (Base & { readonly kind: 'payment-void'; readonly paymentId: string; readonly reason: string })
  | (Base & { readonly kind: 'completion' })
  | (Base & { readonly kind: 'completion-revoke'; readonly completionId: string; readonly reason: string })
  | (Base & { readonly kind: 'enrollment-create'; readonly learnerId: string })
  | (Base & { readonly kind: 'enrollment-cancel'; readonly reason: string });

export const markLabels = {
  attendance: 'Présence à confirmer', payment: 'Règlement à confirmer', voiding: 'Annulation à confirmer',
  validating: 'Validation à confirmer', revoking: 'Retrait à confirmer', cancelling: 'Annulation de l’inscription à confirmer',
} as const;
export type Mark = keyof typeof markLabels;

/** What was typed and is worth giving back after a refusal: a wanted amount or a motive, never an inferred value. */
export type ParticipantsResume =
  | { readonly kind: 'payment'; readonly enrollmentId: string; readonly amountCents: number; readonly note: string | null }
  | { readonly kind: 'void'; readonly enrollmentId: string; readonly paymentId: string; readonly reason: string }
  | { readonly kind: 'revoke'; readonly enrollmentId: string; readonly completionId: string; readonly reason: string }
  | { readonly kind: 'cancel'; readonly enrollmentId: string; readonly reason: string }
  | { readonly kind: 'enroll'; readonly learnerId: string };

export const resumeOf = (intention: ParticipantsIntention): ParticipantsResume | null => {
  if (intention.kind === 'payment') return { kind: 'payment', enrollmentId: intention.enrollmentId, amountCents: intention.amountCents, note: intention.note };
  if (intention.kind === 'payment-void') return { kind: 'void', enrollmentId: intention.enrollmentId, paymentId: intention.paymentId, reason: intention.reason };
  if (intention.kind === 'completion-revoke') return { kind: 'revoke', enrollmentId: intention.enrollmentId, completionId: intention.completionId, reason: intention.reason };
  if (intention.kind === 'enrollment-cancel') return { kind: 'cancel', enrollmentId: intention.enrollmentId, reason: intention.reason };
  if (intention.kind === 'enrollment-create') return { kind: 'enroll', learnerId: intention.learnerId };
  return null;
};

/** A refusal is shown as a "Reprendre la saisie" notice only when something was typed or chosen. */
export const resumable = (intention: ParticipantsIntention): boolean => resumeOf(intention) !== null;

export interface SheetRead { readonly sheet: CourseSheet; readonly generation: number }
/** The row a confirmed answer brought back, and the write generation it belongs to. */
export interface OverlaidRow { readonly row: CourseSheetRow; readonly order: number }
export type SheetOverlay = ReadonlyMap<string, OverlaidRow>;

/**
 * The sheet as it is shown: a row brought back by a confirmed answer replaces the read row only when that read started before
 * the answer. Another participant's row keeps whatever was already shown for it, never the older copy this answer carries.
 */
export function mergeSheet(read: SheetRead, overlay: SheetOverlay): CourseSheet {
  const rows = read.sheet.rows.map(row => {
    const found = overlay.get(row.enrollmentId);
    return found && found.order > read.generation ? found.row : row;
  });
  for (const [enrollmentId, found] of overlay) {
    if (found.order > read.generation && !rows.some(row => row.enrollmentId === enrollmentId)) rows.push(found.row);
  }
  return rows.length === read.sheet.rows.length && rows.every((row, index) => row === read.sheet.rows[index]) ? read.sheet : { ...read.sheet, rows };
}

/** Intentions that still show: the followed ones, and the confirmed ones until a read newer than their confirmation is shown. */
export function visibleIntentions(intentions: readonly ParticipantsIntention[], followed: ReadonlySet<string>, readAt: number | undefined): ParticipantsIntention[] {
  return intentions.filter(intention => intention.settledAt !== undefined ? (readAt ?? 0) < intention.settledAt : followed.has(intention.operationId));
}

export interface ProjectedParticipants {
  /** The school's own facts, plus the rows a confirmed answer already replaced. Nothing here is wanted, only confirmed. */
  readonly sheet: CourseSheet;
  readonly marks: ReadonlyMap<string, readonly Mark[]>;
  /** Presence asked for, by cell (`cellKey`): the confirmed value of the cell stays as the school has it. */
  readonly attendance: ReadonlyMap<string, AttendanceStatus>;
  /** Settlement asked for, by participant: the wanted amount, never counted in a confirmed total. */
  readonly payments: ReadonlyMap<string, { readonly amountCents: number; readonly note: string | null }>;
  /** Participants whose gesture still waits for the school: the next gesture on them waits, the others do not. */
  readonly followed: ReadonlySet<string>;
}

/**
 * The participants as they are shown. A gesture still followed is a mark on the line of the person it concerns; a confirmed
 * one stops marking and the school's answer, already merged or read again, carries the fact. No mark ever replaces another
 * participant's, whatever the order the answers come back in.
 */
export function projectParticipants(read: SheetRead, overlay: SheetOverlay, intentions: readonly ParticipantsIntention[]): ProjectedParticipants {
  const sheet = mergeSheet(read, overlay);
  const marks = new Map<string, Mark[]>(), attendance = new Map<string, AttendanceStatus>();
  const payments = new Map<string, { amountCents: number; note: string | null }>();
  const followed = new Set<string>();
  const mark = (enrollmentId: string, value: Mark) => {
    const known = marks.get(enrollmentId);
    if (known) { if (!known.includes(value)) known.push(value); } else marks.set(enrollmentId, [value]);
  };
  for (const intention of intentions) {
    if (intention.settledAt !== undefined) continue;
    followed.add(intention.enrollmentId);
    if (intention.kind === 'attendance') {
      mark(intention.enrollmentId, 'attendance');
      attendance.set(cellKey(intention.enrollmentId, intention.occurrenceId), intention.status);
    } else if (intention.kind === 'payment') {
      mark(intention.enrollmentId, 'payment');
      payments.set(intention.enrollmentId, { amountCents: intention.amountCents, note: intention.note });
    } else if (intention.kind === 'payment-void') {
      mark(intention.enrollmentId, 'voiding');
    } else if (intention.kind === 'completion') {
      mark(intention.enrollmentId, 'validating');
    } else if (intention.kind === 'completion-revoke') {
      mark(intention.enrollmentId, 'revoking');
    } else if (intention.kind === 'enrollment-cancel') {
      mark(intention.enrollmentId, 'cancelling');
    }
  }
  return { sheet, marks, attendance, payments, followed };
}
