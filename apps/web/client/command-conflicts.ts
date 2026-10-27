import { commandSpecs, type SchoolCommand } from './command-core.js';

/** Shared versions and aggregates, not screens. Unknown/restored commands remain conservative. */
export function commandConflictKeys(command: SchoolCommand): readonly string[] {
  const kind = command.kind;
  if (['activate', 'applySetupDraft', 'updateModules', 'updateMember', 'deactivateMember'].includes(kind)) return ['*'];
  if (['updateSchool', 'saveSetup', 'saveSetupDraft', 'saveDataPolicy'].includes(kind)) return ['school'];
  if (kind === 'saveObservationThemes') return ['observation-themes'];
  if (kind === 'saveCoursePolicy') return ['course-policy'];
  if (['createProfilePolicy', 'publishProfilePolicy'].includes(kind)) return ['profile-policy'];
  if (['createInvitation', 'resendInvitation', 'revokeInvitation'].includes(kind)) return ['invitations'];
  if (['createOffering', 'createCurriculum', 'createCatalogPolicy', 'createCommercialTerms', 'createServiceProduct',
    'createFormation', 'saveFormationProgramme', 'saveTariff'].includes(kind)) return ['catalogue'];
  // Scheduling and enrolment share occupancy and eligibility, even across two series.
  if (['createAvailabilityRule', 'updateAvailabilityRule', 'removeAvailabilityRule', 'createClosure', 'removeClosure',
    'createCourseSeries', 'updateCourseSeries', 'publishCourseSeries', 'changeCourseCapacity', 'staffEnrollCourse',
    'staffCancelCourseEnrollment', 'cancelCourseSeries', 'rescheduleCourseSeries', 'createLesson', 'moveLesson', 'cancelLesson'].includes(kind)) return ['planning'];
  if (kind === 'createCourseType') return ['course-types'];
  // Attendance, payment and completion currently return a common roster projection.
  if (['recordCourseAttendance', 'recordCoursePayment', 'voidCoursePayment', 'validateCourse', 'revokeCourseCompletion'].includes(kind)) return ['course-facts'];
  if (['createTraining', 'createAssignment', 'transitionTraining', 'endAssignment', 'archiveLearner', 'restoreLearner',
    'recordPermitCheck', 'updateAdministrativeProfile'].includes(kind)) return ['learners', 'planning'];
  // New commands must be audited before they can run alongside existing mutations.
  return ['*'];
}

export function commandsConflict(a: SchoolCommand | null, b: SchoolCommand): boolean {
  if (!a) return true; // Metadata restored after reload has no request body/dependency information.
  if (a.schoolId !== b.schoolId) return false;
  const left = commandConflictKeys(a), right = commandConflictKeys(b);
  return left.includes('*') || right.includes('*') || left.some(key => right.includes(key));
}

/** Only changes to the school itself or access require rereading the school/access envelope. */
export function commandRefreshesSchool(kind: SchoolCommand['kind']): boolean {
  return commandSpecs[kind].target === 'school' || ['updateMember', 'deactivateMember', 'applySetupDraft'].includes(kind);
}
