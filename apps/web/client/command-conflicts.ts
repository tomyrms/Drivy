import { commandSpecs, type CommandKind, type SchoolCommand } from './command-core.js';

/**
 * What decides whether two commands may run side by side, known before a command exists: a control asks whether it may start
 * without building (and numbering) a command it would not send.
 */
export interface ConflictSubject {
  readonly kind: CommandKind;
  readonly operationId?: string | undefined;
  readonly resourceId?: string | undefined;
  /** Aggregate named by the caller when the body does not carry it (see SchoolCommand.scope). */
  readonly scope?: string | undefined;
  readonly body?: Readonly<Record<string, unknown>> | undefined;
}

const lower = (value: unknown): string | undefined => typeof value === 'string' && value.trim() !== '' ? value.trim().toLowerCase() : undefined;

/**
 * Shared versions and aggregates, not screens. Keys are paths: `planning:availability:<instructor>:rules` is inside
 * `planning:availability:<instructor>`, which is inside `planning`. Two keys conflict when they are equal or one contains the other,
 * so a refined key still waits for the whole family it belongs to and never for its siblings. Unknown/restored commands remain conservative.
 */
export function commandConflictKeys(command: ConflictSubject): readonly string[] {
  const kind = command.kind;
  if (['activate', 'applySetupDraft', 'updateModules', 'updateMember', 'deactivateMember'].includes(kind)) return ['*'];
  if (['updateSchool', 'saveSetup', 'saveSetupDraft', 'saveDataPolicy'].includes(kind)) return ['school'];
  if (kind === 'saveObservationThemes') return ['observation-themes'];
  if (kind === 'saveCoursePolicy') return ['course-policy'];
  if (['createProfilePolicy', 'publishProfilePolicy'].includes(kind)) return ['profile-policy'];
  // One invitation is ordered with itself (its version); a creation waits only for an identical request (same address, same operation).
  if (kind === 'createInvitation') {
    const own = (command.body?.delivery === 'EMAIL' ? lower(command.body.email) : undefined) ?? lower(command.operationId);
    return [own ? `invitations:new:${own}` : 'invitations:new'];
  }
  if (kind === 'resendInvitation' || kind === 'revokeInvitation') {
    const target = lower(command.resourceId);
    return [target ? `invitations:${target}` : 'invitations'];
  }
  if (['createOffering', 'createCurriculum', 'createCatalogPolicy', 'createCommercialTerms', 'createServiceProduct',
    'createFormation'].includes(kind)) return ['catalogue'];
  // Un enregistrement de programme s'ordonne par formation (#124) ; sans portée — une création, qui n'a pas encore d'identifiant
  // d'école — la clé reste la famille entière.
  if (kind === 'saveFormationProgramme') {
    const offering = lower(command.scope);
    return [offering ? `catalogue:offering:${offering}` : 'catalogue'];
  }
  // Un tarif s'ordonne par produit, une révision de conditions par jeu de conditions (#124). Sans agrégat nommé — une création,
  // qui n'a pas encore d'identifiant d'école, ou un tarif qui partage ses conditions — la clé reste la famille entière.
  if (kind === 'saveTariff') {
    const product = lower(command.scope);
    return [product ? `catalogue:product:${product}` : 'catalogue'];
  }
  // Une révision de conditions reste ordonnée avec la planification, comme le repli « * » qu'elle avait avant (#124).
  if (kind === 'reviseSharedTerms') {
    const terms = lower(command.scope);
    return terms ? [`catalogue:terms:${terms}`, 'planning'] : ['catalogue', 'planning'];
  }
  // Weekly hours and absences of one instructor are ordered with their own kind only; both still wait for lessons and courses (`planning`).
  if (kind === 'createAvailabilityRule' || kind === 'updateAvailabilityRule' || kind === 'removeAvailabilityRule'
    || kind === 'createClosure' || kind === 'removeClosure') {
    const instructor = lower(command.scope) ?? lower(command.body?.instructorMembershipId);
    const family = kind.endsWith('Closure') ? 'closures' : 'rules';
    return [instructor ? `planning:availability:${instructor}:${family}` : 'planning'];
  }
  // Scheduling and enrolment share occupancy and eligibility, even across two series.
  if (['createCourseSeries', 'updateCourseSeries', 'publishCourseSeries', 'changeCourseCapacity', 'staffEnrollCourse',
    'staffCancelCourseEnrollment', 'cancelCourseSeries', 'rescheduleCourseSeries', 'createLesson', 'moveLesson', 'cancelLesson', 'refuseLessonChangeRequest'].includes(kind)) return ['planning'];
  // Un accompagnement occupe l'agenda du moniteur comme une leçon ; un résultat ne touche que les examens.
  if (['createExam', 'updateExam', 'postponeExam'].includes(kind)) return ['exams', 'planning'];
  if (kind === 'setExamResult') return ['exams'];
  if (kind === 'createCourseType') return ['course-types'];
  // Attendance, payment and completion currently return a common roster projection.
  if (['recordCourseAttendance', 'recordCoursePayment', 'voidCoursePayment', 'validateCourse', 'revokeCourseCompletion'].includes(kind)) return ['course-facts'];
  // A learner's dossier is ordered with itself; another learner's dossier does not wait for it. Planning still waits for every one of them.
  if (['createTraining', 'createAssignment', 'transitionTraining', 'endAssignment', 'archiveLearner', 'restoreLearner',
    'recordPermitCheck', 'updateAdministrativeProfile'].includes(kind)) {
    const learner = lower(command.scope) ?? lower(command.body?.learnerId) ?? (kind === 'archiveLearner' || kind === 'restoreLearner' ? lower(command.resourceId) : undefined);
    return learner ? [`learners:${learner}`, `planning:learner:${learner}`] : ['learners', 'planning'];
  }
  // New commands must be audited before they can run alongside existing mutations.
  return ['*'];
}

const related = (a: string, b: string) => a === b || a.startsWith(`${b}:`) || b.startsWith(`${a}:`);

function subjectsConflict(a: ConflictSubject, b: ConflictSubject): boolean {
  // The same intention submitted twice (a double press) is never a second request.
  if (a.operationId !== undefined && a.operationId === b.operationId) return true;
  const left = commandConflictKeys(a), right = commandConflictKeys(b);
  return left.includes('*') || right.includes('*') || left.some(one => right.some(other => related(one, other)));
}

export function commandsConflict(a: SchoolCommand | null, b: SchoolCommand): boolean {
  if (!a) return true; // Metadata restored after reload has no request body/dependency information.
  if (a.schoolId !== b.schoolId) return false;
  return subjectsConflict(a, b);
}

/**
 * Would a command like `subject` be refused locally right now? A control stays available when no followed request concerns the
 * same aggregate. A request restored after a reload (no body) concerns everything until its result is settled.
 */
export function wouldConflict(entries: Iterable<{ readonly meta: { readonly schoolId: string }; readonly command: SchoolCommand | null }>,
  schoolId: string, subject: ConflictSubject): boolean {
  for (const entry of entries) {
    if (entry.meta.schoolId !== schoolId) continue;
    if (entry.command === null || subjectsConflict(entry.command, subject)) return true;
  }
  return false;
}

/** Only changes to the school itself or access require rereading the school/access envelope. */
export function commandRefreshesSchool(kind: SchoolCommand['kind']): boolean {
  return commandSpecs[kind].target === 'school' || ['updateMember', 'deactivateMember', 'applySetupDraft'].includes(kind);
}
